# create variables for resource group name and location
$resourceGroupName = "ecpl-websites-rg"
$location = "southafricanorth"
$staticwebSiteSku = "Standard"  
$frontEndRepositoryUrl = "https://dev.azure.com/eclegislature/Website/_git/ecpl-frontend.git"
$cmsRepositoryUrl = "https://dev.azure.com/eclegislature/Website/_git/ecpl-content-service.git"
$environment = "qa"


# create a resource group using az cli
az group create --name $resourceGroupName --location $location

# output the result
Write-Output "Resource group '$resourceGroupName' created in location '$location'."

# create a standard static web app using az cli
$frontEndStaticWebAppName = "ecpl-frontend-$environment"
az staticwebapp create --name $frontEndStaticWebAppName --resource-group $resourceGroupName --location $location --source --sku $staticwebSiteSku --source $frontEndRepositoryUrl --login-with-ado
Write-Output "Static web app '$frontEndStaticWebAppName' created in resource group '$resourceGroupName'."

# create a second static web app using az cli
$cmsStaticWebAppName = "ecpl-cms-$environment"
az staticwebapp create --name $cmsStaticWebAppName --resource-group $resourceGroupName  --location $location --source --sku $staticwebSiteSku --source $cmsRepositoryUrl --login-with-ado
Write-Output "Static web app '$cmsStaticWebAppName' created in resource group '$resourceGroupName'."

