Param(
    [Parameter(Mandatory=$true)]
    [string]$Mounthost,
    [Parameter(Mandatory=$true)]
    [string]$Scanhost,
    [Parameter(Mandatory=$true)]
    [string]$Jobname,
    [Parameter(Mandatory=$true)]
    [string]$vCenter,
    [Parameter(Mandatory = $false)]
    [String] $LogFilePath = "C:\Temp\log.txt"
    )
    
Clear-Host
# Variables
$host.ui.RawUI.WindowTitle = "VBR Instant Disk Recovery"

# Connect VBR Server
Connect-VBRServer -Server localhost

# Log Message function
function Log-Message {
    param (
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $Message"
    Add-Content -Path $LogFilePath -Value $logEntry
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
        Write-Host "The following restore points were found...(newest first)" -ForegroundColor White
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
# Ask for the backup to be scanned
do { [int]$restorePointID = Read-Host "Please select restore point (Id)" } until (($restorePointID -lt $Result.Count) -and ($restorePointID -ge 0))

# Get the selected restore point
$selectedRp        = $Result | Select-Object -Index $restorePointID

# Prepare environment
$mountVM           = Find-VBRViEntity -Name $Mounthost

# Get the virtual devices from the restore point
$virtualDevice     = Get-VBRViVirtualDevice -RestorePoint $selectedRp

# Set another SCSI Device Node for attaching to a running VM
#$virtualDevice     = Set-VBRViVirtualDevice -VirtualDevice $virtualDevice -ControllerNumber 0 -Type SCSI -VirtualDeviceNode 5

# Start Instant VM Disk Recovery
Log-Message -Message "Info - Instant Disk Recovery - Scanning started"
$instantRecovery   = Start-VBRViInstantVMDiskRecovery -RestorePoint $selectedRp -TargetVM $mountVM -TargetVirtualDevice $virtualDevice -Reason "Backup Scanning Tools Scan"

# Connect to vCenter Server 
Connect-VIServer -Server $vCenter | Out-Null

# Start VM
start-vm -VM $Mounthost | Out-Null

# Disconnect from vCenter Server
Disconnect-VIServer -Confirm:$false

# Wait for scan completion
$input = $(Write-Host "Please start the scan in the VM. After completion press Enter to continue..." -NoNewLine -ForegroundColor White ; Read-Host)
Write-Host ""
Write-Host "Was malware detected during the manual scan? (Y/N)?" -ForegroundColor "White"
      $confirm   = Read-Host
      $confirmed = ($confirm -eq "Y" -or $confirm -eq "y")
          if ($confirmed) {
             Log-Message -Message "Warning - Instant Disk Recovery - Scanning ended - Threads found - Manually confirmed"
          } else {
             Log-Message -Message "Info - Instant Disk Recovery - Scanning ended - No threads were found"
          }

# Stop Instant VM Disk Recovery Session
Stop-VBRViInstantVMDiskRecovery -InstantRecovery $instantRecovery -Force

# Disconnect from VBR Server
Disconnect-VBRServer
