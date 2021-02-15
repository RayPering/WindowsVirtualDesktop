

<#    #######       Get data from webhook body    #############
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

#######       Translate Webhook Data into Variables       #######

    $aadTenantId = $Input.aadTenantId
    $azureSubId = $Input.azureSubId
    $sessionHostRg = $Input.sessionHostRg 
    $hostPoolName = $Input.hostpoolname
    $callbackurl = $Input.callbackUrl
    $deploymentName = $Input.deploymentName
    $storageAccount = $Input.storageAccount
    $shareName = $Input.shareName
    $templateFile = $Input.templateFile
    $parameterFile = $Input.parameterFile
    $vmCustomImageSourceId = $Input.vmCustomImageSourceId

#>

$aadTenantId = "23e4a13a-5331-4ee7-8b99-3146c19eb951"
$azureSubId = "0b002d7a-7032-49bd-8de6-b74909a4f8c9"
$sessionHostRg = "rg-mpn-wvd-2"
$hostPoolName = "WVD2-Desktops"
$deploymentName = "HostPoolRebuild"
$storageAccount = "peringcloudstorage"
$shareName = "resource-templates"
$templateFile = "template.json"
$parameterFile = "rebuildParameters.json"
$vmCustomImageSourceId = "/subscriptions/0b002d7a-7032-49bd-8de6-b74909a4f8c9/resourceGroups/RG-MPN-WVD-Templates/providers/Microsoft.Compute/images/WVD-Template-image-1"

#######       Section for Functions       ####### 

## Get current active user sessions
Function Get-Sessions{
    
    $currentSessions = 0
    foreach ($sessionHost in $sessionHosts) 
    {
        $count = $sessionHost.session
        $script:currentSessions += $count
    }
        Write-Output "CurrentSessions: $currentSessions"

}


#######       Script Execution       #######

## Log into Azure
<#
try 
{
    $creds = Get-AutomationPSCredential -Name 'WVD-Automation'
    Connect-AzAccount -ErrorAction Stop -ServicePrincipal -SubscriptionId $azureSubId -TenantId $aadTenantId -Credential $creds
}
catch 
{
    $ErrorMessage = $_.Exception.message
    Write-Error ("Error logging into WVD: " + $ErrorMessage)
    Break
}
#>
## Get Host Pool 
try 
{
    $hostpool = Get-AzWvdHostPool -ErrorVariable Stop -Name $hostPoolName -SubscriptionId $azureSubId -ResourceGroupName $sessionHostRg
    $hpName = $hostPool.name
    Write-Output "HostPool: $hpName"
}
catch 
{
    $ErrorMessage = $_.Exception.message
    Write-Error ("Error getting host pool details: " + $ErrorMessage)
    Break
}

## Put hosts in to drain mode
$sessionHosts = Get-AzWvdSessionHost -HostPoolName $hostPoolName -ResourceGroupName $sessionHostRg -SubscriptionId $azureSubId
Try
{
    ForEach($sessionHost in $sessionHosts){
        Update-AzWvdSessionHost -ErrorAction Stop -HostPoolName $hostPoolName -ResourceGroupName $sessionHostRg -SubscriptionId $azureSubId `
        -Name $sessionHost.name.Split('/')[1] -AllowNewSession:$false
        Write-Output "Session Host set to drain: $sessionHost.name"
    }
}
catch 
{
    $ErrorMessage = $_.Exception.message
    Write-Error ("Error setting hosts to drain: " + $ErrorMessage)
    Break
}

## Send each active session a message informing user to save and log off
Get-Sessions
If($currentSessions -gt 0){
    $sessions = Get-AzWvdUserSession -HostPoolName $hostPoolName -ResourceGroupName $sessionHostRg -SubscriptionId $azureSubId
    ForEach($Session in $sessions){
        Send-AzWvdUserSessionMessage -HostPoolName $hostPoolName -ResourceGroupName $sessionHostRg -SubscriptionId $azureSubId `
        -SessionHostName $Session.name.Split('/')[1] -UserSessionId $Session.name.Split('/')[2] -MessageTitle "Important Updates" `
        -MessageBody "Updates are about to be installed and this desktop restarted, you must save all work and log off."
        } 
    Start-Sleep -s 120
}

## Log active sessions off
Get-Sessions
If($currentSessions -gt 0){
    $sessions = Get-AzWvdUserSession -HostPoolName $hostPoolName -ResourceGroupName $sessionHostRg -SubscriptionId $azureSubId
    ForEach($Session in $sessions){
        Remove-AzWvdUserSession -HostPoolName $hostPoolName -ResourceGroupName $sessionHostRg -SubscriptionId $azureSubId `
        -SessionHostName $Session.name.Split('/')[1] -UserSessionId $Session.name.Split('/')[2] -Force
        Write-Output "User session logged off: $Session.UserPrincipalName"
        } 
}

