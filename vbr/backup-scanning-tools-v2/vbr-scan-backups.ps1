<#
.SYNOPSIS
    Scans Veeam backups with Veeam Threat Hunter / antivirus software and/or YARA rules.

.DESCRIPTION
    Wraps Start-VBRScanBackup. Works for VM backups (VMware, Hyper-V, AHV, RHV, Cloud
    Director), backup copy jobs and Veeam Agent backups for Microsoft Windows and Linux.
    Not supported by Veeam: agent backups for IBM AIX, Oracle Solaris and macOS.

    The signature engine (Veeam Threat Hunter or a third-party antivirus) is not chosen
    here - it is whatever is configured under Malware Detection Settings > Signature
    Detection. -AVScan triggers the configured engine.

    Runs completely non-interactive so it can be launched from the web menu or a
    scheduled task. Restore points and YARA rules can be enumerated with -ListRestorePoints
    and -ListYARARules, which is how the web dialog fills its drop-downs.

.PARAMETER JobName
    Name of the backup job holding the data to scan.

.PARAMETER ObjectName
    Name of the machine inside that backup.

.PARAMETER ScanMode
    MostRecent      - newest to oldest, stops at the first clean restore point.
    FirstInInterval - optimal order, stops at the first clean restore point.
    AllInInterval   - oldest to newest, scans everything. Requires a YARA rule.

.PARAMETER AVScan
    Scan with the configured signature engine (Veeam Threat Hunter or third-party AV).

.PARAMETER YARARule
    One or more YARA rule file names including extension, for example 'ransomware.yar'.
    Veeam looks them up in C:\Program Files\Veeam\Backup and Replication\Backup\YaraRules.
    Each rule is scanned in its own session. Use -ListYARARules to see what is available.

    A rule tagged SuppressMalwareDetectionNotification does not raise a malware event;
    its session ends with the Warning state instead.

.PARAMETER RestorePointId
    Scan one specific restore point instead of letting the scan mode pick.

.PARAMETER EnableEntireImageScan
    Keep scanning after the first hit instead of stopping there.

.PARAMETER AsJson
    Emit the result as JSON on stdout. Intended for the web menu.

.EXAMPLE
    .\vbr-scan-backups.ps1 -JobName 'demo_vm' -ObjectName 'lnxvm01' -AVScan

.EXAMPLE
    .\vbr-scan-backups.ps1 -JobName 'demo_vm' -ObjectName 'lnxvm01' -YARARule 'ransomware.yar' -ScanMode AllInInterval

.EXAMPLE
    .\vbr-scan-backups.ps1 -JobName 'demo_vm' -ObjectName 'lnxvm01' -ListRestorePoints -AsJson

.OUTPUTS
    Exit code 0 = clean, 2 = threat or warning, 1 = error.

.NOTES
    Author   : Stephan "Steve" Herzig
    Requires : Veeam Backup & Replication v13, PowerShell 7
    Version  : 2.0
