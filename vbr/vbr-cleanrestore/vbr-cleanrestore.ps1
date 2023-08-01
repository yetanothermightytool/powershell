<# 
.NAME
   VBR Clean Restore
.DESCRIPTION
    This script facilitates the restore process for virtual machine backup data using Veeam Backup & Replication and Data Integration API.
    The script iterates through the restore points, attempting to find a clean restore point. If a clean restore point is found, 
    it initiates the restore (if selected). If not, it stops after the specified number of iterations.
.NOTES  
    File Name  : vbr-cleanrestore.ps1  
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell & Veeam Backup & Replication v12
.VERSION
    1.0
#>
Param(
    [Parameter(Mandatory=$true)]
    [string]$Mounthost,
    [Parameter(Mandatory=$true)]
    [string]$Scanhost,
    [Parameter(Mandatory=$true)]
    [string]$Jobname,
    [Parameter(Mandatory=$true)]
    [string]$Keyfile,
    [Parameter(Mandatory=$true)]
    [Switch]$AVScan,
    [Parameter(Mandatory=$false)]
    [int]$MaxIterations = 5,
    [Switch]$Restore,
    [String]$LogFilePath = "C:\Temp\log.txt"
    )
Clear-Host

# Variables
$host.ui.RawUI.WindowTitle = "VBR Clean Restore - Data Integration API"

# Connect VBR Server
Connect-VBRServer -Server localhost

# Logging function
function BackupScan-Logentry {
    param (
        [string]$Message
    )

    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    $logEntry = "$timestamp - $Message - Scanning Restore Point: $($restorePointCreationTime.ToString("dd-MM-yyyy HH:mm:ss")) - Iteration $iteration"
    Add-Content -Path $logFilePath -Value $logEntry
}

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
        @{ Expression={ $_.Type };Label="Type";Width=10;Align="left" }
    }
    end {
 
        Write-Host
        Write-Host "The following restore points were found...(newest first)"
        Write-Host
        return $Output | Format-Table $RestoreTable
    }
}
# end function

$Result = Get-VBRBackup | Where-Object { $_.jobname -eq $JobName } | Get-VBRRestorePoint | Where-Object { $_.name -eq $Scanhost } | Sort-Object CreationTime -Descending

# If no restore points have been found
if ($Result.Count -eq 0) {
	Write-Host 'Unable to locate any restore points for' $Scanhost 'in backup job' $Jobname -ForegroundColor White
    Disconnect-VBRServer
	Exit
} else {
# Present the result using the function rpLister
  rpLister $Result
}
# Ask for the restore point to be scanned - Automatically select latest restore points after 30 seconds
$stopTime       = [datetime]::Now.AddSeconds(30)
$restorePointID = 0

Write-Host -NoNewline "Please select restore point (Id) - Automatically selects the latest restore point after 30 seconds: "

while ([datetime]::Now -lt $stopTime -and -not [console]::KeyAvailable) {
    Start-Sleep -Milliseconds 50
}

if ([console]::KeyAvailable) {
    $restorePointID = [console]::ReadLine()
    while (!($restorePointID -lt $Result.Count -and $restorePointID -ge 0)) {
    $restorePointID = [console]::ReadLine()
    }
} 

while ([console]::KeyAvailable) {
       [console]::ReadKey($true) | Out-Null 
}

$restorePointID = [int]$restorePointID
Write-Host 
Write-Host

# Initialize Variables
$iteration = 0
$infectionFound = $false

do {
$iteration++
Clear-Host
    
# Get the selected restore point
$selectedRp       = $Result | Select-Object -Index $restorePointID

# Start scanning
Write-Host "Start scanning - Iteration $iteration - Selected Restore Point: $($selectedRp.VmName) (Creation Time: $($selectedRp.CreationTime))"
    
# Set the Linux Server where scanning will take place. Note: This host needs to be added to VBR 
$lnxHost          = Get-VBRServer -Name $Mounthost

# Get the configured credentials for the specified host where the backup will be mounted
$creds            = Get-VBRCredentials -Entity $lnxHost

# Check if the restore point ID is within the valid range
if ($restorePointID -ge $Result.Count) {
     Write-Host "No more restore points available. Stopping the scanning process." -ForegroundColor Yellow
     Break
    }

# Get the selected restore point
$selectedRp       = $Result | Select-Object -Index $restorePointID 

# Store the restore point's creation time in a variable
$restorePointCreationTime = $selectedRp.CreationTime

# Check from regular backup
$session           = Publish-VBRBackupContent -RestorePoint $selectedRp -TargetServerName $mountHost-TargetServerCredentials $creds -EnableFUSEProtocol -Reason "Clean Restore - Backup Scanning Tools"

if($AVScan){
# Start scanning using ClamAV
BackupScan-Logentry -Message "Info - Clean Restore - AV Scan - Scanning started - Iteration $iteration"
$scanner           = ssh administrator@$mountHost -i $Keyfile "sudo clamdscan --multiscan --fdpass /tmp/Veeam.Mount.FS.*"
Write-Host     "***Scanning start***" -ForegroundColor White

# Catch line "Infected files"
$infectedFilesLine = $scanner -match 'Infected files: 0'
$foundFile         = $scanner -match 'FOUND'

if ($infectedFilesLine.Count -eq "") {
        Write-Host ""
        Write-Host "Infected file(s) detected" -ForegroundColor Yellow
        Write-Host ""
        Write-Host $foundFile "" -ForegroundColor Yellow
        BackupScan-Logentry -Message "Warning - Clean Restore - AV Scan - Iteration $iteration Scanning ended - Result: $foundFile"
        $infectionFound = $true
        Unpublish-VBRBackupContent -Session $session 
        $restorePointID++
        } else {
        Write-Host "No infected files found." -ForegroundColor White
        BackupScan-Logentry -Message "Info - Clean Restore - AV Scan - Scanning ended - No threads were found"
        if ($Restore -and $selectedRp.GetPlatform() -eq "EVmware"){
        Write-Host "Start-VBRRestoreVM -RestorePoint $restorePoint -Reason "Clean Restore - YaMT Secure Restore" -ToOriginalLocation -StoragePolicyAction Default"
        $infectionFound = $false
        Unpublish-VBRBackupContent -Session $session 
        }  
   }

}
# Increment the restorePointID only if infection is found
  if ($infectionFound) {
      $restorePointID++
     }

} while ($infectionFound -and $iteration -lt $MaxIterations)

# Write End Message
Write-Host "***Scanning end***" -ForegroundColor White

# Disconnect VBR Server
Disconnect-VBRServer
