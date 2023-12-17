Param(
    [Parameter(Mandatory=$true)]
    [string]$Jobname,
    [Parameter(Mandatory=$true)]
    [string]$HostToScan
     )
Clear-Host
Connect-VBRServer -Server localhost

# Variables section
$host.ui.RawUI.WindowTitle = "VBR Scan Backup"
$backup                    = Get-VBRBackup | Where-Object { $_.jobname -eq $Jobname } 
$bkpObjects                = Get-VBRBackupObject -Backup $backup | Where-Object {$_.IsLinux -ne "False" -and $_.Name -eq $HostToScan}
$yaraRules                 = Get-VBRYARARule

# No backup no scan
if ($bkpObjects.Count -eq 0) {
	Write-Host 'Unable to locate any restore points for scanning in backup job' $Jobname 'for host' $HostToScan -ForegroundColor Yellow
    Disconnect-VBRServer
	Exit

} else {
    $timeoutSeconds = 30
    $stopTime = [datetime]::Now.AddSeconds($timeoutSeconds)

    Write-Host "Available YARA rules:" -ForegroundColor White
    for ($i = 0; $i -lt $yaraRules.Count; $i++) {
        Write-Host "$($i + 1). $($yaraRules[$i])" -ForegroundColor White
    }
    Write-Host
    Write-Host "Enter YARA rule number(s) - comma-separated - or press Enter for all rules. All rules will be used after $timeoutSeconds seconds." -ForegroundColor Cyan

    while ([datetime]::Now -lt $stopTime -and -not [console]::KeyAvailable) {
        Start-Sleep -Milliseconds 50
    }

    if ([console]::KeyAvailable) {
        $selectedRulesInput = [console]::ReadLine()

        while ($selectedRulesInput -ne "" -and ($selectedRulesInput -split ',' | ForEach-Object { $_ -as [int] }) -eq $null) {
            Write-Host "Invalid input. Please enter valid rule numbers." -ForegroundColor Red
            $selectedRulesInput = [console]::ReadLine()
        }

        if ($selectedRulesInput -ne "") {
            $selectedRulesIndices = $selectedRulesInput -split ',' | ForEach-Object { $_ -as [int] }

            $selectedRulesIndices = $selectedRulesIndices | Where-Object { $_ -ge 1 -and $_ -le $yaraRules.Count }

            if ($selectedRulesIndices.Count -gt 0) {
                $selectedYaraRules = $selectedRulesIndices | ForEach-Object { $yaraRules[$_ - 1] }
            } else {
                Write-Host "No valid YARA rule selected. Bye bye." -ForegroundColor Yellow
                Disconnect-VBRServer
                exit
            }
        } else {
            Write-Host "No YARA rule selected. Using all YARArules." -ForegroundColor Yellow
            $selectedYaraRules = $yaraRules
        }
    } else {
        
        Write-Host "You pressed Enter! Let's use all YARA rules." -ForegroundColor Yellow
        $selectedYaraRules = $yaraRules
       }

    }
 
 # Start scanning
    foreach ($bkpObject in $bkpObjects) {
    Write-Host "Processing object: $bkpObject" -ForegroundColor White

    foreach ($yaraRule in $selectedYaraRules) {
        Write-Host "Applying YARA rule $yaraRule" -ForegroundColor White
        Write-Host
        
        $result = Start-VBRScanBackup -Object $bkpObject -ScanMode FirstInInterval -EnableYARAScan -YARARule $yaraRule
    }
        Write-Host "Finished processing object: $object"
    }
 
Disconnect-VBRServer
