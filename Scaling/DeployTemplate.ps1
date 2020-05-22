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

$azureSubId = '0b002d7a-7032-49bd-8de6-b74909a4f8c9'
$aadTenantId = '23e4a13a-5331-4ee7-8b99-3146c19eb951'
$ResourceGroupName = 'RG-MPN-WVD-2'
$ResourceGroupLocation = 'UK South'
$DeploymentName = 'PoolExpansion'

$StorageAccountKey = Get-AutomationVariable -Name 'StorageKey'
$Context = New-AzStorageContext -StorageAccountName 'peringcloudstorage' -StorageAccountKey $StorageAccountKey

# Get Template File
Get-AzStorageFileContent -ShareName 'resource-templates' -Context $context -Path 'template.json' -Destination 'C:\Temp' -Force
$TemplateFilePath = Join-path -path 'C:\temp' -ChildPath 'template.json'

# Get Parameter File
Get-AzStorageFileContent -ShareName 'resource-templates' -Context $context -Path 'parameters.json' -Destination 'C:\Temp' -Force
$ParametersFilePath = Join-path -path 'C:\temp' -ChildPath 'parameters.json'

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

## Get highes VM number and increment by 1
$VMs = (Get-AzVm -ResourceGroupName RG-MPN-WVD-2).Name
$VMs = ($VMs | measure -Maximum).Maximum
$VMs = $VMs.split('-')[2]
$VMs = $VMs.ToInt32($null)
$VMs++

## Update starting VM number in parameter file
(Get-Content -Path $ParametersFilePath) -replace 'ReplaceIntNumber', $VMs | Set-Content -Path $ParametersFilePath

## Run Deployment

Deploy
