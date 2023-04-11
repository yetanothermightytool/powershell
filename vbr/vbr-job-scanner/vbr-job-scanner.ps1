<# 
.NAME
    Veeam Backup & Replication - Backup Checker
.DESCRIPTION
    This script checks for suspicious incremental backup sizes and analyzes the last 
    x (-Depth) incremental backup jobs and determines if the incremental size has grown above y% (-Growth).
    
    It also determines the duration of a job session that is above the specified percentage (-Duration), based on the amount of 
    last backup sessions (-Depth).

    Details can be found on https://github.com/yetanothermightytool/powershell/blob/master/vbr/vbr-job-scanner/README.md
.NOTES  
    File Name  : vbr-job-scanner.ps1		
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12
.VERSION
    1.1
#>
Param(
    [Parameter(Mandatory=$true)]
    [string]$JobName,
    [Parameter(Mandatory=$true)]
    [string]$Depth,
    [Parameter(Mandatory=$false)]
    [string]$Growth,
    [Parameter(Mandatory=$false)]
    [string]$Duration
  )

# Variables
$finalResult   = @()
$bkpJob          = Get-VBRJob -Name $JobName -WarningAction SilentlyContinue
$bkpSession      = Get-VBRBackupSession| Where-Object {$_.jobId -eq $bkpJob.Id.Guid} | Where-Object  {$_.sessioninfo.SessionAlgorithm  -eq "Increment"} | Sort-Object EndTimeUTC -Descending

# Put the information together
for ($i = 0; $i -le $bkpSession.count; $i++) {
    foreach ($sessDetails in $bkpSession) {
    $finalResult       += New-Object psobject -Property @{
    TransferedSize     = $sessDetails[0].sessioninfo.Progress.TransferedSize[$i]
    DurationSec        = $sessDetails[0].sessioninfo.Progress.Duration.TotalSeconds[$i]
               }   
             }
           }

### Backup Size Calculation ###
if($Growth){

# Get the last x values (Depth) from the array
$lastValues = $finalResult.TransferedSize[0..$Depth]

# Calculate the average of the last x backups
$average = ($lastValues | Measure-Object -Average).Average

# Check if any of the last x backups are more than y% larger than the average
if (($lastValues | Where-Object { $_ -gt $average * $Growth }).Count -gt 0) {
    Write-Host "Suspicious backup file sizes detected!" 
} else {
    Write-Host "No unexpected growth detected in the last $Depth incremental Backups." 
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
    Write-Host "Unusual job duration" 
} else {
    Write-Host "Normal job duration" 
 }
}
