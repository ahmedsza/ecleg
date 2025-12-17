# MySQL AWS → Azure Migration (Backup + Restore)

This guide explains how to use the PowerShell script in [sqlrestore.ps1](sqlrestore.ps1) to migrate a MySQL database from AWS (typically RDS MySQL) to Azure Database for MySQL Flexible Server.

## What the script does

The script performs these steps:

1. **Reads the source database defaults** from AWS:
   - Default character set
   - Default collation
   (from `information_schema.SCHEMATA`)

2. **Reads and compares key MySQL settings** between source (AWS) and target (Azure):
   - `character_set_server`
   - `collation_server`
   - `sql_mode`
   - `time_zone`

   It prints the raw values and emits warnings if any of these differ.

3. **Creates the target database in Azure** with the same **default charset/collation** as the source database.
   - Optionally drops and recreates the target DB (see flags below)

4. **Performs the data move**:
   - Runs `mysqldump` against AWS and writes a timestamped `.sql` dump file
   - Restores the dump into Azure using the `mysql` client

5. **Verifies** the target database default charset/collation post-restore.

## Prerequisites

### Tools
- PowerShell (`pwsh`)
- MySQL client utilities available in your PATH:
  - `mysql`
  - `mysqldump`

Examples of how to get them:
- Install “MySQL Server” / “MySQL Client” via MySQL Installer (Windows)
- Or install a MySQL client package that includes `mysql.exe` and `mysqldump.exe`

### Network access
- The machine running the script must be able to connect to:
  - AWS DB endpoint (RDS hostname/IP) on port `3306` (or your port)
  - Azure MySQL Flexible Server hostname on port `3306`

If Azure MySQL is private (Private Endpoint), run this script from a network that can resolve and reach it.

### Credentials
- You need:
  - AWS MySQL username/password with permission to read schema and dump data
  - Azure MySQL username/password with permission to create DB and restore data

## Inputs (Parameters)

### Source (AWS)
- `-SourceHost` (required): AWS hostname (e.g., RDS endpoint)
- `-SourcePort` (default `3306`)
- `-SourceUser` (required)
- `-SourcePassword` (required, `SecureString`)
- `-SourceDatabase` (required)
- `-SourceSslMode` (default `REQUIRED`)

### Target (Azure MySQL Flexible Server)
- `-TargetHost` (required): Azure MySQL FQDN (e.g., `myserver.mysql.database.azure.com`)
- `-TargetPort` (default `3306`)
- `-TargetUser` (required)
- `-TargetPassword` (required, `SecureString`)
- `-TargetDatabase` (required)
- `-TargetSslMode` (default `REQUIRED`)

### Behavior flags
- `-WorkingDirectory` (default `./mysql-migration`): where the dump file is created
- `-RecreateTargetDatabase`: if set, drops and recreates the target DB
- `-FailIfTargetDbExists`: if set, aborts if target DB already exists
- `-SkipDump`: skips the dump step (useful if you already have a dump file and only want restore)
- `-SkipRestore`: skips restore step (useful to validate dump only)

## How to run

### 1) Run a full migration (dump from AWS → restore to Azure)

```powershell
pwsh .\sqlrestore.ps1 \
  -SourceHost 'mydb.abc123xyz.eu-west-1.rds.amazonaws.com' \
  -SourceUser 'awsadmin' \
  -SourcePassword (Read-Host -AsSecureString 'AWS password') \
  -SourceDatabase 'myapp' \
  -TargetHost 'myserver.mysql.database.azure.com' \
  -TargetUser 'azureadmin' \
  -TargetPassword (Read-Host -AsSecureString 'Azure password') \
  -TargetDatabase 'myapp'
```

### 2) Fail if target DB exists

```powershell
pwsh .\sqlrestore.ps1 \
  -SourceHost '...' -SourceUser '...' -SourcePassword (Read-Host -AsSecureString) -SourceDatabase 'myapp' \
  -TargetHost '...' -TargetUser '...' -TargetPassword (Read-Host -AsSecureString) -TargetDatabase 'myapp' \
  -FailIfTargetDbExists
```

### 3) Drop and recreate target DB (destructive)

```powershell
pwsh .\sqlrestore.ps1 \
  -SourceHost '...' -SourceUser '...' -SourcePassword (Read-Host -AsSecureString) -SourceDatabase 'myapp' \
  -TargetHost '...' -TargetUser '...' -TargetPassword (Read-Host -AsSecureString) -TargetDatabase 'myapp' \
  -RecreateTargetDatabase
```

## Output

- The script prints progress markers `[1/6]` … `[6/6]`.
- A dump file is created under `WorkingDirectory` with a timestamped filename:
  - Example: `mydb-20251217-142233.sql`
- It prints settings comparison and warns on mismatches.

## How it ensures collation/charset match

- It reads the **source database defaults** via:

```sql
SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME
FROM information_schema.SCHEMATA
WHERE SCHEMA_NAME = '<db>';
```

- It then creates the target database with:

```sql
CREATE DATABASE IF NOT EXISTS `<targetDb>`
  CHARACTER SET <sourceCharset>
  COLLATE <sourceCollation>;
```

This ensures **new tables created without explicit collation** inherit a matching database default.

## “Same settings” caveat (important)

The script **checks** a small set of key settings and **reports mismatches**.

Not all server-level settings can be made identical between AWS RDS and Azure MySQL Flexible Server because:
- Some are managed/locked by the platform
- Names/behavior can differ across versions

If you need strict parity beyond the currently-checked list, extend the settings query in the script to include additional `@@variables` relevant to your application (e.g., `lower_case_table_names`, `innodb_strict_mode`, `max_allowed_packet`, etc.).

## Troubleshooting

### “mysql” or “mysqldump” not found
Install MySQL client tools and ensure `mysql` and `mysqldump` are in PATH.

### TLS/SSL errors
Azure MySQL commonly requires TLS.
- Default is `REQUIRED`.
- For stricter validation (`VERIFY_CA` / `VERIFY_IDENTITY`), you may need to configure CA certificates on the machine running the script.

### Permission errors
- Source user must be able to `SELECT` schema and dump tables/procs/events.
- Target user must be able to `CREATE DATABASE` and create/insert objects.

### Dump/restore performance
- Large DBs may require running from a VM near AWS/Azure to reduce latency.
- Consider downtime window and/or replication-based strategies for near-zero downtime.

## Notes for production cutover

- Do a **test migration** first (dev/staging) to validate:
  - Schema compatibility
  - Collations
  - Application queries
  - Performance
- For production, define:
  - Freeze window / maintenance mode
  - Final dump timing
  - DNS/app config cutover
  - Rollback plan
