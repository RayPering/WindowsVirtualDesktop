<#
.SYNOPSIS
    Automate the build and distribution of WVD images
.DESCRIPTION
    This runbook does the following:
        Inports an image template from a GitHub repo
        Triggers the build of the image template and distributes the final image
        The runbook could be triggered via a power app, api call or logic using a webhook
        Logic appexample below shows basic HHTP WebHook trigger

.LOGIC_APP_EXAMPLE
    {
        "definition": { 
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "actions": {},
            "contentVersion": "1.0.0.0",
            "outputs": {},
            "parameters": {},
            "triggers": {
                "HTTP_Webhook": {
                    "inputs": {
                        "subscribe": {
                            "body": {
                                "callbackUrl": "@{listCallbackURL()}",
                                "aibResourceGroup": "<AIBResourceGroup>",
                                "imageResourceGroup": "<ImageDistributionResourceGroup>",
                                "identityName": "<AIBIdentity>",
                                "location": "<BuildRegion>",
                                "DistLocation": "<ImageDistributionRegion>",
                                "subscriptionID": "<SubscriptionID>",
                                "aadTenantId": "<AADTenantID>",
                                "imageTemplateName": "<ImageTemplateName>",
                                "imageDefName": "<SIGImageDefinition>",
                                "sigGalleryName": "<SIGName>",
                                "runOutputName": "sigOutput",
                                "templateUrl": "<TemplateURL>",
                                "templateFilePath": "<TemplateName>"
                            },
                            "method": "POST",
                            "uri": "<RunbookWebhookUrl>"
                        },
                        "unsubscribe": {}
                    },
                    "type": "HttpWebhook"
                }
            }
        },
        "parameters": {}
    }
.NOTES 
    Author:       Ray Pering
    Version:      1.0.0     Initial Build
#>

# Get data from webhook body
param(
    [Parameter(mandatory = $false)]
    [object]$WebHookData
)
# If runbook was called from Webhook, WebhookData will not be null.
if ($WebHookData) {

    # Collect properties of WebhookData
    $WebhookName = $WebHookData.WebhookName
    $WebhookHeaders = $WebHookData.RequestHeader
    $WebhookBody = $WebHookData.RequestBody

    # Collect individual headers. Input converted from JSON.
    $From = $WebhookHeaders.From
    $Input = (ConvertFrom-Json -InputObject $WebhookBody)
}
else
{
    Write-Error -Message 'Runbook was not started from Webhook' -ErrorAction stop
}

# Convert webhook data to variables
$callbackUrl = $Input.callbackUrl
$aibResourceGroup = $Input.aibResourceGroup
$imageResourceGroup = $Input.imageResourceGroup
$identityName = $Input.identityName
$location = $Input.location
$DistLocation = $Input.DistLocation
$subscriptionID = $Input.subscriptionID
$aadTenantId = $Input.aadTenantId
$imageTemplateName = $Input.imageTemplateName
$imageDefName = $Input.imageDefName
$sigGalleryName = $Input.sigGalleryName
$runOutputName = $Input.runOutputName

$templateUrl = $Input.templateUrl
$templateFilePath = $Input.templateFilePath

## Log into Azure WVD
try 
{
    $creds = Get-AutomationPSCredential -Name 'WVD-Automation'
    Connect-AzAccount -ErrorAction Stop -ServicePrincipal -SubscriptionId $subscriptionID -TenantId $aadTenantId -Credential $creds
}
catch 
{
    $ErrorMessage = $_.Exception.message
    Write-Error ("Error logging into WVD: " + $ErrorMessage)
    Break
}

# Get managed identity
$identityNameResourceId = $(Get-AzUserAssignedIdentity -ResourceGroupName $aibResourceGroup -Name $identityName).Id

# Download template
Invoke-WebRequest -Uri $templateUrl -OutFile $templateFilePath -UseBasicParsing

# Update template
((Get-Content -path $templateFilePath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<rgName>',$imageResourceGroup) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region>',$location) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<runOutputName>',$runOutputName) | Set-Content -Path $templateFilePath

((Get-Content -path $templateFilePath -Raw) -replace '<imageDefName>',$imageDefName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<sharedImageGalName>',$sigGalleryName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region1>',$distLocation) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<imgBuilderId>',$identityNameResourceId) | Set-Content -Path $templateFilePath

# Write comlete template to output
Write-Output (Get-Content -Path $templateFilePath -Raw)

# Submit template
try {
    New-AzResourceGroupDeployment -ResourceGroupName $aibResourceGroup -TemplateFile $templateFilePath -api-version "2020-02-14" -imageTemplateName $imageTemplateName -svclocation $location
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ("Error: " + $ErrorMessage)
    Break
}

# Wait for submit to complete
while (!(Get-AzImageBuilderTemplate -ImageTemplateName $imageTemplateName -ResourceGroupName $aibResourceGroup -ErrorAction SilentlyContinue)) {
    Start-Sleep 10    
}

# Deploy template
try {
    Start-AzImageBuilderTemplate -ResourceGroupName $aibResourceGroup -Name $imageTemplateName -NoWait
    Invoke-RestMethod -Method Post -Uri $callbackurl
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ("Error: " + $ErrorMessage)
    Break
}