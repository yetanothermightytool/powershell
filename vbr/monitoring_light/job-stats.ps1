param(
    [Parameter(Mandatory = $false)]
    [String] $DaysBack = "7",
    [String] $JobType  = "0"
)

# Get the date 7 (Default) days ago
$startDate  = (Get-Date).AddDays(-$DaysBack)

# Get job statistics using the Get-WmiObject command
$jobStats  = @(Get-WmiObject -Namespace ROOT\VeeamBS -Class JobSession | Where-Object {$_.JobType -eq $JobType} | Select-Object -Property StartTimeUTC, EndTimeUTC, JobDetails, JobName, JobType, ProcessedUsedSize, ProcessingRate, TransferredSize)

$results   = @()

foreach ($job in $jobStats) {
    $start = $null
    $end   = $null

    try {
        $start = [datetime]::ParseExact($job.StartTimeUTC.Substring(0, 14), 'yyyyMMddHHmmss', $null)
        $end   = [datetime]::ParseExact($job.EndTimeUTC.Substring(0, 14), 'yyyyMMddHHmmss', $null)
    }
    catch {
        Write-Host "Invalid date format for job $($job.JobName). Skipping..."
        continue
    }
        # Skip jobs outside the specified date range
    if ($start -lt $startDate) {
        continue
    }

    $processedUsedSize = [math]::Round([double]$job.ProcessedUsedSize / 1GB, 2)

    $processingRate = $null
    if ($job.ProcessingRate -match '^\d+(\.\d+)?$') {
        $processingRate = [math]::Round([double]$job.ProcessingRate / 1GB, 2)
    }

    $transferredSize = $null
    if ($job.TransferredSize -match '^\d+(\.\d+)?$') {
        $transferredSize = [math]::Round([double]$job.TransferredSize / 1GB, 2)
    }
    elseif ($job.TransferredSize -is [double]) {
        $transferredSize = [math]::Round($job.TransferredSize / 1GB, 2)
    }

    $results += [PSCustomObject]@{
        JobName = $job.JobName
        StartTime = $start
        EndTime = $end
        ProcessedUsedSize = $processedUsedSize
        ProcessingRate = $processingRate
        TransferredSize = $transferredSize
    }
}
$results
