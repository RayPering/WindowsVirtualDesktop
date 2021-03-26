 <#
.Synopsis
Created by: Ray Pering
Downloads and installs the latest Microsoft Teams and Websocket for WVD environments

.Description
Adds WVD reg key
Downloads and installs the C++ Redistributable
Downloads and installs the Teams WebSocket
Downloads and installs the Teams in Machine mode
#>

# Set Registry Key
write-host 'AIB Customisation: Set required regKey'
New-Item -Path HKLM:\SOFTWARE\Microsoft -Name "Teams" 
New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Teams -Name "IsWVDEnvironment" -Type "Dword" -Value "1"
write-host 'AIB Customisation: Finished Set required regKey'

# Install C++
write-host 'AIB Customisation: Install the latest Microsoft Visual C++ Redistributable'
$appName = 'teams'
$drive = 'C:\'
New-Item -Path $drive -Name $appName  -ItemType Directory -ErrorAction SilentlyContinue
$LocalPath = $drive + '\' + $appName 
set-Location $LocalPath
$visCplusURL = 'https://aka.ms/vs/16/release/vc_redist.x64.exe'
$visCplusURLexe = 'vc_redist.x64.exe'
$outputPath = $LocalPath + '\' + $visCplusURLexe
Invoke-WebRequest -Uri $visCplusURL -OutFile $outputPath
write-host 'AIB Customisation: Starting Install the latest Microsoft Visual C++ Redistributable'
Start-Process `
    -FilePath $outputPath `
    -Args "/install /quiet /norestart /log vcdist.log" `
    -Wait
write-host 'AIB Customisation: Finished Install the latest Microsoft Visual C++ Redistributable'

# Install WebSocket
write-host 'AIB Customisation: Install the Teams WebSocket Service'
$webSocketsURL = 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RE4AQBt'
$webSocketsInstallerMsi = 'webSocketSvc.msi'
$outputPath = $LocalPath + '\' + $webSocketsInstallerMsi
Invoke-WebRequest -Uri $webSocketsURL -OutFile $outputPath
Start-Process `
    -FilePath msiexec.exe `
    -Args "/I $outputPath /quiet /norestart /log webSocket.log" `
    -Wait
write-host 'AIB Customisation: Finished Install the Teams WebSocket Service'

# Install Teams
write-host 'AIB Customisation: Install MS Teams'
$teamsURL = 'https://teams.microsoft.com/downloads/desktopurl?env=production&plat=windows&arch=x64&managedInstaller=true&download=true'
$teamsMsi = 'teams.msi'
$outputPath = $LocalPath + '\' + $teamsMsi
Invoke-WebRequest -Uri $teamsURL -OutFile $outputPath
Start-Process `
    -FilePath msiexec.exe `
    -Args "/I $outputPath /quiet /norestart /log teams.log ALLUSER=1 ALLUSERS=1" `
    -Wait
write-host 'AIB Customisation: Finished Install MS Teams' 