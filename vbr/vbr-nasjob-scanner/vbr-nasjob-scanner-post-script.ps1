<# 
.NAME
    Veeam Backup & Replication - NAS Backup Checker
.DESCRIPTION
    This script checks for an unexpectedly high number of files that have been backed up compared to the last time.
    
    This script is for use as a post-job script within a backup job. A warning message is generated in the corresponding backup job 
    if the threshold value was exceeded

    Details can be found on https://github.com/yetanothermightytool/powershell/blob/master/vbr/vbr-nasjob-scanner/README.md
.NOTES  
    File Name  : vbr-nasjob-scanner-post-script.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12
.VERSION
    1.0
#>
Param(
    [Parameter(Mandatory=$true)]
    [string]$JobName,
    [Parameter(Mandatory=$true)]
    [string]$Depth,
    [Parameter(Mandatory=$true)]
    [string]$Growth
     )

# Funciton to get Process ID - Credits to Tom Sightler
function Get-VbrJobSessionFromPID {
$parentpid = (Get-WmiObject Win32_Process -Filter "processid='$pid'").parentprocessid.ToString()
$parentcmd = (Get-WmiObject Win32_Process -Filter "processid='$parentpid'").CommandLine
$job       = Get-VBRJob -WarningAction SilentlyContinue | ?{$parentcmd -like "*"+$_.Id.ToString()+"*"}
$session   = Get-VBRBackupSession | ?{($_.OrigJobName -eq $job.Name) -and ($parentcmd -like "*"+$_.Id.ToString()+"*")}
    return $session
}

# Variables
$finalResult        = @()
$NASBkpJob          = get-vbrnasbackupjob -Name $JobName

foreach($NASBkpJobPath in $NASBkpJob.BackupObject.Path){
$NASBkpJobSession   = Get-VBRNASBackupTaskSession -Name $NASBkpJobPath | Sort EndTime -Descending

# Compiling the information
for ($i = 0; $i -le $NASBkpJobSession.count; $i++) {
    foreach ($sessDetails in $NASBkpJobSession) {
    $sessDetails[$i].progress.TransferredFilesCount
    $finalResult       += New-Object psobject -Property @{
    TransferredFiles     = $sessDetails[$i].progress.TransferredFilesCount
               }   
             }
           }

# Get the last x values (Depth) from the array
$lastValues = $finalResult.TransferredFiles[0..$Depth]

# Calculate the average of the last x backups
$average = ($lastValues | Measure-Object -Average).Average

$BackupSession   = Get-VbrJobSessionFromPID

# Check if any of the last x backups transferred more files than the average
if (($lastValues | Where-Object { $_ -gt $average * $Growth }).Count -gt 0) {
    $BackupSession.Logger.AddWarning("Unexpectedly high number of files backed up compared to the last $Depth backups for path $NASBkpJobPath!")
} else {
    $BackupSession.Logger.AddSuccess("No unexpected growth detected in the last $Depth backups for path $NASBkpJobPath.")
}
}                                                                                      
