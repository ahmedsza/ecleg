
<#
MySQL migration helper: AWS (RDS/MySQL) -> Azure Database for MySQL Flexible Server

What it does:
1) Reads source DB default charset/collation (information_schema.SCHEMATA)
2) Reads a small set of relevant MySQL settings from source + target
3) Creates the target database in Azure with matching charset/collation
4) Runs mysqldump from source and restores into target via mysql client
5) Re-checks target DB charset/collation and prints a comparison report

Prereqs on the machine running this script:
- az login is NOT required for dump/restore (this uses mysql client tools)
- mysql client tools installed: mysql.exe and mysqldump.exe available in PATH
  (e.g., MySQL Installer, MariaDB client, or MySQL Shell bundle)

Security note:
- This script accepts passwords as plain strings and uses the MYSQL_PWD env var
	for the subprocess invocation to avoid putting passwords on the command line.
#>

[CmdletBinding()]
param(
	# Source (AWS)
	[Parameter(Mandatory)]
	[string] $SourceHost,

	[Parameter()]
	[int] $SourcePort = 3306,

	[Parameter(Mandatory)]
	[string] $SourceUser,

	[Parameter(Mandatory)]
	[string] $SourcePassword,

	[Parameter(Mandatory)]
	[string] $SourceDatabase,

	[Parameter()]
	[ValidateSet('DISABLED', 'PREFERRED', 'REQUIRED', 'VERIFY_CA', 'VERIFY_IDENTITY')]
	[string] $SourceSslMode = 'REQUIRED',

	# Target (Azure MySQL Flexible Server)
	[Parameter(Mandatory)]
	[string] $TargetHost,

	[Parameter()]
	[int] $TargetPort = 3306,

	[Parameter(Mandatory)]
	[string] $TargetUser,

	[Parameter(Mandatory)]
	[string] $TargetPassword,

	[Parameter(Mandatory)]
	[string] $TargetDatabase,

	[Parameter()]
	[ValidateSet('DISABLED', 'PREFERRED', 'REQUIRED', 'VERIFY_CA', 'VERIFY_IDENTITY')]
	[string] $TargetSslMode = 'REQUIRED',

	# Dump/restore options
	[Parameter()]
	[string] $WorkingDirectory = (Join-Path $PWD 'mysql-migration'),

	[Parameter()]
	[switch] $RecreateTargetDatabase,

	[Parameter()]
	[switch] $FailIfTargetDbExists,

	[Parameter()]
	[switch] $SkipDump,

	[Parameter()]
	[switch] $SkipRestore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MySqlSslArgs {
	param(
		[Parameter(Mandatory)][ValidateSet('mysql', 'mysqldump')][string] $Tool,
		[Parameter(Mandatory)][ValidateSet('DISABLED', 'PREFERRED', 'REQUIRED', 'VERIFY_CA', 'VERIFY_IDENTITY')][string] $SslMode
	)

	# Some mysql/mysqldump clients (notably the one in Azure Cloud Shell) do not support --ssl-mode.
	# When unsupported, passing --ssl-mode=REQUIRED is interpreted as a server variable assignment and fails with:
	#   /usr/bin/mysql: unknown variable 'ssl-mode=REQUIRED'
	if (-not $script:__sslModeSupportCache) {
		$script:__sslModeSupportCache = @{}
	}
	if (-not $script:__sslModeSupportCache.ContainsKey($Tool)) {
		try {
			$help = & $Tool '--help' 2>&1 | Out-String
			$script:__sslModeSupportCache[$Tool] = ($help -match '(?m)^\s*--ssl-mode')
		}
		catch {
			$script:__sslModeSupportCache[$Tool] = $false
		}
	}

	if ($script:__sslModeSupportCache[$Tool]) {
		return @("--ssl-mode=$SslMode")
	}

	switch ($SslMode) {
		'DISABLED' { return @('--skip-ssl') }
		'PREFERRED' { return @() }
		default { return @('--ssl') }
	}
}

function Test-CommandExists {
	param([Parameter(Mandatory)][string] $Name)
	if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
		throw "Required tool '$Name' not found in PATH. Install MySQL client tools (mysql/mysqldump) and retry."
	}
}

function ConvertTo-PlainText {
	param([Parameter(Mandatory)][string] $Password)
	return $Password
}

