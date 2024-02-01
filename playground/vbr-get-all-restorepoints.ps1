param(
    [Parameter(Mandatory = $true)]
    [String] $JobName,
    [Parameter(Mandatory=$true)]
    [String] $Hostname
)
Connect-VBRServer -Server localhost

# Get backup job sessions
$vbrBkpSessions = Get-VBRBackupSession -Name "*$JobName*" -WarningAction Ignore

# Get restore points
$vbrRp          = Get-VBRRestorePoint -Backup $JobName

# Filter
$matchedEntries  = foreach ($rp in $vbrRp) {
    $matchingJob = $vbrBkpSessions | Where-Object { $_.Id -eq $rp.JobRunId -and $rp.Name -eq $Hostname }
    
    if ($matchingJob) {
        [PSCustomObject]@{
            JobName          = $matchingJob.Name
            VMName           = $rp.Name
            EndTimeUTC       = $matchingJob.EndTimeUTC
            RansomwareStatus = $rp.GetRansomwareStatus().Status
        }
    }
}

$sortedEntries = $matchedEntries | Sort-Object -Property EndTimeUTC -Descending
$sortedEntries | Format-Table -AutoSize

Disconnect-VBRServer
