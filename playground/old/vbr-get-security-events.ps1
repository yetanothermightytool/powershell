Connect-VBRServer -Server localhost

$startDate = (Get-Date).AddDays(-7)
$vbrBuild  = (Get-VBRBackupServerInfo).Build

if ($vbrBuild.Major -eq 12 -and $vbrBuild.Minor-eq 1){

    $securityActivityEvents = Get-WinEvent -FilterHashtable @{
        LogName    = 'Veeam Backup'
        ID         = 390, 41600, 42210, 42220
        StartTime  = $startDate
    } | Where-Object { 
        ($_.ID -eq 41600 -or $_.ID -eq 42220 -or $_.ID -eq 390) -or 
        ($_.ID -eq 42210 -and $_.Message -notlike '*Malware detection session has finished with Success*')
    } | Sort-Object TimeCreated -Descending

    $securityActivityEvents | Select-Object TimeCreated, Id, LevelDisplayName, @{Name='Message'; Expression={$_.Message -replace "`r`n", "`n"}} | Format-List

    foreach ($event in $securityActivityEvents) {
        if ($event.Id -eq 390 -and $event.Message -like '*Scanning with YARA rule*') {
            $logDirectory = 'C:\ProgramData\Veeam\Backup\Malware_Detection_Logs' 

            if (Test-Path $logDirectory) {
                $logFiles = Get-ChildItem -Path $logDirectory -Filter *.log

                foreach ($logFile in $logFiles) {
                    $additionalLogEntries = Get-Content $logFile.FullName | Where-Object { $_ -like '*<38> Warning (3)*' }

                    if ($additionalLogEntries.Count -gt 0) {
                        Write-Host "Log entries in '$($logFile.FullName)'" -ForegroundColor White
                        $additionalLogEntries | Format-Table -AutoSize
                    }
                }
            }
        }
    }
}
else { 
write-host "Not running on Veeam Backup & Replication 12.1"
}

Disconnect-VBRServer
