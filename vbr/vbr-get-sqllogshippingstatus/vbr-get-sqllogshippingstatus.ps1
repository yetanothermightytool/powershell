Param(
    [Parameter(Mandatory=$true)]
    [string]$VBRServer,
    [Parameter(Mandatory=$true)]
    [int]$RPO
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

foreach ($sqlJobName in $sqlJobNames) {

    $job                 = Get-VBRJob -name $sqlJobName
    $sqlJob              = $Job.FindChildSqlLogBackupJob()
    $session             = $sqlJob.FindLastSession()
    $taskSession         = Get-VBRTaskSession -Session $session
    $logBackupLogs       = $taskSession.Logger.GetLog().UpdatedRecords
    $lastSessionStartLog = $logBackupLogs | ? { $_.Title.Contains("New transaction log backup interval started") } | Select -Last 1
    $lastSessionEndLog   = $logBackupLogs | ? { $_.Title.Contains("Transaction log backup completed") } | Select -Last 1

    # Calculate the RPO time
    $currentDateTime     = Get-Date
    $rpoTime             = $lastSessionEndLog.StartTime.AddMinutes($RPO)

    Write-Output $sqlJobName
    Write-Output "Start Time Last Log Session: " $lastSessionStartLog.StartTime
    Write-Output "Stop Time Last Log Session: " $lastSessionEndLog.StartTime
    Write-Host

    # Calculate the difference
    $rpoDifference       = [Math]::Round(($currentDateTime - $rpoTime).TotalMinutes, 2)

    # Check if RPO is greater than or equal to 0
   if ($rpoDifference -ge 0) {
    Write-Host "RPO exceeded by $rpoDifference minutes." -ForegroundColor Yellow
} else {
    Write-Host "RPO is within the specified time." -ForegroundColor Green
}
}

Disconnect-VBRServer
