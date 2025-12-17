$rg = "<resourceGroupName>"
$acct = "<storageAccountName>"
$container = "<containerName>"

# create the container if it doesn't exist
az storage container create --name $container --account-name $acct --public-access blob

# Key
$key = (az storage account keys list -g $rg -n $acct --query "[0].value" -o tsv)

# Expiry (example: 24 hours from now)
$expiry = (Get-Date).ToUniversalTime().AddHours(24).ToString("yyyy-MM-ddTHH:mmZ")

# Full container permissions
$sas = az storage container generate-sas `
  --account-name $acct `
  --account-key $key `
  --name $container `
  --permissions racwdl `
  --https-only `
  --expiry $expiry `
  -o tsv

$sasUrl = "https://$acct.blob.core.windows.net/$container?$sas"

git clone https://github.com/ahmedsza/awss3toazureblobcopy.git
 
Set-Location awss3toazureblobcopy

# create a pythin virtual environment
python -m venv venv
# activate the virtual environment
.\venv\Scripts\Activate.ps1
# install the required packages
pip install -r requirements.txt
# run the copy script
$env:S3_BUCKET = "YOUR-BUCKET-NAME"
$env:AWS_REGION = "YOUR-AWS-REGION"  # e.g., us-east-1, af-south-1
$env:AWS_ACCESS_KEY_ID = "YOUR-AWS-ACCESS-KEY"
$env:AWS_SECRET_ACCESS_KEY = "YOUR-AWS-SECRET-KEY"
$env:AZURE_BLOB_SAS_URL = $sasUrl
python reads3_copyazure.py 

