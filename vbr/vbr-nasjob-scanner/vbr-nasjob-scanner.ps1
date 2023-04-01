<# 
.NAME
    Veeam Backup & Replication - NAS Backup Checker
.DESCRIPTION
    This script checks for an unexpectedly high number of files that have been backed up compared to the last time.

    Details can be found on https://github.com/yetanothermightytool/powershell/blob/master/vbr/vbr-nasjob-scanner/README.md
    .NOTES  
    File Name  : vbr-nasjob-scanner.ps1
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

# Variables
$finalResult        = @()
$NASBkpJob          = Get-VBRNASBackupJob -Name $JobName

foreach($NASBkpJobPath in $NASBkpJob.BackupObject.Path){
$NASBkpJobSession   = Get-VBRNASBackupTaskSession -Name $NASBkpJobPath | Sort EndTime -Descending

# Compiling the information
for ($i = 0; $i -le $NASBkpJobSession.count; $i++) {
    foreach ($sessDetails in $NASBkpJobSession) {
    $finalResult       += New-Object psobject -Property @{
    TransferredFiles     = $sessDetails[$i].progress.TransferredFilesCount
               }   
             }
           }

# Get the last x values (Depth) from the array
$lastValues = $finalResult.TransferredFiles[0..$Depth]

# Calculate the average of the last x backups
$average = ($lastValues | Measure-Object -Average).Average

# Check if any of the last x backups transferred more files than the average
if (($lastValues | Where-Object { $_ -gt $average * $Growth }).Count -gt 0) {
    Write-Host "Unexpected growth detected in the last $Depth Backups for path $NASBkpJobPath" $lastValues
} else {
    Write-Host "No unexpected growth detected in the last $Depth Backup for path $NASBkpJobPath " $lastValues
}      
}                                                                                      
