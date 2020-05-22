<#
.SYNOPSIS
    Automate the WVD starting and stop of the WVD session hosts based 
    on the amount of users sessions
.DESCRIPTION
    This powershell script does the following:
        Automatically start, stop and deploy session hosts in the WVD environment based on the number of users logged in
        Determines the number of servers that are required to be running to meet the specifications outlined
            (number is divided by the definition of maximum session set as defined in the depth-first load balancing settings for the pool) 
        Session hosts are scaled up or down based on that metric
    
.REQUIREMENTS    
        An Azure Automation Account
        A Service Principal for WVD
        A runbook with an enabled webhook
        The corresponding secret url for the webhook
        An Azure Logic App configured to manipulate the runbook via the webhook
        WVD Host Pool must be configured for Depth First load balancing
        The WVD Service Principal for the Automation Account must be a "Contributor" role for the WVD Resource Groups
        A template and parmater json file saved in blob storage
        Azure Automation Account runbook needs the following added PowerShell modules:
            Az.account, Az.compute, Az.Storage and Az.DesktopVirtualization
        
.LOGIC_APP_EXAMPLE
    {
        "definition": { 
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "actions": {
                "HTTP_Webhook": {
                    "inputs": {
                        "subscribe": {
                            "body": {
                                "aadTenantId": "<AADTenant>",
                                "azureSubId": "<AzureSubscriptionId>",
                                "callbackUrl": "@{listCallbackUrl()}",
                                "endPeakTime": "18:00:00",
                                "hostpoolname": "<WVDHostPoolName>",
                                "peakServerStartThreshold": "2",
                                "peakday": [
                                    "Monday",
                                    "Tuesday",
                                    "Wednesday",
                                    "Thursday",
                                    "Friday"
                                ],
                                "serverStartThreshold": "1",
                                "sessionHostRg": "<WVDHostPoolResourceGroup>",
                                "startPeakTime": "06:00:00",
                                "usePeak": "yes",
                                "utcoffset": "-1"
                                "deploymentName": "HostExpansion"
                                "storageAccount": "<StorageAccount>"
                                "shareName": "<ShareName>"
                                "templateFile": "template.json"
                                "parameterFile": "parameters.json"
                            },
                            "method": "POST",
                            "uri": "<RunbookWebhookUrl>"
                        },
                        "unsubscribe": {}
                    },
                    "runAfter": {},
                    "type": "HttpWebhook"
                }
            },
            "contentVersion": "1.0.0.0",
            "outputs": {},
            "parameters": {},
            "triggers": {
                "Recurrence": {
                    "recurrence": {
                        "frequency": "Minute",
                        "interval": 5
                    },
                    "type": "Recurrence"
                }
            }
        },
        "parameters": {}
    }
.NOTES 
    Author:       Ray Pering
    Version:      1.0.0     Initial Build Donald Harris see here for her information https://github.com/eulogious/AzureRunbooks/blob/master/AutoScaleWVD.ps1
                  2.0.0     Updated to fit the spring release of WVD
#>

    #######       Get data from webhook body    #############
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

    $serverStartThreshold = $Input.serverStartThreshold
    $usePeak = $Input.usePeak
    $peakServerStartThreshold = $Input.peakServerStartThreshold
    $startPeakTime = $Input.startPeakTime
    $endPeakTime = $Input.endPeakTime
    $utcoffset = $Input.utcoffset
    $peakDay = $Input.peakDay 
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


