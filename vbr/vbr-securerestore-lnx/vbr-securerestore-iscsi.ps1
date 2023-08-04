<# 
.NAME
    Veeam Backup & Replication - VBR Secure Restore using Data Integration API over iSCSI
.DESCRIPTION
    This Powershell script performs an antivirus scan on a specified virtual machine from a backup restore point. The backup is presented on the mountserver 
    using iSCSI. The script interacts with a Linux host running ClamAV to perform the scan over this iSCSI connection.
.EXAMPLE
    
    This command runs the Powershell script to scan a virtual machine named "MyVM" from a specified Veeam backup job using ClamAV on a Linux host.
    Linux user "mylinuxuser" with the corresponding private key file is used for authentication when connecting to the -Scanhost. If no infections 
    are found, it proceeds with restoring the VM.

    The script detects the file system type of each partition on the VM's disks and only proceeds to scan partitions with supported file systems 
    (NTFS, XFS, or ext4). Any other file systems found will not be scanned.

    PS > .\vbr-securerestore-iscsi.ps1 -Mounthost "mountsrv01" -Scanhost "lnxhost01" -HosttoScan "myVM01" -Jobname "myBackupJob" -LinuxUser "mylinuxuser" -Keyfile "C:\Path\to\private_key_of_linuxuser.pem" -Restore

.NOTES  
    File Name  : vbr-securerestore-iscsi.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12
.VERSION
    1.0
#>

Param(
    [Parameter(Mandatory=$true)]
    [string]$Mounthost,               # iSCSI Target 
    [Parameter(Mandatory=$true)]
    [string]$Scanhost,                # Linux host with ClamAV
    [Parameter(Mandatory=$true)]
    [string]$HosttoScan,              # VM to scan
    [Parameter(Mandatory=$true)]
    [string]$Jobname,
    [Parameter(Mandatory=$true)]
    [string]$LinuxUser,
    [Parameter(Mandatory=$true)]
    [string]$Keyfile,
    [Parameter(Mandatory = $false)]
    [Switch] $Restore,
    [Parameter(Mandatory = $false)]
    [String] $LogFilePath = "C:\Temp\log.txt"
    
    )
Clear-Host

# Define some variables
$mountedPartitions         = @()
$lnxhost                   = $Scanhost
$allowedIP                 = ($ipAddress = (Test-Connection -ComputerName $Scanhost -Count 1).IPv4Address.IPAddressToString)
$host.ui.RawUI.WindowTitle = "VBR Secure Restore AV Scan - Data Integration API via iSCSI"

#Define logging function
function BackupScan-Logentry {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    $logEntry = "$timestamp - $Message - Scanning Restore Point $Scanhost *** $($restorePointCreationTime.ToString("dd-MM-yyyy HH:mm:ss"))"
    Add-Content -Path $logFilePath -Value $logEntry
}

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
        @{ Expression={ $_.Type };Label="Type";Width=10;Align="left" }
    }
    end {
 
        Write-Host
        Write-Host "The following restore points were found...(newest first)"
        Write-Host
        return $Output | Format-Table $RestoreTable
    }
}

# Get Backups on Disk/Object
$Result = Get-VBRBackup | Where-Object { $_.jobname -eq $JobName } | Get-VBRRestorePoint | Where-Object { $_.name -eq $HosttoScan } | Sort-Object CreationTime -Descending