#>
#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Scan')]
param (
    [Parameter(Mandatory = $true, ParameterSetName = 'Scan')]
    [Parameter(Mandatory = $true, ParameterSetName = 'ListRestorePoints')]
    [ValidateNotNullOrEmpty()]
    [string]$JobName,

    [Parameter(Mandatory = $true, ParameterSetName = 'Scan')]
    [Parameter(Mandatory = $true, ParameterSetName = 'ListRestorePoints')]
    [ValidateNotNullOrEmpty()]
    [string]$ObjectName,

    [Parameter(ParameterSetName = 'Scan')]
    [ValidateSet('MostRecent', 'FirstInInterval', 'AllInInterval')]
    [string]$ScanMode = 'MostRecent',

    [Parameter(ParameterSetName = 'Scan')]
    [switch]$AVScan,

    [Parameter(ParameterSetName = 'Scan')]
    [string[]]$YARARule,

    [Parameter(ParameterSetName = 'Scan')]
    [string]$RestorePointId,

    [Parameter(ParameterSetName = 'Scan')]
    [datetime]$FromPointInTime,

    [Parameter(ParameterSetName = 'Scan')]
    [datetime]$ToPointInTime,

    [Parameter(ParameterSetName = 'Scan')]
    [switch]$EnableEntireImageScan,

    # By default only events from this run are reported. A machine keeps its whole
    # event history, which makes the output unusable otherwise.
    [Parameter(ParameterSetName = 'Scan')]
    [switch]$AllEvents,

    [Parameter(ParameterSetName = 'Scan')]
    [ValidateRange(1, 500)]
    [int]$EventLimit = 20,

    # The malware detection API reports that something was found, but not always
    # what. The scan session logs carry the actual threat text including file
    # names, so they are parsed as well.
    [Parameter(ParameterSetName = 'Scan')]
    [switch]$SkipLogAnalysis,

    [Parameter(ParameterSetName = 'Scan')]
    [string]$ScanSessionLogPath = 'C:\ProgramData\Veeam\Backup\FLRSessions',

    [Parameter(ParameterSetName = 'Scan')]
    [string]$MalwareLogPath = 'C:\ProgramData\Veeam\Backup\Malware_Detection_Logs',

    [Parameter(Mandatory = $true, ParameterSetName = 'ListRestorePoints')]
    [switch]$ListRestorePoints,

    [Parameter(Mandatory = $true, ParameterSetName = 'ListYARARules')]
    [switch]$ListYARARules,

    [switch]$AsJson,

    [ValidateNotNullOrEmpty()]
    [string]$Server = 'localhost',

    [switch]$ForceAcceptTlsCertificate,

    [ValidateNotNullOrEmpty()]
    [string]$LogFilePath = 'C:\Temp\log.txt'
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$script:ExitClean  = 0
$script:ExitError  = 1
$script:ExitThreat = 2

$script:WeConnected = $false
$script:LogPrefix   = 'Scan Backup'

#region Helpers ----------------------------------------------------------------

# Same format the other scanning tools and the web menu dashboard use:
#   dd-MM-yyyy HH:mm:ss - Level - Message
function Write-ScanLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    try {
        $directory = Split-Path -Path $LogFilePath -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        $timestamp = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
        Add-Content -LiteralPath $LogFilePath -Value "$timestamp - $Level - $script:LogPrefix - $Message"
    } catch {
        Write-Warning "Could not write to '$LogFilePath': $($_.Exception.Message)"
    }
}

# Status goes to stderr in JSON mode so it cannot corrupt the JSON on stdout.
function Write-Status {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Color = 'Gray'
    )

    if ($AsJson) {
        [Console]::Error.WriteLine($Message)
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

# Veeam objects vary between platforms and versions, so never assume a property
# is there - a missing one must not abort a scan.
function Get-SafeProperty {
    param (
        $InputObject,
        [Parameter(Mandatory = $true)] [string]$Name,
        $Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    try {
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -eq $property) { return $Default }
        if ($null -eq $property.Value) { return $Default }
        return $property.Value
    } catch {
        return $Default
    }
}

<#
    Normalises a Veeam timestamp to local time.

    Veeam hands out some timestamps as UTC (Kind = Utc) and others already local.
    Everything this script compares or prints is local, so mixing the two silently
    shifts values by the UTC offset - which is exactly what put the scan window two
    hours off for Proxmox backups. The DateTime carries its own Kind, so no hard
    coded offset is needed and daylight saving stays correct.
#>
function ConvertTo-LocalDateTime {
    param ($Value)

    if ($Value -isnot [datetime]) { return [datetime]::MinValue }
    if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value.ToLocalTime() }
    return $Value
}

function Get-EventDetectionTime {
    param ($Event)
    return ConvertTo-LocalDateTime (Get-SafeProperty -InputObject $Event -Name 'DetectionTime')
}

