param (
    [int]$Port             = 8080,
    [int]$RefreshInterval  = 300,
    [String] $LogFilePath  = "C:\Temp\log.txt"
)
# Variables
$refreshInMs               = "{0}000" -f $RefreshInterval
$scanningToolsPath         = "D:\Scripts\vbr\scanningtools"
$lineBreaks                = '<br>' * 8
$host.ui.RawUI.WindowTitle = "Backup Sanning Tools Webmenu"

# Function to get the Warning Events from the Log file
function Get-Last10WarningEntries {
    $warningLines = @()

    if (Test-Path $LogFilePath) {
        $fileContents = Get-Content $LogFilePath
        $warningLines = $fileContents | Where-Object { $_ -match "\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}.*Warning" } | ForEach-Object {
            $logEntry = $_
            $timestamp = [regex]::Match($logEntry, "\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}").Value
            $dateTime = [datetime]::ParseExact($timestamp, 'dd-MM-yyyy HH:mm:ss', $null)
            [PSCustomObject]@{
                DateTime = $dateTime
                LogEntry = $logEntry
            }
        }
        $warningLines = $warningLines | Sort-Object { $_.DateTime }
        # Select the last 10 entries across multiple dates
        $warningLines = $warningLines | Select-Object -Last 10 | Sort-Object { $_.DateTime } -Descending
    }
    $tableRows        = @()
    $isGrayBackground = $true

    foreach ($warningLine in $warningLines) {
        $warningEntry     = $warningLine.LogEntry.ToString().Replace("<", "&lt;").Replace(">", "&gt;").Replace("&", "&amp;").Replace('"', "&quot;").Replace("'", "&#39;")
        # Limit each line to 200 characters
        $warningEntry     = $warningEntry.Substring(0, [Math]::Min(200, $warningEntry.Length))
        
        $backgroundColor  = if ($isGrayBackground) { "lightgray" } else { "white" }
        $isGrayBackground = !$isGrayBackground
        $tableRow         = "<tr style='background-color: $backgroundColor;'><td>$warningEntry</td></tr>"
        $tableRows       += $tableRow
    }
    $table = "<table style='width: 100%;'><tbody>$($tableRows -join '')</tbody></table>"
    return $table
}
$warningLines = Get-Last10WarningEntries

# Function get Info Events
function Show-ScanEvents {
    $searchText            = "Scanning started"
    $fileContent           = Get-Content -Path $logFilePath
    $currentTime           = Get-Date
    $filteredEntries       = $fileContent | Where-Object {
        $timestampString   = ($_ -split ' - ')[0]
        $entryTime         = [DateTime]::ParseExact($timestampString, "dd-MM-yyyy HH:mm:ss", $null)
        $currentTime.Subtract($entryTime).TotalHours -lt 168
    }
    $scanEventsCount       = ($filteredEntries | Select-String -Pattern $searchText -AllMatches).Matches.Count

    return $scanEventsCount
}

# Function get Warning Events
function Show-ScanWarningEvents {
    $searchText = "Warning - "
    $fileContent           = Get-Content -Path $logFilePath
    $currentTime           = Get-Date
    $filteredEntries       = $fileContent | Where-Object {
        $timestampString   = ($_ -split ' - ')[0]
        $entryTime         = [DateTime]::ParseExact($timestampString, "dd-MM-yyyy HH:mm:ss", $null)
        $currentTime.Subtract($entryTime).TotalHours -lt 168
    }
    $scanEventsCount       = ($filteredEntries | Select-String -Pattern $searchText -AllMatches).Matches.Count

    return $scanEventsCount
}

# Function for getting suspicious incremental VM backup job size 
function Get-SuspiciousBackup {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Depth,
        [Parameter(Mandatory = $false)]
        [string]$Growth
        )
    $suspiciousIncrBackups = @()
    $bkpJobs               = Get-VBRJob -WarningAction SilentlyContinue | Where-Object { $_.JobType -eq "Backup" }

    foreach ($bkpJob in $bkpJobs) {
        $bkpSession = Get-VBRBackupSession | Where-Object { $_.jobId -eq $bkpJob.Id.Guid } | Where-Object { $_.sessioninfo.SessionAlgorithm -eq "Increment" } | Sort-Object EndTimeUTC -Descending

        ### Backup Size Calculation ###
            $finalResult = @()
            for ($i = 0; $i -lt $bkpSession.Count; $i++) {
                $sessDetails = $bkpSession[$i]
                $finalResult += New-Object psobject -Property @{
                    TransferedSize = $sessDetails.sessioninfo.Progress.TransferedSize
                    DurationSec    = $sessDetails.sessioninfo.Progress.Duration.TotalSeconds #Keeping this for the future
                    JobName        = $bkpJob.Name
                }   
            }
            # Get the last x values (Depth) from the array
            $lastValues = $finalResult.TransferedSize[0..($Depth - 1)]
            # Calculate the average of the last x backups
            $average = ($lastValues | Measure-Object -Average).Average
            # Check if any of the last x backups are more than y% larger than the average
            if (($lastValues | Where-Object { $_ -gt $average * $Growth }).Count -gt 0) {
                $suspiciousIncrBackups += New-Object psobject -Property @{
                    JobName = $bkpJob.Name
                    Count   = ($lastValues | Where-Object { $_ -gt $average * $Growth }).Count
                }
            }
        }
    return $suspiciousIncrBackups
}

