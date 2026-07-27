<#
.SYNOPSIS
    Web front end for the YAMT backup scanning tools.

.DESCRIPTION
    Starts a small HTTP listener that serves a dashboard and lets the operator
    launch the individual backup scanning scripts.

    The listener binds to localhost only and is not authenticated. It is meant
    to be used interactively on the VBR server console. Do not expose the port
    to a network.

.PARAMETER Port
    TCP port for the local listener.

.PARAMETER RefreshInterval
    Dashboard auto-refresh interval in seconds. Also used as the cache lifetime
    for the (expensive) suspicious backup analysis.

.PARAMETER LogFilePath
    Log file that the scanning scripts write to and that the dashboard reads.
    The path is passed through to every launched script so both sides always
    agree on the same file.

.PARAMETER ScanningToolsPath
    Directory that holds the individual scanning scripts.

.PARAMETER JobOutputPath
    Directory for the stdout/stderr transcripts of launched scans.

.PARAMETER SuspiciousDepth
    Number of most recent incremental sessions per job to analyse.

.PARAMETER SuspiciousGrowth
    A session is flagged when it is larger than this factor times the average
    of the other analysed sessions of the same job.

.PARAMETER StatsWindowHours
    Time window for the "started scans" and "scan warnings" counters.

.EXAMPLE
    .\backup-scanning-tools-webmenu.ps1 -Port 8080 -LogFilePath 'C:\Temp\log.txt'

.NOTES
    Version: 2.0
#>
[CmdletBinding()]
param (
    [ValidateRange(1, 65535)]
    [int]$Port = 8080,

    [ValidateRange(10, 86400)]
    [int]$RefreshInterval = 300,

    [ValidateNotNullOrEmpty()]
    [string]$LogFilePath = 'C:\Temp\log.txt',

    [ValidateNotNullOrEmpty()]
    [string]$ScanningToolsPath = 'D:\Scripts\vbr\scanningtools',

    [ValidateNotNullOrEmpty()]
    [string]$JobOutputPath = (Join-Path $env:ProgramData 'BackupScanningTools\jobs'),

    [ValidateRange(3, 100)]
    [int]$SuspiciousDepth = 5,

    [ValidateRange(1.1, 100)]
    [double]$SuspiciousGrowth = 1.8,

    [ValidateRange(1, 8760)]
    [int]$StatsWindowHours = 168,

    # Host that runs the scan scripts. Empty means auto detect (pwsh).
    # Veeam PowerShell v13 requires PowerShell 7.
    [string]$PowerShellExecutable = '',

    [ValidateNotNullOrEmpty()]
    [string]$VbrServer = 'localhost',

    [switch]$ForceAcceptTlsCertificate
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$script:Version            = '2.0'
$script:LogTimestampFormat = 'dd-MM-yyyy HH:mm:ss'
$script:CsrfToken          = [guid]::NewGuid().ToString('N')

# Not available in every host (ISE, remoting) - never let it break startup.
try { $host.UI.RawUI.WindowTitle = 'Backup Scanning Tools Webmenu' } catch { }

#region Tool definitions -------------------------------------------------------
# Single source of truth. The buttons, the dialogs, the input validation and the
# argument splatting are all generated from this list, so a new scanning tool
# only has to be added here.
#
#   Fields[].Type : text | number | switch | select | remote-select
#   Fixed         : parameters that are always passed (not operator editable)
#   Warning       : optional banner shown in the dialog
#
#   select        : fixed Options list
#   remote-select : Options fetched from Source endpoint. DependsOn names the
#                   fields that must be filled before the list can be loaded.

$script:Tools = @(
    [ordered]@{
        Id          = 8
        Migrated    = $true
        Name        = 'Backup Scan (Threat Hunter / YARA)'
        Script      = 'vbr-scan-backups.ps1'
        Description = 'Scans a backup with the configured signature engine (Veeam Threat Hunter or third-party antivirus) and/or YARA rules. Works for VM backups and for Veeam Agent backups on Windows and Linux. The result is written to the Veeam malware status, not just to the log.'
        Fixed       = [ordered]@{}
        # At least one scan engine has to be picked.
        RequireAnyOf = @('AVScan', 'YARARule')
        Fields      = @(
            [ordered]@{
                Name       = 'JobName'
                Label      = 'Backup job'
                Type       = 'remote-select'
                Source     = 'jobs'
                Required   = $true
                EmptyLabel = '(pick a job)'
            }
            [ordered]@{
                Name       = 'ObjectName'
                Label      = 'Machine to scan'
                Type       = 'remote-select'
                Source     = 'objects'
                DependsOn  = @('JobName')
                Required   = $true
                EmptyLabel = '(pick a job first)'
            }
            [ordered]@{
                Name    = 'ScanMode'
                Label   = 'Scan mode'
                Type    = 'select'
                Default = 'MostRecent'
                Options = @(
                    [ordered]@{ value = 'MostRecent';      label = 'MostRecent - newest first, stop at first clean point' }
                    [ordered]@{ value = 'FirstInInterval'; label = 'FirstInInterval - optimal order, stop at first clean point' }
                    [ordered]@{ value = 'AllInInterval';   label = 'AllInInterval - scan everything (needs a YARA rule)' }
                )
            }
            [ordered]@{
                Name       = 'RestorePointId'
                Label      = 'Restore point'
                Type       = 'remote-select'
                Source     = 'restorepoints'
                DependsOn  = @('JobName', 'ObjectName')
                EmptyLabel = '(let the scan mode decide)'
            }
            [ordered]@{ Name = 'AVScan'; Label = 'Signature scan (Threat Hunter / antivirus)'; Type = 'switch' }
            [ordered]@{
                Name       = 'YARARule'
                Label      = 'YARA rule'
                Type       = 'remote-select'
                Source     = 'yararules'
                EmptyLabel = '(no YARA scan)'
            }
            [ordered]@{ Name = 'EnableEntireImageScan'; Label = 'Keep scanning after the first hit'; Type = 'switch' }
        )
    }
    [ordered]@{
        Id          = 1
        Name        = 'Secure Restore - AV Scan'
        Script      = 'vbr-securerestore.ps1'
        Description = 'Mounts the selected restore point of a Veeam VM or agent backup via the Data Integration API to a Linux mount server and runs a ClamAV file level scan.'
        Fixed       = [ordered]@{ AVScan = $true }
        Fields      = @(
            [ordered]@{ Name = 'Mounthost'; Label = 'Host to attach backup to'; Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Scanhost';  Label = 'Host to scan';             Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Jobname';   Label = 'Backup job name';          Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Keyfile';   Label = 'SSH key path and file name'; Type = 'text'; Required = $true; Placeholder = 'D:\Scripts\opensshkey.key' }
            [ordered]@{ Name = 'Restore';   Label = 'Restore when the scan is clean'; Type = 'switch' }
        )
    }
    [ordered]@{
        Id          = 6
        Name        = 'Clean Restore - AV Scan'
        Script      = 'vbr-cleanrestore.ps1'
        Description = 'Scans VM backup data via the Data Integration API and walks back through the restore points until a clean one is found. If one is found the restore is started (when selected), otherwise the run is aborted after the configured number of iterations.'
        Fixed       = [ordered]@{ AVScan = $true }
        Fields      = @(
            [ordered]@{ Name = 'Mounthost';     Label = 'Host to attach backup to'; Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Scanhost';      Label = 'Host to scan';             Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Jobname';       Label = 'Backup job name';          Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Keyfile';       Label = 'SSH key path and file name'; Type = 'text'; Required = $true; Placeholder = 'D:\Scripts\opensshkey.key' }
            [ordered]@{ Name = 'MaxIterations'; Label = 'Number of iterations';     Type = 'number'; Required = $true; Default = '5'; Min = 1; Max = 100 }
            [ordered]@{ Name = 'Restore';       Label = 'Restore when a clean restore point is found'; Type = 'switch' }
        )
    }
    [ordered]@{
        Id          = 3
        Name        = 'YARA Backup Scan'
        Script      = 'vbr-securerestore.ps1'
        Description = 'Mounts the selected restore point of a Veeam VM or agent backup via the Data Integration API to a Linux mount server and runs a YARA scan.'
        Fixed       = [ordered]@{ YARAScan = $true }
        Fields      = @(
            [ordered]@{ Name = 'Mounthost'; Label = 'Host to attach backup to'; Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Scanhost';  Label = 'Host to scan';             Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Jobname';   Label = 'Backup job name';          Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Keyfile';   Label = 'SSH key path and file name'; Type = 'text'; Required = $true; Placeholder = 'D:\Scripts\opensshkey.key' }
        )
    }
    [ordered]@{
        Id          = 2
        Name        = 'NAS Backup AV Scan'
        Script      = 'vbr-nas-avscanner.ps1'
        Description = 'Starts a Microsoft Defender scan on a NAS backup for the given backup job.'
        Fixed       = [ordered]@{}
        Fields      = @(
            [ordered]@{ Name = 'JobName'; Label = 'NAS backup job name'; Type = 'text'; Required = $true }
        )
    }
    [ordered]@{
        Id          = 4
        Name        = 'Instant VM Disk Recovery'
        Script      = 'vbr-instantdiskrecovery.ps1'
        Description = 'Attaches backup disks to a virtual machine for scanning. Make sure the target VM boots from the attached rescue ISO.'
        Fixed       = [ordered]@{}
        Fields      = @(
            [ordered]@{ Name = 'Mounthost'; Label = 'VM to attach backup to';         Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Scanhost';  Label = 'Hostname (disk source) to scan'; Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Jobname';   Label = 'Backup job name';                Type = 'text'; Required = $true }
            [ordered]@{ Name = 'vCenter';   Label = 'vCenter server hostname or IP';  Type = 'text'; Required = $true }
        )
    }
    [ordered]@{
        Id          = 5
        Name        = 'Staged VM Restore'
        Script      = 'vbr-staged-restore.ps1'
        Description = 'Triggers a staged VM recovery on the given ESXi host and runs the staging script. If the script succeeds the VM is restored into production.'
        Fixed       = [ordered]@{}
        Fields      = @(
            [ordered]@{ Name = 'ESXiServer';    Label = 'Target ESXi server';       Type = 'text'; Required = $true }
            [ordered]@{ Name = 'VMName';        Label = 'VM name';                  Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Jobname';       Label = 'Backup job name';          Type = 'text'; Required = $true }
            [ordered]@{ Name = 'VirtualLab';    Label = 'Virtual lab name';         Type = 'text'; Required = $true }
            [ordered]@{ Name = 'StagingScript'; Label = 'Staging script (full path)'; Type = 'text'; Required = $true }
            [ordered]@{ Name = 'Credentials';   Label = 'Credentials for the script'; Type = 'text'; Required = $true }
        )
    }
    [ordered]@{
        Id          = 7
        Migrated    = $true
        Name        = 'FLR Hashscanner'
        Script      = 'vbr-flr-hashscanner.ps1'
        Description = 'Mounts a restore point through a file level recovery session and compares the SHA256 values of the files in the user profile folders against a hash list. Covers what the Veeam engines do not: lookups against a large hash set. Windows guest OS only. Loading the restore point list takes a few seconds because the scanning script is asked for it.'
        Fixed       = [ordered]@{}
        Fields      = @(
            [ordered]@{
                Name       = 'JobName'
                Label      = 'Backup job'
                Type       = 'remote-select'
                Source     = 'jobs'
                Required   = $true
                EmptyLabel = '(pick a job)'
            }
            [ordered]@{
                Name       = 'VM'
                Label      = 'Windows machine to scan'
                Type       = 'remote-select'
                Source     = 'objects'
                DependsOn  = @('JobName')
                Required   = $true
                EmptyLabel = '(pick a job first)'
            }
            [ordered]@{
                Name       = 'RestorePointId'
                Label      = 'Restore point'
                Type       = 'remote-select'
                Source     = 'flrrestorepoints'
                DependsOn  = @('JobName', 'VM')
                EmptyLabel = '(newest)'
            }
        )
    }
)
#endregion

#region Logging ---------------------------------------------------------------

# Writes to the same log file and in the same format the scanning scripts use,
# so webmenu entries show up on the dashboard as well.
function Write-MenuLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('Info', 'Warning')]
        [string]$Level = 'Info'
    )

    try {
        $directory = Split-Path -Path $LogFilePath -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        $timestamp = Get-Date -Format $script:LogTimestampFormat
        Add-Content -LiteralPath $LogFilePath -Value "$timestamp - $Level - Webmenu - $Message"
    } catch {
        Write-Warning "Could not write to log file '$LogFilePath': $($_.Exception.Message)"
    }
}

function Write-Console {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Gray' }
    }
    Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) -ForegroundColor $color
}
#endregion

