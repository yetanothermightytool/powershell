# Variables
$finalResult     = @()
$bkpJob          = Get-VBRJob -Name "demo_vm_fra_obj_01" -WarningAction SilentlyContinue
$bkpSession      = Get-VBRBackupSession| Where {$_.jobId -eq $bkpJob.Id.Guid} | Sort EndTimeUTC -Descending

# Funciton to get Process ID - Credits to Tom Sightler
function Get-VbrJobSessionFromPID {
$parentpid = (Get-WmiObject Win32_Process -Filter "processid='$pid'").parentprocessid.ToString()
$parentcmd = (Get-WmiObject Win32_Process -Filter "processid='$parentpid'").CommandLine
$job       = Get-VBRJob -WarningAction SilentlyContinue | ?{$parentcmd -like "*"+$_.Id.ToString()+"*"}
$session   = Get-VBRBackupSession | ?{($_.OrigJobName -eq $job.Name) -and ($parentcmd -like "*"+$_.Id.ToString()+"*")}
    return $session
}

# Get Backup Session
$BackupSession = Get-VbrJobSessionFromPID

# Put the information together
for ($i = 0; $i -le $bkpSession.count; $i++) {
    foreach ($sessDetails in $bkpSession) {
    $finalResult       += New-Object psobject -Property @{
    TransferedSize     = $sessDetails[0].sessioninfo.Progress.TransferedSize[$i]
               }   
             }
           }

# Get the last 5 values from the array
$lastValues = $finalResult.TransferedSize[0..5]

# Calculate the average of the last 5 backups
$average = ($lastValues | Measure-Object -Average).Average

# Check if any of the last 5 backups are more than 10% larger than the average
if (($lastValues | Where-Object { $_ -gt $average * 1.1 }).Count -gt 0) {
    $BackupSession.Logger.AddWarning("Unexpected growth detected in the last 5 backups!")
} else {
    $BackupSession.Logger.AddSuccess("No unexpected growth detected in the last 5 backups.")
}                                                                                      