# function to just get the suspicious backup job names
function Get-SuspiciousBackupJobNames {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Depth,
        [Parameter(Mandatory = $false)]
        [string]$Growth
        )
    $jobNames = @()
    $bkpJobs  = Get-VBRJob -WarningAction SilentlyContinue | Where-Object { $_.JobType -eq "Backup" }

    foreach ($bkpJob in $bkpJobs) {
        $bkpSession = Get-VBRBackupSession | Where-Object { $_.jobId -eq $bkpJob.Id.Guid } | Where-Object { $_.sessioninfo.SessionAlgorithm -eq "Increment" } | Sort-Object EndTimeUTC -Descending

        ### Backup Size Calculation ###
            $finalResult = @()
            for ($i = 0; $i -lt $bkpSession.Count; $i++) {
                $sessDetails = $bkpSession[$i]
                $finalResult += New-Object psobject -Property @{
                    TransferedSize = $sessDetails.sessioninfo.Progress.TransferedSize
                    JobName        = $bkpJob.Name
                }   
            }
            # Get the last x values (Depth) from the array
            $lastValues = $finalResult.TransferedSize[0..($Depth - 1)]
            # Calculate the average of the last x backups
            $average = ($lastValues | Measure-Object -Average).Average
            # Check if any of the last x backups are more than y% larger than the average
            if (($lastValues | Where-Object { $_ -gt $average * $Growth }).Count -gt 0) {
                $jobNames += $bkpJob.Name
            }
        }
     return $jobNames
}