#######       Section for Functions       ####### 

  # Convert UTC to Local Time

    function Convert-UTCtoLocalTime
    {
        param(
            $TimeDifferenceInHours
    )
   
        $UniversalTime = (Get-Date).ToUniversalTime()
        $TimeDifferenceMinutes = 0
        if ($TimeDifferenceInHours -match ":") {
            $TimeDifferenceHours = $TimeDifferenceInHours.Split(":")[0]
            $TimeDifferenceMinutes = $TimeDifferenceInHours.Split(":")[1]
        }
        else {
            $TimeDifferenceHours = $TimeDifferenceInHours
        }
        #Azure is using UTC time, justify it to the local time
        $ConvertedTime = $UniversalTime.AddHours($TimeDifferenceHours).AddMinutes($TimeDifferenceMinutes)
        return $ConvertedTime
    }

  # Start Session Hosts

    function Start-SessionHost 
    {
        param   
        (
            $SessionHosts,
            $sessionsToStart
        )
            
        # Number of off hosts accepting connections
        $offSessionHosts = $sessionHosts | Where-Object { $_.status -eq "Unavailable" }
        $offSessionHostsCount = $offSessionHosts.count
        Write-Output "Off Session Hosts $offSessionHostsCount"
        Write-Output ($offSessionHost | Out-String)
        
        if ($offSessionHostsCount -eq 0 ) 
        {   
            Write-Output "Start threshold met, but the status variable is still not finding an available host to start. Will try to deploy another host"
            Deploy-SessionHosts
        }
        else 
        {
            if  ($sessionsToStart -gt $offSessionHostsCount)
                {$sessionsToStart = $offSessionHostsCount}
            $counter = 0
                Write-Output "Conditions met to start a host"
            while ($counter -lt $sessionsToStart)
            {
                $startServerName = ($offSessionHosts | Select-Object -Index $counter).Name
                Write-Output "Server that will be started $startServerName"
                try
                {  
                    # Start the VM
                    $creds = Get-AutomationPSCredential -Name 'WVD-Automation'  
                    Connect-AzAccount -ErrorAction Stop -ServicePrincipal -SubscriptionId $azureSubId -TenantId $aadTenantId -Credential $creds
                    $vmName = $startServerName.Split('.')[0]
                    $vmName = $vmName.Split('/')[1]
                    Start-AzVM -ErrorAction Stop -ResourceGroupName $sessionHostRg -Name $vmName
                }
                catch 
                {
                    $ErrorMessage = $_.Exception.message
                    Write-Error ("Error starting the session host: " + $ErrorMessage)
                    Break
                }
            $counter++
            }
        }
    }

  # Stop Session Hosts

    function Stop-SessionHost 
    {
        param 
        (
            $SessionHosts,
            $sessionsToStop
        )

        ##  Get computers running with no users
        $emptyHosts = $sessionHosts | Where-Object { $_.Session -eq 0 -and $_.Status -eq 'Available' }
        $emptyHostsCount = $emptyHosts.count 
        ##  Count hosts without users and shut down all unused hosts until desire threshold is met
        Write-Output "Evaluating servers to shut down"
            
        if ($emptyHostsCount -eq 0) 
            {Write-Error "Error: No hosts available to shut down"}
        else
        {
            if ($sessionsToStop -gt $emptyHostsCount)
            {$sessionsToStop = $emptyHostsCount}
            $counter = 0
            Write-Output "Conditions met to stop a host"
            while ($counter -lt $sessionsToStop) 
                {
                $shutServerName = ($emptyHosts | Select-Object -Index $counter).Name
                Write-Output "Shutting down server $shutServerName"
                try 
                {
                    # Stop the VM
                    $creds = Get-AutomationPSCredential -Name 'WVD-Automation'
                    Connect-AzAccount -ErrorAction Stop -ServicePrincipal -SubscriptionId $azureSubId -TenantId $aadTenantId -Credential $creds
                    $vmName = $shutServerName.Split('.')[0]
                    $vmName = $vmName.Split('/')[1]
                    Stop-AzVM -ErrorAction Stop -ResourceGroupName $sessionHostRg -Name $vmName -Force
                }
                catch 
                {
                    $ErrorMessage = $_.Exception.Message
                    Write-Error ("Error stopping the VM: " + $ErrorMessage)
                    Break  
                }
            $counter++
            }   
        }
    }

    # Deploy Session Hosts
    Function Deploy-SessionHosts {
    
    # Set Storage Context
    $storageAccountKey = Get-AutomationVariable -Name 'StorageKey'
    $Context = New-AzStorageContext -StorageAccountName $storageAccount -StorageAccountKey $storageAccountKey
        
    # Get Template File
    Get-AzStorageFileContent -ShareName $shareName -Context $context -Path $templateFile -Destination 'C:\Temp' -Force
    $templateFilePath = Join-path -path 'C:\temp' -ChildPath $templateFile
        
    # Get Parameter File
    Get-AzStorageFileContent -ShareName $shareName -Context $context -Path $parameterFile -Destination 'C:\Temp' -Force
    $parametersFilePath = Join-path -path 'C:\temp' -ChildPath $parameterFile

    # Get highest VM number and increment by 1
    $VMs = (Get-AzVm -ResourceGroupName $sessionHostRg).Name
    $VMs = ($VMs | measure -Maximum).Maximum
    $VMs = $VMs.split('-')[2]
    $VMs = $VMs.ToInt32($null)
    $VMs++

    # Update starting VM number in parameter file
    (Get-Content -Path $parametersFilePath) -replace 'ReplaceIntNumber', $VMs | Set-Content -Path $parametersFilePath

    # Start the deployment
    Write-Output "Starting deployment...";
        if(Test-Path $parametersFilePath) {
            Write-Output "Parameter file found. Continuing"
            Try
            {
                New-AzResourceGroupDeployment -ResourceGroupName $sessionHostRg -Name $deploymentName -TemplateFile $templateFilePath`
                -TemplateParameterFile $parametersFilePath;
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
    }

#######       Script Execution       #######

## Log into Azure

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


## Get Host Pool 
try 
{
    $hostpool = Get-AzWvdHostPool -ErrorVariable Stop -Name $hostPoolName -SubscriptionId $azureSubId -ResourceGroupName $sessionHostRg
    Write-Output "HostPool:"
    Write-Output $hostPool.Name
}
catch 
{
    $ErrorMessage = $_.Exception.message
    Write-Error ("Error getting host pool details: " + $ErrorMessage)
    Break
}

## Verify load balancing is set to Depth-first
if ($hostPool.LoadBalancerType -ne "DepthFirst") 
{
    Write-Error "Error: Host pool not set to Depth-First load balancing. This script requires Depth-First load balancing to execute"
    exit
}

## Check if peak time and adjust threshold
     # Converting date time from UTC to Local
	$dateTime = Convert-UTCtoLocalTime -TimeDifferenceInHours $utcoffset
    	$BeginPeakDateTime = [datetime]::Parse($dateTime.ToShortDateString() + ' ' + $startPeakTime)
	$EndPeakDateTime = [datetime]::Parse($dateTime.ToShortDateString() + ' ' + $EndPeakTime)
    Write-Output "Current Day, Date, and Time:"
    Write-Output $dateTime
    $dateDay = (((get-date).ToUniversalTime()).AddHours($utcOffset)).dayofweek
    #Write-Output $dateDay
if ($dateTime -gt $BeginPeakDateTime -and $dateTime -lt $EndPeakDateTime -and $dateDay -in $peakDay -and $usePeak -eq "yes") 
    { Write-Output "Threshold set for peak hours" 
    $serverStartThreshold = $peakServerStartThreshold }
else 
    { Write-Output "Thershold set for outside of peak hours" }

## Get the Max Session Limit on the host pool
## This is the total number of sessions per session host
    $maxSession = $hostPool.MaxSessionLimit
    Write-Output "MaxSession: $maxSession"

# Find the total number of session hosts
# Exclude servers that do not allow new connections
try 
{
   $SessionHosts = Get-AzWvdSessionHost -ErrorAction Stop -HostPoolName $hostPoolName -ResourceGroupName $sessionHostRg -SubscriptionId $azureSubId | `
   Where-Object { $_.AllowNewSession -eq $true}
}
catch 
{
   $ErrorMessage = $_.Exception.message
   Write-Error ("Error getting session hosts details: " + $ErrorMessage)
   Break
}

## Get current active user sessions
    $currentSessions = 0
foreach ($sessionHost in $sessionHosts) 
{
   $count = $sessionHost.sessions
   $currentSessions += $count
}
    Write-Output "CurrentSessions"
    Write-Output $currentSessions

## Number of running and available session hosts
## Host that are shut down are excluded
    $runningSessionHosts = $sessionHosts | Where-Object { $_.Status -eq "Available" }
    $runningSessionHostsCount = $runningSessionHosts.count
    Write-Output "Running Session Host $runningSessionHostsCount"
    Write-Output ($runningSessionHosts | Out-string)

# Target number of servers required running based on active sessions, Threshold and maximum sessions per host
    $sessionHostTarget = [math]::Ceiling((($currentSessions + $serverStartThreshold) / $maxSession))

if ($runningSessionHostsCount -lt $sessionHostTarget) 
{
   Write-Output "Running session host count $runningSessionHosts is less than session host target count $sessionHostTarget, starting sessions"
   $sessionsToStart = ($sessionHostTarget - $runningSessionHostsCount)
   Start-SessionHost -Sessionhosts $sessionHosts -sessionsToStart $sessionsToStart
   Invoke-RestMethod -Method Post -Uri $callbackurl
}
elseif ($runningSessionHostsCount -gt $sessionHostTarget) 
{
   Write-Output "Running session hosts count $runningSessionHostsCount is greater than session host target count $sessionHostTarget, stopping sessions"
   $sessionsToStop = ($runningSessionHostsCount - $sessionHostTarget)
   Stop-SessionHost -SessionHosts $sessionHosts -sessionsToStop $sessionsToStop
   Invoke-RestMethod -Method Post -Uri $callbackurl
}
else 
{
 Write-Output "Running session host count $runningSessionHostsCount matches session host target count $sessionHostTarget, doing nothing"
 Invoke-RestMethod -Method Post -Uri $callbackurl    
}