#region Log parsing -----------------------------------------------------------

$script:LogCacheEntries   = @()
$script:LogCacheSignature = $null

# Parses the log once and caches the result until the file changes. All three
# dashboard values are derived from this, instead of re-reading the file per
# endpoint.
function Get-LogEntry {
    if (-not (Test-Path -LiteralPath $LogFilePath -PathType Leaf)) {
        $script:LogCacheEntries   = @()
        $script:LogCacheSignature = $null
        return @()
    }

    try {
        $file      = Get-Item -LiteralPath $LogFilePath
        $signature = '{0}|{1}' -f $file.LastWriteTimeUtc.Ticks, $file.Length
    } catch {
        return $script:LogCacheEntries
    }

    if ($signature -eq $script:LogCacheSignature) {
        return $script:LogCacheEntries
    }

    $entries = New-Object System.Collections.ArrayList
    $pattern = '^(?<ts>\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2})\s+-\s+(?<rest>.*)$'

    try {
        $lines = Get-Content -LiteralPath $LogFilePath -ErrorAction Stop
    } catch {
        Write-Console "Could not read log file '$LogFilePath': $($_.Exception.Message)" -Level Warning
        return $script:LogCacheEntries
    }

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $match = [regex]::Match($line, $pattern)
        if (-not $match.Success) { continue }

        # TryParseExact instead of ParseExact: a malformed timestamp must never
        # be able to terminate the web server.
        $parsed = [datetime]::MinValue
        $ok = [datetime]::TryParseExact(
            $match.Groups['ts'].Value,
            $script:LogTimestampFormat,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$parsed)

        if (-not $ok) { continue }

        $rest  = $match.Groups['rest'].Value
        $level = 'Info'
        if ($rest -match '^\s*(?<level>[A-Za-z]+)\s*(-|$)') {
            $candidate = $Matches['level']
            if ($candidate -in @('Info', 'Warning', 'Error')) { $level = $candidate }
        }

        [void]$entries.Add([pscustomobject]@{
            Time  = $parsed
            Level = $level
            Text  = $rest
            Line  = $line
        })
    }

    $script:LogCacheEntries   = @($entries)
    $script:LogCacheSignature = $signature
    return $script:LogCacheEntries
}

function Get-RecentLogEntry {
    param ([int]$WindowHours = $StatsWindowHours)

    $cutoff = (Get-Date).AddHours(-$WindowHours)
    return @(Get-LogEntry | Where-Object { $_.Time -ge $cutoff })
}

function Get-ScanStartedCount {
    return @(Get-RecentLogEntry | Where-Object { $_.Text -like '*Scanning started*' }).Count
}

function Get-ScanWarningCount {
    return @(Get-RecentLogEntry | Where-Object { $_.Level -eq 'Warning' }).Count
}

# Returns the most recent warnings as plain data. The table is built client side
# with textContent, so no server side HTML escaping is involved at all.
function Get-RecentWarning {
    param ([int]$Count = 10)

    $warnings = @(Get-LogEntry | Where-Object { $_.Level -eq 'Warning' })
    if ($warnings.Count -eq 0) { return @() }

    $selected = @($warnings | Sort-Object Time | Select-Object -Last $Count)
    [array]::Reverse($selected)

    return @($selected | ForEach-Object {
        $text = $_.Text
        if ($text.Length -gt 300) { $text = $text.Substring(0, 300) + '...' }
        [ordered]@{
            time = $_.Time.ToString($script:LogTimestampFormat)
            text = $text
        }
    })
}
#endregion

#region Veeam -----------------------------------------------------------------

$script:VeeamState = $null

function Initialize-VeeamModule {
    if ($null -ne $script:VeeamState) { return $script:VeeamState }

    $script:VeeamState = [pscustomobject]@{ Available = $false; Message = '' }

    try {
        if (Get-Module -Name 'Veeam.Backup.PowerShell') {
            $script:VeeamState.Available = $true
            return $script:VeeamState
        }

        if (Get-Module -ListAvailable -Name 'Veeam.Backup.PowerShell') {
            Import-Module -Name 'Veeam.Backup.PowerShell' -DisableNameChecking -ErrorAction Stop
            $script:VeeamState.Available = $true
            return $script:VeeamState
        }

        # No PSSnapin fallback: that was Veeam v11 and earlier, and the snapin
        # cmdlets do not exist in PowerShell 7 anyway.
        $script:VeeamState.Message = 'Veeam PowerShell module not found. Install the Veeam Backup & Replication Console on this host.'
    } catch {
        $script:VeeamState.Message = "Could not load the Veeam PowerShell module: $($_.Exception.Message)"
    }

    return $script:VeeamState
}

<#
    Ensures there is a live Veeam server session.

    The original web menu called Get-VBRJob and Get-VBRBackupSession without ever
    connecting, which is why the suspicious backup tile could not work. v13 allows
    one connection per PowerShell session, so an existing one is reused and only a
    lost session is re-established.
#>
function Connect-VeeamServer {
    $veeam = Initialize-VeeamModule
    if (-not $veeam.Available) { return $false }

    try {
        if (Get-VBRServerSession) { return $true }
    } catch {
        # No session yet - fall through and connect.
    }

    try {
        $connectArguments = @{ Server = $VbrServer }
        if ($ForceAcceptTlsCertificate) { $connectArguments['ForceAcceptTlsCertificate'] = $true }

        Connect-VBRServer @connectArguments
        Write-Console "Connected to Veeam backup server '$VbrServer'."
        return $true
    } catch {
        $script:VeeamState.Message = "Could not connect to '$VbrServer': $($_.Exception.Message)"
        Write-Console $script:VeeamState.Message -Level Warning
        return $false
    }
}

function Assert-VeeamReady {
    if (Connect-VeeamServer) { return }

    $reason = $script:VeeamState.Message
    if ([string]::IsNullOrWhiteSpace($reason)) { $reason = 'Veeam PowerShell is not available.' }
    throw $reason
}

function Get-VeeamBackupByJob {
    param ([Parameter(Mandatory = $true)] [string]$JobName)

    $backups = @(Get-VBRBackup -WarningAction SilentlyContinue |
        Where-Object { $_.JobName -eq $JobName } |
        Sort-Object CreationTime -Descending)

    if ($backups.Count -eq 0) { throw "No backup found for job '$JobName'." }
    return $backups[0]
}

# Only jobs that actually have backup data are worth offering.
function Get-JobChoice {
    Assert-VeeamReady

    return @(Get-VBRBackup -WarningAction SilentlyContinue |
        ForEach-Object { [string]$_.JobName } |
        Where-Object { $_ } |
        Sort-Object -Unique |
        ForEach-Object { [ordered]@{ value = $_; label = $_ } })
}

function Get-ObjectChoice {
    param ([Parameter(Mandatory = $true)] [string]$JobName)

    Assert-VeeamReady
    $backup = Get-VeeamBackupByJob -JobName $JobName

    return @(Get-VBRBackupObject -Backup $backup | Sort-Object Name | ForEach-Object {
        $name  = [string]$_.Name
        $notes = @()
        try { if ($_.IsLinux) { $notes += 'Linux' } else { $notes += 'Windows' } } catch { }
        try {
            $count = [int]$_.RestorePointsCount
            if ($count -gt 0) { $notes += "$count restore points" }
        } catch { }

        $label = $name
        if ($notes.Count -gt 0) { $label = "$name  ($($notes -join ', '))" }

        [ordered]@{ value = $name; label = $label }
    })
}

<#
    Restore points are resolved through the machine's ObjectId, never by name.

    VBRObjectRestorePoint.Name is the name of the restore point, not of the
    machine - filtering it against a host name silently returns nothing. Which id
    matches is not clear from the documentation (VBRBackupObject carries both Id
    and ObjectId with overlapping descriptions), so both are tried.

    Get-VBRObjectRestorePoint rather than Get-VBRRestorePoint: the ids listed here
    are handed to vbr-scan-backups.ps1 for Start-VBRScanBackup -RestorePoint,
    which only binds a VBRObjectRestorePoint. Both sides must use the same cmdlet.
#>
function Get-BackupRestorePoint {
    param (
        [Parameter(Mandatory = $true)] [string]$JobName,
        [Parameter(Mandatory = $true)] [string]$ObjectName
    )

    $backup = Get-VeeamBackupByJob -JobName $JobName

    $backupObject = Get-VBRBackupObject -Backup $backup |
        Where-Object { $_.Name -eq $ObjectName } |
        Select-Object -First 1

    if (-not $backupObject) {
        $available = @(Get-VBRBackupObject -Backup $backup | ForEach-Object { $_.Name }) -join ', '
        throw "Machine '$ObjectName' not found in job '$JobName'. Available: $available"
    }

    $candidateIds = @($backupObject.ObjectId, $backupObject.Id) |
        Where-Object { $_ } |
        Select-Object -Unique

    foreach ($candidate in $candidateIds) {
        $points = @(Get-VBRObjectRestorePoint -ObjectId $candidate -ErrorAction SilentlyContinue)
        if ($points.Count -gt 0) { return $points }
    }

    $wanted = @($candidateIds | ForEach-Object { [string]$_ })
    return @(Get-VBRObjectRestorePoint -Backup $backup |
        Where-Object { [string]$_.ObjectId -in $wanted })
}

<#
    Returns the restore point's creation time in LOCAL time.

    VBRObjectRestorePoint uses CreationDate, the older COib type used CreationTime.
    Proxmox backups return CreationDate with Kind = Utc, so the raw value would put
    the drop-down two hours off what the Veeam console shows - and the scan script
    derives its scan window from the same value.