# Function to log messages to the scaning tool log file
function Log-Message {
    param (
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry  = "$timestamp - $Message"
    Add-Content -Path $logFilePath -Value $logEntry
}

# Function for the different button actions
function Process-MenuChoice {
    param (
        [string]$choice,
        [string]$param1,
        [string]$param2,
        [string]$param3,
        [string]$param4,
        [string]$param5,
        [string]$param6,
        [string]$param7,
        [string]$param8,
        [string]$param9,
        [string]$param10,
        [string]$param11,
        [string]$param12,
        [string]$param13,
        [string]$param14,
        [string]$param15,
        [string]$param16,
        [string]$param17,
        [string]$param18,
        [string]$param19,
        [string]$param20,
        [string]$param21,
        [string]$param22,
        [string]$param23,
        [string]$param24,
        [string]$param25,
        [string]$param26,
        [string]$param27,
        [string]$param28
        )
    switch ($choice) {
        # Secure Restore - AV scan
        1 {
        $scriptPath = "$scanningToolsPath\vbr-securerestore.ps1"

        # Check if the tickbox (Restore) is checked
        if ($param20 -eq "true") {
            $arguments = "-Mounthost", $param1, "-Scanhost", $param2, "-Jobname", $param3, "-Keyfile", $param4, "-AVScan", "-Restore"
                } else {
            $arguments = "-Mounthost", $param1, "-Scanhost", $param2, "-Jobname", $param3, "-Keyfile", $param4, "-AVScan"
            }
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # NAS AV Scan
        2 {
            $scriptPath = "$scanningToolsPath\vbr-nas-avscanner.ps1"
            $arguments  = "-JobName", $param9
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # YARA Backup Scan
        3 {
            $scriptPath = "$scanningToolsPath\vbr-securerestore.ps1"
            $arguments  = "-Mounthost", $param5, "-Scanhost", $param6, "-Jobname", $param7, "-Keyfile", $param8, "-YARAScan"
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # Instant VM Disk Recovery - Scan from booted ISO Image 
        4 {
            $scriptPath = "$scanningToolsPath\vbr-instantdiskrecovery.ps1"
            $arguments  = "-Mounthost", $param10, "-Scanhost", $param11, "-Jobname", $param12, "-vCenter", $param13
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # Staged VM Restore
        5 {
            $scriptPath = "$scanningToolsPath\vbr-staged-restore.ps1"
            $arguments  = "-ESXiServer", $param14, "-VMName", $param15, "-Jobname", $param16, "-VirtualLab", $param17, "-StagingScript", $param18, "-Credentials", $param19
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # Clean Restore - AV scan
        6 {
        $scriptPath = "$scanningToolsPath\vbr-cleanrestore.ps1"
        # Check if the tickbox (Restore) is checked
        if ($param26 -eq "true") {
            $arguments = "-Mounthost", $param21, "-Scanhost", $param22, "-Jobname", $param23, "-Keyfile", $param24, "-MaxIterations", $param25, "-AVScan", "-Restore"
            } else {
            $arguments = "-Mounthost", $param21, "-Scanhost", $param22, "-Jobname", $param23, "-Keyfile", $param24, "-MaxIterations", $param25, "-AVScan"
            }
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # FLR Hashscanner
        7 {
            $scriptPath = "$scanningToolsPath\vbr-flr-hashscanner.ps1"
            $arguments  = "-VM", $param27, "-JobName", $param28
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
           default { return "Invalid choice." }
          }
}

# Start http listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Clear-Host
Write-Host "Starting Backup Scanning Tools Web Server..."
Write-Host "Web Server started. Listening for incoming requests on port $Port. Refresh interval $RefreshInterval"

# The HTML Website is defined down below
$menuHtml = @"
<!DOCTYPE html>
<html>
    <head>
        <title>Backup Scanning Tools</title>
        <style>
            body {
                font-family: Arial, Helvetica, sans-serif;
                background-color: #F1F1F1;
                margin: 0;
                padding: 0;
            }
            .header {
                background-color: #4CAF50;
                color: white;
                text-align: center;
                padding: 20px;
                margin: 0;
                width: 100%; 
                position: relative;
                display: flex;
                align-items: center;
            }
            .header h1 {
               color: white;
               text-align: left; 
            }
            .scan-count-container {
               position: absolute;
               width: 220px; 
               height: 75px;
               bottom: 50px;
               left: 20px;
               background-color: #E1E1E3;
               color: #5132EE;
               padding: 8px 16px;
               border-radius: 15px;
               font-size: 16px;
               font-weight: bold;
               display: flex;
               flex-direction: column;
               align-items: center; 
               justify-content: space-between;
            }
            .scan-warning-count-container {
               position: absolute;
               width: 220px; 
               height: 75px;
               bottom: 50px;
               left: 280px;
               background-color: #E1E1E3;
               color: #5132EE;
               padding: 8px 16px;
               border-radius: 15px;
               font-size: 16px;
               font-weight: bold;
               display: flex;
               flex-direction: column;
               align-items: center; 
               justify-content: space-between;
            }
            .suspicious-backup-container {
                position: absolute;
                width: 220px;
                height: 75px;
                bottom: 50px;
                left: 540px;
                background-color: #E1E1E3;
                color: #5132EE;
                padding: 8px 16px;
                border-radius: 15px;
                font-size: 16px;
                font-weight: bold;
                display: flex;
                flex-direction: column;
                align-items: center;
                justify-content: space-between;
            }
            .suspicious-backup-count {
                font-size: 24px;
                font-weight: bold;
                color: #5132EE;
            }
            .suspicious-backup-data {
                display: none;
                font-size: 16px;
                background-color: #333;
                color: #fff;
                padding: 5px;
                position: absolute;
                bottom: 100%;
                left: 0;
                width: 100%;
                width: 500px;
                white-space: pre-wrap; 
            }
            .scan-count,
            .scan-warning-count {
                font-size: 24px;
                font-weight: bold;
                color: #5132EE;
            }
            .help-button {
                width: 36px;
                height: 36px;
                background-color: #fff;
                color: #4CAF50;
                border-radius: 50%;
                font-size: 28px;
                text-align: center;
                z-index: 1;
                cursor: pointer;
                margin-left: auto; 
                margin-right: 75px; 
            }
            .help-tooltip {
                display: none;
                position: absolute;
                top: calc(100% + 5px);
                right: +80px;
                padding: 10px;
                background-color: rgba(0, 0, 0, 0.7);
                color: #fff;
                border-radius: 5px;
                font-size: 16px;
                z-index: 1;
            }
            .header:hover .help-tooltip {
                display: block; 
            }
            .button-container {
                display: flex;
                justify-content: flex-start;
                margin-top: 20px;
            }
            .button {
                background-color: #4CAF50;
                color: white;
                padding: 14px 20px;
                margin: 10px;
                border: none;
                border-radius: 10px;
                cursor: pointer;
                font-size: 16px;
            }
            .button:hover {
                background-color: #45a049;
            }
            .button:focus {
                outline: none;
            }
            .button:active {
                background-color: #3e8e41;
            }
            .container {
                display: flex;
                flex-direction: column;
                align-items: flex-start;
                justify-content: flex-start; 
                height: 100vh;
            }
            .menu {
                display: flex;
                flex-wrap: wrap;
                justify-content: flex-start; 
                align-items: flex-start; 
                flex-direction: column; 
                margin-top: 20px;
            }
            .parameter-dialog {
                display: none;
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background-color: #00000080;
            }
            .parameter-dialog-content {
                background-color: #FFFFFF;
                width: 400px;
                margin: 50px auto;
                padding: 20px;
                border-radius: 10px;
            }
            .parameter-input {
                display: block;
                margin-bottom: 10px;
                border: 1px solid #ccc;
                border-radius: 5px;
                padding: 8px;
                width: 100%;
                box-sizing: border-box;
            }
            .parameter-submit {
                background-color: #4CAF50;
                color: white;
                padding: 10px 20px;
                border: none;
                border-radius: 5px;
                cursor: pointer;
                font-size: 16px;
            }
            .parameter-submit:hover {
                background-color: #45a049;
            }
            .parameter-submit:focus {
                outline: none;
            }
            .parameter-submit:active {
                background-color: #3e8e41;
            }
            .timestamp {
                position: fixed;
                bottom: 0;
                left: 0;
                margin: 5px;
                color: gray;
                font-size: 12px;
            }
        </style>
    </head>
    <body>
        <div class="header">
            <img src="http://localhost:$Port/scanner.png" alt="Backup Scanning Tools" style="height: 80px; margin-right: 10px;">
            <h1>Backup Scanning Tools</h1>
        <div class="help-button">?</div>
        <div class="help-tooltip">
            <p>A collection of all the available backup scanning tools from the YAMT repository.</p>
            <p>It allows the user to choose from a number of options, each corresponding to a specific type of backup scan.</p>
            <p>Click on a button to perform a scan.</p>
        </div>
        </div>
        </div>
        <div class="button-container">
            <button class="button" onclick="showParameterDialog(1)">Secure Restore - AV scan</button>
            <button class="button" onclick="showParameterDialog(6)">Clean Restore - AV scan</button>
            <button class="button" onclick="showParameterDialog(3)">YARA Backup Scan</button>
            <button class="button" onclick="showParameterDialog(2)">NAS Backup AV Scan</button>
            <button class="button" onclick="showParameterDialog(4)">Instant VM Disk Recovery</button>
            <button class="button" onclick="showParameterDialog(5)">Staged VM Restore</button>
            <button class="button" onclick="showParameterDialog(7)">FLR Hashscanner</button>
        </div>
        $lineBreaks
        <h2>Last 10 Scan Warnings</h2>
        <div id="last10Warnings">Loading...</div>
          <div class="scan-count-container">
            <span>Started Scans</span>
            <span class="scan-count" id="eventCount">Loading...</span>
        </div>
        <div class="scan-warning-count-container">
            <span>Number of Scan Warnings</span>
            <span class="scan-warning-count" id="warningEventCount">Loading...</span>
        </div>
        <div class="suspicious-backup-container">
            <span>Suspicious Incr VM Backups</span>
            <span class="suspicious-backup-count" id="SuspiciousBackupCount">Loading...</span>
            <span class="suspicious-backup-data" id="SuspiciousBackupData"></span>
        </div>
        <div class="timestamp">
            V1.1 - Last refresh: $((Get-Date).ToString("dd-MM-yyyy HH:mm:ss")) 
        </div>
        
<!-- Parameter Dialog for Secure Restore - AV scan (Hidden by default) -->
<div id="parameterDialog1" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Secure Restore - AV Scan</p>
        <p>This option mounts the selected restore point of a Veeam VM or Agent backup using the Data Integration API function to a Linux server (mount server) and runs an anti-virus file-level scan using ClamAV.</p>
        <label for="param1-1">Host to attach backup to:</label>
        <input type="text" id="param1-1" class="parameter-input">

        <label for="param2-1">Host to scan:</label>
        <input type="text" id="param2-1" class="parameter-input">

        <label for="param3-1">Backup Job Name:</label>
        <input type="text" id="param3-1" class="parameter-input">

        <label for="param4-1">SSH key path & file name:</label>
        <input type="text" id="param4-1" class="parameter-input" placeholder="D:\Scripts\opensshkey.key">

        <label for="restoreAV">Restore:</label>
        <input type="checkbox" id="restoreAV-1" value="true" data-restore="false">
        <p> </p>

        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(1)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>

<!-- Parameter Dialog for NAS AV Scan (Hidden by default) -->
<div id="parameterDialog2" class="parameter-dialog">
        <div class="parameter-dialog-content">
        <p style="font-weight: bold;">NAS AV Scan</p>
        <p>This option initiates a MS Defender scan on a NAS backup using a designated backup job name.</p>
        <label for="param9-2">NAS Backup Job Name:</label>
        <input type="text" id="param9-2" class="parameter-input">

        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(2)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>

<!-- Parameter Dialog for YARA Backup Scan (Hidden by default) -->
<div id="parameterDialog3" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">YARA Backup Scan</p>
        <p>This option mounts the selected restore point of a Veeam VM or Agent backup using the Data Integration API function to a Linux server (mount server) and runs a YARA scan.</p>
        <label for="param5-1">Host to attach backup to:</label>
        <input type="text" id="param5-1" class="parameter-input">

        <label for="param6-1">Host to scan:</label>
        <input type="text" id="param6-1" class="parameter-input">

        <label for="param7-1">Backup Job Name:</label>
        <input type="text" id="param7-1" class="parameter-input">

        <label for="param8-1">SSH key path & file name:</label>
        <input type="text" id="param8-1" class="parameter-input">

        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(3)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>

<!-- Parameter Dialog for Instant VM Disk Reocvery (Hidden by default) -->
<div id="parameterDialog4" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Instant VM Disk Recovery - ISO Boot</p>
        <p>This option is specific to Instant VM Disk Recovery and allows the user to attach disk(s) to a virtual machine (VM) for scanning.<br><br><strong>Important!</strong> Make sure that the VM starts from the attached Rescue ISO.</p>
        <label for="param10-1">VM to attach backup to:</label>
        <input type="text" id="param10-1" class="parameter-input">

        <label for="param11-1">Hostname (Disk Source) to scan:</label>
        <input type="text" id="param11-1" class="parameter-input">

        <label for="param12-1">Backup Job Name:</label>
        <input type="text" id="param12-1" class="parameter-input">

        <label for="param13-1">vCenter Server Hostname/IP:</label>
        <input type="text" id="param13-1" class="parameter-input">

        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(4)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>

<!-- Parameter Dialog for Staged VM Restore(Hidden by default) -->
<div id="parameterDialog5" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Staged VM Restore</p>
        <p>This script triggers a staged VM recovery on the specified ESXi server and runs the specified script. If the script runs successfully, the VM is restored into production.</p>
        <label for="param14-1">Target ESXi server:</label>
        <input type="text" id="param14-1" class="parameter-input">

        <label for="param15-1">VM Name:</label>
        <input type="text" id="param15-1" class="parameter-input">

        <label for="param16-1">Backup Job Name:</label>
        <input type="text" id="param16-1" class="parameter-input">

        <label for="param17-1">Virtual Lab Name:</label>
        <input type="text" id="param17-1" class="parameter-input">

        <label for="param18-1">Staging Script (Full path):</label>
        <input type="text" id="param18-1" class="parameter-input">

        <label for="param19-1">Credentials for Script:</label>
        <input type="text" id="param19-1" class="parameter-input">

        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(5)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>

<!-- Parameter Dialog for Clean Restore - AV scan (Hidden by default) -->
<div id="parameterDialog6" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Clean Restore - AV Scan</p>
        <p>This script scans VM backup data using the Data Integration API. It traverses the restore points and searches for a clean point. If a clean restore point is found, the restore is initiated (if selected); otherwise, the restore is aborted after the specified iterations.</p>
        <label for="param21-1">Host to attach backup to:</label>
        <input type="text" id="param21-1" class="parameter-input">

        <label for="param22-1">Host to scan:</label>
        <input type="text" id="param22-1" class="parameter-input">

        <label for="param23-1">Backup Job Name:</label>
        <input type="text" id="param23-1" class="parameter-input">

        <label for="param24-1">SSH key path & file name:</label>
        <input type="text" id="param24-1" class="parameter-input" placeholder="D:\Scripts\opensshkey.key">

        <label for="param25-1">Number of iterations:</label>
        <input type="text" id="param25-1" class="parameter-input" placeholder="5">

        <label for="cleanRestore">Restore:</label>
        <input type="checkbox" id="cleanRestore-1" value="true" clean-restore="false">
        <p> </p>

        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(6)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>

<!-- Parameter Dialog for FLR hashscanner (Hidden by default) -->
<div id="parameterDialog7" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">FLR Hashscanner</p>
        <p>This Powershell script scans specific subfolders within a Veeam File Level Recovery session and checks if any of the scanned files match a SHA256 value by comparing the values to a list of known hash values. </p>
        <label for="param27-1">Windows VM to scan:</label>
        <input type="text" id="param27-1" class="parameter-input">

        <label for="param28-1">Backup Job Name:</label>
        <input type="text" id="param28-1" class="parameter-input">
        
        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(7)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>


<script>
        function updateTextColor(element) {
                    if (parseInt(element.innerText) > 0) {
                        element.style.color = 'orange';
                    } else {
                        element.style.color = 'darkblue';
                    }
       }

       function fetchEventCount() {
        fetch("http://localhost:8080/eventCount")
            .then(response => response.text())
            .then(eventCount => {
                var eventCountElement = document.getElementById("eventCount");
                eventCountElement.textContent = eventCount;
                
            })
            .catch(error => {
                alert("Failed to fetch data. Please try again later.");
                console.error(error);
            });
        }

        // Fetch the event count when the page is loaded
        window.addEventListener("load", function () {
            fetchEventCount();
        });

        function fetchWarningEventCount() {
        fetch("http://localhost:8080/warningEventCount")
            .then(response => response.text())
            .then(warningEventCount => {
                var warningEventCountElement = document.getElementById("warningEventCount");
                warningEventCountElement.textContent = warningEventCount;
                updateTextColor(warningEventCountElement);
            })
            .catch(error => {
                alert("Failed to fetch data. Please try again later.");
                console.error(error);
            });
        }

        // Fetch the warning event count when the page is loaded
        window.addEventListener("load", function () {
            fetchWarningEventCount();
        });

       function updateLast10Warnings() {
            fetch("http://localhost:8080/last10WarningEntries")
              .then(response => response.text())
              .then(tableHtml => {
                var warningTableDiv = document.getElementById("last10Warnings");
                warningTableDiv.innerHTML = tableHtml;
              })
              .catch(error => {
                alert("Failed to fetch data. Please try again later.");
                console.error(error);
              });
          }

          // Fetch the last 10 warning entries when the page is loaded
          window.addEventListener("load", function () {
            updateLast10Warnings();
          });
    
        let isDataFetched = false; // Keep track of whether data has been fetched

        function fetchSuspiciousBackupCount() {
            fetch("http://localhost:8080/SuspiciousBackupCount")
                .then(response => response.text())
                .then(SuspiciousBackupCount => {
                    const countElement = document.getElementById("SuspiciousBackupCount");
                    countElement.textContent = SuspiciousBackupCount;
                    updateTextColor(countElement);
                })
                .catch(error => {
                    alert("Failed to fetch data. Please try again later.");
                    console.error(error);
                });
        }

        function fetchSuspiciousBackupData() {
            fetch("http://localhost:8080/SuspiciousBackupJobNames")
                .then(response => response.text())
                .then(data => {
                    const customText = "Job Name(s): ";
                    const jobNames = data.trim().split('\n');

                    const dataElement = document.getElementById("SuspiciousBackupData");
                    dataElement.innerText = customText + jobNames.join(" // ");
                })
                .catch(error => {
                    alert("Failed to fetch data. Please try again later.");
                    console.error(error);
                });
        }

        fetchSuspiciousBackupCount();

        // Hovering fetch
        const container = document.querySelector(".suspicious-backup-container");
        const dataElement = document.getElementById("SuspiciousBackupData");

        container.addEventListener("mouseenter", () => {
            if (!isDataFetched) {
                fetchSuspiciousBackupData();
                isDataFetched = true;
            }
            dataElement.style.display = "block";
        });

        container.addEventListener("mouseleave", () => {
            dataElement.style.display = "none";
        });

        function showParameterDialog(choice) {
            var dialog1 = document.getElementById('parameterDialog1');
            var dialog2 = document.getElementById('parameterDialog2');
            var dialog3 = document.getElementById('parameterDialog3');
            var dialog4 = document.getElementById('parameterDialog4');
            var dialog5 = document.getElementById('parameterDialog5');
            var dialog6 = document.getElementById('parameterDialog6');
            var dialog7 = document.getElementById('parameterDialog7');
        if (choice === 1) {
            dialog1.style.display = 'block';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
            
            // Reset the input fields for Secure Restore - AV scan
            document.getElementById('param1-1').value = '';
            document.getElementById('param2-1').value = '';
            document.getElementById('param3-1').value = '';
            document.getElementById('param4-1').value = '';
            document.getElementById('restoreAV-1').checked = false;
        } else if (choice === 2) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'block';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
            // Reset the input fields for NAS AV Scan
            document.getElementById('param9-2').value = '';
        } else if (choice === 3) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'block';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
        // Reset the input fields for Secure Restore - YARA Scan
            document.getElementById('param5-1').value = '';
            document.getElementById('param6-1').value = '';
            document.getElementById('param7-1').value = '';
            document.getElementById('param8-1').value = '';
        } else if (choice === 4) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'block';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
        // Reset the input fields for Instant Disk Recovery
            document.getElementById('param10-1').value = '';
            document.getElementById('param11-1').value = '';
            document.getElementById('param12-1').value = '';
            document.getElementById('param13-1').value = ''; 
        }  else if (choice === 5) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'block';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
        // Reset the input fields for Staged VM Restore
            document.getElementById('param14-1').value = '';
            document.getElementById('param15-1').value = '';
            document.getElementById('param16-1').value = '';
            document.getElementById('param17-1').value = '';
            document.getElementById('param18-1').value = '';
            document.getElementById('param19-1').value = '';
        }  else if (choice === 6) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'block';
            dialog7.style.display = 'none';
        // Reset the input fields for Clean Restore
            document.getElementById('param21-1').value = '';
            document.getElementById('param22-1').value = '';
            document.getElementById('param23-1').value = '';
            document.getElementById('param24-1').value = '';
            document.getElementById('param25-1').value = '';
            document.getElementById('cleanRestore-1').checked = false;
        }  else if (choice === 7) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'block';
        // Reset the input fields for Clean Restore
            document.getElementById('param27-1').value = '';
            document.getElementById('param28-1').value = '';
        }


}
        function closeParameterDialog() {
            var dialog1 = document.getElementById('parameterDialog1');
            var dialog2 = document.getElementById('parameterDialog2');
            var dialog3 = document.getElementById('parameterDialog3');
            var dialog4 = document.getElementById('parameterDialog4');
            var dialog5 = document.getElementById('parameterDialog5');
            var dialog6 = document.getElementById('parameterDialog6');
            var dialog7 = document.getElementById('parameterDialog7');
    
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
        }

    function sendChoice(choice) {
        var param1, param2, param3, param4, param5, param6, param7, param8, param9, param10, param11, param12, param13, param14, param15, param16, param17, param18, param19, param20, param21, param22, param23, param24, param25, param26, param27, param28;
        var xhr = new XMLHttpRequest();

        if (choice === 1) {
            param1 = document.getElementById('param1-1').value;
            param2 = document.getElementById('param2-1').value;
            param3 = document.getElementById('param3-1').value;
            param4 = document.getElementById('param4-1').value;
            var checkbox = document.getElementById('restoreAV-1');
            param20 = checkbox.checked;
            checkbox.setAttribute('data-restore', param20 ? "true" : "false");
            
            if (!param1 || !param2 || !param3 || !param4) {
                alert("Please fill in all parameters.");
                return;
            }

            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        alert("Script executed successfully!");
                        console.log(xhr.responseText); 
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText); 
                    }
                }
            };
        } else if (choice === 2) {
            param9 = document.getElementById('param9-2').value;

            if (!param9) {
                alert("Please fill in all parameters.");
                return;
            }

            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        alert("Script executed successfully!");
                        console.log(xhr.responseText);
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText);
                    }
                }
            };
        } else if (choice === 3) {
            param5 = document.getElementById('param5-1').value;
            param6 = document.getElementById('param6-1').value;
            param7 = document.getElementById('param7-1').value;
            param8 = document.getElementById('param8-1').value;

            if (!param5 || !param6 || !param7 || !param8) {
                alert("Please fill in all parameters.");
                return;	
            }

            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        alert("Script executed successfully!");
                        console.log(xhr.responseText); 
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText); 
                    }
                }
            };
        }  else if (choice === 4) {
            param10 = document.getElementById('param10-1').value;
            param11 = document.getElementById('param11-1').value;
            param12 = document.getElementById('param12-1').value;
            param13 = document.getElementById('param13-1').value;

            if (!param10 || !param11 || !param12 || !param13) {
                alert("Please fill in all parameters.");
                return;
            }

            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        alert("Script executed successfully!");
                        console.log(xhr.responseText); // Log the response from the server - just for truuubleshuuting
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText); // Log any error response from the server - just for truuubleshuuting
                    }
                }
            };
        } else if (choice === 5) {
            param14 = document.getElementById('param14-1').value;
            param15 = document.getElementById('param15-1').value;
            param16 = document.getElementById('param16-1').value;
            param17 = document.getElementById('param17-1').value;
            param18 = document.getElementById('param18-1').value;
            param19 = document.getElementById('param19-1').value;

            if (!param14 || !param15 || !param16 || !param17 || !param18 || !param19) {
                alert("Please fill in all parameters.");
                return;
            }

            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        alert("Script executed successfully!");
                        console.log(xhr.responseText);
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText);
                    }
                }
            };
         } else if (choice === 6) {
            param21 = document.getElementById('param21-1').value;
            param22 = document.getElementById('param22-1').value;
            param23 = document.getElementById('param23-1').value;
            param24 = document.getElementById('param24-1').value;
            param25 = document.getElementById('param25-1').value;
            var checkbox = document.getElementById('cleanRestore-1');
            param26 = checkbox.checked;
            checkbox.setAttribute('clean-restore', param26 ? "true" : "false");

            if (!param21 || !param22 || !param23 || !param24 || !param25) {
                alert("Please fill in all parameters.");
                return;
            }

            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        alert("Script executed successfully!");
                        console.log(xhr.responseText);
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText);
                    }
                }
            };

          } else if (choice === 7) {
            param27 = document.getElementById('param27-1').value;
            param28 = document.getElementById('param28-1').value;
            
            if (!param27 || !param28) {
                alert("Please fill in all parameters.");
                return;
            }

            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        alert("Script executed successfully!");
                        console.log(xhr.responseText); // Log the response from the server - just for truuubleshuuting
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText); // Log any error response from the server - just for truuubleshuuting
                    }
                }
            };
            
        }   xhr.open("POST", "http://localhost:8080/processChoice", true);
            xhr.setRequestHeader("Content-Type", "application/json");
        var data = {
            choice: choice,
            param1: param1,
            param2: param2,
            param3: param3,
            param4: param4,
            param5: param5,
            param6: param6,
            param7: param7,
            param8: param8,
            param9: param9,
            param10: param10,
            param11: param11,
            param12: param12,
            param13: param13,
            param14: param14,
            param15: param15,
            param16: param16,
            param17: param17,
            param18: param18,
            param19: param19,
            param20: param20,
            param21: param21,
            param22: param22,
            param23: param23,
            param24: param24,
            param25: param25,
            param26: param26,
            param27: param27,
            param28: param28
        };
        xhr.send(JSON.stringify(data));
    }
    </script>
  </body>