## Count total number of session hosts
$totalHosts = $sessionHosts.count

## Remove all session hosts from host pool
try {
    ForEach($sessionHost in $sessionHosts){
    Remove-AzWvdSessionHost -ErrorAction Stop -HostPoolName $hostPoolName -ResourceGroupName $sessionHostRg -SubscriptionId $azureSubId `
    -Name $sessionHost.name.Split('/')[1] -Force
    Write-Output "Session Host: $sessionhost.Name Removed from host pool: $hsotPoolName"
    }
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ("Error removing session hosts from hostpool: " + $ErrorMessage)
    Break
}

## Delete resources
    # Delete VMs
    Select-AzSubscription -Subscription $azureSubId
    $resources = Get-AzResource -ResourceGroupName $sessionHostRg | Where ResourceType -EQ Microsoft.Compute/virtualMachines
    try {
        ForEach($resource in $resources){
            Remove-AzResource -ErrorAction Stop -ResourceId $resource.ResourceId -Force
            Write-Output "Resource deleted: $resource.name"
        }
    }
    catch {
        $ErrorMessage = $_.Exception.message
        Write-Error ("Error removing resources: " + $ErrorMessage)
        Break
    }


    # Delete remaining resources
    Select-AzSubscription -Subscription $azureSubId
    $resources = Get-AzResource -ResourceGroupName $sessionHostRg | Where ResourceType -NE Microsoft.DesktopVirtualization/hostpools 
    try {
        ForEach($resource in $resources){
            Remove-AzResource -ErrorAction Stop -ResourceId $resource.ResourceId -Force
            Write-Output "Resource deleted: $resource.name"
        }
    }
    catch {
        $ErrorMessage = $_.Exception.message
        Write-Error ("Error removing resources: " + $ErrorMessage)
        Break
    }

## Generate registration key




## Deploy hosts

    # Set Storage Context
    $storageAccountKey = Get-AutomationVariable -Name 'StorageKey'
    $Context = New-AzStorageContext -StorageAccountName $storageAccount -StorageAccountKey $storageAccountKey
        
    # Get Template File
    Get-AzStorageFileContent -ShareName $shareName -Context $context -Path $templateFile -Destination 'C:\Temp' -Force
    $templateFilePath = Join-path -path 'C:\temp' -ChildPath $templateFile
        
    # Get Parameter File
    Get-AzStorageFileContent -ShareName $shareName -Context $context -Path $parameterFile -Destination 'C:\Temp' -Force
    $parametersFilePath = Join-path -path 'C:\temp' -ChildPath $parameterFile

    # Update Parameter File
    # (Get-Content -Path $$parametersFilePath) -replace 'ReplaceInstancesNumber', $totalHosts | Set-Content -Path $parametersFilePath
    (Get-Content -Path $parametersFilePath) -replace 'ReplaceSourceID', $vmCustomImageSourceId | Set-Content -Path $parametersFilePath
    Write-Output "Updated parameter file"

    # Start the deployment
    Write-Output "Starting deployment...";
        if(Test-Path $parametersFilePath) {
            Write-Output "Parameter file found. Continuing"
            Try
            {
                New-AzResourceGroupDeployment -ResourceGroupName $sessionHostRg -Name $deploymentName -TemplateFile $templateFilePath -TemplateParameterFile $parametersFilePath;
            }
            Catch
            {
                $ErrorMessage = $_.Exeption.Message
                Write-Error ("Error unable to complete deployment: " + $ErrorMessage)
                Break
            }
        }
        Else
        {
            Write-Output "Parameter file not found. Stopping"
            Break
        }       