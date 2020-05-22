


# Get Parameter File
#$StorageAccountKey = Get-AzAutomationVariable -Name 'StorageKey'
$Context = New-AzStorageContext -StorageAccountName 'peringcloudstorage' -StorageAccountKey ylhSBw7vy1FdKVFmWG8iZvrKYX5yTPbE3BCjcLAIzVrH9L7JoDj4jRDn+j9XDio2d2j38DuM1xPUOwwXqY4hTQ== #$StorageAccountKey
Get-AzStorageFileContent -ShareName 'resource-templates' -Context $context -Path 'parameters.json' -Destination 'C:\Temp' -Force
$ParametersFilePath = Join-path -path 'C:\temp' -ChildPath 'parameters.json'

# Get highes VM number and increment by 1
$VMs = (Get-AzVm -ResourceGroupName RG-MPN-WVD-2).Name
$VMs = ($VMs | measure -Maximum).Maximum
$VMs = $VMs.split('-')[2]
$VMs = $VMs.ToInt32($null)
$VMs++

# Update starting VM number in parameter file
(Get-Content -Path $ParametersFilePath) -replace 'ReplaceIntNumber', $VMs | Set-Content -Path $ParametersFilePath
