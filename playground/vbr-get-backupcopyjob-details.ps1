# Variables
$vbrCopyJobDetails = @()

# Connect to VBR server
Connect-VBRServer -Server localhost

# Get all Backup Copy Job Information
$vbrCopyJobs = Get-VBRBackupCopyJob

foreach ($vbrCopyJob in $vbrCopyJobs) {
        
        $obj = New-Object PSObject -Property @{
            CopyJobName         = $vbrCopyJob.Name
            CopyJobType         = $vbrCopyJob.Type
            ProtectedEntities   = $vbrCopyJob.BackupJob
        }
        $vbrCopyJobDetails += $obj
}

# Display the results
$vbrCopyJobDetails | Select-Object CopyJobName, CopyJobType, ProtectedEntities| Format-Table -AutoSize

Disconnect-VBRServer
