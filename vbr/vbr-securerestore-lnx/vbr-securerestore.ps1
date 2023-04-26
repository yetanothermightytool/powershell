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
Clear-Host

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

$Result = Get-VBRBackup | Where-Object { $_.jobname -eq $JobName } | Get-VBRRestorePoint | Where-Object { $_.name -eq $Scanhost } | Sort-Object CreationTime -Descending

if ($Result.Count -eq 0) {
	Write-Host 'Unable to locate any restore points for' $Scanhost 'in backup job' $Jobname -ForegroundColor White
	Exit
} else {
    rpLister $Result
}

do { [int]$restorePointID = Read-Host "Please select restore point (Id)" } until (($restorePointID -lt $Result.Count) -and ($restorePointID -ge 0))

Write-Host
# Set the Linux Server where scanning will take place. Note: This host needs to be added to VBR 
$lnxHost      = Get-VBRServer -Name $Mounthost

# Get the configured credentials for the specified host where the backup will be mounted
$creds        = Get-VBRCredentials -Entity $lnxHost

# now we present the backup to the "mounthost"
$selectedRp   = $Result | Select-Object -Index $restorePointID 
$session      = Publish-VBRBackupContent -RestorePoint $selectedRp -TargetServerName $mountHost-TargetServerCredentials $creds -EnableFUSEProtocol


# Start scanning using ClamAV
Write-Progress "Start Scanning..." -PercentComplete 95
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
    } else {
        Write-Host "No infected files found." -ForegroundColor White
        if ($Restore){
        Write-Host "Start-VBRRestoreVM -RestorePoint $restorePoint -Reason "Clean Restore - YaMT Secure Restore Linux" -ToOriginalLocation -StoragePolicyAction Default"
        }  
  }

# Write End Message
Write-Host "***Scanning end***" -ForegroundColor White
  
# Stop Disk Publish Session
Unpublish-VBRBackupContent -Session $session