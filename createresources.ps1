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
$storageSku = "StandardV2_ZRS"  # Zone Redundant Storage (if supported in region)
$appServicePlanSKU="P1v3"  # Premium v3 for App Service Plan
$workerCount=2
$mysqlAdminUserName="ecpladminuser"
$mysqlAdminPassword=""  # Replace with a secure password
$mysqlSku="Standard_B1ms"
$logAnalyticsWorkspaceName = "ecpl-loganalytics-$environment"
$appInsightsName = "ecpl-appinsights-$environment"


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

az storage account create --name $storageAccountName --resource-group $resourceGroupName --location $location --sku Standard_ZRS --kind StorageV2
Write-Output "Storage account '$storageAccountName' created in resource group '$resourceGroupName' with zone redundancy."

# create an app service with zone redundancy 
az appservice plan create --name $appServicePlanName --resource-group $resourceGroupName --location $location --sku $appServicePlanSKU --is-linux --zone-redundant
Write-Output "App Service Plan '$appServicePlanName' created in resource group '$resourceGroupName' with zone redundancy enabled."

# create an app service with support for expres/node

az webapp create --name $appServiceName --resource-group $resourceGroupName --plan $appServicePlanName --runtime "NODE|20-lts" --number-of-workers $workerCount
Write-Output "App Service '$appServiceName' created in resource group '$resourceGroupName'."


# create a keyvault
az keyvault create --name $keyVaultName --resource-group $resourceGroupName --location $location
Write-Output "Key Vault '$keyVaultName' created in resource group '$resourceGroupName'."

# create a mysql flexible server and database
az mysql flexible-server create --name $mysqlServerName --resource-group $resourceGroupName --location $location --admin-user $mysqlAdminUserName --admin-password $mysqlAdminPassword --sku-name $mysqlSku --zone 1
Write-Output "MySQL Flexible Server '$mysqlServerName' created in resource group '$resourceGroupName'."

# create a mysql database
az mysql flexible-server db create --name $mysqlDatabaseName --resource-group $resourceGroupName --server-name $mysqlServerName
Write-Output "MySQL Database '$mysqlDatabaseName' created on server '$mysqlServerName'."

# create a log analytics workspace with support for app insights
az monitor log-analytics workspace create --resource-group $resourceGroupName --workspace-name $logAnalyticsWorkspaceName --location $location
Write-Output "Log Analytics Workspace '$logAnalyticsWorkspaceName' created in resource group '$resourceGroupName'."
# create an application insights resource
az monitor app-insights component create --app $appInsightsName --location $location --resource -group $resourceGroupName --workspace $logAnalyticsWorkspaceName
Write-Output "Application Insights '$appInsightsName' created in resource group '$resourceGroupName'."