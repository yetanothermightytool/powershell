<# 
.NAME
    Veeam Backup Scanning Tools Installer
.DESCRIPTION
    This script downloads and saves essential backup scanning tools from the YAMT Git repository to a specified 
    local directory for subsequent use in the main backup scanning tool script.
 .EXAMPLE
    Execute the backup-scanning-tools-installer.ps1 script with the required parameter -InstallDir. This parameter
    specifies the directory where the backup scanning scripts will be installed. Replace "C:\Scripts\scanningtools" 
    with the path to the directory where you want to install the backup scanning tools.

    PS > .\backup-scanning-tools-installer.ps1 -InstallDir "C:\Scripts\scanningtools"
.NOTES  
    File Name  : backup-scanning-tools-installer.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell
.VERSION
    1.0
#>
Param(
    [Parameter(Mandatory=$true)]
    [string]$InstallDir
    )
Clear-Host
# Display a welcome message
Write-Host "Welcome to the YAMT Script Downloader!"
Write-Host "This script will download some useful backup scanning tools from the YAMT Git Repository."

# Set the local directory 
$localDirectory = $InstallDir

# Create the local directory if it doesn't exist
if (-Not (Test-Path -Path $localDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $localDirectory | Out-Null
}

# List of the backup scanning tools scripts
$scriptUrls = @(
    "https://raw.githubusercontent.com/yetanothermightytool/powershell/master/vbr/backup-scanning-tools/backup-scanning-tools-menu.ps1",
    "https://raw.githubusercontent.com/yetanothermightytool/powershell/master/vbr/vbr-securerestore-lnx/vbr-securerestore.ps1",
    "https://raw.githubusercontent.com/yetanothermightytool/powershell/master/vbr/vbr-nas-avscanner/vbr-nas-avscanner.ps1",
    "https://raw.githubusercontent.com/yetanothermightytool/powershell/master/vbr/vbr-staged-restore/vbr-staged-restore.ps1",
    "https://raw.githubusercontent.com/yetanothermightytool/powershell/master/vbr/vbr-instantdiskrecovery/vbr-instantdiskrecovery.ps1"
)

# Download the scripts
$scriptCount = $scriptUrls.Count
for ($i = 0; $i -lt $scriptCount; $i++) {
    $url             = $scriptUrls[$i]
    $scriptName      = Split-Path -Leaf $url
    $localPath       = Join-Path -Path $localDirectory -ChildPath $scriptName
    $percentComplete = ($i + 1) / $scriptCount * 100
    Write-Progress -Activity "Downloading Scripts" -Status "Downloading..." -PercentComplete $percentComplete

    Invoke-WebRequest -Uri $url -OutFile $localPath -UseBasicParsing
    Start-Sleep -Milliseconds 500
}

Write-Progress -Activity "Downloading Scripts" -Completed
Write-Host "Download completed successfully. Scripts are saved in: $localDirectory"
