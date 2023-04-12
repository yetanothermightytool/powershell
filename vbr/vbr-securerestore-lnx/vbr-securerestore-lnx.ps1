Param(
    [Parameter(Mandatory=$true)]
    [string]$Mounthost,
    [Parameter(Mandatory=$true)]
    [string]$Scanhost,
    [Parameter(Mandatory=$true)]
    [string]$Jobname,
    [Parameter(Mandatory=$true)]
    [string]$Keyfile,
    [Switch]$Restore
    )
#example .\vbr-securerestore-lnx.ps1 -mountHost lnx-ubuntu-02 -scanHost lnx-tinyvm-01 -jobName demo_vm_zrh_obj_01
Clear-Host

# Get the Backup Job
Write-Progress "Get Backup Job..." -PercentComplete 10
$backup       = Get-VBRBackup -Name $Jobname

# Get the Restore Point for the Host to be scanned
Write-Progress "Get Latest Restore Point..." -PercentComplete 30
$restorePoint = Get-VBRRestorePoint -Backup $backup | Sort-Object -Property CreationTime -Descending | Select-Object -First 1 | Where-Object {$_.VmName -eq $Scanhost}

# Set the Linux Server where scanning will take place. Note: This host needs to be added to VBR 
$lnxHost      = Get-VBRServer -Name $Mounthost

# Get the configured credentials for the specified host where the backup will be mounted
$creds        = Get-VBRCredentials -Entity $lnxHost

# now we present the backup to the "mounthost"
$session      = Publish-VBRBackupContent -RestorePoint $restorePoint -TargetServerName $mountHost-TargetServerCredentials $creds -EnableFUSEProtocol

# Get-VBRPublishedBackupContentInfo -session $session 
$scanPath     = ($sessionInfo = Get-VBRPublishedBackupContentInfo -session $session).Disks.MountPoints

# Start scanning using ClamAV
Write-Progress "Start Scanning..." -PercentComplete 95
$scanner           = ssh administrator@$mountHost -i $Keyfile "clamscan -r $scanPath"

# Catch line "Infected files"
$infectedFilesLine = $scanner -match 'Infected files: 0'
$foundFile         = $scanner -match 'FOUND'

if ($infectedFilesLine.Count -eq "") {
        Write-Host "Infected file(s) detected" -ForegroundColor Yellow
        $foundFile
    } else {
        Write-Host "No infected files found."
        if ($Restore){
        Write-Host "Start-VBRRestoreVM -RestorePoint $restorePoint -Reason "Clean Restore - YaMT Secure Restore Linux" -ToOriginalLocation -StoragePolicyAction Default"
        }  
  }
  
# Stop Disk Publish Session
Unpublish-VBRBackupContent -Session $session 
