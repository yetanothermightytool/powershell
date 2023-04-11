Param(
    [Parameter(Mandatory=$true)]
    [string]$Mounthost,
    [Parameter(Mandatory=$true)]
    [string]$Scanhost,
    [Parameter(Mandatory=$true)]
    [string]$Jobname
    )
Clear-Host

# Set the variables
$keyFile      = "D:\Scripts\vbr\securerestore-lnx\key"

# Get the Backup Job
Write-Progress "Get Backup Job..." -PercentComplete 10
$backup       = Get-VBRBackup -Name $Jobname

# Get the Restore Point for the Host to be scanned
Write-Progress "Get Latest Restore Point..." -PercentComplete 30
$restorePoint = Get-VBRRestorePoint -Backup $backup | Select-Object -last 1  | Where-Object {$_.VmName -eq $Scanhost}

# Set the Linux Server where scanning will take place. Note: This host needs to be added to VBR 
$lnxHost      = Get-VBRServer -Name $Mounthost

# Get the configured credentials for the specified host where the backup will be mounted
$creds        = Get-VBRCredentials -Entity $lnxHost

# now we present the backup to the "mounthost"
Write-Progress "Publish Backup to Mounthost $Mounthost..." -PercentComplete 60
$session      = Publish-VBRBackupContent -RestorePoint $restorePoint -TargetServerName $mountHost-TargetServerCredentials $creds -EnableFUSEProtocol

# Get-VBRPublishedBackupContentInfo -session $session 
$scanPath     = ($sessionInfo = Get-VBRPublishedBackupContentInfo -session $session).Disks.MountPoints

# Start scanning using ClamAV
Write-Progress "Start Scanning..." -PercentComplete 95
$scanner      = ssh administrator@$mountHost -i $keyFile "clamscan -r $scanPath"

# Assuming the PowerShell variable is named $scanSummary
$infectedFilesLine = $scanner -match 'Infected files: 0'

if ($infectedFilesValue.Count -ne 0) {
        Write-Host $infectedFilesLine
    } else {
        Write-Host "No infected files found."
  }

# Stop the Data Integration API Session
Unpublish-VBRBackupContent -Session $session 
