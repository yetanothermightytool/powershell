<# 
.NAME
    Veeam Backup & Replication - Restore Point Scan for Linux, Windows VM and Agent Backups - Veeam Data Platform v12.1 
.DESCRIPTION
    This script presents all restore points from a Linux, Windows VM or Agent backup and then mounts the selected restore point to a Linux host,
    scans and marks it as infected if anything gets found. The script utilizes the Veeam Data Integration API and integrates with ClamAV for 
    antivirus scans or YARA rules installed on the Linux host. 

    The script displays all existing restore points for the selected host and starts the scan automatically after 15 seconds, using the last restore point.
 .NOTES  
    File Name  : vbr-secrurerestore.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12.1, Linux host with ClamAV installed, OpenSSH Keyfile
.VERSION
1.1
#>
Param(
    [Parameter(Mandatory=$true)]
    [string]$HostToScan,
    [Parameter(Mandatory=$true)]
    [string]$Jobname,
    [Parameter(Mandatory=$true)]
    [string]$Mounthost,
    [Parameter(Mandatory=$true)]
    [string]$LinuxUser,
    [Parameter(Mandatory=$true)]
    [string]$Keyfile,
    [Parameter(Mandatory=$false)]
    [Switch]$AVScan,
    [Switch]$YARAScan
    )

Clear-Host
# Variables
$host.ui.RawUI.WindowTitle = "Scan Backup Data"
$execUserInfo              = whoami

# Connect VBR Server
Connect-VBRServer -Server localhost

# function to list restore points
function rpLister {
Param (
    [Parameter(Position = 0,Mandatory = $False)]
    [PSObject]
$Output = $Result
    )
    begin {
        $Global:n = 0
    }
    process {
        $RestoreTable = @{ Expression={ $Global:n;$Global:n++ };Label="Id";Width=5;Align="center" }, `
        @{ Expression={ $_.VmName };Label="Server Name";Width=25;Align="left" }, `
        @{ Expression={ $_.CreationTime };Label="Creation Time";Width=25;Align="left" }, `
        @{ Expression={ $_.Type };Label="Type";Width=10;Align="left" },
        @{ Expression={ $_.GetRansomwareStatus().Status };Label="Malware";Width=10;Align="left" }
    }
    end {
 
        Write-Host
        Write-Host "The following restore points were found...(newest first)"
        Write-Host
        return $Output | Format-Table $RestoreTable
    }
}
# end function

# Get Backups on Disk/Object
$Result = Get-VBRBackup | Where-Object { $_.jobname -eq $JobName } | Get-VBRRestorePoint | Where-Object { $_.name -eq $HostToScan } | Sort-Object CreationTime -Descending

# If no restore points have been found
if ($Result.Count -eq 0) {
	Write-Host 'Unable to locate any restore points for' $HostToScan 'in backup job' $Jobname -ForegroundColor White
    Disconnect-VBRServer
	Exit
} else {
# Present the result using the function rpLister
    rpLister $Result
}

# Ask for the restore point to be scanned - Automatically select latest restore points after 15 seconds
$stopTime       = [datetime]::Now.AddSeconds(15)
$restorePointID = 0

Write-Host -NoNewline "Please select restore point (Id) - Automatically selects the latest restore point after 15 seconds: "

while ([datetime]::Now -lt $stopTime -and -not [console]::KeyAvailable) {
    Start-Sleep -Milliseconds 50
}

if ([console]::KeyAvailable) {
    $restorePointID = [console]::ReadLine()
    
    while (($restorePointID -ge $Result.Count -or $restorePointID -lt 0)) {
        $restorePointID = [console]::ReadLine()
    }
} 

while ([console]::KeyAvailable) {
       [console]::ReadKey($true) | Out-Null 
}

$restorePointID = [int]$restorePointID
Write-Host 
Write-Host

# Set the Linux Server where scanning will take place. Note: This host needs to be added to VBR 
$lnxHost                  = Get-VBRServer -Name $Mounthost

# Get the configured credentials for the specified host where the backup will be mounted
$creds                    = Get-VBRCredentials -Entity $lnxHost

# Get the selected restore point
$selectedRp               = $Result | Select-Object -Index $restorePointID 

# Store the restore point's information into variables
$restorePointCreationTime = $selectedRp.CreationTime
$selectedRpObject         = Get-VBRObjectRestorePoint -Id $selectedRp.Id
$restorePointObjectID     = $selectedRp.ObjectId

# Check from regular backup
$session           = Publish-VBRBackupContent -RestorePoint $selectedRp -TargetServerName $mountHost-TargetServerCredentials $creds -EnableFUSEProtocol

if($AVScan){
# Start scanning using ClamAV
$scanner           = ssh $LinuxUser@$mountHost -i $Keyfile "sudo clamdscan --multiscan --fdpass /tmp/Veeam.Mount.FS.*"
Write-Host     "***Scanning start***" -ForegroundColor White

# Catch line "Infected files"
$infectedFilesLine = $scanner -match 'Infected files: 0'
$foundFile         = $scanner -match 'FOUND'

if ($infectedFilesLine.Count -eq "") {
        Write-Host ""
        Write-Host "Infected file(s) detected" -ForegroundColor Yellow
        Write-Host ""
        Write-Host $foundFile "" -ForegroundColor Yellow
        Set-VBRObjectRestorePointStatus -RestorePoint $selectedRpObject -Status Infected
                
        } else {
        Write-Host "No infected files found." -ForegroundColor White
        Set-VBRObjectRestorePointStatus -RestorePoint $selectedRpObject -Status Clean
        }  
   
# Write End Message
Write-Host "***Scanning end***" -ForegroundColor White
}

if($YARAScan){
# Start scanning using YARA / Used parameters: recursive / fastscan / no-warnings / no-follow-symlinks / threads (16)
$scanner           = ssh $LinuxUser@$mountHost -i $Keyfile "sudo yara -rfwN -p 16 ./yara-rules/rules/index.yar /tmp/Veeam.Mount.FS.*"
Write-Host     "***Scanning start***" -ForegroundColor White
$infectedFilesLine = $scanner
$scanner
if ($infectedFilesLine.Count -gt 0) {
        Write-Host ""
        Write-Host "Infected file(s) detected" -ForegroundColor Yellow
        Write-Host ""
        Write-Host $infectedFilesLine "a" -ForegroundColor Yellow
        Set-VBRObjectRestorePointStatus -RestorePoint $selectedRpObject -Status Infected
        
        } else {
        Write-Host "No infected files found." -ForegroundColor White
        }
    
# Write End Message
Write-Host "***Scanning end***" -ForegroundColor White
}
  
# Stop Disk Publish Session
Unpublish-VBRBackupContent -Session $session 

# Disconnect VBR Server
Disconnect-VBRServer
