Param(
    [Parameter(Mandatory=$true)]
    [string]$JobName,
    [Parameter(Mandatory=$true)]
    [string]$Depth
  )

# Variables
$finalResult   = @()
$bkpJob          = Get-VBRJob -Name $JobName -WarningAction SilentlyContinue
$bkpSession      = Get-VBRBackupSession| Where {$_.jobId -eq $bkpJob.Id.Guid} | Where-Object  {$_.sessioninfo.SessionAlgorithm  -eq "Increment"} | Sort EndTimeUTC -Descending

# Put the information together
for ($i = 0; $i -le $bkpSession.count; $i++) {
    foreach ($sessDetails in $bkpSession) {
    $finalResult       += New-Object psobject -Property @{
    TransferedSize     = $sessDetails[0].sessioninfo.Progress.TransferedSize[$i]
               }   
             }
           }

# Get the last x values (Depth) from the array
$lastValues = $finalResult.TransferedSize[0..$Depth]

# Calculate the average of the last x backups
$average = ($lastValues | Measure-Object -Average).Average

# Check if any of the last x backups are more than 50% larger than the average
if (($lastValues | Where-Object { $_ -gt $average * 1.5 }).Count -gt 0) {
    Write-Host "Unexpected growth detected in the last $Depth Backups!"
} else {
    Write-Host "No unexpected growth detected in the last $Depth Backups."
}                                                                                            
