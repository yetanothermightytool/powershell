Param(
    [Parameter(Mandatory=$true)]
    [string]$VBRServer
    )

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

$job     = Get-VBRJob -name $sqlJobName
$sqlJob  = $Job.FindChildSqlLogBackupJob()
$Session = [Veeam.Backup.Core.CBackupSession]::GetByJob($sqlJob.Id) | sort creationtimeutc -Descending | select -First 10
Write-Host
Write-Host "Last 10 SQL log shipping session entries for Backup Job $sqlJobName"
$session
}
Disconnect-VBRServer
