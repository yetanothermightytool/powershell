<# 
.NAME
    Veeam Backup & Replication - Backup Checker
.DESCRIPTION
    This script checks for suspicious incremental backup sizes and analyzes the last 
    x (-Depth) incremental backup jobs and determines if the incremental size has grown above y% (-Growth).
    
    It also determines the duration of a job session that is above the specified percentage (-Duration), based on the amount of 
    last backup sessions (-Depth).

    This script is for use as a post-job script within a backup job. A warning message is generated in the corresponding backup job 
    if the threshold value was exceeded.

    Details can be found on https://github.com/yetanothermightytool/powershell/blob/master/vbr/vbr-job-scanner/README.md
.NOTES  
    File Name  : vbr-job-scanner-post-script.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12
.VERSION
    1.1
#>
Param(
    [Parameter(Mandatory=$true)]
    [string]$Depth,
    [Parameter(Mandatory=$false)]
    [string]$Growth,
    [Parameter(Mandatory=$false)]
    [string]$Duration
     )

# Funciton to get Process ID - Credits to Tom Sightler
function Get-VbrJobSessionFromPID {
$parentpid = (Get-WmiObject Win32_Process -Filter "processid='$pid'").parentprocessid.ToString()
$parentcmd = (Get-WmiObject Win32_Process -Filter "processid='$parentpid'").CommandLine
$job       = Get-VBRJob -WarningAction SilentlyContinue | ?{$parentcmd -like "*"+$_.Id.ToString()+"*"}
$session   = Get-VBRBackupSession | ?{($_.OrigJobName -eq $job.Name) -and ($parentcmd -like "*"+$_.Id.ToString()+"*")}
    return $session
}

# Function to get JobName from running process
function Get-VbrJobNameFromPID {
    $parentPid = (Get-WmiObject Win32_Process -Filter "processid='$pid'").parentprocessid.ToString()
    $parentCmd = (Get-WmiObject Win32_Process -Filter "processid='$parentPid'").CommandLine
    $cmdArgs = $parentCmd.Replace('" "','","').Replace('"','').Split(',')
    $jobName = (Get-VBRJob | ? {$cmdArgs[4] -eq $_.Id.ToString()}).Name
    return $jobName
}

# Variables
$finalResult     = @()
$bkpJobName      = Get-VbrJobNameFromPID
$bkpJob          = Get-VBRJob -Name $bkpJobName -WarningAction SilentlyContinue
$bkpSession      = Get-VBRBackupSession| Where-Object {$_.jobId -eq $bkpJob.Id.Guid} | Where-Object  {$_.sessioninfo.SessionAlgorithm -eq "Increment"} | Sort-Object EndTimeUTC -Descending

# Get Backup Session
$BackupSession   = Get-VbrJobSessionFromPID

# Put the information together
for ($i = 0; $i -le $bkpSession.count; $i++) {
    foreach ($sessDetails in $bkpSession) {
    $finalResult       += New-Object psobject -Property @{
    TransferedSize     = $sessDetails[0].sessioninfo.Progress.TransferedSize[$i]
               }   
             }
           }

### Backup Size Calculation ###
if($Growth){

# Get the last 5 values from the array
$lastValues = $finalResult.TransferedSize[0..$Depth]

# Calculate the average of the last 5 backups
$average = ($lastValues | Measure-Object -Average).Average

# Check if any of the last x backups are more than x% larger than the average
if (($lastValues | Where-Object { $_ -gt $average * $Growth }).Count -gt 0) {
    $BackupSession.Logger.AddWarning("Suspicious backup file sizes detected!")
} else {
    $BackupSession.Logger.AddSuccess("No unexpected growth detected in the last $Depth incremental Backups")
 }          
}

### Job Duration Calculation ###
if($Duration){

# Get the last x values (Depth) from the array
$lastValues = $finalResult.DurationSec[0..$Depth]

# Calculate the average of the last x backups
$average = ($lastValues | Measure-Object -Average).Average

# Check if any of the last x backups took more time than the average
if (($lastValues | Where-Object { $_ -gt $average * $Duration }).Count -gt 0) {
    $BackupSession.Logger.AddWarning("Unusual job duration")
} else {
    $BackupSession.Logger.AddSuccess("Normal job duration")
 }                                                                                 
}
