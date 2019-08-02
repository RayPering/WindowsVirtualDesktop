<#
 .SYNOPSIS
    Deploys a template to Azure

 .DESCRIPTION
    Deploys an Azure Resource Manager template
#>

#Fuction to run the deployments
Function Deploy {

    #Create or check for existing resource group
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

    #Start the deployment
    Write-Host "Starting deployment...";
    if(Test-Path $ParametersFilePath) {
        New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -TemplateFile $TemplateFilePath -TemplateParameterFile $ParametersFilePath;
    } else {
        New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -TemplateFile $TemplateFilePath;
    }

}

$Script:ErrorActionPreference = "Stop"

#Define core template path
$Script:CoreTemplatePath = "Template.json"

#Import json
If (Test-Path -Path $CoreTemplatePath) {
    $CoreTemplate = Get-Content -Path $CoreTemplatePath | ConvertFrom-Json
}

#Import module
Import-Module -Name Az

#Sign in
Write-Host "Logging in..."
Connect-AzAccount

#Select subscription
$Script:SubscriptionId = $CoreTemplate.subscriptionId
Write-Host "Selecting subscription '$SubscriptionId'"
$Script:azSub = Get-AzSubscription -SubscriptionId $SubscriptionId
Select-AzSubscription -SubscriptionObject $azSub

#Create VNet if required
If ($CoreTemplate.VNet -eq "Yes") {

    #Create variables
    $ResourceGroupName = $CoreTemplate.VNetresourceGroup
    $ResourceGroupLocation = $CoreTemplate.azLocation
    $DeploymentName = $CoreTemplate.VNetDeploymentName
    $templateFilePath = "VNetTemplate.json"
    $parametersFilePath = "VNetParameters.json"
    
    #Run Deployment
    Deploy
}

#Create Domain controller if required
If ($CoreTemplate.DC -eq "Yes") {

   #Create variables
   $ResourceGroupName = $CoreTemplate.VMresourceGroup
   $ResourceGroupLocation = $CoreTemplate.azLocation
   $DeploymentName = $CoreTemplate.DCDeploymentName
   $templateFilePath = "DCTemplate.json"
   $parametersFilePath = "DCParameters.json"
   
   #Run Deployment
   Deploy
}

#Create File Server if required
If ($CoreTemplate.File -eq "Yes") {

   #Create variables
   $ResourceGroupName = $CoreTemplate.VMresourceGroup
   $ResourceGroupLocation = $CoreTemplate.azLocation
   $DeploymentName = $CoreTemplate.FileServerDeploymentName
   $templateFilePath = "FSTemplate.json"
   $parametersFilePath = "FSParameters.json"
   
   #Run Deployment
   Deploy
}