function Invoke-MySqlQuery {
	param(
		[Parameter(Mandatory)][string] $MySqlHost,
		[Parameter(Mandatory)][int] $Port,
		[Parameter(Mandatory)][string] $User,
		[Parameter(Mandatory)][string] $Password,
		[Parameter(Mandatory)][string] $Query,
		[Parameter()][string] $Database,
		[Parameter(Mandatory)][string] $SslMode
	)

	$plain = ConvertTo-PlainText -Password $Password
	$old = $env:MYSQL_PWD
	$env:MYSQL_PWD = $plain
	try {
		$sslArgs = Get-MySqlSslArgs -Tool 'mysql' -SslMode $SslMode
		$args = @(
			'--host', $MySqlHost,
			'--port', $Port,
			'--user', $User,
			$sslArgs,
			'--batch', '--skip-column-names',
			'--execute', $Query
		)
		$args = @($args | Where-Object { $_ -ne $null -and $_ -ne '' } | ForEach-Object { $_ })
		if ($Database) {
			$args += @('--database', $Database)
		}

		$out = & mysql @args 2>&1
		if ($LASTEXITCODE -ne 0) {
			throw "mysql query failed (exit $LASTEXITCODE) against ${MySqlHost}:$Port. Output:`n$out"
		}
		return $out
	}
	finally {
		$env:MYSQL_PWD = $old
	}
}

function Invoke-MySqlDump {
	param(
		[Parameter(Mandatory)][string] $MySqlHost,
		[Parameter(Mandatory)][int] $Port,
		[Parameter(Mandatory)][string] $User,
		[Parameter(Mandatory)][string] $Password,
		[Parameter(Mandatory)][string] $Database,
		[Parameter(Mandatory)][string] $SslMode,
		[Parameter(Mandatory)][string] $OutFile
	)

	$plain = ConvertTo-PlainText -Password $Password
	$old = $env:MYSQL_PWD
	$env:MYSQL_PWD = $plain
	try {
		$sslArgs = Get-MySqlSslArgs -Tool 'mysqldump' -SslMode $SslMode
		$args = @(
			'--host', $MySqlHost,
			'--port', $Port,
			'--user', $User,
			$sslArgs,
			'--databases', $Database,
			'--single-transaction',
			'--routines', '--events', '--triggers',
			'--hex-blob',
			'--set-gtid-purged=OFF',
			'--column-statistics=0'
		)
		$args = @($args | Where-Object { $_ -ne $null -and $_ -ne '' } | ForEach-Object { $_ })

		$errFile = "$OutFile.stderr.txt"
		if (Test-Path $errFile) { Remove-Item -Force $errFile }

		$p = Start-Process -FilePath 'mysqldump' -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
		if ($p.ExitCode -ne 0) {
			$err = if (Test-Path $errFile) { (Get-Content -Path $errFile -Raw) } else { '' }
			throw "mysqldump failed (exit $($p.ExitCode)). Error output:`n$err"
		}
	}
	finally {
		$env:MYSQL_PWD = $old
	}
}

function Invoke-MySqlRestore {
	param(
		[Parameter(Mandatory)][string] $MySqlHost,
		[Parameter(Mandatory)][int] $Port,
		[Parameter(Mandatory)][string] $User,
		[Parameter(Mandatory)][string] $Password,
		[Parameter(Mandatory)][string] $SslMode,
		[Parameter(Mandatory)][string] $InFile
	)

	$plain = ConvertTo-PlainText -Password $Password
	$old = $env:MYSQL_PWD
	$env:MYSQL_PWD = $plain
	try {
		$sslArgs = Get-MySqlSslArgs -Tool 'mysql' -SslMode $SslMode
		$args = @(
			'--host', $MySqlHost,
			'--port', $Port,
			'--user', $User,
			$sslArgs
		)
		$args = @($args | Where-Object { $_ -ne $null -and $_ -ne '' } | ForEach-Object { $_ })

		Get-Content -Path $InFile -Raw | & mysql @args 2>&1 | Out-Null
		if ($LASTEXITCODE -ne 0) {
			throw "mysql restore failed (exit $LASTEXITCODE)."
		}
	}
	finally {
		$env:MYSQL_PWD = $old
	}
}

function Convert-SettingsOutputToMap {
	param([Parameter(Mandatory)][string] $Text)
	$map = @{}
	foreach ($line in ($Text -split "\r?\n")) {
		if (-not $line) { continue }
		$parts = $line -split "\t"
		if ($parts.Count -lt 2) { continue }
		$map[$parts[0]] = $parts[1]
	}
	return $map
}

function Write-SettingsComparison {
	param(
		[Parameter(Mandatory)][hashtable] $Source,
		[Parameter(Mandatory)][hashtable] $Target
	)

	$keys = @('character_set_server', 'collation_server', 'sql_mode', 'time_zone')
	foreach ($k in $keys) {
		$sv = $Source[$k]
		$tv = $Target[$k]
		if ($sv -ne $tv) {
			Write-Warning "Setting mismatch: $k (source='$sv', target='$tv')"
		}
		else {
			Write-Output "Setting match: $k = '$sv'"
		}
	}
}

Test-CommandExists -Name 'mysql'
Test-CommandExists -Name 'mysqldump'

New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
$dumpFile = Join-Path $WorkingDirectory ("{0}-{1:yyyyMMdd-HHmmss}.sql" -f $SourceDatabase, (Get-Date))