function ConvertFrom-VeeamLogTimestamp {
    param ([string]$Text)

    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact(
        $Text,
        'dd.MM.yyyy HH:mm:ss',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed)

    if ($ok) { return $parsed }
    return $null
}

<#
    Pulls the actual findings out of the Veeam log files.

    Start-VBRScanBackup and Get-VBRMalwareDetectionEvent tell you that something
    was detected; the log files tell you what. Two sources:

      * Scan session logs    - "Threat found. Antivirus output: <detail>", which
                               is where the file names show up.
      * Malware detection    - indicators_of_compromise_* and suspicious_files_*

    Files are pre-filtered by LastWriteTime so old sessions are never opened.
    Based on the approach in vbr-scan-malware-detection-logs.ps1.
#>
function Get-ThreatLogFinding {
    param ([Parameter(Mandatory = $true)] [datetime]$Since)

    $findings = [System.Collections.Generic.List[object]]::new()
    if ($SkipLogAnalysis) { return $findings }

    $threatPattern = '\[(?<ts>\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2})\.\d+\]\s+<\d+>\s+Warning\s+\(\d+\)\s+Threat found\.\s*Antivirus output:\s*(?<msg>.*)'
    $warnPattern   = '\[(?<ts>\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2})\.\d+\]\s+<\d+>\s+Warning\s+\(\d+\)\s+(?<msg>.*)'

    $sources = @(
        [ordered]@{ Path = $ScanSessionLogPath; Recurse = $true;  Pattern = $threatPattern; Label = 'Scan session' }
        [ordered]@{ Path = $MalwareLogPath;     Recurse = $false; Pattern = $warnPattern;   Label = '' }
    )

    foreach ($source in $sources) {
        if ([string]::IsNullOrWhiteSpace($source.Path)) { continue }
        if (-not (Test-Path -LiteralPath $source.Path)) {
            Write-Verbose "Log directory not found, skipping: $($source.Path)"
            continue
        }

        try {
            $files = @(Get-ChildItem -LiteralPath $source.Path -Filter '*.log' -Recurse:$source.Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $Since })
        } catch {
            Write-Verbose "Could not enumerate '$($source.Path)': $($_.Exception.Message)"
            continue
        }

        foreach ($file in $files) {
            # Veeam keeps some of these open - a locked file must not abort the run.
            try {
                $lines = @(Get-Content -LiteralPath $file.FullName -ErrorAction Stop)
            } catch {
                Write-Verbose "Could not read '$($file.FullName)': $($_.Exception.Message)"
                continue
            }

            $label = $source.Label
            if (-not $label) {
                $label = if ($file.Name -match '^(indicators_of_compromise|suspicious_files)_') { $Matches[1] } else { 'Malware log' }
            }

            foreach ($line in $lines) {
                $match = [regex]::Match($line, $source.Pattern)
                if (-not $match.Success) { continue }

                $when = ConvertFrom-VeeamLogTimestamp $match.Groups['ts'].Value
                if ($null -eq $when -or $when -lt $Since) { continue }

                $findings.Add([pscustomobject]@{
                    detected = $when.ToString('dd-MM-yyyy HH:mm:ss')
                    source   = $label
                    message  = $match.Groups['msg'].Value.Trim()
                    logFile  = $file.Name
                })
            }
        }
    }

    return @($findings | Sort-Object detected -Descending)
}

