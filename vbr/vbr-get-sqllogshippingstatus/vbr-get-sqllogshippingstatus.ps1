Param(
    [Parameter(Mandatory=$true)]
    [string]$VBRServer
    )
Clear-Host
# Variables
$sqlJobNames = @()

# Connect to VBR server
Connect-VBRServer -Server $VBRServer

# Get all backup jobs
$vbrJobs = Get-VBRJob -WarningAction Ignore

# Loop through each job and get the job names where logshipping is enabled
foreach ($vbrJob in $vbrJobs) {
    $sqlJobObjects = Get-VBRJobObject -Job $vbrJob | Where-Object { $_.VssOptions.SqlBackupOptions.BackupLogsEnabled -eq $true }
      
    if ($sqlJobObjects.Count -gt 0) {
        $sqlJobNames += $vbrJob.Name
    }
}

foreach ($sqlJobName in $sqlJobNames){

$job                 = Get-VBRJob -name $sqlJobName
$sqlJob              = $Job.FindChildSqlLogBackupJob()
$session             = $sqlJob.FindLastSession()
$taskSession         = Get-VBRTaskSession -Session $session
$logBackupLogs       = $taskSession.Logger.GetLog().UpdatedRecords
$lastSessionStartLog = $logBackupLogs | Where-Object { $_.Title.Contains("New transaction log backup interval started") } | Select -Last 1
$lastSessionEndLog   = $logBackupLogs | Where-Object { $_.Title.Contains("Transaction log backup completed") } | Select -Last 1

Write-Output $sqlJobName
Write-Output "Start Time Last Log Session:" $lastSessionStartLog.StartTime
Write-Output "Stop Time Last Log Session" $lastSessionEndLog.StartTime
}

Disconnect-VBRServer
