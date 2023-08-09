Param(
    [Parameter(Mandatory=$true)]
    [string]$Depth,
    [Parameter(Mandatory=$true)]
    [string]$Growth
)

# Variables
$finalResult = @()
$suspiciousIncrBackups = @()
$allValues = @()

# Get VBR Job Information
$bkpJobs = Get-VBRJob -WarningAction SilentlyContinue | Where-Object { $_.JobType -eq "Backup" }

# Go through each job
foreach ($bkpJob in $bkpJobs) {
    $bkpSession = Get-VBRBackupSession | Where-Object { $_.jobId -eq $bkpJob.Id.Guid } | Where-Object { $_.sessioninfo.SessionAlgorithm -eq "Increment" } | Sort-Object EndTimeUTC -Descending

    ### Backup Size Calculation ###
    if ($Growth) {
        # Put the information together
        $finalResult = @()
        for ($i = 0; $i -lt $bkpSession.Count; $i++) {
            $sessDetails = $bkpSession[$i]
            $finalResult += New-Object psobject -Property @{
                TransferedSize = $sessDetails.sessioninfo.Progress.TransferedSize
                DurationSec = $sessDetails.sessioninfo.Progress.Duration.TotalSeconds
                JobName = $bkpJob.Name
            }
        }

        # Get the last x values (Depth) from the array
        $lastValues = $finalResult.TransferedSize[0..($Depth - 1)]

        # Store all values used for the calculation in the $allValues array
        $allValues += $lastValues

        # Calculate the average of the last x backups
        $average = ($lastValues | Measure-Object -Average).Average

        # Calculate the median of the last x backups
        $sortedValues = $lastValues | Sort-Object
        $count = $sortedValues.Count

        if ($count % 2 -eq 0) {
            # If the count is even, take the average of the two middle elements
            $middleIndex1 = ($count / 2) - 1
            $middleIndex2 = $count / 2
            $median = ($sortedValues[$middleIndex1] + $sortedValues[$middleIndex2]) / 2
        } else {
            # If the count is odd, take the middle element
            $middleIndex = [math]::Floor($count / 2)
            $median = $sortedValues[$middleIndex]
        }

        # Check if any of the last x backups are more than y% larger than the average or median
        $suspiciousType = ""
        if ($average -gt 0 -and ($lastValues | Where-Object { $_ -gt $average * $Growth }).Count -gt 0) {
            $suspiciousType += "Average"
        }
        if ($median -gt 0 -and ($lastValues | Where-Object { $_ -gt $median * $Growth }).Count -gt 0) {
            if ($suspiciousType -ne "") {
                $suspiciousType += " and Median"
            } else {
                $suspiciousType += "Median"
            }
        }

        if ($suspiciousType -ne "" -and ($average -ne 0 -or $median -ne 0) -and ($average * $Growth -gt 0 -or $median * $Growth -gt 0) -and ($lastValues | Where-Object { $_ -gt $average * $Growth }).Count -gt 0) {
            $suspiciousIncrBackups += New-Object psobject -Property @{
                Count = ($lastValues | Where-Object { $_ -gt $average * $Growth }).Count
                JobName = $bkpJob.Name
                Median = [Math]::Round($median / 1GB, 2)
                Average = [Math]::Round($average / 1GB, 2)
                Type = $suspiciousType
            }

            # Display the intermediate values for this suspicious job in a custom format (values in GB)
            Write-Host "Intermediate values for Suspicious Job: $($bkpJob.Name)"
            $finalResult | Select-Object -First $Depth | ForEach-Object {
                [PSCustomObject]@{
                    'Transfered Size (GB)' = [Math]::Round($_.TransferedSize / 1GB, 2)
                    'Duration (Sec)'  = $_.DurationSec
                }
            } | Format-Table -AutoSize
        }
    }
}

# Output the result with the desired column order as a formatted table
if ($suspiciousIncrBackups.Count -gt 0) {
    Write-Host "Suspicious Incremental Backups:"
    $suspiciousIncrBackups | Where-Object { $_.Count -ne 0 } | Format-Table Count, JobName, @{Name="Average (GB)"; Expression={$_.Average}}, @{Name="Median (GB)"; Expression={$_.Median}}, Type
} else {
    Write-Host "No Suspicious Incremental Backups found."
}
