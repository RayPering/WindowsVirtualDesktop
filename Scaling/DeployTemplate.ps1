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
        Write-Host "Resource group '$ResourceGroupName' does not exist. Resouce group will be created.";
        if(!$ResourceGroupLocation) {
            $ResourceGroupLocation = Read-Host "resourceGroupLocation";
        }
        Write-Host "Creating resource group '$ResourceGroupName' in location '$ResourceGroupLocation'";
        New-AzResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation
    }
    else{
        Write-Host "Using existing resource group '$ResourceGroupName'";
    }

    # Start the deployment
    Write-Host "Starting deployment...";
    if(Test-Path $ParametersFilePath) {
        New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -TemplateFile $TemplateFilePath -TemplateParameterFile $ParametersFilePath;
    } else {
        New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -TemplateFile $TemplateFilePath;
    }

}

#######       Section for Variables       #######

$Template = 'https://peringcloudstorage.file.core.windows.net/resource-templates/template.json'
$Parameters = 'https://peringcloudstorage.file.core.windows.net/resource-templates/parameters.json'

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