function Write-Result {
    param ([Parameter(Mandatory = $true)] $Result)

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 6
        return
    }

    switch ($Result.status) {
        'Clean'  { Write-Host "`nResult: no threats found." -ForegroundColor Green }
        'Threat' { Write-Host "`nResult: THREAT FOUND." -ForegroundColor Red }
        default  { Write-Host "`nResult: $($Result.status)." -ForegroundColor Yellow }
    }

    if ($Result.message) {
        Write-Host ''
        Write-Host $Result.message -ForegroundColor Yellow
    }

    $sessions = @($Result.sessions)
    if ($sessions.Count -gt 0) {
        Write-Host ''
        $sessions | Format-Table -AutoSize -Property engine, rule, sessionResult, sessionState
    }

    # Most useful block, so it goes first.
    $findings = @($Result.findings)
    if ($findings.Count -gt 0) {
        Write-Host ''
        Write-Host "Threats found in the Veeam logs ($($findings.Count)):" -ForegroundColor Red
        $findings | ForEach-Object {
            Write-Host ("  [{0}] {1}" -f $_.detected, $_.source) -ForegroundColor DarkGray
            Write-Host ("      {0}" -f $_.message)
        }
        Write-Host ''
    }

    $events = @($Result.events)
    if ($events.Count -gt 0) {
        Write-Host ("Malware detection events ({0}, showing {1} of {2} in the machine's history):" -f
            $Result.eventsScope, $events.Count, $Result.eventsTotal) -ForegroundColor Yellow
        $events | Format-Table -AutoSize -Property detected, type, state, severity, createdBy

        # Message carries the actual finding, so give it the room it needs.
        $withMessage = @($events | Where-Object { $_.message })
        if ($withMessage.Count -gt 0) {
            Write-Host 'Details:' -ForegroundColor Yellow
            $withMessage | ForEach-Object {
                Write-Host ("  [{0}] {1}" -f $_.detected, $_.message)
            }
        }

        if (-not $AllEvents -and $Result.eventsTotal -gt $events.Count) {
            Write-Host ''
            Write-Host "Use -AllEvents to see the machine's full event history." -ForegroundColor DarkGray
        }
    }
    elseif ($Result.eventsTotal -gt 0) {
        # No table at all rather than the history: a clean scan must not look like a
        # list of infections.
        Write-Host ''
        Write-Host ("No new malware events from this scan ({0} in the machine's history - use -AllEvents to see them)." -f
            $Result.eventsTotal) -ForegroundColor DarkGray
    }
}

function Connect-Veeam {
    # Only one Veeam connection per PowerShell session, so reuse an existing one.
    try {
        if (Get-VBRServerSession) {
            Write-Verbose 'Reusing the existing Veeam server session.'
            return
        }
    } catch {
        # No session yet - fall through and connect.
    }

    $connectArguments = @{ Server = $Server }
    if ($ForceAcceptTlsCertificate) { $connectArguments['ForceAcceptTlsCertificate'] = $true }

    Connect-VBRServer @connectArguments
    $script:WeConnected = $true
}

function Disconnect-Veeam {
    if (-not $script:WeConnected) { return }
    try { Disconnect-VBRServer } catch { }
    $script:WeConnected = $false
}

function Get-TargetBackup {
    $backups = @(Get-VBRBackup -WarningAction SilentlyContinue |
        Where-Object { $_.JobName -eq $JobName })

    if ($backups.Count -eq 0) {
        throw "No backup found for job '$JobName'."
    }
    if ($backups.Count -gt 1) {
        # Imported or copied backups can share a job name; the newest wins.
        Write-Verbose "Found $($backups.Count) backups named '$JobName' - using the most recent one."
        $backups = @($backups | Sort-Object CreationTime -Descending)
    }
    return $backups[0]
}

function Get-TargetObject {
    param ([Parameter(Mandatory = $true)] $Backup)

    $objects = @(Get-VBRBackupObject -Backup $Backup |
        Where-Object { $_.Name -eq $ObjectName })

    if ($objects.Count -eq 0) {
        $available = @(Get-VBRBackupObject -Backup $Backup | ForEach-Object { $_.Name }) -join ', '
        throw "Machine '$ObjectName' not found in job '$JobName'. Available: $available"
    }
    return $objects[0]
}