#>
function Get-RestorePointDate {
    param ($RestorePoint)

    foreach ($name in @('CreationDate', 'CreationTime')) {
        try {
            $value = $RestorePoint.$name
            if ($value -is [datetime]) {
                if ($value.Kind -eq [System.DateTimeKind]::Utc) { return $value.ToLocalTime() }
                return $value
            }
        } catch { }
    }
    return [datetime]::MinValue
}

function Get-RestorePointChoice {
    param (
        [Parameter(Mandatory = $true)] [string]$JobName,
        [Parameter(Mandatory = $true)] [string]$ObjectName
    )

    Assert-VeeamReady

    $points = @(Get-BackupRestorePoint -JobName $JobName -ObjectName $ObjectName |
        Sort-Object -Property @{ Expression = { Get-RestorePointDate $_ } } -Descending)

    return @($points | ForEach-Object {
        $created = Get-RestorePointDate $_
        $label   = if ($created -eq [datetime]::MinValue) { 'unknown time' } else { $created.ToString($script:LogTimestampFormat) }

        # Status is the malware state of that restore point.
        try {
            $status = [string]$_.Status
            if ($status) { $label = "$label  -  $status" }
        } catch { }

        [ordered]@{
            value = [string]$_.Id
            label = $label
        }
    })
}

<#
    Restore points for the FLR hash scanner.

    Deliberately not queried here: the hash scanner mounts through
    Start-VBRWindowsFileRestore, which needs a COib restore point, while the
    restorepoints source above returns VBRObjectRestorePoint ids. Same restore
    point, different id - a list built here would simply not be found by the
    script. Letting the script list them keeps both sides in agreement.
#>
function Get-FlrRestorePointChoice {
    param (
        [Parameter(Mandatory = $true)] [string]$JobName,
        [Parameter(Mandatory = $true)] [string]$VM
    )

    $points = Invoke-ToolQuery -ScriptName 'vbr-flr-hashscanner.ps1' -Parameters ([ordered]@{
        JobName           = $JobName
        VM                = $VM
        ListRestorePoints = $true
        AsJson            = $true
    })

    return @($points | ForEach-Object {
        $label = [string]$_.creationTime
        if ($_.type) { $label = "$label  -  $($_.type)" }
        [ordered]@{ value = [string]$_.id; label = $label }
    })
}

function Get-YaraRuleChoice {
    Assert-VeeamReady

    return @(Get-VBRYARARule | ForEach-Object { [string]$_ } | Sort-Object | ForEach-Object {
        [ordered]@{ value = $_; label = $_ }
    })
}

$script:SuspiciousCache       = $null
$script:SuspiciousCacheExpiry = [datetime]::MinValue

# Normalises the various shapes a Veeam id can take. The original code used
# $job.Id.Guid, but Job.Id is a [System.Guid], which has no .Guid property - the
# comparison therefore ran against $null and never matched anything.
function ConvertTo-GuidString {
    param ($Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [guid]) { return $Value.ToString().ToLowerInvariant() }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    return $text.Trim().Trim('{', '}').ToLowerInvariant()
}

<#
    Flags incremental sessions that are unusually large.

    Two things are handled differently from a naive average check:
      * All sessions are fetched once and grouped by job, instead of querying
        the whole session list again inside the per job loop.
      * Each value is compared against the average of the *other* analysed
        sessions. Including the outlier in its own baseline raises the very
        threshold it is tested against and can hide it.
#>
function Get-SuspiciousBackup {
    param (
        [ValidateRange(3, 100)]
        [int]$Depth = $SuspiciousDepth,

        [ValidateRange(1.1, 100)]
        [double]$Growth = $SuspiciousGrowth,

        [switch]$Force
    )

    if (-not $Force -and $null -ne $script:SuspiciousCache -and (Get-Date) -lt $script:SuspiciousCacheExpiry) {
        return $script:SuspiciousCache
    }

    $result = [ordered]@{
        available = $false
        message   = ''
        count     = 0
        jobs      = @()
        updated   = (Get-Date).ToString($script:LogTimestampFormat)
    }

    if (-not (Connect-VeeamServer)) {
        $result.message = $script:VeeamState.Message
        $script:SuspiciousCache       = $result
        $script:SuspiciousCacheExpiry = (Get-Date).AddSeconds($RefreshInterval)
        return $result
    }

    try {
        $backupJobs = @(Get-VBRJob -WarningAction SilentlyContinue | Where-Object { $_.JobType -eq 'Backup' })
        if ($backupJobs.Count -eq 0) {
            $result.available = $true
            $script:SuspiciousCache       = $result
            $script:SuspiciousCacheExpiry = (Get-Date).AddSeconds($RefreshInterval)
            return $result
        }

        # One query for all sessions, then group in memory.
        $sessionsByJob = @{}
        foreach ($session in Get-VBRBackupSession -WarningAction SilentlyContinue) {
            try {
                if ($session.SessionInfo.SessionAlgorithm -ne 'Increment') { continue }
                $jobId = ConvertTo-GuidString $session.JobId
                if ([string]::IsNullOrWhiteSpace($jobId)) { continue }

                if (-not $sessionsByJob.ContainsKey($jobId)) {
                    $sessionsByJob[$jobId] = New-Object System.Collections.ArrayList
                }
                [void]$sessionsByJob[$jobId].Add($session)
            } catch {
                continue
            }
        }

        $flagged = New-Object System.Collections.ArrayList

        foreach ($job in $backupJobs) {
            $jobId = ConvertTo-GuidString $job.Id
            if ([string]::IsNullOrWhiteSpace($jobId)) { continue }
            if (-not $sessionsByJob.ContainsKey($jobId)) { continue }

            $sizes = @($sessionsByJob[$jobId] |
                Sort-Object EndTimeUTC -Descending |
                Select-Object -First $Depth |
                ForEach-Object {
                    try { [double]$_.SessionInfo.Progress.TransferedSize } catch { $null }
                } |
                Where-Object { $null -ne $_ -and $_ -gt 0 })

            # Fewer than three data points make the comparison meaningless.
            if ($sizes.Count -lt 3) { continue }

            $sum      = ($sizes | Measure-Object -Sum).Sum
            $hitCount = 0
            $largest  = 0

            foreach ($size in $sizes) {
                $baseline = ($sum - $size) / ($sizes.Count - 1)
                if ($baseline -gt 0 -and $size -gt ($baseline * $Growth)) {
                    $hitCount++
                    if ($size -gt $largest) { $largest = $size }
                }
            }

            if ($hitCount -gt 0) {
                [void]$flagged.Add([ordered]@{
                    name      = [string]$job.Name
                    hits      = $hitCount
                    analysed  = $sizes.Count
                    largestGb = [math]::Round($largest / 1GB, 2)
                })
            }
        }

        $result.available = $true
        $result.jobs      = @($flagged)
        $result.count     = $flagged.Count
    } catch {
        $result.message = "Could not analyse backup sessions: $($_.Exception.Message)"
        Write-Console $result.message -Level Warning
    }

    $script:SuspiciousCache       = $result
    $script:SuspiciousCacheExpiry = (Get-Date).AddSeconds($RefreshInterval)
    return $result
}
#endregion

#region Scan execution --------------------------------------------------------

$script:ScanJobs       = New-Object System.Collections.ArrayList
$script:NextJobId      = 1
$script:PowerShellHost = $null

# Veeam PowerShell v13 dropped Windows PowerShell 5.1 and requires PowerShell 7,
# so the scan scripts must be launched with pwsh.
function Resolve-PowerShellHost {
    if ($script:PowerShellHost) { return $script:PowerShellHost }

    if (-not [string]::IsNullOrWhiteSpace($PowerShellExecutable)) {
        $script:PowerShellHost = $PowerShellExecutable
        return $script:PowerShellHost
    }

    $command = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        $script:PowerShellHost = $command.Source
        return $script:PowerShellHost
    }

    throw 'pwsh was not found. Veeam PowerShell v13 requires PowerShell 7 - install it, or point -PowerShellExecutable at the executable.'
}

# Renders a value as a PowerShell literal. Strings are single quoted with the
# embedded quotes doubled, so a value can never turn into a parameter or a
# command of its own.
function ConvertTo-PowerShellLiteral {
    param ($Value)

    if ($null -eq $Value) { return '$null' }
    if ($Value -is [bool]) { if ($Value) { return '$true' } else { return '$false' } }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return ([string]$Value -replace ',', '.')
    }
    return "'" + ([string]$Value -replace "'", "''") + "'"
}

<#
    Builds the child process command line.

    The original version concatenated the arguments into one string, which broke
    on any value containing a space (job names almost always do) and allowed
    extra switches such as -Restore to be smuggled in through an input field.

    Here the call is assembled as a script, every value is emitted as a quoted
    literal, and the whole thing is passed base64 encoded via -EncodedCommand.
    That removes command line parsing from the picture entirely.
#>
function New-ScanCommand {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Parameters
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine('$ErrorActionPreference = ''Continue''')
    [void]$builder.AppendLine('$scanParameters = @{')

    foreach ($key in $Parameters.Keys) {
        # Defensive: parameter names come from the tool definitions above, never
        # from the request, but an invalid name must not reach the child shell.
        if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid parameter name '$key'."
        }
        [void]$builder.AppendLine(('    {0} = {1}' -f $key, (ConvertTo-PowerShellLiteral $Parameters[$key])))
    }

    [void]$builder.AppendLine('}')
    [void]$builder.AppendLine('try {')
    [void]$builder.AppendLine(('    & {0} @scanParameters' -f (ConvertTo-PowerShellLiteral $ScriptPath)))
    [void]$builder.AppendLine('    exit 0')
    [void]$builder.AppendLine('} catch {')
    # Plain text with position info: "Write-Error $_" alone loses the line number,
    # which is exactly what you need when the target script fails to parse.
    [void]$builder.AppendLine('    Write-Host "ERROR: $($_.Exception.Message)"')
    [void]$builder.AppendLine('    if ($_.InvocationInfo) { Write-Host $_.InvocationInfo.PositionMessage }')
    [void]$builder.AppendLine('    if ($_.ScriptStackTrace) { Write-Host $_.ScriptStackTrace }')
    [void]$builder.AppendLine('    exit 1')
    [void]$builder.AppendLine('}')

    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($builder.ToString()))
}

<#
    Runs a scanning script synchronously and returns its parsed JSON output.

    Used to fill drop-downs from a script rather than re-implementing its lookup
    logic here. That matters for restore points: vbr-scan-backups.ps1 works with
    VBRObjectRestorePoint ids and vbr-flr-hashscanner.ps1 with COib ids, so the two
    have different ids for the same restore point. Asking the script that will
    actually mount it keeps the ids consistent by construction.

    Costs a process start plus its own Connect-VBRServer, and blocks the request
    loop while it runs - hence the timeout.
