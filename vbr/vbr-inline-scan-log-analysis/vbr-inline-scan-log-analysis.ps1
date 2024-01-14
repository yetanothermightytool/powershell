<# 
.NAME
    Veeam Backup & Replication - Inline Scan Log Analysis
.DESCRIPTION
    This PowerShell script reads the Svc.VeeamDataAnalyzer.log file containing entries related to the inline scan.
    The script displays which metrics were identified during the analysis in a tabular format.
 .NOTES  
    File Name  : vbr-inline-scan-log-analysis
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12.1.pt-library-67/vbr-securerestore-lnx-ps1-secure-restore-for-linux-vm-4617
.VERSION
1.0
#>
Clear-Host
# Prepare environment
$logFilePath      = "C:\ProgramData\Veeam\Backup\Svc.VeeamDataAnalyzer.log"
$logContent       = Get-Content -Path $logFilePath

$metricsInfo      = @()
$capturingMetrics = $false

# Start extract
foreach ($line in $logContent) {
    
    if ($line -match "\[(\d{2}.\d{2}.\d{4} \d{2}:\d{2}:\d{2}.\d{3})\]\s+<\d+>\s+(Info|Warning)\s+\(\d+\)\s+\[RansomwareIndexAnalyzer\] VM \[([^\]]+)\]") {
        $date     = $matches[1]
        $severity = $matches[2]
        $vmName   = $matches[3]
                
        $capturingMetrics = $true
    }

    # Get metrics
    if ($capturingMetrics -and $line -match "Metrics:.*inPlaceEncryptionCrossC: \[([^\]]+)\], inPlaceEncryptionMagic: \[([^\]]+)\], hiEncryption: \[([^\]]+)\], loEncryption: \[([^\]]+)\], text: \[([^\]]+)\]") {
        $inPlaceEncryptionCrossC = $matches[1]
        $inPlaceEncryptionMagic  = $matches[2]
        $hiEncryption            = $matches[3]
        $loEncryption            = $matches[4]
        $text                    = $matches[5]

        # Add metrics information to the array
        $metricsInfo += [PSCustomObject]@{
            Date                    = $date
            VMName                  = $vmName
            InPlaceEncryptionCrossC = $inPlaceEncryptionCrossC
            InPlaceEncryptionMagic  = $inPlaceEncryptionMagic
            HiEncryption            = $hiEncryption
            LoEncryption            = $loEncryption
            RansomwareNotes         = $text
        }
                
        $capturingMetrics = $false
    }
}

$metricsInfo | Format-Table -AutoSize
