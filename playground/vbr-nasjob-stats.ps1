Param(
    [Parameter(Mandatory=$true)]
    [string]$JobName,
    [Parameter(Mandatory=$true)]
    [string]$Depth
  )

$finalResult              = @()
$transferredTotalBytes    = 0
$NASBkpJob                = Get-VBRNASBackupJob -Name $JobName

foreach ($NASBkpJobPath in $NASBkpJob.BackupObject.Path) {
    $NASBkpJobSession = Get-VBRNASBackupTaskSession -Name $NASBkpJobPath | Sort-Object EndTime -Descending

    foreach ($sessDetails in $NASBkpJobSession) {
        $transferredFiles = $sessDetails.Progress.TransferredFilesCount
        $skippedSize      = $sessDetails.Progress.SkippedNotChangedSize
        $processedSize    = $sessDetails.Progress.ProcessedSize

        if ($skippedSize -eq 0 -and $processedSize -gt 0) {
            $dataTransferred        = $true
            $transferredAmountBytes = $processedSize
        } else {
            $dataTransferred        = $false
            $transferredAmountBytes = 0
        }

        $finalResult += New-Object psobject -Property @{
            TransferredFiles        = $transferredFiles
            SkippedNotChangedSize   = $skippedSize
            ProcessedSize           = $processedSize
            DataTransferred         = $dataTransferred
            TransferredAmountBytes  = $transferredAmountBytes
        }

        $transferredTotalBytes     += $transferredAmountBytes
    }
}
$transferredTotalGB = [math]::Round($transferredTotalBytes / 1GB, 2)

$finalResult | Format-Table -AutoSize
Write-Host "Total transferred data: $transferredTotalGB GB"