Write-Output "[1/6] Reading source DB charset/collation from AWS..."
$sourceSchemaLine = Invoke-MySqlQuery -MySqlHost $SourceHost -Port $SourcePort -User $SourceUser -Password $SourcePassword -SslMode $SourceSslMode -Query (
	"SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$SourceDatabase';"
)
if (-not $sourceSchemaLine) {
	throw "Source database '$SourceDatabase' not found on $SourceHost."
}

$firstLine = ($sourceSchemaLine -split "\r?\n" | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1)
$parts = $firstLine -split "\t"
if ($parts.Count -lt 2) {
	$parts = $firstLine.Trim() -split "\s+"
}

$sourceCharset = $parts[0]
$sourceCollation = $parts[1]
Write-Output "Source DB default charset='$sourceCharset', collation='$sourceCollation'"

Write-Output "[2/6] Reading key MySQL settings (source + target)..."
$settingsQuery = "SELECT 'character_set_server', @@character_set_server UNION ALL SELECT 'collation_server', @@collation_server UNION ALL SELECT 'sql_mode', @@sql_mode UNION ALL SELECT 'time_zone', @@time_zone;"
$sourceSettings = Invoke-MySqlQuery -MySqlHost $SourceHost -Port $SourcePort -User $SourceUser -Password $SourcePassword -SslMode $SourceSslMode -Query $settingsQuery
$targetSettings = Invoke-MySqlQuery -MySqlHost $TargetHost -Port $TargetPort -User $TargetUser -Password $TargetPassword -SslMode $TargetSslMode -Query $settingsQuery

Write-Output "Source settings:"; Write-Output $sourceSettings
Write-Output "Target settings:"; Write-Output $targetSettings

$sourceMap = Convert-SettingsOutputToMap -Text $sourceSettings
$targetMap = Convert-SettingsOutputToMap -Text $targetSettings
Write-Output "Settings comparison (key items):"
Write-SettingsComparison -Source $sourceMap -Target $targetMap

Write-Output "[3/6] Creating target DB in Azure with matching charset/collation..."
$targetDbLine = Invoke-MySqlQuery -MySqlHost $TargetHost -Port $TargetPort -User $TargetUser -Password $TargetPassword -SslMode $TargetSslMode -Query (
	"SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$TargetDatabase';"
) | Select-Object -First 1

if ($targetDbLine) {
	if ($FailIfTargetDbExists) {
		throw "Target database '$TargetDatabase' already exists on $TargetHost and -FailIfTargetDbExists was specified."
	}

	if ($RecreateTargetDatabase) {
		Write-Output "Dropping existing target DB '$TargetDatabase'..."
		$bt = [char]96
		$dropSql = "DROP DATABASE IF EXISTS $bt$TargetDatabase$bt;"
		$null = Invoke-MySqlQuery -MySqlHost $TargetHost -Port $TargetPort -User $TargetUser -Password $TargetPassword -SslMode $TargetSslMode -Query $dropSql
	}
}

# Create DB (or ensure it exists) with matching defaults
$bt = [char]96
$createDbSql = "CREATE DATABASE IF NOT EXISTS $bt$TargetDatabase$bt CHARACTER SET $sourceCharset COLLATE $sourceCollation;"
$null = Invoke-MySqlQuery -MySqlHost $TargetHost -Port $TargetPort -User $TargetUser -Password $TargetPassword -SslMode $TargetSslMode -Query $createDbSql

$verifyLine = Invoke-MySqlQuery -MySqlHost $TargetHost -Port $TargetPort -User $TargetUser -Password $TargetPassword -SslMode $TargetSslMode -Query (
	"SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$TargetDatabase';"
)
Write-Output "Target DB defaults now:"; Write-Output $verifyLine

if (-not $SkipDump) {
	Write-Output "[4/6] Dumping source DB to $dumpFile ..."
	Invoke-MySqlDump -MySqlHost $SourceHost -Port $SourcePort -User $SourceUser -Password $SourcePassword -Database $SourceDatabase -SslMode $SourceSslMode -OutFile $dumpFile
}
else {
	Write-Output "[4/6] Skipping dump as requested."
}

if (-not $SkipRestore) {
	Write-Output "[5/6] Restoring dump into target (Azure)..."
	if (-not (Test-Path $dumpFile)) {
		throw "Dump file not found: $dumpFile"
	}
	Invoke-MySqlRestore -MySqlHost $TargetHost -Port $TargetPort -User $TargetUser -Password $TargetPassword -SslMode $TargetSslMode -InFile $dumpFile
}
else {
	Write-Output "[5/6] Skipping restore as requested."
}

Write-Output "[6/6] Post-restore verification..."
$postLine = Invoke-MySqlQuery -MySqlHost $TargetHost -Port $TargetPort -User $TargetUser -Password $TargetPassword -SslMode $TargetSslMode -Query (
	"SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$TargetDatabase';"
)
Write-Output "Target DB default charset/collation:"; Write-Output $postLine

Write-Output "Done. Dump file: $dumpFile"

