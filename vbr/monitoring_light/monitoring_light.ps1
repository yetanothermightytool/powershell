param(
    [int]$Port            = 80,
    [int]$RefreshInterval = 30
)

# Variables
$refreshInMs              = "{0}000" -f $RefreshInterval

# Start http server
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Server started. Listening for incoming requests on port $Port. Refresh interval $RefreshInterval"

# Build webpage
$style = @"
<style>
    body {
        font-family: Arial, Helvetica, sans-serif;
    }
    table {
        border-collapse: collapse;
        width: 100%;
    }
    th, td {
        border: 1px solid black;
        padding: 8px;
    }
    th.title-row {
        background-color: lightgray;
    }
    .row-white {
        background-color: white;
    }
    .row-gray {
        background-color: lightgray;
    }
    .timestamp {
        color: gray;
        font-size: 12px;
    }
    canvas {
        max-width: 600px;
        margin-top: 20px;
    }
</style>
"@

$rowColor = "row-white"

# Getting Veeam data over WMI
$fetchData = {
    $vbrServer              = @(Get-WmiObject -Namespace ROOT\VeeamBS -Class BackupServer | Select-Object -Property Version, MarketName)
    $proxyRunning           = @(Get-WmiObject -Namespace ROOT\VeeamBS -Class Proxy | Select-Object -Property Name, ConcurrentJobsMax, ConcurrentJobsNow)
    $repoRunning            = @(Get-WmiObject -Namespace ROOT\VeeamBS -Class Repository | Select-Object -Property Name, ConcurrentJobsMax, ConcurrentJobsNow, ConcurrentTasksNow, FreeSpace, IsImmutabilityEnabled)

    # Sort proxyRunning by Name
    $proxyRunning           = $proxyRunning | Sort-Object -Property Name

    # Sort repoRunning by Name
    $repoRunning            = $repoRunning | Sort-Object -Property Name

    # Execute rts-extractor.ps1 and capture the output
    $rtsUsage               = .\rts-extractor.ps1 -DaysBack 1

    # Execute job-stats.ps1 and capture the output
    $jobstats               = .\job-stats.ps1 -DaysBack 7

    # Sort the $rtsUsage array by the "Hour" column
    $rtsUsageSorted         = $rtsUsage | Sort-Object -Property Date, Hour -Descending

    # Calculate Backup Job Statistics sum for last 24 hours
    $sumProcessedUsedSize   = ($jobstats | Where-Object { $_.StartTime -ge (Get-Date).AddDays(-1) } | Measure-Object -Property ProcessedUsedSize -Sum).Sum
    $sumTransferredSize     = ($jobstats | Where-Object { $_.StartTime -ge (Get-Date).AddDays(-1) } | Measure-Object -Property TransferredSize -Sum).Sum

    # Calculate the Change Rate
    $sumProcessedUsedSize2d = ($jobstats | Where-Object { $_.StartTime -ge (Get-Date).AddDays(-2) } | Measure-Object -Property ProcessedUsedSize -Sum).Sum
    $changeRate             = [Math]::Round((($sumProcessedUsedSize - $sumProcessedUsedSize2d) / $sumProcessedUsedSize2d) * 100, 2)


    # Build page
    $data = @"

<html>
<head>
    <title>VBR - Quick Analyzer - YAMT</title>
    <meta http-equiv="refresh" content="$RefreshInterval">
    <style>$style</style>
    
</head>
<body>
    <h1 style="background-color: lightgreen;">VBR - Check da stats</h1>
"@

    # Get the VBR server information
    $vbrServerVersion = $vbrServer.Version
    $vbrServerPatch   = $vbrServer.MarketName

    $data += @"
    <pre>VBR Server Version $vbrServerVersion $vbrServerPatch</pre>

"@

    # Get the VBR server information
    
    $data += @"
    <h2>Backup Job Statistics - Last 24 h</h2>
    <pre>Processed $sumProcessedUsedSize GB - Change Rate $changeRate % - Transferred $sumTransferredSize GB</pre>

"@

    $data += @"
    <h2>Proxy Running Activities</h2>
    <table>
        <tr class="title-row">
            <th>Name</th>
            <th>Max Concurrent Jobs</th>
            <th>Current Concurrent Jobs</th>
        </tr>
"@

    foreach ($proxy in $proxyRunning) {
        $name              = $proxy.Name
        $concurrentJobsMax = $proxy.ConcurrentJobsMax
        $concurrentJobsNow = $proxy.ConcurrentJobsNow

        if ($rowColor -eq "row-white") {
            $rowClass = "row-white"
        } else {
            $rowClass = "row-gray"
        }

        $data += "<tr class='$rowClass'><td>$name</td><td>$concurrentJobsMax</td><td>$concurrentJobsNow</td></tr>"

        if ($rowColor -eq "row-white") {
            $rowColor = "row-gray"
        } else {
            $rowColor = "row-white"
        }
    }

    $data += @"
    </table>

    <h2>Repository Running Activities</h2>
    <table>
        <tr class="title-row">
            <th>Name</th>
            <th>Max Concurrent Jobs</th>
            <th>Current Concurrent Jobs</th>
            <th>Current Concurrent Tasks</th>
            <th>FreeSpace (GB)</th>
            <th>Immutability enabled</th>
        </tr>
"@

    foreach ($repo in $repoRunning) {
        $name                  = $repo.Name
        $ConcurrentJobsMax     = $repo.ConcurrentJobsMax
        $concurrentJobsNow     = $repo.ConcurrentJobsNow
        $concurrentTasksNow    = $repo.ConcurrentTasksNow
        $freeSpaceBytes        = $repo.FreeSpace
        $freeSpaceGB           = [math]::Round(($freeSpaceBytes / 1GB), 2)
        $isImmutabilityEnabled = $repo.IsImmutabilityEnabled

        if ($rowColor -eq "row-white") {
            $rowClass = "row-white"
        } else {
            $rowClass = "row-gray"
        }

        $data += "<tr class='$rowClass'><td>$name</td><td>$ConcurrentJobsMax</td><td>$concurrentJobsNow</td><td>$concurrentTasksNow</td><td>$freeSpaceGB</td><td>$isImmutabilityEnabled</td></tr>"

        if ($rowColor -eq "row-white") {
            $rowColor = "row-gray"
        } else {
            $rowColor = "row-white"
        }
    }

    $data += @"
    </table>

    <h2>RTS.ResourcesUsage.log Entries - Last 24 h</h2>
    <table>
        <tr class="title-row">
            <th>Date</th>
            <th>Hour</th>
            <th>Resource</th>
            <th>Usage</th>
        </tr>
"@

    foreach ($rtsEntry in $rtsUsageSorted) {
        $date      = $rtsEntry.Date
        $hour      = $rtsEntry.Hour
        $resource  = $rtsEntry.Resource
        $usageType = $rtsEntry.Usage

        if ($rowColor -eq "row-white") {
            $rowClass = "row-white"
        } else {
            $rowClass = "row-gray"
        }

        $data += "<tr class='$rowClass'><td>$date</td><td>$hour</td><td>$resource</td><td>$usageType</td></tr>"

        if ($rowColor -eq "row-white") {
            $rowColor = "row-gray"
        } else {
            $rowColor = "row-white"
        }
    }

    $data += @"
    </table>
    
    <div class="timestamp">
        Last updated: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) 
    </div>

    
</body>
</html>
"@

    return $data
}

# Respond to requests
while ($listener.IsListening) {
    $context  = $listener.GetContext()
    $response = $context.Response

    $webpage = & $fetchData 
    $buffer  = [System.Text.Encoding]::Default.GetBytes($webpage)

    $response.ContentLength64 = $buffer.Length
    $output  = $response.OutputStream
    $output.Write($buffer, 0, $buffer.Length)
    $output.Close()
}

# Stop the listener and clear the prefix
$listener.Stop()
