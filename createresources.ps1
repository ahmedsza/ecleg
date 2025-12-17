# create variables for resource group name and location
# be sure to do az login before running this script
# run az account show to make sure you run az account show to verify

$location = "southafricanorth"
$staticwebSiteSku = "Standard"  
$frontEndRepositoryUrl = "https://dev.azure.com/eclegislature/Website/_git/ecpl-frontend.git"
$cmsRepositoryUrl = "https://dev.azure.com/eclegislature/Website/_git/ecpl-content-service.git"
$environment = "qa"
$resourceGroupName = "ecpl-websites-rg-$environment"
$staticWebAppLocation="westeurope"
$frontEndBranchName="main"
$cmsBranchName="main"
$storageAccountName = "ecplstorage$environment"
$appServicePlanName = "ecpl-appserviceplan-$environment"
$appServiceName = "ecpl-appservice-$environment"
$keyVaultName = "ecpl-keyvault-$environment"
$mysqlServerName = "ecplmysqlserver$environment"
$mysqlDatabaseName = "ecplmysqldb$environment"
$storageSku = "ZRS"  # Zone Redundant Storage


# create a resource group using az cli
az group create --name $resourceGroupName --location $location

# output the result
Write-Output "Resource group '$resourceGroupName' created in location '$location'."

# create a standard static web app using az cli
$frontEndStaticWebAppName = "ecpl-frontend-$environment"
az staticwebapp create --name $frontEndStaticWebAppName --resource-group $resourceGroupName --location $staticWebAppLocation --source $frontEndRepositoryUrl --sku $staticwebSiteSku --source $frontEndRepositoryUrl --login-with-ado --branch $frontEndBranchName
Write-Output "Static web app '$frontEndStaticWebAppName' created in resource group '$resourceGroupName'."

# create a second static web app using az cli
$cmsStaticWebAppName = "ecpl-cms-$environment"
az staticwebapp create --name $cmsStaticWebAppName --resource-group $resourceGroupName  --location $staticWebAppLocation --source $cmsRepositoryUrl --sku $staticwebSiteSku --source $cmsRepositoryUrl --login-with-ado --branch $cmsBranchName
Write-Output "Static web app '$cmsStaticWebAppName' created in resource group '$resourceGroupName'."

# create a storage account for all the documents using zone redundant storage
az storage account create --name $storageAccountName --resource-group $resourceGroupName --location $location --sku $storageSku --kind StorageV2
Write-Output "Storage account '$storageAccountName' created in resource group '$resourceGroupName'."

# create an app service

# create a keyvault

# create a mysql flexible server and database

