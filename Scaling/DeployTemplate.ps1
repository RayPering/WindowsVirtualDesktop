<#
.SYNOPSIS
    Automate the deployment of an ARM template
.DESCRIPTION
    This powershell script does the following:
        Deploys an ARM template within azure
    
.NOTES 
    Author:       Ray Pering
    Version:      0.0.1     Initial build
#>



#######       Section for Functions       ####### 

# Fuction to run the deployments
Function Deploy {

    # Create or check for existing resource group
    $ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if(!$ResourceGroup)
    {
        Write-Output "Resource group '$ResourceGroupName' does not exist. Resouce group will be created.";
        if(!$ResourceGroupLocation) {
            $ResourceGroupLocation = Read-Host "resourceGroupLocation";
        }
        Write-Output "Creating resource group '$ResourceGroupName' in location '$ResourceGroupLocation'";
        New-AzResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation
    }
    else{
        Write-Output "Using existing resource group '$ResourceGroupName'";
    }

    # Start the deployment
    Write-Output "Starting deployment...";
    if(Test-Path $ParametersFilePath) {
        New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -TemplateFile $TemplateFilePath -TemplateParameterFile $ParametersFilePath;
    } else {
        New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -TemplateFile $TemplateFilePath;
    }

}

#######       Section for Variables       #######

$TemplateFilePath = 'https://peringcloudstorage.file.core.windows.net/resource-templates/template.json'
$ParametersFilePath = 'https://peringcloudstorage.file.core.windows.net/resource-templates/parameters.json'
$azureSubId = '0b002d7a-7032-49bd-8de6-b74909a4f8c9'
$aadTenantId = '23e4a13a-5331-4ee7-8b99-3146c19eb951'
$ResourceGroupName = 'RG-MPN-WVD-2'
$ResourceGroupLocation = 'UK South'
$DeploymentName = 'PoolExpansion'

#######       Script Execution       #######

## Log into Azure WVD

try 
{
    $creds = Get-AutomationPSCredential -Name 'WVD-Automation'
    Connect-AzAccount -ErrorAction Stop -ServicePrincipal -SubscriptionId $azureSubId -TenantId $aadTenantId -Credential $creds
}
catch 
{
    $ErrorMessage = $_.Exception.message
    Write-Error ("Error logging in: " + $ErrorMessage)
    Break
}

## Run Deployment

Deploy
