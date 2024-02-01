Clear-Host
# Variables
$startDate          = (Get-Date).AddDays(-7)
$winEventLogEntries = @()

# Get Veeam Security related Event-ID 41600 
Write-Host "Checking for Event-ID 41600..." -ForegroundColor Cyan

$securityActivityEvents = Get-WinEvent -FilterHashtable @{
    LogName    = 'Veeam Backup'
    ID         = 41600
    StartTime  = $startDate
} | Where-Object { 
    ($_.ID -eq 41600 )
} | Sort-Object TimeCreated -Descending

if ($securityActivityEvents.Count -gt 0) {
    Write-Host "Event-ID 41600 entries found..." -ForegroundColor Cyan
    Write-Host "Getting restore point(s) marked as Suspicious or Infected..." -ForegroundColor Cyan

    # Start VBR Part
    Connect-VBRServer -Server localhost

    # Get backup job sessions
    $vbrBkpSessions = Get-VBRBackupSession  -WarningAction Ignore

    # Get restore points
    $vbrRp          = Get-VBRRestorePoint 

    # Filter
    $matchedEntries  = foreach ($rp in $vbrRp) {
        $matchingJob = $vbrBkpSessions | Where-Object { $_.Id -eq $rp.JobRunId -and $rp.GetRansomwareStatus().Status -ne "Clean" }
   
        if ($matchingJob) {
            [PSCustomObject]@{
                JobName          = $matchingJob.Name
                Id               = $rp.Id
                VMName           = $rp.Name
                EndTimeUTC       = $matchingJob.EndTimeUTC
                RansomwareStatus = $rp.GetRansomwareStatus().Status
            }
        }
    }

    $sortedEntries = $matchedEntries | Sort-Object -Property EndTimeUTC -Descending
    $sortedEntries | Format-Table -AutoSize

    Disconnect-VBRServer

    # Display the Event ID 41600 entries, the Hostname and the message
    foreach ($event in $securityActivityEvents) {
        
        # Use a regex to extract hostname from parentheses ()
        $extractedHostname = [regex]::Match($event.Message, '\(([^)]+)\)').Groups[1].Value

        # Add the modified entry to the array
        $winEventLogEntries += [PSCustomObject]@{
            TimeCreated       = $event.TimeCreated
            EventId           = $event.Id           
            Hostname          = $extractedHostname
            Message           = $event.Message -replace "`r`n", "`n"
        }
    }
     
    $winEventLogEntries | Format-Table
   
}

 # Nothing to do
else {
    Write-Host "No Event ID 41600 found"
    exit
}
