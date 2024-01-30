# Variables
$vbrJobDetails = @()

# Connect to VBR server
Connect-VBRServer -Server hq-vbr1.demolab.local

# Get all VM Backup Jobs
$vbrJobs = Get-VBRJob -WarningAction Ignore | Where-Object { $_.JobType -eq 'Backup' }

foreach ($vbrJob in $vbrJobs) {
    $vbrJobObject = Get-VBRJobObject -Job $vbrJob

    if ($vbrJobObject.Count -gt 0) {
        $resolvedAddresses = @{}  # Reset the hashtable for each job

        $entityNames = $vbrJobObject.Name

        foreach ($entityName in $entityNames) {
            try {
                $resolvedAddress = Resolve-DnsName -Name $entityName -ErrorAction Stop | Where-Object { $_.QueryType -eq 'A' } | Select-Object -ExpandProperty IPAddress
                $resolvedAddresses[$entityName] = $resolvedAddress
            }
            catch {
                # catch timeouts if name can't be resolved
                if ($_.Exception.Message -match 'timeout period expired' -or $_.Exception.Message -match 'DNS name does not exist') {
                    $resolvedAddresses[$entityName] = 'n/a'
                }
                else {
                    throw
                }
            }
        }


        $timeOnly = $vbrJob.ScheduleOptions.StartDateTimeLocal.ToString("HH:mm:ss")

        $obj = New-Object PSObject -Property @{
            JobName             = $vbrJob.Name
            JobStartTime        = $timeOnly
            JobNextRun          = $vbrJob.GetScheduleOptions().NextRun
            ProtectedEntities   = $vbrJobObject.Name
            ProtectedEntitiesIP = $resolvedAddresses
        }

        $vbrJobDetails += $obj
    }
}

# Display the results
$vbrJobDetails | Select-Object JobName, JobStartTime, JobNextRun, ProtectedEntities, @{Name='ProtectedEntitiesIP';Expression={$_.ProtectedEntitiesIP.Values -join ', '}} | Format-Table -AutoSize

Disconnect-VBRServer