#>
function Invoke-ToolQuery {
    param (
        [Parameter(Mandatory = $true)] [string]$ScriptName,
        [Parameter(Mandatory = $true)] [System.Collections.IDictionary]$Parameters,
        [int]$TimeoutSeconds = 120
    )

    $scriptPath = Join-Path -Path $ScanningToolsPath -ChildPath $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Script not found: $scriptPath"
    }

    if (-not (Test-Path -LiteralPath $JobOutputPath)) {
        New-Item -Path $JobOutputPath -ItemType Directory -Force | Out-Null
    }

    $encoded = New-ScanCommand -ScriptPath $scriptPath -Parameters $Parameters
    $stdOut  = Join-Path $JobOutputPath ("query-{0}.out" -f [guid]::NewGuid().ToString('N'))
    $stdErr  = "$stdOut.err"

    try {
        $process = Start-Process -FilePath (Resolve-PowerShellHost) `
            -ArgumentList '-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdOut `
            -RedirectStandardError $stdErr `
            -PassThru

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            throw "Query timed out after $TimeoutSeconds seconds."
        }

        $output = ''
        if (Test-Path -LiteralPath $stdOut) {
            $output = [string](Get-Content -LiteralPath $stdOut -Raw -ErrorAction SilentlyContinue)
        }

        if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
            $detail = $output
            if ([string]::IsNullOrWhiteSpace($detail) -and (Test-Path -LiteralPath $stdErr)) {
                $detail = [string](Get-Content -LiteralPath $stdErr -Raw -ErrorAction SilentlyContinue)
            }
            $detail = ($detail -replace '\s+', ' ').Trim()
            if ($detail.Length -gt 400) { $detail = $detail.Substring(0, 400) + '...' }
            throw ("{0} failed (exit {1}): {2}" -f $ScriptName, $process.ExitCode, $detail)
        }

        return ($output | ConvertFrom-Json)
    } finally {
        foreach ($file in @($stdOut, $stdErr)) {
            try { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } } catch { }
        }
    }
}

function Get-ToolDefinition {
    param ($Id)

    $numericId = 0
    if (-not [int]::TryParse([string]$Id, [ref]$numericId)) { return $null }
    return $script:Tools | Where-Object { $_.Id -eq $numericId } | Select-Object -First 1
}

function Get-ToolScriptPath {
    param ($Tool)
    return (Join-Path -Path $ScanningToolsPath -ChildPath $Tool.Script)
}

# Builds the parameter set from the request. Only fields declared in the tool
# definition are read, so unknown properties in the payload are ignored.
function ConvertTo-ScanParameter {
    param (
        [Parameter(Mandatory = $true)] $Tool,
        $Fields
    )

    $parameters = [ordered]@{}
    $errors     = New-Object System.Collections.ArrayList

    $supplied = @{}
    if ($null -ne $Fields) {
        foreach ($property in $Fields.PSObject.Properties) {
            $supplied[$property.Name] = $property.Value
        }
    }

    foreach ($field in $Tool.Fields) {
        $name       = $field.Name
        $isRequired = $field.Contains('Required') -and $field.Required
        $value      = $null
        if ($supplied.ContainsKey($name)) { $value = $supplied[$name] }

        switch ($field.Type) {
            'switch' {
                $enabled = $false
                if ($value -is [bool]) {
                    $enabled = $value
                } elseif ($null -ne $value) {
                    $enabled = ([string]$value -eq 'true')
                }
                # Only pass the switch when it is actually on.
                if ($enabled) { $parameters[$name] = $true }
            }

            'select' {
                $text = ([string]$value).Trim()
                if ([string]::IsNullOrEmpty($text)) {
                    if ($isRequired) { [void]$errors.Add("$($field.Label) is required.") }
                    break
                }
                # Whitelist: the value must be one the definition actually offers.
                $allowed = @($field.Options | ForEach-Object { [string]$_.value })
                if ($allowed -notcontains $text) {
                    [void]$errors.Add("$($field.Label): '$text' is not a valid choice.")
                    break
                }
                $parameters[$name] = $text
            }

            'remote-select' {
                $text = ([string]$value).Trim()
                if ([string]::IsNullOrEmpty($text)) {
                    # Empty means "not selected" - the parameter is simply omitted.
                    if ($isRequired) { [void]$errors.Add("$($field.Label) is required.") }
                    break
                }
                $parameters[$name] = $text
            }

            'number' {
                $text = ([string]$value).Trim()
                if ([string]::IsNullOrEmpty($text)) {
                    if ($isRequired) { [void]$errors.Add("$($field.Label) is required.") }
                    break
                }
                $number = 0
                if (-not [int]::TryParse($text, [ref]$number)) {
                    [void]$errors.Add("$($field.Label) must be a whole number.")
                    break
                }
                if ($field.Contains('Min') -and $number -lt $field.Min) {
                    [void]$errors.Add("$($field.Label) must be at least $($field.Min).")
                    break
                }
                if ($field.Contains('Max') -and $number -gt $field.Max) {
                    [void]$errors.Add("$($field.Label) must not be greater than $($field.Max).")
                    break
                }
                $parameters[$name] = $number
            }

            default {
                $text = ([string]$value).Trim()
                if ([string]::IsNullOrEmpty($text)) {
                    if ($isRequired) { [void]$errors.Add("$($field.Label) is required.") }
                    break
                }
                $parameters[$name] = $text
            }
        }
    }

    if ($Tool.Contains('RequireAnyOf')) {
        $chosen = @($Tool.RequireAnyOf | Where-Object { $parameters.Contains($_) })
        if ($chosen.Count -eq 0) {
            $labels = @($Tool.RequireAnyOf | ForEach-Object {
                # Capture it: $_ inside the nested Where-Object refers to the field.
                $wanted = $_
                $match  = $Tool.Fields | Where-Object { $_.Name -eq $wanted } | Select-Object -First 1
                if ($match) { $match.Label } else { $wanted }
            })
            [void]$errors.Add("Pick at least one of: $($labels -join ', ').")
        }
    }

    foreach ($key in $Tool.Fixed.Keys) {
        $parameters[$key] = $Tool.Fixed[$key]
    }

    # Keep the scanning scripts and the dashboard on the same log file.
    $parameters['LogFilePath'] = $LogFilePath

    return [pscustomobject]@{
        Parameters = $parameters
        Errors     = @($errors)
    }
}

# Starts the scan without -Wait. The original blocked the single request loop
# for the entire duration of a scan, which froze the whole UI and made the
# browser time out on a request that had in fact succeeded.
function Start-ScanJob {
    param (
        [Parameter(Mandatory = $true)] $Tool,
        [Parameter(Mandatory = $true)] [System.Collections.IDictionary]$Parameters
    )

    $scriptPath = Get-ToolScriptPath -Tool $Tool
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Script not found: $scriptPath"
    }

    # Parse before launching. A syntax error in the target script otherwise only
    # shows up as an unreadable CLIXML blob in the job output, with no line number.
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        $first = $parseErrors[0]
        throw ("Syntax error in {0} at line {1}, column {2}: {3}{4}(Is the deployed copy up to date?)" -f
            (Split-Path -Leaf $scriptPath),
            $first.Extent.StartLineNumber,
            $first.Extent.StartColumnNumber,
            $first.Message,
            [Environment]::NewLine)
    }

    if (-not (Test-Path -LiteralPath $JobOutputPath)) {
        New-Item -Path $JobOutputPath -ItemType Directory -Force | Out-Null
    }

    $jobId     = $script:NextJobId++
    $stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
    $stdOut    = Join-Path $JobOutputPath ("job-{0}-{1}.out.log" -f $jobId, $stamp)
    $stdErr    = Join-Path $JobOutputPath ("job-{0}-{1}.err.log" -f $jobId, $stamp)
    $encoded   = New-ScanCommand -ScriptPath $scriptPath -Parameters $Parameters

    $process = Start-Process -FilePath (Resolve-PowerShellHost) `
        -ArgumentList '-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdOut `
        -RedirectStandardError $stdErr `
        -PassThru

    $job = [pscustomobject]@{
        Id        = $jobId
        Tool      = $Tool.Name
        Started   = Get-Date
        Ended     = $null
        Process   = $process
        State     = 'Running'
        ExitCode  = $null
        StdOut    = $stdOut
        StdErr    = $stdErr
    }

    [void]$script:ScanJobs.Add($job)

    $shown = ($Parameters.Keys | Where-Object { $_ -ne 'LogFilePath' } | ForEach-Object {
        '{0}={1}' -f $_, $Parameters[$_]
    }) -join ', '

    Write-MenuLog -Message "Started '$($Tool.Name)' as job $jobId ($shown)"
    Write-Console "Job $jobId started: $($Tool.Name) [$shown]"

    return $job
}

function Update-ScanJobState {
    foreach ($job in $script:ScanJobs) {
        if ($job.State -ne 'Running') { continue }
        try {
            if ($job.Process.HasExited) {
                $job.ExitCode = $job.Process.ExitCode
                $job.Ended    = Get-Date

                # Exit code 2 means the scan worked and found something. Veeam
                # reports such a scan session as "Failed", so without a state of
                # its own a finding is indistinguishable from a broken script.
                $job.State = switch ($job.ExitCode) {
                    0       { 'Completed' }
                    2       { 'Threat' }
                    default { 'Failed' }
                }

                $level = if ($job.ExitCode -eq 0) { 'Info' } else { 'Warning' }
                Write-MenuLog -Level $level -Message "Job $($job.Id) '$($job.Tool)' finished as $($job.State) (exit code $($job.ExitCode))"
                Write-Console "Job $($job.Id) finished: $($job.State) (exit code $($job.ExitCode))" -Level $level
            }
        } catch {
            $job.State = 'Unknown'
            $job.Ended = Get-Date
        }
    }

    # Keep the list from growing without bound.
    while ($script:ScanJobs.Count -gt 50) {
        $script:ScanJobs.RemoveAt(0)
    }
}

function Get-ScanJobReport {
    Update-ScanJobState

    $jobs = @($script:ScanJobs | Sort-Object Id -Descending | Select-Object -First 15 | ForEach-Object {
        $duration = if ($_.Ended) { $_.Ended - $_.Started } else { (Get-Date) - $_.Started }
        [ordered]@{
            id       = $_.Id
            tool     = $_.Tool
            state    = $_.State
            started  = $_.Started.ToString($script:LogTimestampFormat)
            duration = '{0:hh\:mm\:ss}' -f $duration
            exitCode = $_.ExitCode
        }
    })

    return [ordered]@{
        running = @($script:ScanJobs | Where-Object { $_.State -eq 'Running' }).Count
        jobs    = $jobs
    }
}

function Get-ScanJobOutput {
    param ([int]$Id, [int]$Tail = 200)

    Update-ScanJobState

    $job = $script:ScanJobs | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $job) { return $null }

    $text = New-Object System.Text.StringBuilder

    foreach ($item in @(
        @{ Label = 'Output'; Path = $job.StdOut }
        @{ Label = 'Errors'; Path = $job.StdErr }
    )) {
        if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) { continue }
        try {
            $content = @(Get-Content -LiteralPath $item.Path -Tail $Tail -ErrorAction Stop)
        } catch {
            continue
        }
        if ($content.Count -eq 0) { continue }
        [void]$text.AppendLine("--- $($item.Label) ---")
        [void]$text.AppendLine(($content -join [Environment]::NewLine))
    }

    $body = $text.ToString()
    if ([string]::IsNullOrWhiteSpace($body)) { $body = '(no output yet)' }

    return [ordered]@{
        id       = $job.Id
        tool     = $job.Tool
        state    = $job.State
        exitCode = $job.ExitCode
        output   = $body
    }
}
#endregion

#region HTML generation -------------------------------------------------------

function ConvertTo-HtmlText {
    param ([string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function New-ToolButtonHtml {
    $builder = New-Object System.Text.StringBuilder

    foreach ($tool in $script:Tools) {
        $scriptPath = Get-ToolScriptPath -Tool $tool
        $available  = Test-Path -LiteralPath $scriptPath -PathType Leaf
        $name       = ConvertTo-HtmlText $tool.Name

        if ($available) {
            [void]$builder.AppendLine(('        <button type="button" class="btn tool-btn" data-open="{0}">{1}</button>' -f $tool.Id, $name))
        } else {
            $title = ConvertTo-HtmlText "Script not found: $scriptPath"
            [void]$builder.AppendLine(('        <button type="button" class="btn tool-btn" disabled title="{0}">{1}</button>' -f $title, $name))
        }
    }

    return $builder.ToString()
}

function New-ToolDialogHtml {
    $builder = New-Object System.Text.StringBuilder

    foreach ($tool in $script:Tools) {
        $id    = $tool.Id
        $name  = ConvertTo-HtmlText $tool.Name
        $desc  = ConvertTo-HtmlText $tool.Description

        [void]$builder.AppendLine(('<div id="dialog-{0}" class="dialog-backdrop" role="dialog" aria-modal="true" aria-labelledby="dialog-{0}-title" hidden>' -f $id))
        [void]$builder.AppendLine('    <div class="dialog-card">')
        [void]$builder.AppendLine(('        <h2 id="dialog-{0}-title">{1}</h2>' -f $id, $name))
        [void]$builder.AppendLine(('        <p class="dialog-desc">{0}</p>' -f $desc))

        if (-not ($tool.Contains('Migrated') -and $tool.Migrated)) {
            [void]$builder.AppendLine('        <p class="dialog-note">Not migrated to v13 yet. This script still expects console input and will fail when started from here.</p>')
        }

        foreach ($field in $tool.Fields) {
            $fieldId    = 'f{0}-{1}' -f $id, $field.Name
            $label      = ConvertTo-HtmlText $field.Label
            $fieldName  = ConvertTo-HtmlText $field.Name
            $isRequired = $field.Contains('Required') -and $field.Required

            if ($field.Type -eq 'switch') {
                [void]$builder.AppendLine('        <div class="field field-switch">')
                [void]$builder.AppendLine(('            <input type="checkbox" id="{0}" data-field="{1}">' -f $fieldId, $fieldName))
                [void]$builder.AppendLine(('            <label for="{0}">{1}</label>' -f $fieldId, $label))
                [void]$builder.AppendLine('        </div>')
                continue
            }

            if ($field.Type -eq 'select') {
                [void]$builder.AppendLine('        <div class="field">')
                [void]$builder.AppendLine(('            <label for="{0}">{1}</label>' -f $fieldId, $label))
                [void]$builder.AppendLine(('            <select id="{0}" data-field="{1}" class="parameter-input">' -f $fieldId, $fieldName))
                foreach ($option in $field.Options) {
                    $selected = if ($field.Contains('Default') -and [string]$option.value -eq [string]$field.Default) { ' selected' } else { '' }
                    [void]$builder.AppendLine(('                <option value="{0}"{1}>{2}</option>' -f
                        (ConvertTo-HtmlText ([string]$option.value)), $selected, (ConvertTo-HtmlText ([string]$option.label))))
                }
                [void]$builder.AppendLine('            </select>')
                [void]$builder.AppendLine('        </div>')
                continue
            }

            if ($field.Type -eq 'remote-select') {
                $emptyLabel = if ($field.Contains('EmptyLabel')) { ConvertTo-HtmlText $field.EmptyLabel } else { '(none)' }
                $dependsOn  = if ($field.Contains('DependsOn')) { ($field.DependsOn -join ',') } else { '' }

                [void]$builder.AppendLine('        <div class="field">')
                [void]$builder.AppendLine(('            <label for="{0}">{1}</label>' -f $fieldId, $label))
                [void]$builder.AppendLine('            <div class="field-remote">')
                $requiredAttribute = if ($isRequired) { ' data-required="true"' } else { '' }
                [void]$builder.AppendLine(('                <select id="{0}" data-field="{1}" data-source="{2}" data-depends="{3}" data-empty="{4}"{5} class="parameter-input">' -f
                    $fieldId, $fieldName, (ConvertTo-HtmlText $field.Source), (ConvertTo-HtmlText $dependsOn), $emptyLabel, $requiredAttribute))
                [void]$builder.AppendLine(('                    <option value="">{0}</option>' -f $emptyLabel))
                [void]$builder.AppendLine('                </select>')
                if ($dependsOn) {
                    [void]$builder.AppendLine(('                <button type="button" class="btn btn-secondary btn-small" data-action="load" data-target="{0}">Load</button>' -f $fieldId))
                }
                [void]$builder.AppendLine('            </div>')
                [void]$builder.AppendLine('        </div>')
                continue
            }

            $attributes = New-Object System.Text.StringBuilder
            [void]$attributes.Append(('id="{0}" data-field="{1}" class="parameter-input"' -f $fieldId, $fieldName))
            if ($isRequired) { [void]$attributes.Append(' data-required="true" required') }
            if ($field.Contains('Placeholder')) {
                [void]$attributes.Append((' placeholder="{0}"' -f (ConvertTo-HtmlText $field.Placeholder)))
            }
            if ($field.Type -eq 'number') {
                [void]$attributes.Append(' type="number"')
                if ($field.Contains('Min')) { [void]$attributes.Append((' min="{0}"' -f $field.Min)) }
                if ($field.Contains('Max')) { [void]$attributes.Append((' max="{0}"' -f $field.Max)) }
            } else {
                [void]$attributes.Append(' type="text" autocomplete="off" spellcheck="false"')
            }
            if ($field.Contains('Default')) {
                [void]$attributes.Append((' data-default="{0}"' -f (ConvertTo-HtmlText $field.Default)))
            }

            $labelSuffix = if ($isRequired) { ' <span class="req" aria-hidden="true">*</span>' } else { '' }

            [void]$builder.AppendLine('        <div class="field">')
            [void]$builder.AppendLine(('            <label for="{0}">{1}{2}</label>' -f $fieldId, $label, $labelSuffix))
            [void]$builder.AppendLine(('            <input {0}>' -f $attributes.ToString()))
            [void]$builder.AppendLine('        </div>')
        }

        [void]$builder.AppendLine(('        <p class="dialog-error" id="dialog-{0}-error" role="alert" hidden></p>' -f $id))
        [void]$builder.AppendLine('        <div class="dialog-actions">')
        [void]$builder.AppendLine(('            <button type="button" class="btn btn-primary" data-action="submit" data-tool="{0}">Start scan</button>' -f $id))
        [void]$builder.AppendLine('            <button type="button" class="btn btn-secondary" data-action="cancel">Cancel</button>')
        [void]$builder.AppendLine('        </div>')
        [void]$builder.AppendLine('    </div>')
        [void]$builder.AppendLine('</div>')
    }

    return $builder.ToString()
}

# The template is a single quoted here string on purpose: PowerShell performs no
# interpolation inside it, so CSS and JavaScript cannot collide with PowerShell
# syntax. Values are injected through the placeholders below.
$script:PageTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Backup Scanning Tools</title>
    <style>
        :root {
            --accent: #4CAF50;
            --accent-dark: #3e8e41;
            --accent-hover: #45a049;
            --ink: #24292f;
            --muted: #6a737d;
            --surface: #ffffff;
            --page: #f1f1f1;
            --alert: #d97706;
            --danger: #c0392b;
        }
        * { box-sizing: border-box; }
        body {
            font-family: Arial, Helvetica, sans-serif;
            background-color: var(--page);
            color: var(--ink);
            margin: 0;
            padding: 0;
        }
        .header {
            background-color: var(--accent);
            color: #fff;
            padding: 16px 24px;
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .header h1 { font-size: 24px; margin: 0; flex: 1; }
        .header img { height: 56px; }
        .help {
            position: relative;
            width: 34px;
            height: 34px;
            line-height: 34px;
            text-align: center;
            border-radius: 50%;
            background: #fff;
            color: var(--accent);
            font-size: 22px;
            font-weight: bold;
            cursor: help;
            flex: none;
        }
        .help-tooltip {
            display: none;
            position: absolute;
            top: calc(100% + 8px);
            right: 0;
            width: 320px;
            padding: 12px;
            background: rgba(0, 0, 0, 0.85);
            color: #fff;
            border-radius: 6px;
            font-size: 14px;
            font-weight: normal;
            line-height: 1.45;
            text-align: left;
            z-index: 20;
        }
        .help-tooltip p { margin: 0 0 8px; }
        .help-tooltip p:last-child { margin-bottom: 0; }
        .help:hover .help-tooltip, .help:focus-within .help-tooltip { display: block; }
        main { padding: 24px; max-width: 1200px; }
        h2 { font-size: 18px; margin: 32px 0 12px; }
        .tiles {
            display: flex;
            flex-wrap: wrap;
            gap: 16px;
            margin-bottom: 8px;
        }
        .tile {
            position: relative;
            min-width: 220px;
            background: #e1e1e3;
            border-radius: 14px;
            padding: 12px 16px;
            display: flex;
            flex-direction: column;
            gap: 6px;
        }
        .tile-label { font-size: 13px; font-weight: bold; color: #5132ee; }
        .tile-value { font-size: 26px; font-weight: bold; color: #5132ee; }
        .tile-value.alert { color: var(--alert); }
        .tile-note { font-size: 12px; color: var(--muted); }
        .tile-detail {
            display: none;
            position: absolute;
            bottom: calc(100% + 6px);
            left: 0;
            min-width: 100%;
            max-width: 480px;
            background: #333;
            color: #fff;
            padding: 8px 10px;
            border-radius: 6px;
            font-size: 13px;
            font-weight: normal;
            white-space: pre-wrap;
            z-index: 10;
        }
        .tile:hover .tile-detail[data-has-content="true"] { display: block; }
        .button-container { display: flex; flex-wrap: wrap; gap: 12px; }
        .btn {
            background-color: var(--accent);
            color: #fff;
            padding: 12px 18px;
            border: none;
            border-radius: 10px;
            cursor: pointer;
            font-size: 15px;
        }
        .btn:hover:not(:disabled) { background-color: var(--accent-hover); }
        .btn:active:not(:disabled) { background-color: var(--accent-dark); }
        .btn:focus-visible { outline: 3px solid #1b5e20; outline-offset: 2px; }
        .btn:disabled { background-color: #b6b6b6; cursor: not-allowed; }
        .btn-secondary { background-color: #6a737d; }
        .btn-secondary:hover:not(:disabled) { background-color: #55595f; }
        table { width: 100%; border-collapse: collapse; background: var(--surface); }
        th, td { text-align: left; padding: 8px 10px; font-size: 14px; vertical-align: top; }
        thead th { background: #e8e8e8; font-size: 13px; }
        tbody tr:nth-child(odd) { background: #f7f7f7; }
        td.nowrap { white-space: nowrap; }
        td.state-Running { color: #1565c0; font-weight: bold; }
        td.state-Completed { color: #2e7d32; font-weight: bold; }
        td.state-Failed { color: var(--danger); font-weight: bold; }
        td.state-Threat {
            color: #fff;
            background: var(--danger);
            font-weight: bold;
            border-radius: 4px;
            text-align: center;
        }
        .table-wrap { overflow-x: auto; }
        .empty { color: var(--muted); font-size: 14px; padding: 8px 0; }
        .dialog-backdrop {
            position: fixed;
            inset: 0;
            background: rgba(0, 0, 0, 0.5);
            display: flex;
            align-items: flex-start;
            justify-content: center;
            padding: 40px 16px;
            overflow-y: auto;
            z-index: 100;
        }
        .dialog-backdrop[hidden] { display: none; }
        .dialog-card {
            background: var(--surface);
            width: 460px;
            max-width: 100%;
            padding: 20px 24px 24px;
            border-radius: 12px;
        }
        .dialog-card h2 { margin: 0 0 8px; font-size: 19px; }
        .dialog-desc { font-size: 14px; line-height: 1.5; color: #444; margin: 0 0 16px; }
        .field { margin-bottom: 12px; }
        .field label { display: block; font-size: 13px; margin-bottom: 4px; }
        .field-switch { display: flex; align-items: center; gap: 8px; margin: 16px 0; }
        .field-switch label { margin: 0; font-size: 14px; }
        .req { color: var(--danger); }
        .parameter-input {
            display: block;
            width: 100%;
            border: 1px solid #ccc;
            border-radius: 5px;
            padding: 8px;
            font-size: 14px;
        }
        .dialog-error {
            color: var(--danger);
            font-size: 13px;
            margin: 0 0 12px;
            white-space: pre-line;
        }
        .dialog-note {
            background: #fff4e5;
            border-left: 4px solid var(--alert);
            color: #7a4a00;
            font-size: 13px;
            line-height: 1.45;
            padding: 8px 10px;
            margin: 0 0 16px;
        }
        .field-remote { display: flex; gap: 8px; align-items: center; }
        .field-remote select { flex: 1; min-width: 0; }
        .btn-small { padding: 8px 12px; font-size: 13px; white-space: nowrap; }
        select.parameter-input { background: #fff; }
        select.parameter-input:disabled { background: #f0f0f0; color: var(--muted); }
        .dialog-actions { display: flex; gap: 10px; }
        .toast {
            position: fixed;
            right: 16px;
            bottom: 16px;
            max-width: 380px;
            padding: 12px 16px;
            border-radius: 8px;
            color: #fff;
            font-size: 14px;
            background: #2e7d32;
            box-shadow: 0 4px 14px rgba(0, 0, 0, 0.25);
            z-index: 200;
        }
        .toast[hidden] { display: none; }
        .toast.error { background: var(--danger); }
        .statusbar {
            padding: 10px 24px;
            font-size: 12px;
            color: var(--muted);
            border-top: 1px solid #ddd;
            margin-top: 24px;
        }
        .statusbar .stale { color: var(--danger); font-weight: bold; }
    </style>
</head>
<body>
    <header class="header">
        __LOGO__
        <h1>Backup Scanning Tools</h1>
        <div class="help" tabindex="0" role="note" aria-label="About this page">?
            <div class="help-tooltip">
                <p>A collection of the backup scanning tools from the YAMT repository.</p>
                <p>Pick a tool, fill in its parameters and start the scan. Scans run in the background; progress appears under "Scan jobs".</p>
                <p>The dashboard refreshes every __REFRESH_SECONDS__ seconds.</p>
            </div>
        </div>
    </header>

    <main>
        <div class="tiles">
            <div class="tile">
                <span class="tile-label">Started scans (__WINDOW_HOURS__ h)</span>
                <span class="tile-value" id="scanCount">&hellip;</span>
            </div>
            <div class="tile">
                <span class="tile-label">Scan warnings (__WINDOW_HOURS__ h)</span>
                <span class="tile-value" id="warningCount">&hellip;</span>
            </div>
            <div class="tile">
                <span class="tile-label">Suspicious incremental backups</span>
                <span class="tile-value" id="suspiciousCount">&hellip;</span>
                <span class="tile-note" id="suspiciousNote"></span>
                <span class="tile-detail" id="suspiciousDetail" data-has-content="false"></span>
            </div>
            <div class="tile">
                <span class="tile-label">Running scans</span>
                <span class="tile-value" id="runningCount">&hellip;</span>
            </div>
        </div>

        <h2>Start a scan</h2>
        <div class="button-container">
__BUTTONS__
        </div>

        <h2>Scan jobs</h2>
        <div class="table-wrap">
            <table>
                <thead>
                    <tr><th>ID</th><th>Tool</th><th>State</th><th>Started</th><th>Duration</th><th>Exit</th><th></th></tr>
                </thead>
                <tbody id="jobRows"></tbody>
            </table>
        </div>
        <p class="empty" id="jobsEmpty" hidden>No scans started yet.</p>

        <h2>Last 10 scan warnings</h2>
        <div class="table-wrap">
            <table>
                <thead>
                    <tr><th style="width: 170px;">Time</th><th>Entry</th></tr>
                </thead>
                <tbody id="warningRows"></tbody>
            </table>
        </div>
        <p class="empty" id="warningsEmpty" hidden>No warnings in the log.</p>
    </main>

    <div class="statusbar">
        V__VERSION__ &middot; log file: __LOGFILE__ &middot; last refresh: <span id="lastRefresh">never</span>
        <span id="staleFlag" class="stale" hidden>(connection lost)</span>
    </div>

__DIALOGS__

    <div id="jobOutputDialog" class="dialog-backdrop" role="dialog" aria-modal="true" aria-labelledby="jobOutputTitle" hidden>
        <div class="dialog-card" style="width: 760px;">
            <h2 id="jobOutputTitle">Job output</h2>
            <pre id="jobOutputBody" style="max-height: 60vh; overflow: auto; background: #f5f5f5; padding: 12px; border-radius: 6px; font-size: 12px; white-space: pre-wrap;"></pre>
            <div class="dialog-actions">
                <button type="button" class="btn btn-secondary" data-action="cancel">Close</button>
            </div>
        </div>
    </div>

    <div id="toast" class="toast" role="status" hidden></div>

<script>
(function () {
    'use strict';

    var CSRF_TOKEN   = '__CSRF__';
    var REFRESH_MS   = __REFRESH_MS__;
    var toastTimer   = null;

    function byId(id) { return document.getElementById(id); }

    // Windows PowerShell 5.1 unwraps single element arrays in ConvertTo-Json,
    // so a list with exactly one entry arrives as a bare object.
    function asArray(value) {
        if (value === null || value === undefined) { return []; }
        return Array.isArray(value) ? value : [value];
    }

    function showToast(message, isError) {
        var toast = byId('toast');
        toast.textContent = message;
        toast.className = isError ? 'toast error' : 'toast';
        toast.hidden = false;
        if (toastTimer) { clearTimeout(toastTimer); }
        toastTimer = setTimeout(function () { toast.hidden = true; }, isError ? 8000 : 4000);
    }

    function request(url, options) {
        var settings = options || {};
        settings.cache = 'no-store';
        settings.headers = settings.headers || {};
        settings.headers['X-Csrf-Token'] = CSRF_TOKEN;
        return fetch(url, settings).then(function (response) {
            return response.json().catch(function () {
                throw new Error('Server returned an unreadable response (HTTP ' + response.status + ').');
            }).then(function (data) {
                if (!response.ok) {
                    throw new Error((data && data.message) ? data.message : 'HTTP ' + response.status);
                }
                return data;
            });
        });
    }

    function setValue(id, value, isAlert) {
        var element = byId(id);
        element.textContent = value;
        element.className = isAlert ? 'tile-value alert' : 'tile-value';
    }

    function markStale(isStale) {
        byId('staleFlag').hidden = !isStale;
    }

    function renderWarnings(data) {
        var warnings = asArray(data);
        var body = byId('warningRows');
        body.textContent = '';
        byId('warningsEmpty').hidden = warnings.length > 0;

        warnings.forEach(function (entry) {
            var row = document.createElement('tr');
            var time = document.createElement('td');
            time.className = 'nowrap';
            time.textContent = entry.time;
            var text = document.createElement('td');
            text.textContent = entry.text;
            row.appendChild(time);
            row.appendChild(text);
            body.appendChild(row);
        });
    }

    function renderJobs(report) {
        var jobs = asArray(report ? report.jobs : null);
        var running = (report && report.running) ? report.running : 0;
        var body = byId('jobRows');
        body.textContent = '';
        byId('jobsEmpty').hidden = jobs.length > 0;
        setValue('runningCount', running, running > 0);

        jobs.forEach(function (job) {
            var row = document.createElement('tr');

            ['id', 'tool'].forEach(function (key) {
                var cell = document.createElement('td');
                cell.textContent = job[key];
                row.appendChild(cell);
            });

            var state = document.createElement('td');
            state.textContent = job.state;
            state.className = 'state-' + job.state;
            if (job.state === 'Threat') {
                state.title = 'The scan ran fine and found something. Veeam reports such a session as "Failed" - '
                            + 'that is how a finding is signalled, not a script error. Open Output for the details.';
            }
            row.appendChild(state);

            var started = document.createElement('td');
            started.className = 'nowrap';
            started.textContent = job.started;
            row.appendChild(started);

            var duration = document.createElement('td');
            duration.className = 'nowrap';
            duration.textContent = job.duration;
            row.appendChild(duration);

            var exit = document.createElement('td');
            exit.textContent = (job.exitCode === null || job.exitCode === undefined) ? '-' : job.exitCode;
            row.appendChild(exit);

            var actions = document.createElement('td');
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'btn btn-secondary';
            button.style.padding = '4px 10px';
            button.style.fontSize = '12px';
            button.textContent = 'Output';
            button.setAttribute('data-action', 'output');
            button.setAttribute('data-job', job.id);
            actions.appendChild(button);
            row.appendChild(actions);

            body.appendChild(row);
        });
    }

    function refreshStatus() {
        return request('/api/status').then(function (data) {
            setValue('scanCount', data.scanCount, false);
            setValue('warningCount', data.warningCount, data.warningCount > 0);
            renderWarnings(data.warnings);
            renderJobs(data.jobReport);
            byId('lastRefresh').textContent = data.now;
            markStale(false);
        }).catch(function (error) {
            markStale(true);
            console.error(error);
        });
    }

    function refreshSuspicious() {
        return request('/api/suspicious').then(function (data) {
            var detail = byId('suspiciousDetail');
            var note = byId('suspiciousNote');

            if (!data.available) {
                setValue('suspiciousCount', 'n/a', false);
                note.textContent = data.message || 'Veeam data unavailable';
                detail.setAttribute('data-has-content', 'false');
                return;
            }

            setValue('suspiciousCount', data.count, data.count > 0);
            note.textContent = 'checked ' + data.updated;

            var flagged = asArray(data.jobs);
            if (flagged.length) {
                detail.textContent = flagged.map(function (job) {
                    return job.name + '  (' + job.hits + '/' + job.analysed + ' sessions, largest ' + job.largestGb + ' GB)';
                }).join('\n');
                detail.setAttribute('data-has-content', 'true');
            } else {
                detail.textContent = '';
                detail.setAttribute('data-has-content', 'false');
            }
        }).catch(function (error) {
            byId('suspiciousNote').textContent = 'analysis failed';
            console.error(error);
        });
    }

    function refreshAll() {
        refreshStatus();
        refreshSuspicious();
    }

    function closeDialogs() {
        var dialogs = document.querySelectorAll('.dialog-backdrop');
        Array.prototype.forEach.call(dialogs, function (dialog) { dialog.hidden = true; });
    }

    // Puts a remote-select back to just its placeholder option.
    function resetRemoteSelect(select, text) {
        select.textContent = '';
        var placeholder = document.createElement('option');
        placeholder.value = '';
        placeholder.textContent = text || select.getAttribute('data-empty') || '(none)';
        select.appendChild(placeholder);
    }

    function fillRemoteSelect(select, options, preserve) {
        var previous = preserve ? select.value : '';
        resetRemoteSelect(select);

        asArray(options).forEach(function (option) {
            var element = document.createElement('option');
            element.value = option.value;
            element.textContent = option.label;
            select.appendChild(element);
        });

        // Keep the operator's choice if it survived a manual refresh.
        if (previous) { select.value = previous; }
    }

    // isAuto: triggered by a dependency change rather than by the Load button.
    // Those runs stay quiet and do not try to keep the previous selection.
    function loadRemoteSelect(select, dialog, isAuto) {
        var source = select.getAttribute('data-source');
        if (!source) { return Promise.resolve(); }

        var url = '/api/options?source=' + encodeURIComponent(source);
        var depends = (select.getAttribute('data-depends') || '').split(',').filter(Boolean);

        for (var i = 0; i < depends.length; i++) {
            var field = dialog.querySelector('[data-field="' + depends[i] + '"]');
            var value = field ? field.value.trim() : '';
            if (!value) {
                if (!isAuto) { showToast('Pick "' + depends[i] + '" first.', true); }
                return Promise.resolve();
            }
            url += '&' + encodeURIComponent(depends[i]) + '=' + encodeURIComponent(value);
        }

        // Some sources shell out to a scanning script and take seconds, so say so
        // instead of leaving an empty box that looks broken.
        select.disabled = true;
        resetRemoteSelect(select, 'loading ...');

        return request(url).then(function (options) {
            fillRemoteSelect(select, options, !isAuto);
            if (asArray(options).length === 0) {
                showToast('Nothing found for ' + source + '.', true);
            }
        }).catch(function (error) {
            showToast(error.message, true);
        }).then(function () {
            select.disabled = false;
            // Nothing arrived (empty result or error): back to the normal placeholder.
            if (select.options.length <= 1) { resetRemoteSelect(select); }
        });
    }

    // Chains the drop-downs: job -> machine -> restore point.
    function refreshDependents(dialog, changedField) {
        var dependents = dialog.querySelectorAll('select[data-source][data-depends]');

        Array.prototype.forEach.call(dependents, function (select) {
            var depends = (select.getAttribute('data-depends') || '').split(',').filter(Boolean);
            if (depends.indexOf(changedField) === -1) { return; }

            var ready = depends.every(function (name) {
                var element = dialog.querySelector('[data-field="' + name + '"]');
                return element && element.value.trim() !== '';
            });

            if (ready) {
                loadRemoteSelect(select, dialog, true);
            } else {
                // A dependency was cleared, so anything below it is stale.
                resetRemoteSelect(select);
            }
        });
    }

    function openDialog(toolId) {
        closeDialogs();
        var dialog = byId('dialog-' + toolId);
        if (!dialog) { return; }

        var errorBox = byId('dialog-' + toolId + '-error');
        errorBox.hidden = true;
        errorBox.textContent = '';

        var inputs = dialog.querySelectorAll('[data-field]');
        Array.prototype.forEach.call(inputs, function (input) {
            if (input.type === 'checkbox') {
                input.checked = false;
            } else if (input.tagName === 'SELECT') {
                if (input.getAttribute('data-source')) {
                    resetRemoteSelect(input);
                } else {
                    // Static select: fall back to the option marked selected.
                    var preset = input.querySelector('option[selected]');
                    input.value = preset ? preset.value
                                : (input.options.length ? input.options[0].value : '');
                }
            } else {
                input.value = input.getAttribute('data-default') || '';
            }
        });

        dialog.hidden = false;

        // Lists without dependencies can be loaded right away.
        var remotes = dialog.querySelectorAll('select[data-source]');
        Array.prototype.forEach.call(remotes, function (select) {
            if (!(select.getAttribute('data-depends') || '')) {
                loadRemoteSelect(select, dialog);
            }
        });

        var first = dialog.querySelector('input:not([type=checkbox])');
        if (first) { first.focus(); }
    }

    function submitTool(toolId) {
        var dialog = byId('dialog-' + toolId);
        var errorBox = byId('dialog-' + toolId + '-error');
        var fields = {};
        var missing = [];

        var inputs = dialog.querySelectorAll('[data-field]');
        Array.prototype.forEach.call(inputs, function (input) {
            var name = input.getAttribute('data-field');
            if (input.type === 'checkbox') {
                fields[name] = input.checked;
                return;
            }
            var value = input.value.trim();
            fields[name] = value;
            if (input.getAttribute('data-required') === 'true' && value === '') {
                var label = dialog.querySelector('label[for="' + input.id + '"]');
                missing.push(label ? label.textContent.replace('*', '').trim() : name);
            }
        });

        if (missing.length) {
            errorBox.textContent = 'Please fill in: ' + missing.join(', ');
            errorBox.hidden = false;
            return;
        }

        var buttons = dialog.querySelectorAll('button');
        Array.prototype.forEach.call(buttons, function (b) { b.disabled = true; });

        request('/api/run', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ tool: toolId, fields: fields })
        }).then(function (data) {
            closeDialogs();
            showToast('Started: ' + data.tool + ' (job ' + data.jobId + ')', false);
            refreshStatus();
        }).catch(function (error) {
            errorBox.textContent = error.message;
            errorBox.hidden = false;
        }).then(function () {
            Array.prototype.forEach.call(buttons, function (b) { b.disabled = false; });
        });
    }

    function showJobOutput(jobId) {
        request('/api/joboutput?id=' + encodeURIComponent(jobId)).then(function (data) {
            byId('jobOutputTitle').textContent = 'Job ' + data.id + ' - ' + data.tool + ' (' + data.state + ')';
            byId('jobOutputBody').textContent = data.output;
            closeDialogs();
            byId('jobOutputDialog').hidden = false;
        }).catch(function (error) {
            showToast(error.message, true);
        });
    }

    document.addEventListener('click', function (event) {
        var target = event.target;
        if (!target || typeof target.closest !== 'function') { return; }

        var opener = target.closest('[data-open]');
        if (opener) { openDialog(opener.getAttribute('data-open')); return; }

        var action = target.closest('[data-action]');
        if (action) {
            var kind = action.getAttribute('data-action');
            if (kind === 'cancel') { closeDialogs(); }
            else if (kind === 'submit') { submitTool(action.getAttribute('data-tool')); }
            else if (kind === 'output') { showJobOutput(action.getAttribute('data-job')); }
            else if (kind === 'load') {
                var select = byId(action.getAttribute('data-target'));
                if (select) { loadRemoteSelect(select, action.closest('.dialog-backdrop')); }
            }
            return;
        }

        if (target.classList && target.classList.contains('dialog-backdrop')) { closeDialogs(); }
    });

    document.addEventListener('change', function (event) {
        var target = event.target;
        if (!target || target.tagName !== 'SELECT') { return; }

        var field = target.getAttribute('data-field');
        if (!field || !target.closest) { return; }

        var dialog = target.closest('.dialog-backdrop');
        if (dialog) { refreshDependents(dialog, field); }
    });

    document.addEventListener('keydown', function (event) {
        if (event.key === 'Escape') { closeDialogs(); }
    });

    refreshAll();
    setInterval(refreshAll, REFRESH_MS);
}());
</script>
</body>
</html>
'@

function New-MenuPage {
    $logoPath = Join-Path -Path $ScanningToolsPath -ChildPath 'scanner.png'
    $logoHtml = if (Test-Path -LiteralPath $logoPath -PathType Leaf) {
        '<img src="scanner.png" alt="">'
    } else {
        ''
    }

    $html = $script:PageTemplate
    $html = $html.Replace('__LOGO__',            $logoHtml)
    $html = $html.Replace('__BUTTONS__',         (New-ToolButtonHtml))
    $html = $html.Replace('__DIALOGS__',         (New-ToolDialogHtml))
    $html = $html.Replace('__CSRF__',            $script:CsrfToken)
    $html = $html.Replace('__REFRESH_MS__',      ([string]($RefreshInterval * 1000)))
    $html = $html.Replace('__REFRESH_SECONDS__', ([string]$RefreshInterval))
    $html = $html.Replace('__WINDOW_HOURS__',    ([string]$StatsWindowHours))
    $html = $html.Replace('__VERSION__',         $script:Version)
    $html = $html.Replace('__LOGFILE__',         (ConvertTo-HtmlText $LogFilePath))
    return $html
}
#endregion

#region HTTP ------------------------------------------------------------------

function Send-HttpContent {
    param (
        [Parameter(Mandatory = $true)] $Response,
        [Parameter(Mandatory = $true)] [byte[]]$Bytes,
        [Parameter(Mandatory = $true)] [string]$ContentType,
        [int]$StatusCode = 200
    )

    $Response.StatusCode      = $StatusCode
    $Response.ContentType     = $ContentType
    $Response.ContentLength64 = $Bytes.Length
    $Response.Headers['Cache-Control']         = 'no-store'
    $Response.Headers['X-Content-Type-Options'] = 'nosniff'
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
}

function Send-HttpText {
    param ($Response, [string]$Text, [string]$ContentType = 'text/plain; charset=utf-8', [int]$StatusCode = 200)
    Send-HttpContent -Response $Response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text)) -ContentType $ContentType -StatusCode $StatusCode
}

function Send-HttpJson {
    param ($Response, $Data, [int]$StatusCode = 200)

    # -InputObject rather than the pipeline: piping an empty array sends nothing
    # to ConvertTo-Json (which then returns $null), and the pipeline also unrolls
    # a single element array into a bare object. Both break the client.
    $json = ConvertTo-Json -InputObject $Data -Depth 6 -Compress
    if ($null -eq $json) { $json = 'null' }

    Send-HttpText -Response $Response -Text $json -ContentType 'application/json; charset=utf-8' -StatusCode $StatusCode
}

function Send-HttpError {
    param ($Response, [string]$Message, [int]$StatusCode = 400)
    Send-HttpJson -Response $Response -Data ([ordered]@{ message = $Message }) -StatusCode $StatusCode
}

# The listener is bound to localhost, but a page in the operator's browser could
# still post here from another origin. The token is only readable by same origin
# script, which is what makes a cross site request fail.
function Test-CsrfToken {
    param ($Request)
    return ($Request.Headers['X-Csrf-Token'] -eq $script:CsrfToken)
}

function Invoke-GetRequest {
    param ($Request, $Response, [string]$Path)

    switch ($Path) {
        '/' {
            Send-HttpText -Response $Response -Text $script:MenuHtml -ContentType 'text/html; charset=utf-8'
            return
        }

        '/api/status' {
            if (-not (Test-CsrfToken -Request $Request)) {
                Send-HttpError -Response $Response -Message 'Invalid or missing token.' -StatusCode 403
                return
            }
            $data = [ordered]@{
                scanCount    = Get-ScanStartedCount
                warningCount = Get-ScanWarningCount
                warnings     = Get-RecentWarning -Count 10
                jobReport    = Get-ScanJobReport
                now          = (Get-Date).ToString($script:LogTimestampFormat)
            }
            Send-HttpJson -Response $Response -Data $data
            return
        }

        '/api/suspicious' {
            if (-not (Test-CsrfToken -Request $Request)) {
                Send-HttpError -Response $Response -Message 'Invalid or missing token.' -StatusCode 403
                return
            }
            Send-HttpJson -Response $Response -Data (Get-SuspiciousBackup)
            return
        }

        '/api/options' {
            if (-not (Test-CsrfToken -Request $Request)) {
                Send-HttpError -Response $Response -Message 'Invalid or missing token.' -StatusCode 403
                return
            }

            $source = [string]$Request.QueryString['source']
            try {
                switch ($source) {
                    'yararules' {
                        Send-HttpJson -Response $Response -Data @(Get-YaraRuleChoice)
                        return
                    }
                    'jobs' {
                        Send-HttpJson -Response $Response -Data @(Get-JobChoice)
                        return
                    }
                    'objects' {
                        $job = [string]$Request.QueryString['JobName']
                        if ([string]::IsNullOrWhiteSpace($job)) {
                            Send-HttpError -Response $Response -Message 'Pick a backup job first.'
                            return
                        }
                        Send-HttpJson -Response $Response -Data @(Get-ObjectChoice -JobName $job)
                        return
                    }
                    'restorepoints' {
                        $job    = [string]$Request.QueryString['JobName']
                        $object = [string]$Request.QueryString['ObjectName']
                        if ([string]::IsNullOrWhiteSpace($job) -or [string]::IsNullOrWhiteSpace($object)) {
                            Send-HttpError -Response $Response -Message 'Fill in the job name and the machine name first.'
                            return
                        }
                        Send-HttpJson -Response $Response -Data @(Get-RestorePointChoice -JobName $job -ObjectName $object)
                        return
                    }
                    'flrrestorepoints' {
                        $job = [string]$Request.QueryString['JobName']
                        $vm  = [string]$Request.QueryString['VM']
                        if ([string]::IsNullOrWhiteSpace($job) -or [string]::IsNullOrWhiteSpace($vm)) {
                            Send-HttpError -Response $Response -Message 'Pick a backup job and a machine first.'
                            return
                        }
                        Send-HttpJson -Response $Response -Data @(Get-FlrRestorePointChoice -JobName $job -VM $vm)
                        return
                    }
                    default {
                        Send-HttpError -Response $Response -Message "Unknown option source '$source'."
                        return
                    }
                }
            } catch {
                Send-HttpError -Response $Response -Message $_.Exception.Message -StatusCode 500
                return
            }
        }

        '/api/joboutput' {
            if (-not (Test-CsrfToken -Request $Request)) {
                Send-HttpError -Response $Response -Message 'Invalid or missing token.' -StatusCode 403
                return
            }
            $id = 0
            if (-not [int]::TryParse([string]$Request.QueryString['id'], [ref]$id)) {
                Send-HttpError -Response $Response -Message 'Missing or invalid job id.'
                return
            }
            $output = Get-ScanJobOutput -Id $id
            if ($null -eq $output) {
                Send-HttpError -Response $Response -Message "Job $id not found." -StatusCode 404
                return
            }
            Send-HttpJson -Response $Response -Data $output
            return
        }

        '/scanner.png' {
            $imagePath = Join-Path -Path $ScanningToolsPath -ChildPath 'scanner.png'
            if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
                Send-HttpError -Response $Response -Message 'Not found.' -StatusCode 404
                return
            }
            try {
                $bytes = [System.IO.File]::ReadAllBytes($imagePath)
            } catch {
                Send-HttpError -Response $Response -Message 'Image could not be read.' -StatusCode 500
                return
            }
            Send-HttpContent -Response $Response -Bytes $bytes -ContentType 'image/png'
            return
        }

        default {
            Send-HttpError -Response $Response -Message 'Not found.' -StatusCode 404
        }
    }
}

function Invoke-PostRequest {
    param ($Request, $Response, [string]$Path)

    if ($Path -ne '/api/run') {
        Send-HttpError -Response $Response -Message 'Not found.' -StatusCode 404
        return
    }

    if (-not (Test-CsrfToken -Request $Request)) {
        Send-HttpError -Response $Response -Message 'Invalid or missing token.' -StatusCode 403
        return
    }

    $reader = $null
    try {
        $reader = New-Object System.IO.StreamReader($Request.InputStream, [System.Text.Encoding]::UTF8)
        $body   = $reader.ReadToEnd()
    } finally {
        if ($reader) { $reader.Dispose() }
    }

    try {
        $payload = $body | ConvertFrom-Json
    } catch {
        Send-HttpError -Response $Response -Message 'Request body is not valid JSON.'
        return
    }

    if ($null -eq $payload -or -not ($payload.PSObject.Properties.Name -contains 'tool')) {
        Send-HttpError -Response $Response -Message 'Request is missing the tool id.'
        return
    }

    $tool = Get-ToolDefinition -Id $payload.tool
    if (-not $tool) {
        Send-HttpError -Response $Response -Message 'Unknown tool.'
        return
    }

    $fields = $null
    if ($payload.PSObject.Properties.Name -contains 'fields') { $fields = $payload.fields }

    $bound = ConvertTo-ScanParameter -Tool $tool -Fields $fields
    if ($bound.Errors.Count -gt 0) {
        Send-HttpError -Response $Response -Message ($bound.Errors -join [Environment]::NewLine)
        return
    }

    try {
        $job = Start-ScanJob -Tool $tool -Parameters $bound.Parameters
    } catch {
        Write-Console "Could not start '$($tool.Name)': $($_.Exception.Message)" -Level Error
        Send-HttpError -Response $Response -Message $_.Exception.Message -StatusCode 500
        return
    }

    Send-HttpJson -Response $Response -Data ([ordered]@{
        jobId = $job.Id
        tool  = $job.Tool
        state = $job.State
    })
}

function Invoke-RequestHandler {
    param ($Context)

    $request  = $Context.Request
    $response = $Context.Response
    $path     = $request.Url.LocalPath.TrimEnd('/')
    if ([string]::IsNullOrEmpty($path)) { $path = '/' }

    switch ($request.HttpMethod) {
        'GET'  { Invoke-GetRequest  -Request $request -Response $response -Path $path }
        'POST' { Invoke-PostRequest -Request $request -Response $response -Path $path }
        default {
            $response.Headers['Allow'] = 'GET, POST'
            Send-HttpError -Response $response -Message 'Method not allowed.' -StatusCode 405
        }
    }
}
#endregion

#region Startup ---------------------------------------------------------------

Clear-Host
Write-Host ''
Write-Host '  Backup Scanning Tools Webmenu' -ForegroundColor Green
Write-Host ('  Version {0}' -f $script:Version) -ForegroundColor Green
Write-Host ''

if (-not (Test-Path -LiteralPath $ScanningToolsPath -PathType Container)) {
    Write-Console "Scanning tools directory not found: $ScanningToolsPath" -Level Warning
    Write-Console 'All tool buttons will be disabled. Use -ScanningToolsPath to point at the right folder.' -Level Warning
}

$missing = @()
foreach ($tool in $script:Tools) {
    $path = Get-ToolScriptPath -Tool $tool
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing += $tool.Script }
}
if ($missing.Count -gt 0) {
    Write-Console ("Missing scripts (buttons disabled): {0}" -f (($missing | Sort-Object -Unique) -join ', ')) -Level Warning
}

if (Connect-VeeamServer) {
    Write-Console "Veeam PowerShell ready (server '$VbrServer')."
} else {
    Write-Console $script:VeeamState.Message -Level Warning
    Write-Console 'Restore point / YARA rule lists and the suspicious backup tile will not work.' -Level Warning
    Write-Console 'Everything else keeps running.' -Level Warning
}

try {
    Resolve-PowerShellHost | Out-Null
} catch {
    Write-Console $_.Exception.Message -Level Error
    return
}

if (-not (Test-Path -LiteralPath $LogFilePath -PathType Leaf)) {
    Write-Console "Log file does not exist yet: $LogFilePath" -Level Warning
}

try {
    if (-not (Test-Path -LiteralPath $JobOutputPath)) {
        New-Item -Path $JobOutputPath -ItemType Directory -Force | Out-Null
    }
} catch {
    Write-Console "Could not create job output directory '$JobOutputPath': $($_.Exception.Message)" -Level Error
    return
}

$script:MenuHtml = New-MenuPage

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")

try {
    $listener.Start()
} catch {
    Write-Console "Could not start the listener on port ${Port}: $($_.Exception.Message)" -Level Error
    Write-Console 'Is another instance already running, or is the port in use?' -Level Error
    return
}

Write-Host ''
Write-Console "Listening on http://localhost:$Port/"
Write-Console "Refresh interval: $RefreshInterval s | statistics window: $StatsWindowHours h"
Write-Console "Log file: $LogFilePath"
Write-Console "Job output: $JobOutputPath"
Write-Console "Scan host: $script:PowerShellHost"
Write-Host ''
Write-Host '  Press Ctrl+C to stop.' -ForegroundColor DarkGray
Write-Host ''

try {
    while ($listener.IsListening) {
        $context = $null

        try {
            $context = $listener.GetContext()
        } catch [System.Net.HttpListenerException] {
            break
        } catch [System.ObjectDisposedException] {
            break
        }

        try {
            Invoke-RequestHandler -Context $context
        } catch {
            # A single bad request must never take the server down.
            Write-Console "Request failed ($($context.Request.Url.LocalPath)): $($_.Exception.Message)" -Level Error
            try {
                Send-HttpError -Response $context.Response -Message 'Internal server error.' -StatusCode 500
            } catch {
                # Response may already be committed - nothing left to do.
            }
        } finally {
            try { $context.Response.Close() } catch { }
        }
    }
} finally {
    Write-Host ''
    Write-Console 'Shutting down...'

    $running = @($script:ScanJobs | Where-Object { $_.State -eq 'Running' })
    if ($running.Count -gt 0) {
        Write-Console "$($running.Count) scan(s) still running - they keep going in the background." -Level Warning
    }

    try { $listener.Stop() }  catch { }
    try { $listener.Close() } catch { }
    Write-Console 'Listener stopped.'
}
#endregion
