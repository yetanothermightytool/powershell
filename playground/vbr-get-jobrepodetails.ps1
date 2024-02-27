# Variables
$vbrJobDetails = @()

# Connect to VBR server
Connect-VBRServer -Server localhost

# Get all Backup Jobs - Yes using a non supported command for computer backup job.
$vbrJobs = Get-VBRJob -WarningAction Ignore | Where-Object { $_.JobType -eq 'Backup' -or $_.JobType -eq 'EpAgentBackup' }

foreach ($vbrJob in $vbrJobs) {
    
    $obj = New-Object PSObject -Property @{
        JobName             = $vbrJob.Name
        RepositoryName      = $vbrJob.GetTargetRepository().Name
        RepositoryHost      = $vbrJob.GetTargetRepository().Host.Name
        FriendlyPath        = $vbrJob.GetTargetRepository().FriendlyPath
    }
    $vbrJobDetails += $obj
    
}

# Display the results
$vbrJobDetails | Select-Object JobName, RepositoryName, RepositoryHost, FriendlyPath | Format-Table -AutoSize

Disconnect-VBRServer
