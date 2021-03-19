<#
.Synopsis
Created by: Ray Pering
Downloads and installs the latest FsLogix client

.Description
Downloads installer to c:\fslogix
Expands downloaded archive
Installs x64 FsLogix client

#>

write-host 'AIB Customisation: Downloading FsLogix'

# Create FsLogix folder
New-Item -Path C:\\ -Name fslogix -ItemType Directory -ErrorAction SilentlyContinue
$LocalPath = 'C:\\fslogix'

# Change location to FsLogix folder
set-Location $LocalPath

# Set download variaibles
$fsLogixURL="https://aka.ms/fslogix_download"
$installerFile="fslogix_download.zip"

# Download installer and expand archive
Invoke-WebRequest $fsLogixURL -OutFile $LocalPath\$installerFile
Expand-Archive $LocalPath\$installerFile -DestinationPath $LocalPath
write-host 'AIB Customisation: Download Fslogix installer finished'

write-host 'AIB Customisation: Start Fslogix installer'

# Install client
Start-Process `
    -FilePath "C:\fslogix\x64\Release\FSLogixAppsSetup.exe" `
    -ArgumentList "/install /quiet" `
    -Wait `
    -Passthru 

write-host 'AIB Customisation: Finished Fslogix installer' 