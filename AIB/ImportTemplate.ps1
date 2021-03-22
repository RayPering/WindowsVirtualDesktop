

# Set variables
$imageResourceGroup = "rg-azureImageBuilder"
$identityName = "aibIdentity1616061257"
$location = "EastUS"
$DistLocation = "UKSouth"
$subscriptionID = "0b002d7a-7032-49bd-8de6-b74909a4f8c9"
$imageTemplateName = "WVDImage"
$runOutputName = "sigOutput"

$templateUrl = "https://raw.githubusercontent.com/RayPering/WindowsVirtualDesktop/Dev/AIB/NewBuildSimple.json"
$templateFilePath = "NewBuildSimple.json"

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
((Get-Content -path $templateFilePath -Raw) -replace '<imgBuilderId>',$idenityNameResourceId) | Set-Content -Path $templateFilePath

# Submit template
New-AzResourceGroupDeployment -ResourceGroupName $imageResourceGroup -TemplateFile $templateFilePath -api-version "2020-02-14" -imageTemplateName $imageTemplateName -svclocation $location