</html>
"@

# Respond to requests
while ($true) {
    $context  = $listener.GetContext()
    $request  = $context.Request
    $response = $context.Response

    if ($request.HttpMethod -eq "GET") {
        $url = $request.Url.LocalPath
        $query = $request.Url.Query

        if ($url -eq "/") {
            # Serving the menu page
            $response.Headers.Add("Content-Type", "text/html; charset=utf-8")
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($menuHtml)
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        } elseif ($url -eq "/eventCount") {
            $response.Headers.Add("Content-Type", "text/plain; charset=utf-8")
            $eventCount = Show-ScanEvents
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($eventCount.ToString())
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        } elseif ($url -eq "/warningEventCount") {
            $response.Headers.Add("Content-Type", "text/plain; charset=utf-8")
            $eventCount = Show-ScanWarningEvents
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($eventCount.ToString())
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        } elseif ($url -eq "/SuspiciousBackupCount") {
            $response.Headers.Add("Content-Type", "text/plain; charset=utf-8")
            # Depth and Growth can be adjusted here
            $eventCount = Get-SuspiciousBackup -Depth 5 -Growth 1.8
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($eventCount.Count.ToString())
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        } elseif ($url -eq "/SuspiciousBackupJobNames") {
            $response.Headers.Add("Content-Type", "text/plain; charset=utf-8")
            # Depth and Growth can be adjusted here
            $jobNames = Get-SuspiciousBackupJobNames -Depth 5 -Growth 1.8
            if ($jobNames -ne $null -and $jobNames.Length -gt 0) {
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($jobNames -join "`n")  # Join with line breaks
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            } else {
                $response.OutputStream.Write([System.Text.Encoding]::UTF8.GetBytes(""), 0, 0)
            }
            $response.Close()
       } elseif ($url -eq "/last10WarningEntries") {
            $response.Headers.Add("Content-Type", "text/html; charset=utf-8")
            $last10Warnings = Get-Last10WarningEntries
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($last10Warnings)
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        } elseif ($request.Url.LocalPath -eq '/scanner.png') {
            $imagePath = "D:\Scripts\vbr\scanningtools\scanner.png"
            $imageBuffer = [System.IO.File]::ReadAllBytes($imagePath)
            $response.ContentType = "image/png"
            $response.ContentLength64 = $imageBuffer.Length
            $response.OutputStream.Write($imageBuffer, 0, $imageBuffer.Length)
        }
        else {
            # Invalid URL
            $response.StatusCode = 404
            $response.Close()
        }
    }
    elseif ($request.HttpMethod -eq "POST" -and $request.Url.LocalPath -eq "/processChoice") {
        # Handling menu choice
        $formData = $request.InputStream
        $reader = New-Object System.IO.StreamReader $formData
        $formDataStr = $reader.ReadToEnd()
        $reader.Close()
        $formDataObj = ConvertFrom-Json $formDataStr
        $choice  = $formDataObj.choice
        $param1  = $formDataObj.param1
        $param2  = $formDataObj.param2
        $param3  = $formDataObj.param3
        $param4  = $formDataObj.param4
        $param5  = $formDataObj.param5
        $param6  = $formDataObj.param6
        $param7  = $formDataObj.param7
        $param8  = $formDataObj.param8
        $param9  = $formDataObj.param9
        $param10 = $formDataObj.param10
        $param11 = $formDataObj.param11
        $param12 = $formDataObj.param12
        $param13 = $formDataObj.param13
        $param14 = $formDataObj.param14
        $param15 = $formDataObj.param15
        $param16 = $formDataObj.param16
        $param17 = $formDataObj.param17
        $param18 = $formDataObj.param18
        $param19 = $formDataObj.param19
        $param20 = $formDataObj.param20
        $param21 = $formDataObj.param21
        $param22 = $formDataObj.param22
        $param23 = $formDataObj.param23
        $param24 = $formDataObj.param24
        $param25 = $formDataObj.param25
        $param26 = $formDataObj.param26
        $param27 = $formDataObj.param27
        $param28 = $formDataObj.param28
        $menuResult = Process-MenuChoice -choice $choice -param1 $param1 -param2 $param2 -param3 $param3 -param4 $param4 -param5 $param5 -param6 $param6 -param7 $param7 -param8 $param8 -param9 $param9 -param10 $param10 -param11 $param11 -param12 $param12 -param13 $param13 -param14 $param14 -param15 $param15 -param16 $param16 -param17 $param17 -param18 $param18 -param19 $param19 -param20 $param20 -param21 $param21 -param22 $param22 -param23 $param23 -param24 $param24 -param25 $param25 -param26 $param26 -param27 $param27 -param28 $param28
        if ([string]::IsNullOrEmpty($menuResult)) {
        $menuResult = "No data available."
        }
        $response.Headers.Add("Content-Type", "text/plain; charset=utf-8")
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($menuResult) 
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
    else {
        # Invalid HTTP method or URL
        $response.StatusCode = 405
        $response.Close()
    }
}