# If no restore points have been found
if ($Result.Count -eq 0) {
	Write-Host 'Unable to locate any restore points for' $HosttoScan 'in backup job' $Jobname -ForegroundColor White
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

$restorePointID = [int]$restorePointID  # Convert the restore point ID to an integer
Write-Host ""

# Selected Restore Point
$selectedRp               = $Result | Select-Object -Index $restorePointID 

# Store the restore point's creation time in a variable
$restorePointCreationTime = $selectedRp.CreationTime

# Get Mounthost information
$mountSrv          = Get-VBRServer -Name $Mounthost

# Check from regular backup
$session           = Publish-VBRBackupContent -RestorePoint $selectedRp -MountHostId $mountSrv.id -AllowedIps $allowedIP -Reason "Backup Scanning Tools - Secure Restore AV Scan - Data Integration API via iSCSI"
$sessionDetail     = Get-VBRPublishedBackupContentInfo -Session $session

# Start working
Clear-Host
Write-Host ""

# Get "local" disks
$lnxcmd1           = "lsblk -nd -o NAME"
$blkDevBeforeMnt   = ssh $LinuxUser@$lnxhost -i $Keyfile $lnxcmd1

# Discovery via iSCSI Devcies and get disk information again
$lnxcmd2           = "sudo iscsiadm --mode discovery -t sendtargets --portal "+$sessiondetail.ServerIps+":"+$sessiondetail.ServerPort+" -l"
Write-Host "Mount disks via iSCSI" -ForegroundColor White
$mountIscsi        = ssh $LinuxUser@$lnxhost -i $Keyfile $lnxcmd2
$blkDevAfterMnt    = ssh $LinuxUser@$lnxhost -i $Keyfile $lnxcmd1

# Filter before and after mount iSCSI disks
$entriesBefore     = [string[]]$blkDevBeforeMnt
$entriesAfter      = [string[]]$blkDevAfterMnt
$filteredDevs      = $entriesAfter | Where-Object { $entriesBefore -notcontains $_ }

# Find partitions on device(s)
Write-Host "Getting disk partition information" -ForegroundColor White
Write-Host ""
$ntfspart          = @()
$xfspart           = @()
$ext4part          = @()

foreach ($drive in $filteredDevs) {
    $partitionNumber    = 1
    $maxPartitionNumber = 1

    # Determine the maximum partition number for the drive
    while ($true) {
        $checkPartition = "lsblk -f -o NAME /dev/$drive$partitionNumber 2>&1"
        $checkResult    = ssh $LinuxUser@$lnxhost -i $Keyfile $checkPartition

        if ($checkResult -match 'not a block device') {
            $maxPartitionNumber = $partitionNumber - 1
            break
        }
        elseif ($checkResult -match 'lsblk: error: unable to get device') {
            Write-Output "Error: Unable to get device information for /dev/$drive$partitionNumber"
            $partitionNumber++
            continue
        }

        $partitionNumber++
    }

    # Detect filesystem type on partition
    for ($partitionNumber = 1; $partitionNumber -le $maxPartitionNumber; $partitionNumber++) {
        $getFstype = "lsblk -f -o FSTYPE /dev/$drive$partitionNumber"
        $commandResult = ssh $LinuxUser@$lnxhost -i $Keyfile $getFstype

        if ($commandResult) {
            $fileSystemType = $commandResult.Trim()

            if ($fileSystemType -like "*ntfs*") {
                $ntfspart += "$drive$partitionNumber"
            }
            elseif ($fileSystemType -like "*xfs*") {
                $xfspart += "$drive$partitionNumber"
            }
            elseif ($fileSystemType -like "*ext4*") {
                $ext4part += "$drive$partitionNumber"
            }
        }
    }
}
# Start mount and scanning
Write-Host "Found NTFS partitions: $($ntfspart -join ', ')" -ForegroundColor White
Write-Host "Found XFS partitions : $($xfspart -join ', ')" -ForegroundColor White
Write-Host "Found ext4 partitions: $($ext4part -join ', ')" -ForegroundColor White
   
$partitionTypes = @{
    'ntfs' = $ntfspart
    'xfs'  = $xfspart
    'ext4' = $ext4part
}

foreach ($partitionType in $partitionTypes.Keys) {
    $partitions = $partitionTypes[$partitionType]

    if ($partitions -gt 0) {
        $drives = $partitions

        foreach ($drive in $drives) {
            $mountPath = "/mnt/$drive"

            # Create the mount point directory if it doesn't exist
            $createDirCommand = "sudo mkdir -p $mountPath"
            ssh $LinuxUser@$lnxhost -i $Keyfile $createDirCommand

            # Mount the partition
            $mountCommand = "sudo mount -t $partitionType /dev/$drive $mountPath"
            ssh $LinuxUser@$lnxhost -i $Keyfile $mountCommand

            # Add the mount path(s) to the array
            $mountedPartitions += $mountPath
          }

# Perform AV scan
Write-Host
Write-Host "Start scanning..." -ForegroundColor Cyan
BackupScan-Logentry -Message "Info - Secure Restore AV Scan - Data Integration API via iSCSI - Scanning started"
$lsCommand     = "ls $($mountedPartitions -join ' ')"
$command       = "sudo clamdscan --multiscan --fdpass --infected $($mountedPartitions -join ' ')"
$commandResult = ssh $LinuxUser@$lnxhost -i $Keyfile $command

# Split the $commandresult string by the string " FOUND " and take the first part (left side), trim the result
$infected_file = $null
$infected_file_candidate = $commandresult -split " FOUND ", 2 | Select-Object -First 1
$infected_file = $infected_file_candidate.Trim()

if ($commandresult -match "Infected files: 0") {
        Write-Host "No infected files found." -ForegroundColor White
        BackupScan-Logentry -Message "Info - Secure Restore - Data Integration API via iSCSI - No threads were found. Restore Point $restorePointCreationTime"
        
        if ($Restore -and $selectedRp.GetPlatform() -eq "EVmware"){
        Write-Host "Start-VBRRestoreVM -RestorePoint $restorePoint -Reason "Secure Restore - Data Integration API via iSCSI" -ToOriginalLocation -StoragePolicyAction Default"
        }
        } else {

        Write-Host ""
        Write-Host "Infected file(s) detected" -ForegroundColor Yellow
        Write-Host ""
        Write-Host $infected_file "" -ForegroundColor Yellow
        BackupScan-Logentry -Message "Warning - Secure Restore - Data Integration API via iSCSI - Scanning ended - Result: $infected_file - Restore Point $restorePointCreationTime"
        }

# Start cleaning up
foreach ($drive in $drives) {
        $mountPath = "/mnt/$drive"

        # Unmount the partition
        $umountCommand = "sudo umount $mountPath"
        ssh $LinuxUser@$lnxhost -i $Keyfile $umountCommand

        # Remove the mount point directory
        $removeDirCommand = "sudo rmdir $mountPath"
        ssh $LinuxUser@$lnxhost -i $Keyfile $removeDirCommand
        }
    }
}

if (-not $drives) {
    Write-Host "No supported partitions found" -ForegroundColor Yellow
}

# Start unmount devices after scan    
$lnxIscsiUnmount = "sudo iscsiadm --mode node --portal " + $sessiondetail.ServerIps + ":" + $sessiondetail.ServerPort + " -u "
$lnxIscsiDelete  = "sudo iscsiadm --mode node -o delete --portal " + $sessiondetail.ServerIps + ":" + $sessiondetail.ServerPort + " "
$cleanupCommands = @"
$lnxIscsiUnmount
$lnxIscsiDelete
"@
Write-Host "Unmount iSCSI disk(s)" -ForegroundColor White
$umount = ssh $LinuxUser@$lnxhost -i $Keyfile -T $cleanupCommands

# Stop Disk Publish Session
Unpublish-VBRBackupContent -Session $session 

# Disconnect VBR Server
Disconnect-VBRServer
