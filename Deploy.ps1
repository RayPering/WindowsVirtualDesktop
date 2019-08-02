<#
 .SYNOPSIS
    Deploys a template to Azure

 .DESCRIPTION
    Deploys an Azure Resource Manager template

 .PARAMETER subscriptionId
    The subscription id where the template will be deployed.

 .PARAMETER resourceGroupName
    The resource group where the template will be deployed. Can be the name of an existing or a new resource group.

 .PARAMETER resourceGroupLocation
    Optional, a resource group location. If specified, will try to create a new resource group in this location. If not specified, assumes resource group is existing.

 .PARAMETER deploymentName
    The deployment name.

 .PARAMETER templateFilePath
    Optional, path to the template file. Defaults to template.json.

 .PARAMETER parametersFilePath
    Optional, path to the parameters file. Defaults to parameters.json. If file is not found, will prompt for parameter values based on template.

 .Example
  .\Deploy-Template.ps1 -SubscriptionId *****  -ResourceGroupName *** -ResourceGroupLocation CentralUS -DeploymentName *** -templateFilePath .\template.json -parametersFilePath .\parameters.json
#>

<#
param(
 [Parameter(Mandatory=$True)]
 [string]
 $SubscriptionId,

 [Parameter(Mandatory=$True)]
 [string]
 $ResourceGroupName,

 [string]
 $ResourceGroupLocation,

 [Parameter(Mandatory=$True)]
 [string]
 $DeploymentName,

 [string]
 $templateFilePath = "template.json",

 [string]
 $parametersFilePath = "parameters.json"
)
#>

Function Deploy {

    #Create or check for existing resource group
    $ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if(!$ResourceGroup)
    {
        Write-Host "Resource group '$ResourceGroupName' does not exist. To create a new resource group, please enter a location.";
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