<#
    Uses Get-VBRObjectRestorePoint, not Get-VBRRestorePoint.

    The two return different types. Start-VBRScanBackup -RestorePoint requires a
    VBRObjectRestorePoint; Get-VBRRestorePoint hands back a Veeam.Backup.Core.COib,
    which fails to bind with "Cannot convert ... to type VBRRestorePoint". The
    cmdlet reference documents COib here, which is wrong.

    Veeam Agent jobs are also a documented special case: restore points only show
    up when the Name parameter contains a wildcard, hence the fallback.
#>
function Get-TargetRestorePoint {
    param (
        [Parameter(Mandatory = $true)] $Backup,
        $BackupObject
    )

    if (-not $BackupObject) { $BackupObject = Get-TargetObject -Backup $Backup }

    # VBRBackupObject exposes both Id and ObjectId and the documented descriptions
    # overlap, so try both before falling back to a client side filter.
    $candidateIds = @(
        Get-SafeProperty -InputObject $BackupObject -Name 'ObjectId'
        Get-SafeProperty -InputObject $BackupObject -Name 'Id'
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($candidate in $candidateIds) {
        $points = @(Get-VBRObjectRestorePoint -ObjectId $candidate -ErrorAction SilentlyContinue)
        if ($points.Count -gt 0) { return Sort-RestorePoint -RestorePoints $points }
    }

    $wanted = @($candidateIds | ForEach-Object { [string]$_ })
    $points = @(Get-VBRObjectRestorePoint -Backup $Backup |
        Where-Object { [string]$_.ObjectId -in $wanted })

    return Sort-RestorePoint -RestorePoints $points
}

<#
    Returns the restore point's creation time in LOCAL time.

    VBRObjectRestorePoint uses CreationDate, the older COib type used CreationTime.
    Proxmox backups return CreationDate with Kind = Utc, while Start-VBRScanBackup
    interprets FromPointInTime / ToPointInTime in local time. Passing the raw value
    put the scan window two hours off in CEST, so it searched an empty range.

    The DateTime carries its own Kind, so .NET does the conversion - no hard coded
    offset, and daylight saving stays correct.
#>
function Get-RestorePointDate {
    param ($RestorePoint)

    foreach ($name in @('CreationDate', 'CreationTime')) {
        $value = Get-SafeProperty -InputObject $RestorePoint -Name $name
        if ($value -is [datetime]) { return ConvertTo-LocalDateTime $value }
    }
    return [datetime]::MinValue
}

function Sort-RestorePoint {
    param ($RestorePoints)
    return @($RestorePoints | Sort-Object -Property @{ Expression = { Get-RestorePointDate $_ } } -Descending)
}
#endregion

#region Modes ------------------------------------------------------------------

function Invoke-ListRestorePoints {
    $backup       = Get-TargetBackup
    $backupObject = Get-TargetObject -Backup $backup
    $points       = Get-TargetRestorePoint -Backup $backup -BackupObject $backupObject

    $result = @($points | ForEach-Object {
        [ordered]@{
            id            = [string](Get-SafeProperty -InputObject $_ -Name 'Id')
            name          = [string](Get-SafeProperty -InputObject $_ -Name 'Name')
            creationTime  = (Get-RestorePointDate $_).ToString('dd-MM-yyyy HH:mm:ss')
            malwareStatus = [string](Get-SafeProperty -InputObject $_ -Name 'Status' -Default 'Unknown')
        }
    })

    if ($AsJson) {
        # -AsArray keeps a single restore point from collapsing into an object.
        $result | ConvertTo-Json -Depth 4 -AsArray
    } else {
        if ($result.Count -eq 0) {
            Write-Host "No restore points found for '$ObjectName' in job '$JobName'." -ForegroundColor Yellow
        } else {
            $result | ForEach-Object { [pscustomobject]$_ } | Format-Table -AutoSize
        }
    }
}

function Invoke-ListYARARules {
    $rules = @(Get-VBRYARARule | ForEach-Object { [string]$_ } | Sort-Object)

    if ($AsJson) {
        $rules | ConvertTo-Json -Depth 2 -AsArray
    } else {
        if ($rules.Count -eq 0) {
            Write-Host 'No YARA rules found.' -ForegroundColor Yellow
            Write-Host 'Default folder: C:\Program Files\Veeam\Backup and Replication\Backup\YaraRules'
        } else {
            $rules | ForEach-Object { Write-Host "  $_" }
        }
    }
}

function Invoke-Scan {
    if (-not $AVScan -and (-not $YARARule -or $YARARule.Count -eq 0)) {
        throw 'Nothing to do: specify -AVScan, -YARARule, or both.'
    }

    # Veeam requires a YARA rule for this mode.
    if ($ScanMode -eq 'AllInInterval' -and (-not $YARARule -or $YARARule.Count -eq 0)) {
        throw "ScanMode 'AllInInterval' requires at least one -YARARule."
    }

    $backup       = Get-TargetBackup
    $backupObject = Get-TargetObject -Backup $backup

    $baseArguments = @{
        Object   = $backupObject
        ScanMode = $ScanMode
    }

    if ($EnableEntireImageScan) { $baseArguments['EnableEntireImageScan'] = $true }
    if ($PSBoundParameters.ContainsKey('FromPointInTime')) { $baseArguments['FromPointInTime'] = $FromPointInTime }
    if ($PSBoundParameters.ContainsKey('ToPointInTime'))   { $baseArguments['ToPointInTime']   = $ToPointInTime }

    <#
        A single restore point is targeted through a narrow time window rather
        than through -RestorePoint.

        -RestorePoint demands Veeam.Backup.PowerShell.Infos.VBRRestorePoint. Neither
        Get-VBRRestorePoint (returns Veeam.Backup.Core.COib) nor
        Get-VBRObjectRestorePoint (returns VBRObjectRestorePoint) produces that type,
        and the two are not related by inheritance - both are rejected at binding
        time. The cmdlet reference documents COib here, which is wrong.

        -FromPointInTime / -ToPointInTime are documented, work, and achieve the same
        thing: a window of a few seconds around the restore point's creation time
        selects exactly that one.
    #>
    if (-not [string]::IsNullOrWhiteSpace($RestorePointId)) {
        $restorePoint = @(Get-VBRObjectRestorePoint -Id $RestorePointId -ErrorAction SilentlyContinue) |
            Select-Object -First 1

        if (-not $restorePoint) {
            throw "Restore point '$RestorePointId' not found. Use -ListRestorePoints to get the current IDs."
        }

        $created = Get-RestorePointDate $restorePoint
        if ($created -eq [datetime]::MinValue) {
            throw "Restore point '$RestorePointId' has no readable creation date, cannot target it."
        }

        if ($PSBoundParameters.ContainsKey('FromPointInTime') -or $PSBoundParameters.ContainsKey('ToPointInTime')) {
            Write-Status 'Note: -RestorePointId overrides the given time range.' 'Yellow'
        }

        $baseArguments['FromPointInTime'] = $created.AddSeconds(-30)
        $baseArguments['ToPointInTime']   = $created.AddSeconds(30)

        Write-Status ("Restore point: {0}" -f $created.ToString('dd-MM-yyyy HH:mm:ss'))
    }

    # One session per engine: the antivirus scan, plus one per YARA rule.
    $runs = [System.Collections.Generic.List[hashtable]]::new()
    if ($AVScan) {
        $runs.Add(@{ Engine = 'Antivirus'; Rule = $null })
    }
    foreach ($rule in @($YARARule)) {
        if ([string]::IsNullOrWhiteSpace($rule)) { continue }
        $runs.Add(@{ Engine = 'YARA'; Rule = $rule.Trim() })
    }

    $sessions   = [System.Collections.Generic.List[object]]::new()
    $threatSeen = $false
    $warnSeen   = $false

    # Clock skew and event write delay: look slightly before the actual start so
    # events belonging to this run are not filtered out.
    $scanStart = (Get-Date).AddMinutes(-2)

    <#
        Snapshot of the event ids before scanning.

        Deciding afterwards which events are new by comparing timestamps depends on
        DetectionTime and the local clock agreeing about their time zone, and they
        demonstrably do not: a scan that found a threat still reported "no new
        events" because the new entries looked two hours old. Diffing ids is exact
        and has no notion of time at all.
    #>
    $knownEventIds = New-Object 'System.Collections.Generic.HashSet[string]'
    $haveSnapshot  = $false
    try {
        foreach ($existing in @(Get-VBRMalwareDetectionEvent -ObjectName $ObjectName -ErrorAction Stop)) {
            [void]$knownEventIds.Add([string](Get-SafeProperty -InputObject $existing -Name 'Id'))
        }
        $haveSnapshot = $true
    } catch {
        Write-Verbose "Could not snapshot malware events, falling back to time filtering: $($_.Exception.Message)"
    }

    foreach ($run in $runs) {
        $scanArguments = $baseArguments.Clone()
        $label         = $run.Engine

        if ($run.Engine -eq 'Antivirus') {
            $scanArguments['EnableAntivirusScan'] = $true
        } else {
            $scanArguments['EnableYARAScan'] = $true
            $scanArguments['YARARule']       = $run.Rule
            $label                           = "YARA ($($run.Rule))"
        }

        Write-Status "Scanning '$ObjectName' - $label - mode $ScanMode ..." 'White'
        Write-ScanLog -Message "$label - Scanning started - Object: $ObjectName - Job: $JobName - Mode: $ScanMode"

        $session       = Start-VBRScanBackup @scanArguments
        $sessionResult = [string](Get-SafeProperty -InputObject $session -Name 'Result' -Default 'Unknown')
        $sessionState  = [string](Get-SafeProperty -InputObject $session -Name 'State'  -Default 'Unknown')

        $sessions.Add([pscustomobject]@{
            engine        = $run.Engine
            rule          = $run.Rule
            sessionResult = $sessionResult
            sessionState  = $sessionState
            sessionName   = [string](Get-SafeProperty -InputObject $session -Name 'Name')
        })

        # Success is the only result that means "clean". Anything else - including
        # a result we could not read - is escalated rather than silently passed.
        if ($sessionResult -match 'Failed') {
            $threatSeen = $true
            Write-ScanLog -Level Warning -Message "$label - Scanning ended - Result: $sessionResult"
        } elseif ($sessionResult -match 'Success') {
            Write-ScanLog -Message "$label - Scanning ended - No threats found"
        } else {
            $warnSeen = $true
            Write-ScanLog -Level Warning -Message "$label - Scanning ended - Result: $sessionResult"
        }
    }

    # The session result says whether the scan itself was clean. The malware
    # detection events are the authoritative record of what was found.
    # Property names per the documented VBRMalwareDetectionEvent object:
    # Id, ObjectName, ObjectId, DetectionTime, Type, State, CreatedBy, Status, Message.
    $events      = @()
    $eventTotal  = 0
    $eventsScope = 'from this scan'
    try {
        $raw = @(Get-VBRMalwareDetectionEvent -ObjectName $ObjectName -ErrorAction Stop)
        $eventTotal = $raw.Count

        if ($AllEvents) {
            $eventsScope = 'full history'
        } elseif ($haveSnapshot) {
            # Exact: anything whose id was not there before this scan is new.
            $raw = @($raw | Where-Object {
                -not $knownEventIds.Contains([string](Get-SafeProperty -InputObject $_ -Name 'Id'))
            })
        } else {
            # Only reached when the snapshot failed. Accept an empty result: falling
            # back to the history made a clean scan print a wall of "Infected" rows.
            $eventsScope = 'from this scan (by time)'
            $raw = @($raw | Where-Object {
                $when = Get-EventDetectionTime $_
                $when -ne [datetime]::MinValue -and $when -ge $scanStart
            })
        }

        $events = @($raw |
            Sort-Object -Property @{ Expression = { Get-EventDetectionTime $_ } } -Descending |
            Select-Object -First $EventLimit |
            ForEach-Object {
                $when     = Get-EventDetectionTime $_
                $detected = if ($when -eq [datetime]::MinValue) { '' } else { $when.ToString('dd-MM-yyyy HH:mm:ss') }

                [pscustomobject]@{
                    detected  = $detected
                    type      = [string](Get-SafeProperty -InputObject $_ -Name 'Type')
                    state     = [string](Get-SafeProperty -InputObject $_ -Name 'State')
                    severity  = [string](Get-SafeProperty -InputObject $_ -Name 'Status')
                    createdBy = [string](Get-SafeProperty -InputObject $_ -Name 'CreatedBy')
                    message   = [string](Get-SafeProperty -InputObject $_ -Name 'Message')
                }
            })
    } catch {
        Write-Verbose "Could not read malware detection events: $($_.Exception.Message)"
    }

    if ($threatSeen) {
        $status = 'Threat'
        # Veeam reports the scan session as Failed when something is found. That is
        # the expected outcome of a successful detection, not a script error - the
        # wording matters because the exit code makes it look like a failure.
        $summary = 'Veeam ended the scan session with "Failed". For a backup scan this is how a FINDING is reported - the scan itself ran fine. Check the malware detection events below and the machine status in the Veeam console.'
    } elseif ($warnSeen) {
        $status  = 'Warning'
        $summary = 'At least one scan session did not end with "Success". This can be a suppressed YARA rule (SuppressMalwareDetectionNotification) or an aborted session.'
    } else {
        $status  = 'Clean'
        $summary = ''
    }

    $findings = @(Get-ThreatLogFinding -Since $scanStart)

    # The API can stay quiet while the logs clearly show a hit. Trust the logs.
    if ($findings.Count -gt 0 -and $status -eq 'Clean') {
        $status  = 'Threat'
        $summary = 'The scan session reported success, but the Veeam logs contain threat entries for this time window. See the findings below.'
    }

    return [ordered]@{
        status      = $status
        job         = $JobName
        object      = $ObjectName
        scanMode    = $ScanMode
        sessions    = @($sessions)
        events      = @($events)
        eventsTotal = $eventTotal
        eventsScope = $eventsScope
        findings    = $findings
        message     = $summary
    }
}
#endregion

#region Main -------------------------------------------------------------------

$exitCode = $script:ExitError

try {
    if (-not $AsJson) {
        # Both fail when there is no real console, e.g. launched from the web menu.
        try { $host.UI.RawUI.WindowTitle = 'VBR Scan Backup' } catch { }
        try { Clear-Host } catch { }
    }

    Connect-Veeam

    switch ($PSCmdlet.ParameterSetName) {
        'ListRestorePoints' {
            Invoke-ListRestorePoints
            $exitCode = $script:ExitClean
        }
        'ListYARARules' {
            Invoke-ListYARARules
            $exitCode = $script:ExitClean
        }
        default {
            $result = Invoke-Scan
            Write-Result -Result $result
            $exitCode = if ($result.status -eq 'Clean') { $script:ExitClean } else { $script:ExitThreat }
        }
    }
} catch {
    $message = $_.Exception.Message
    Write-ScanLog -Level Error -Message "Aborted: $message"

    if ($AsJson) {
        [ordered]@{ status = 'Error'; message = $message } | ConvertTo-Json -Depth 3
    } else {
        Write-Host ''
        Write-Host "Error: $message" -ForegroundColor Red
    }
    $exitCode = $script:ExitError
} finally {
    Disconnect-Veeam
}

exit $exitCode
#endregion
