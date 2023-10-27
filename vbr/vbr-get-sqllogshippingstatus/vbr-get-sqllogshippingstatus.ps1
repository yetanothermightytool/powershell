Param(
    [Parameter(Mandatory=$true)]
    [string]$VBRServer,
    [Parameter(Mandatory=$true)]
    [int]$RPO
)

Clear-Host
# Variables
$sqlJobData = @()

# Connect to VBR server
Connect-VBRServer -Server $VBRServer

# Get all backup jobs
$vbrJobs = Get-VBRJob -WarningAction Ignore

# Loop through each job and get the job names where logshipping is enabled
foreach ($vbrJob in $vbrJobs) {
    $sqlJobObjects = Get-VBRJobObject -Job $vbrJob | Where-Object { $_.VssOptions.SqlBackupOptions.BackupLogsEnabled -eq $true }
      
    if ($sqlJobObjects.Count -gt 0) {
        $sqlJobName = $vbrJob.Name
        $sqlJob              = $vbrJob.FindChildSqlLogBackupJob()
        $session             = $sqlJob.FindLastSession()
        $taskSession         = Get-VBRTaskSession -Session $session
        $logBackupLogs       = $taskSession.Logger.GetLog().UpdatedRecords
        $lastSessionStartLog = $logBackupLogs | ? { $_.Title.Contains("New transaction log backup interval started") } | Select -Last 1
        $lastSessionEndLog   = $logBackupLogs | ? { $_.Title.Contains("Transaction log backup completed") } | Select -Last 1

        # Calculate the RPO time
        $currentDateTime     = Get-Date
        $rpoTime             = $lastSessionEndLog.StartTime.AddMinutes($RPO)

        # Calculate the difference
        $rpoDifference       = [Math]::Round(($currentDateTime - $rpoTime).TotalMinutes, 2)

        # Determine if RPO is good (yes/no) and choose a color
        if ($rpoDifference -ge 0) {
            $rpoStatus = "no"
        } else {
            $rpoStatus = "yes"
        }

        $sqlJobData += [PSCustomObject]@{
            "Job Name"   = $sqlJobName
            "Start Time" = $lastSessionStartLog.StartTime
            "Stop Time"  = $lastSessionEndLog.StartTime
            "RPO good"   = $rpoStatus
            
        }
    }
}

$sqlJobData | Format-Table -AutoSize -Property "Job Name", "Start Time", "Stop Time", "RPO good"

Disconnect-VBRServer
