<# 
.NAME
    Veeam Backup & Replication - Secure Restore for Linux and Windows VM and Agent Backups
.DESCRIPTION
    This  script performs secure restores for Linux and Windows VM and agent backups using Veeam Backup & Replication. It scans the specified restore
    point before initiating the restore process for VMs. The script leverages the Veeam Data Integration API and integrates with ClamAV for antivirus scanning or
    YARA rules. For tape backups, additional steps are performed to restore the data to the desired repository. The script then initiates the scan using ClamAV or 
    YARA rules.
             
.EXAMPLES
    Scan VM lnxvm01 on Linux host ubuntusrv01 from backup demo_vm
    .\vbr-securerestore.ps1 -Mounthost ubuntusrv01 -Scanhost lnxvm01 -Jobname demo_vm -Keyfile .\key.key -AVScan
     
    Scan VM lnxvm01 on Linux host ubuntusrv01 from backup demo_vm and start a restore (Currently only the command gets printed out - Line 148)
    .\vbr-securerestore.ps1 -Mounthost ubuntusrv01 -Scanhost lnxvm01 -Jobname demo_vm -Keyfile .\key.key -AVScan -Restore 
             
    Scan VM lnxvm01 on Linux host ubuntusrv01 from VM backup demo_vm resding on tape. Restore the backup data from tape onto Repository win_local_01
    .\vbr-securerestore.ps1 -Mounthost ubuntusrv01 -Scanhost lnxvm01 -Jobname demo_vm -Keyfile .\key.key -VMTape -Repository win_local_01
    
    Scan VM lnxvm01 on Linux host ubuntusrv01 from Agent backup demo_agent resding on tape. Restore the backup data from tape onto Repository win_local_01
    .\vbr-securerestore.ps1 -Mounthost ubuntusrv01 -Scanhost lnxvm01 -Jobname demo_agent -Keyfile .\key.key -AgentTape -Repository win_local_01
 .NOTES  
    File Name  : vbr-secrurerestore.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12, Linux host with ClamAV installed, OpenSSH Keyfile
                 More details https://community.veeam.com/script-library-67/vbr-securerestore-lnx-ps1-secure-restore-for-linux-vm-4617
.VERSION
1.2a
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
    [Parameter(Mandatory=$false)]
    [Switch]$AVScan,
    [Switch]$YARAScan,
    [string]$Repository,
    [Switch]$Restore,
    [Switch]$VMTape,
    [Switch]$AgentTape
    )
Clear-Host

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
# end function

# Get Backups on Tape
if ($VMTape -or $AgentTape){
$Result = Get-VBRTapeBackup -WarningAction Ignore | Where-Object { $_.jobname -eq $JobName+" on Tape" } | Get-VBRRestorePoint | Where-Object { $_.name -eq $Scanhost } | Sort-Object CreationTime -Descending
}

# Or get Backups on Disk/Object
else{
$Result = Get-VBRBackup | Where-Object { $_.jobname -eq $JobName } | Get-VBRRestorePoint | Where-Object { $_.name -eq $Scanhost } | Sort-Object CreationTime -Descending
}

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

Write-Host
# Set the Linux Server where scanning will take place. Note: This host needs to be added to VBR 
$lnxHost          = Get-VBRServer -Name $Mounthost

# Get the configured credentials for the specified host where the backup will be mounted
$creds             = Get-VBRCredentials -Entity $lnxHost

# Get the selected restore point
$selectedRp        = $Result | Select-Object -Index $restorePointID 

# If Agent Backup is stored on tape
if ($AgentTape){
Start-VBRTapeRestore -WarningAction Ignore -RestorePoint $selectedRp -Repository $Repository | Out-Null
$tapeJob           = Get-VBRBackup | Where-Object { $_.jobname -eq $Jobname } | Get-VBRRestorePoint | Where-Object { $_.name -eq $Scanhost } | Sort-Object CreationTime -Descending
$selectedTapeRp    = $tapeJob | Where-Object { $_.Type -eq $selectedRp.Type -and $_.GetRepository().Name -eq $Repository}
$session           = Publish-VBRBackupContent -RestorePoint $selectedTapeRp -TargetServerName $mountHost-TargetServerCredentials $creds -EnableFUSEProtocol
}

# If VM Backup is stored on tape
elseif ($VMTape) {
Start-VBRTapeRestore -WarningAction Ignore -RestorePoint $selectedRp -Repository $Repository | Out-Null
$importedTapeJob = " from Tape"
$tapeImportName    = $Jobname+$importedTapeJob
$tapeJob           = Get-VBRBackup | Where-Object { $_.jobname -eq $tapeImportName } | Get-VBRRestorePoint | Where-Object { $_.name -eq $Scanhost } | Sort-Object CreationTime -Descending
$selectedTapeRp    = $tapeJob | Where-Object { $_.Type -eq $selectedRp.Type -and $_.'Creation Time' -eq $selectedRp.'Creation Time' }
$session           = Publish-VBRBackupContent -RestorePoint $selectedTapeRp -TargetServerName $mountHost-TargetServerCredentials $creds -EnableFUSEProtocol
}

# Check from regular backup
else{
$session           = Publish-VBRBackupContent -RestorePoint $selectedRp -TargetServerName $mountHost-TargetServerCredentials $creds -EnableFUSEProtocol
}

if($AVScan){
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
        if ($Restore -and $selectedRp.GetPlatform() -eq "EVmware"){
        Write-Host "Start-VBRRestoreVM -RestorePoint $restorePoint -Reason "Clean Restore - YaMT Secure Restore Linux" -ToOriginalLocation -StoragePolicyAction Default"
        }  
   }

# Write End Message
Write-Host "***Scanning end***" -ForegroundColor White
}
if($YARAScan){
# Start scanning using YARA
Write-Progress "Start Scanning..." -PercentComplete 95
$scanner           = ssh administrator@$mountHost -i $Keyfile "sudo yara -rfw ./yara-rules/rules/index.yar /tmp/Veeam.Mount.FS.*"
Write-Host     "***Scanning start***" -ForegroundColor White
$infectedFilesLine = $scanner -contains 'ANOMALY'
$infectedFilesLine
# Write End Message
Write-Host "***Scanning end***" -ForegroundColor White
}
  
# Stop Disk Publish Session
Unpublish-VBRBackupContent -Session $session 

# Delete restored backup from tape

if($AgentTape){
Get-VBRBackup | Where-Object { $_.GetRepository().Name -eq $Repository -and $_.JobName -eq $JobName } | Remove-VBRBackup -FromDisk -Confirm:$false | Out-Null
}
if($VMTape){
Remove-VBRBackup -Backup $tapeImportName -FromDisk -Confirm:$false | Out-Null
}

# Disconnect VBR Server
Disconnect-VBRServer
