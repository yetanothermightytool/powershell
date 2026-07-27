<#
.SYNOPSIS
    Scans a restore point and restores the machine in one step (Veeam secure restore).

.DESCRIPTION
    Wraps Start-VBRRestoreVM (VMware) and Start-VBRHvRestoreVM (Hyper-V). Both cmdlets
    have secure restore built in: -EnableAntivirusScan / -EnableYARAScan run the scan
    while the disks are mounted to the mount server, and -VirusDetectionAction decides
    what happens when something is found. Scan and restore are one call, not two.

    This replaces three tools from the v1 collection:

      vbr-securerestore.ps1 (v1) - mounted the backup to a Linux host through the Data
                                   Integration API and drove ClamAV over SSH. Not needed
                                   any more: Veeam Threat Hunter scans Windows and Linux
                                   machines natively.
      the YARA scan variant      - -YARARule does the same thing here.
      vbr-cleanrestore.ps1       - walked back through restore points looking for a clean
                                   one. Now -FindCleanRestorePoint, which lets
                                   Start-VBRScanBackup do the walking in its own scan mode.

    Runs completely non-interactive so it can be launched from the web menu or a
    scheduled task. -WhatIf shows what would be restored without touching anything.

.PARAMETER JobName
    Name of the backup job holding the machine.

.PARAMETER VM
    Name of the machine inside that backup.

.PARAMETER RestorePointId
    Restore point to scan and restore. Defaults to the most recent one.
    Use -ListRestorePoints to get the available ids.
    Ignored when -FindCleanRestorePoint is given.

.PARAMETER FindCleanRestorePoint
    Scan first, then restore the newest restore point that came out clean.

    Runs Start-VBRScanBackup in the mode given by -CleanScanMode, which stops as soon as
    it finds a clean restore point, then reads the malware status back from the restore
    points and picks the newest one that is explicitly clean.

    A restore point that was never scanned stays Unknown and is NOT treated as clean - an
    unscanned point must not end up looking like a verified one.

.PARAMETER CleanScanMode
    MostRecent      - newest to oldest. Use when the machine is known to be infected now.
    FirstInInterval - optimal order. Use when it is unclear when the attack started.

.PARAMETER AVScan
    Scan with the engine configured under Malware Detection Settings > Signature
    Detection - Veeam Threat Hunter or a third-party antivirus. The engine is not picked
    here.

.PARAMETER YARARule
    YARA rule file name including extension, for example 'ransomware.yar'. Veeam looks it
    up in C:\Program Files\Veeam\Backup and Replication\Backup\YaraRules and accepts only
    .yar and .yara.

    A single rule, unlike vbr-scan-backups.ps1: the restore cmdlets take one rule per run.

.PARAMETER EntireVolumeScan
    Keep scanning after the first hit so the report covers every threat, not just the
    first one.

.PARAMETER OnThreat
    What Veeam does when the scan finds something:
      AbortRecovery  - cancel the restore (default)
      DisableNetwork - restore anyway, with the network adapters disconnected

.PARAMETER ToOriginalLocation
    Restore to the original location. Mutually exclusive with -TargetServer.

.PARAMETER TargetServer
    Host to restore to - an ESXi host for VMware, a Hyper-V host for Hyper-V. Resolved
    through Get-VBRServer.

.PARAMETER ResourcePool
    VMware only. Resource pool for the restored VM.

.PARAMETER Datastore
    VMware only. Datastore for the restored VM.

.PARAMETER Folder
    VMware only. vSphere folder for the restored VM.

.PARAMETER TargetPath
    Hyper-V only. Folder on the target host to restore the VM into.

.PARAMETER RestoredVMName
    Name for the restored machine. Defaults to the original name.

.PARAMETER PowerUp
    Power the machine on after the restore. Off by default.

.PARAMETER ConnectNetwork
    Connect the restored machine to the network.

    Default is disconnected on both platforms. Veeam's own defaults differ (VMware
    connects, Hyper-V does not), and this tool is used on machines suspected of being
    infected, so it errs on the safe side on both.

.PARAMETER QuickRollback
    Incremental restore, only valid together with -ToOriginalLocation.

.PARAMETER Reason
    Text shown in the restore session history in the Veeam console.

.PARAMETER AsJson
    Emit the result as JSON on stdout. Intended for the web menu.

.EXAMPLE
    .\vbr-securerestore.ps1 -JobName 'demo_vm' -VM 'win-client-04' -AVScan -ToOriginalLocation

.EXAMPLE
    .\vbr-securerestore.ps1 -JobName 'demo_vm' -VM 'win-client-04' -AVScan -FindCleanRestorePoint -TargetServer 'esxi01' -Datastore 'ds-restore'

.EXAMPLE
    .\vbr-securerestore.ps1 -JobName 'demo_vm' -VM 'win-client-04' -YARARule 'ransomware.yar' -OnThreat DisableNetwork -ToOriginalLocation

.EXAMPLE
    .\vbr-securerestore.ps1 -JobName 'demo_vm' -VM 'win-client-04' -AVScan -ToOriginalLocation -WhatIf

.EXAMPLE
    .\vbr-securerestore.ps1 -JobName 'demo_vm' -VM 'win-client-04' -ListRestorePoints -AsJson

.OUTPUTS
    Exit code 0 = clean and restored, 2 = threat found, 1 = error.

.NOTES
    Author   : Stephan "Steve" Herzig
    Requires : Veeam Backup & Replication v13, PowerShell 7
    Version  : 2.0

    Platform limits in v13.0.2: entire VM restore over PowerShell exists for VMware and
    Hyper-V only. The cmdlet index holds nothing for Proxmox VE, Nutanix AHV, oVirt/RHV
    or Scale Computing - those restores are UI only, so this script refuses them up front
    with a clear message instead of failing somewhere deeper. Scanning those platforms
    does work: use vbr-scan-backups.ps1.

    Dropped from v1: the tape parameters (-VMTape, -AgentTape, -Repository). They restored
    a backup from tape to a repository first and deleted it again afterwards. The web menu
    never exposed them. If that workflow is still needed it belongs in a separate script
    around Start-VBRTapeRestore rather than inside the secure restore path.
#>
#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Restore', SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $true, ParameterSetName = 'Restore')]
    [Parameter(Mandatory = $true, ParameterSetName = 'ListRestorePoints')]
    [ValidateNotNullOrEmpty()]
    [string]$JobName,

    [Parameter(Mandatory = $true, ParameterSetName = 'Restore')]
    [Parameter(Mandatory = $true, ParameterSetName = 'ListRestorePoints')]
    [ValidateNotNullOrEmpty()]
    [string]$VM,

    # --- what to scan ----------------------------------------------------------
    [Parameter(ParameterSetName = 'Restore')]
    [string]$RestorePointId,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$FindCleanRestorePoint,

    [Parameter(ParameterSetName = 'Restore')]
    [ValidateSet('MostRecent', 'FirstInInterval')]
    [string]$CleanScanMode = 'MostRecent',

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$AVScan,

    [Parameter(ParameterSetName = 'Restore')]
    [string]$YARARule,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$EntireVolumeScan,

    [Parameter(ParameterSetName = 'Restore')]
    [ValidateSet('AbortRecovery', 'DisableNetwork')]
    [string]$OnThreat = 'AbortRecovery',

    # --- where to restore to ---------------------------------------------------
    [Parameter(ParameterSetName = 'Restore')]
    [switch]$ToOriginalLocation,

    [Parameter(ParameterSetName = 'Restore')]
    [string]$TargetServer,

    # VMware only. Names are resolved through the Find-VBRVi* cmdlets.
    [Parameter(ParameterSetName = 'Restore')]
    [string]$ResourcePool,

    [Parameter(ParameterSetName = 'Restore')]
    [string]$Datastore,

    [Parameter(ParameterSetName = 'Restore')]
    [string]$Folder,

    # Hyper-V only.
    [Parameter(ParameterSetName = 'Restore')]
    [string]$TargetPath,

    [Parameter(ParameterSetName = 'Restore')]
    [string]$RestoredVMName,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$PowerUp,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$ConnectNetwork,

    # Only valid together with -ToOriginalLocation.
    [Parameter(ParameterSetName = 'Restore')]
    [switch]$QuickRollback,

    [Parameter(ParameterSetName = 'Restore')]
    [string]$Reason,

    # --- how the result is evaluated -------------------------------------------
    # By default only events from this run are reported. A machine keeps its whole
    # event history, which makes the output unusable otherwise.
    [Parameter(ParameterSetName = 'Restore')]
    [switch]$AllEvents,

    [Parameter(ParameterSetName = 'Restore')]
    [ValidateRange(1, 500)]
    [int]$EventLimit = 20,

    # The malware detection API reports that something was found, but not always
    # what. The session logs carry the actual threat text including file names.
    [Parameter(ParameterSetName = 'Restore')]
    [switch]$SkipLogAnalysis,

    [Parameter(ParameterSetName = 'Restore')]
    [string]$RestoreSessionLogPath = 'C:\ProgramData\Veeam\Backup',

    [Parameter(ParameterSetName = 'Restore')]
    [string]$MalwareLogPath = 'C:\ProgramData\Veeam\Backup\Malware_Detection_Logs',

    [Parameter(Mandatory = $true, ParameterSetName = 'ListRestorePoints')]
    [switch]$ListRestorePoints,

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
$script:LogPrefix   = 'Secure Restore'

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
# is there - a missing one must not abort a restore.
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
    shifts values by the UTC offset. The DateTime carries its own Kind, so no hard
    coded offset is needed and daylight saving stays correct.
#>
function ConvertTo-LocalDateTime {
    param ($Value)

    if ($Value -isnot [datetime]) { return [datetime]::MinValue }
    if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value.ToLocalTime() }
    return $Value
}

# COib uses CreationTime, VBRObjectRestorePoint uses CreationDate. Both shapes
# turn up in this script, so try both names.
function Get-RestorePointDate {
    param ($RestorePoint)

    foreach ($name in @('CreationTime', 'CreationDate')) {
        $value = Get-SafeProperty -InputObject $RestorePoint -Name $name
        if ($value -is [datetime]) { return ConvertTo-LocalDateTime $value }
    }
    return [datetime]::MinValue
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
#endregion

#region Veeam lookups ----------------------------------------------------------

function Get-TargetBackup {
    $backups = @(Get-VBRBackup -WarningAction SilentlyContinue |
        Where-Object { $_.JobName -eq $JobName } |
        Sort-Object CreationTime -Descending)

    if ($backups.Count -eq 0) { throw "No backup found for job '$JobName'." }
    return $backups
}

function Get-TargetBackupObject {
    param ([Parameter(Mandatory = $true)] $Backup)

    $objects = @(Get-VBRBackupObject -Backup $Backup |
        Where-Object { $_.Name -eq $VM })

    if ($objects.Count -eq 0) {
        $available = @(Get-VBRBackupObject -Backup $Backup | ForEach-Object { $_.Name }) -join ', '
        throw "Machine '$VM' not found in job '$JobName'. Available: $available"
    }
    return $objects[0]
}

<#
    Works out which restore cmdlet applies.

    In v13.0.2 entire VM restore over PowerShell exists for VMware
    (Start-VBRRestoreVM) and Hyper-V (Start-VBRHvRestoreVM) only. The full cmdlet
    index contains nothing for Proxmox VE, Nutanix AHV, oVirt/RHV or Scale
    Computing - those restores are available in the UI but not in PowerShell.

    Failing here with a readable message beats failing later inside a cmdlet that
    was never meant for the platform.
#>
function Get-BackupPlatform {
    param ($Backup, $BackupObject)

    $candidates = @(
        Get-SafeProperty -InputObject $BackupObject -Name 'Platform'
        Get-SafeProperty -InputObject $Backup -Name 'BackupPlatform'
        Get-SafeProperty -InputObject $Backup -Name 'Platform'
        Get-SafeProperty -InputObject $Backup -Name 'TypeToString'
    ) | ForEach-Object { [string]$_ } | Where-Object { $_ }

    foreach ($candidate in $candidates) {
        if ($candidate -match 'hyper\s*-?\s*v') { return 'HyperV' }
        if ($candidate -match 'vmware|vsphere') { return 'VMware' }
    }

    $seen = ($candidates | Select-Object -Unique) -join ', '
    if (-not $seen) { $seen = 'unknown' }
    return "Unsupported:$seen"
}

# A COib restore point does not always expose its backup the same way.
function Get-RestorePointBackupId {
    param ($RestorePoint)

    $value = Get-SafeProperty -InputObject $RestorePoint -Name 'BackupId'
    if ($value) { return ([string]$value).ToLowerInvariant() }

    try {
        $backup = $RestorePoint.GetBackup()
        if ($backup) { return ([string]$backup.Id).ToLowerInvariant() }
    } catch { }

    return ''
}

<#
    Returns the COib restore points of the machine, newest first.

    Start-VBRRestoreVM and Start-VBRHvRestoreVM take a COib, which only
    Get-VBRRestorePoint produces - not Get-VBRObjectRestorePoint, which
    vbr-scan-backups.ps1 uses for Start-VBRScanBackup. The two cmdlets genuinely
    want different types, and the same restore point carries a different id in each.

    Two parameter sets, two behaviours:
      -Backup  fails outright on some backup types. Proxmox backups report
               "encrypted or created by an enterprise application plug-in", which
               is misleading - they are not encrypted.
      -Name    works there, but searches every backup on the server. The same
               machine name can live in several jobs, so the result has to be
               narrowed back down to the requested one before restoring anything.

    Veeam Agent jobs additionally only return restore points when the name contains
    a wildcard, hence the second filter.

    Same logic as vbr-flr-hashscanner.ps1 - both work on COib restore points.
#>
function Get-CoibRestorePoint {
    param ([Parameter(Mandatory = $true)] $Backups)

    $backupIds = @($Backups | ForEach-Object { ([string]$_.Id).ToLowerInvariant() })
    $points    = @()

    try {
        $points = @(Get-VBRRestorePoint -Backup $Backups[0] -ErrorAction Stop |
            Where-Object { $_.Name -eq $VM })
    } catch {
        Write-Verbose "Get-VBRRestorePoint -Backup failed, falling back to -Name: $($_.Exception.Message)"
    }

    if ($points.Count -eq 0) {
        $byName = @()
        foreach ($filter in @($VM, "$VM*")) {
            try {
                $byName = @(Get-VBRRestorePoint -Name $filter -ErrorAction Stop |
                    Where-Object { $_.Name -like $filter })
            } catch {
                continue
            }
            if ($byName.Count -gt 0) { break }
        }

        $scoped = @($byName | Where-Object { $backupIds -contains (Get-RestorePointBackupId $_) })

        if ($scoped.Count -gt 0) {
            $points = $scoped
        } elseif ($byName.Count -gt 0) {
            # -Name searches every backup on the server, and the catalogue can still
            # hold entries whose restore points are long gone. Warn and continue -
            # the newest point is normally the right one - but say it out loud,
            # because this run ends in a restore.
            Write-Status ("Warning: found {0} restore point(s) for '{1}' that could not be tied to job '{2}'. Using them anyway - verify the restore point before you trust the result." -f
                $byName.Count, $VM, $JobName) 'Yellow'
            $points = $byName
        }
    }

    return @($points | Sort-Object -Property @{ Expression = { Get-RestorePointDate $_ } } -Descending)
}

<#
    Returns the VBRObjectRestorePoint list, newest first.

    Needed for the one thing COib does not give reliably: the malware Status of a
    restore point. Only used by the clean restore point search - the restore itself
    always runs on a COib.
#>
function Get-ObjectRestorePoint {
    param (
        [Parameter(Mandatory = $true)] $Backup,
        [Parameter(Mandatory = $true)] $BackupObject
    )

    # VBRBackupObject exposes both Id and ObjectId and the documented descriptions
    # overlap, so try both before falling back to a client side filter.
    $candidateIds = @(
        Get-SafeProperty -InputObject $BackupObject -Name 'ObjectId'
        Get-SafeProperty -InputObject $BackupObject -Name 'Id'
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($candidate in $candidateIds) {
        $points = @(Get-VBRObjectRestorePoint -ObjectId $candidate -ErrorAction SilentlyContinue)
        if ($points.Count -gt 0) {
            return @($points | Sort-Object -Property @{ Expression = { Get-RestorePointDate $_ } } -Descending)
        }
    }

    $wanted = @($candidateIds | ForEach-Object { [string]$_ })
    $points = @(Get-VBRObjectRestorePoint -Backup $Backup |
        Where-Object { [string]$_.ObjectId -in $wanted })

    return @($points | Sort-Object -Property @{ Expression = { Get-RestorePointDate $_ } } -Descending)
}
#endregion

#region Clean restore point search ---------------------------------------------

<#
    Decides whether a restore point's malware status counts as clean.

    Status is a VBRActivitySeverity. Deliberately conservative: only an explicitly
    clean value is accepted. A restore point that was never scanned reports Unknown,
    and after a MostRecent scan every point older than the one that came out clean
    is still Unknown - treating those as clean would restore an unverified restore
    point while reporting it as verified.

    Returns 'Clean', 'Infected' or 'Unknown'.
#>
function Get-CleanState {
    param ($RestorePoint)

    $status = [string](Get-SafeProperty -InputObject $RestorePoint -Name 'Status' -Default '')
    if (-not $status) { return 'Unknown' }

    if ($status -match 'infect|suspicious|malware|threat|error|fail') { return 'Infected' }
    if ($status -match 'clean|healthy|^ok$|^good$|^success')          { return 'Clean' }
    return 'Unknown'
}

<#
    Maps a VBRObjectRestorePoint back to its COib.

    The same restore point carries a different id in each type, so there is nothing
    to join on but the creation time. Both sides are normalised to local time first
    (VBRObjectRestorePoint hands out UTC for some backup types, COib does not), then
    matched within a couple of seconds.
#>
function Resolve-CoibByDate {
    param (
        [Parameter(Mandatory = $true)] $CoibPoints,
        [Parameter(Mandatory = $true)] [datetime]$Created
    )

    if ($Created -eq [datetime]::MinValue) { return $null }

    $hits = @($CoibPoints | Where-Object {
        $when = Get-RestorePointDate $_
        $when -ne [datetime]::MinValue -and [math]::Abs(($when - $Created).TotalSeconds) -le 2
    })

    if ($hits.Count -eq 0) { return $null }
    if ($hits.Count -gt 1) {
        Write-Status ("Warning: {0} restore points share the timestamp {1}. Using the first one." -f
            $hits.Count, $Created.ToString('dd-MM-yyyy HH:mm:ss')) 'Yellow'
    }
    return $hits[0]
}

<#
    Runs a scan and returns the newest restore point that came out clean.

    This is what vbr-cleanrestore.ps1 used to do by hand. Start-VBRScanBackup does
    the walking itself:
      MostRecent      - newest to oldest, stops at the first clean restore point
      FirstInInterval - optimal order, stops at the first clean restore point

    The cmdlet does not report which point it settled on, so the malware status is
    read back from the restore points afterwards.

    A session result of Failed is normal here: it means the scan found something in
    a newer restore point, which is exactly the situation this search is for.
#>
function Find-CleanRestorePoint {
    param (
        [Parameter(Mandatory = $true)] $Backup,
        [Parameter(Mandatory = $true)] $BackupObject,
        [Parameter(Mandatory = $true)] $CoibPoints
    )

    $scanArguments = @{
        Object   = $BackupObject
        ScanMode = $CleanScanMode
    }
    if ($AVScan)   { $scanArguments['EnableAntivirusScan'] = $true }
    if ($YARARule) {
        $scanArguments['EnableYARAScan'] = $true
        $scanArguments['YARARule']       = $YARARule.Trim()
    }
    if ($EntireVolumeScan) { $scanArguments['EnableEntireImageScan'] = $true }

    Write-Status "Searching for a clean restore point ($CleanScanMode) ..." 'White'
    Write-ScanLog -Message "Clean restore point search started - VM: $VM - Job: $JobName - Mode: $CleanScanMode"

    $session       = Start-VBRScanBackup @scanArguments
    $sessionResult = [string](Get-SafeProperty -InputObject $session -Name 'Result' -Default 'Unknown')
    Write-Status "Scan session result: $sessionResult"
    Write-ScanLog -Message "Clean restore point search ended - Result: $sessionResult"

    $objectPoints = @(Get-ObjectRestorePoint -Backup $Backup -BackupObject $BackupObject)
    if ($objectPoints.Count -eq 0) {
        throw 'The scan finished but no restore points could be read back, so no clean one can be picked.'
    }

    $inspected = @($objectPoints | ForEach-Object {
        [pscustomobject]@{
            created = Get-RestorePointDate $_
            state   = Get-CleanState $_
            status  = [string](Get-SafeProperty -InputObject $_ -Name 'Status' -Default '')
        }
    })

    foreach ($candidate in $inspected) {
        if ($candidate.state -ne 'Clean') { continue }

        $coib = Resolve-CoibByDate -CoibPoints $CoibPoints -Created $candidate.created
        if ($coib) {
            Write-Status ("Clean restore point: {0} (status {1})" -f
                $candidate.created.ToString('dd-MM-yyyy HH:mm:ss'), $candidate.status) 'Green'
            return $coib
        }

        # Clean, but with no COib counterpart it cannot be restored. Keep looking
        # rather than silently restoring a different one.
        Write-Status ("Clean restore point {0} has no counterpart for the restore cmdlet - skipping it." -f
            $candidate.created.ToString('dd-MM-yyyy HH:mm:ss')) 'Yellow'
    }

    $summary = ($inspected | ForEach-Object {
        '{0} = {1}' -f $_.created.ToString('dd-MM-yyyy HH:mm:ss'), $(if ($_.status) { $_.status } else { 'no status' })
    }) -join '; '

    throw "No clean restore point found for '$VM'. Restore point status after the scan: $summary"
}
#endregion

#region Restore ----------------------------------------------------------------

<#
    Builds and runs the platform specific restore cmdlet.

    Secure restore is not a separate step - the scan parameters go straight into the
    restore cmdlet and Veeam scans the disks on the mount server before anything is
    written to the target.
#>
function Invoke-Restore {
    param (
        [Parameter(Mandatory = $true)] $RestorePoint,
        [Parameter(Mandatory = $true)] [string]$Platform
    )

    $arguments = @{ RestorePoint = $RestorePoint }

    # --- secure restore --------------------------------------------------------
    if ($AVScan) { $arguments['EnableAntivirusScan'] = $true }
    if ($YARARule) {
        $arguments['EnableYARAScan'] = $true
        # Called YARAScanRule here; Start-VBRScanBackup calls the same thing YARARule.
        $arguments['YARAScanRule']   = $YARARule.Trim()
    }
    if ($EntireVolumeScan) { $arguments['EnableEntireVolumeScan'] = $true }
    $arguments['VirusDetectionAction'] = $OnThreat

    # --- placement -------------------------------------------------------------
    if ($ToOriginalLocation) {
        # Hyper-V has no ToOriginalLocation switch - leaving out -Server is the
        # original location there.
        if ($Platform -eq 'VMware') { $arguments['ToOriginalLocation'] = $true }
        if ($QuickRollback)         { $arguments['QuickRollback'] = $true }
    } else {
        $targetHost = Get-VBRServer -Name $TargetServer
        if (-not $targetHost) { throw "Target server '$TargetServer' not found. Check Get-VBRServer." }
        $arguments['Server'] = $targetHost

        # The Find-VBRVi* cmdlets take -Name as a String[] and return every match,
        # so pin the result down to one object before it goes into the restore.
        if ($Platform -eq 'VMware') {
            if ($ResourcePool) {
                $pool = @(Find-VBRViResourcePool -Server $targetHost -Name $ResourcePool) | Select-Object -First 1
                if (-not $pool) { throw "Resource pool '$ResourcePool' not found on '$TargetServer'." }
                $arguments['ResourcePool'] = $pool
            }
            if ($Datastore) {
                $store = @(Find-VBRViDatastore -Server $targetHost -Name $Datastore) | Select-Object -First 1
                if (-not $store) { throw "Datastore '$Datastore' not found on '$TargetServer'." }
                $arguments['Datastore'] = $store
            }
            if ($Folder) {
                $viFolder = @(Find-VBRViFolder -Server $targetHost -Name $Folder) | Select-Object -First 1
                if (-not $viFolder) { throw "Folder '$Folder' not found on '$TargetServer'." }
                $arguments['Folder'] = $viFolder
            }
        } elseif ($TargetPath) {
            $arguments['Path'] = $TargetPath
        }
    }

    if ($RestoredVMName) { $arguments['VMName'] = $RestoredVMName }
    if ($PowerUp)        { $arguments['PowerUp'] = $true }

    # Set explicitly on both platforms: VMware defaults to connected, Hyper-V to
    # disconnected. A machine restored because it might be infected should not come
    # up on the network by accident.
    $arguments['NICsEnabled'] = [bool]$ConnectNetwork

    $arguments['Reason'] = if ($Reason) { $Reason } else { "Secure restore of '$VM' (vbr-securerestore.ps1)" }

    $cmdlet = if ($Platform -eq 'VMware') { 'Start-VBRRestoreVM' } else { 'Start-VBRHvRestoreVM' }

    Write-Status "Starting $cmdlet for '$VM' ..." 'White'
    & $cmdlet @arguments | Out-Null
}

<#
    Reads the restore session back.

    Both restore cmdlets document "Output Object: None", so the outcome has to be
    queried afterwards. Get-VBRRestoreSession -Name takes VM names; the newest
    session that started inside this run is ours.
#>
function Get-RestoreOutcome {
    param ([Parameter(Mandatory = $true)] [datetime]$Since)

    $unknown = [pscustomobject]@{ result = 'Unknown'; state = 'Unknown'; name = ''; id = '' }

    try {
        $sessions = @(Get-VBRRestoreSession -Name $VM -ErrorAction Stop)
    } catch {
        Write-Verbose "Could not read restore sessions: $($_.Exception.Message)"
        return $unknown
    }

    $ours = @($sessions | ForEach-Object {
        $started = [datetime]::MinValue
        foreach ($name in @('CreationTime', 'CreationTimeUTC', 'StartTime')) {
            $value = Get-SafeProperty -InputObject $_ -Name $name
            if ($value -is [datetime]) { $started = ConvertTo-LocalDateTime $value; break }
        }
        [pscustomobject]@{ started = $started; session = $_ }
    } | Where-Object { $_.started -ge $Since } | Sort-Object started -Descending)

    if ($ours.Count -eq 0) { return $unknown }

    $session = $ours[0].session
    return [pscustomobject]@{
        result = [string](Get-SafeProperty -InputObject $session -Name 'Result' -Default 'Unknown')
        state  = [string](Get-SafeProperty -InputObject $session -Name 'State'  -Default 'Unknown')
        name   = [string](Get-SafeProperty -InputObject $session -Name 'Name')
        id     = [string](Get-SafeProperty -InputObject $session -Name 'Id')
    }
}
#endregion

#region Result analysis --------------------------------------------------------

<#
    Pulls the actual findings out of the Veeam log files.

    The session result and the malware detection events say that something was
    found; the log files say what, including file names. Two sources:

      * Restore session logs - "Threat found. Antivirus output: <detail>"
      * Malware detection    - indicators_of_compromise_* and suspicious_files_*

    Files are pre-filtered by LastWriteTime so old sessions are never opened, and
    the session tree is only walked two levels deep - C:\ProgramData\Veeam\Backup
    also holds every job log.
#>
function Get-ThreatLogFinding {
    param ([Parameter(Mandatory = $true)] [datetime]$Since)

    $findings = [System.Collections.Generic.List[object]]::new()
    if ($SkipLogAnalysis) { return $findings }

    $threatPattern = '\[(?<ts>\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2})\.\d+\]\s+<\d+>\s+Warning\s+\(\d+\)\s+Threat found\.\s*Antivirus output:\s*(?<msg>.*)'
    $warnPattern   = '\[(?<ts>\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2})\.\d+\]\s+<\d+>\s+Warning\s+\(\d+\)\s+(?<msg>.*)'

    $sources = @(
        [ordered]@{ Path = $RestoreSessionLogPath; Depth = 2; Pattern = $threatPattern; Label = 'Restore session' }
        [ordered]@{ Path = $MalwareLogPath;        Depth = 0; Pattern = $warnPattern;   Label = '' }
    )

    foreach ($source in $sources) {
        if ([string]::IsNullOrWhiteSpace($source.Path)) { continue }
        if (-not (Test-Path -LiteralPath $source.Path)) {
            Write-Verbose "Log directory not found, skipping: $($source.Path)"
            continue
        }

        try {
            if ($source.Depth -gt 0) {
                $files = @(Get-ChildItem -LiteralPath $source.Path -Filter '*.log' -Recurse -Depth $source.Depth -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -ge $Since })
            } else {
                $files = @(Get-ChildItem -LiteralPath $source.Path -Filter '*.log' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -ge $Since })
            }
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

<#
    Snapshot of the malware event ids before the restore.

    Deciding afterwards which events are new by comparing timestamps depends on
    DetectionTime and the local clock agreeing about their time zone, and they
    demonstrably do not. Diffing ids is exact and has no notion of time at all.
#>
function Get-MalwareEventSnapshot {
    $known = New-Object 'System.Collections.Generic.HashSet[string]'
    try {
        foreach ($existing in @(Get-VBRMalwareDetectionEvent -ObjectName $VM -ErrorAction Stop)) {
            [void]$known.Add([string](Get-SafeProperty -InputObject $existing -Name 'Id'))
        }
        return @{ Ids = $known; Valid = $true }
    } catch {
        Write-Verbose "Could not snapshot malware events: $($_.Exception.Message)"
        return @{ Ids = $known; Valid = $false }
    }
}

function Get-NewMalwareEvent {
    param (
        [Parameter(Mandatory = $true)] $Snapshot,
        [Parameter(Mandatory = $true)] [datetime]$Since
    )

    $result = [pscustomobject]@{ events = @(); total = 0; scope = 'from this run' }

    try {
        $raw = @(Get-VBRMalwareDetectionEvent -ObjectName $VM -ErrorAction Stop)
    } catch {
        Write-Verbose "Could not read malware detection events: $($_.Exception.Message)"
        return $result
    }

    $result.total = $raw.Count

    if ($AllEvents) {
        $result.scope = 'full history'
    } elseif ($Snapshot.Valid) {
        # Exact: anything whose id was not there before counts as new.
        $raw = @($raw | Where-Object {
            -not $Snapshot.Ids.Contains([string](Get-SafeProperty -InputObject $_ -Name 'Id'))
        })
    } else {
        # Only reached when the snapshot failed. Accept an empty result: falling back
        # to the history would make a clean restore print a wall of findings.
        $result.scope = 'from this run (by time)'
        $raw = @($raw | Where-Object {
            $when = Get-EventDetectionTime $_
            $when -ne [datetime]::MinValue -and $when -ge $Since
        })
    }

    $result.events = @($raw |
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

    return $result
}
#endregion

#region Modes ------------------------------------------------------------------

<#
    Restore point list for the web menu drop-down.

    Deliberately produced here rather than in the web menu: these are COib ids, and
    the /api/options 'restorepoints' source returns VBRObjectRestorePoint ids. Same
    restore point, different id - a list built there would simply not be found here.
#>
function Invoke-ListRestorePoints {
    $backups = Get-TargetBackup
    $points  = Get-CoibRestorePoint -Backups $backups

    $result = @($points | ForEach-Object {
        [ordered]@{
            id           = [string](Get-SafeProperty -InputObject $_ -Name 'Id')
            creationTime = (Get-RestorePointDate $_).ToString('dd-MM-yyyy HH:mm:ss')
            type         = [string](Get-SafeProperty -InputObject $_ -Name 'Type' -Default '')
        }
    })

    if ($AsJson) {
        # -AsArray keeps a single restore point from collapsing into an object.
        $result | ConvertTo-Json -Depth 4 -AsArray
    } else {
        if ($result.Count -eq 0) {
            Write-Host "No restore points found for '$VM' in job '$JobName'." -ForegroundColor Yellow
        } else {
            $result | ForEach-Object { [pscustomobject]$_ } | Format-Table -AutoSize
        }
    }
}

function Invoke-SecureRestore {
    # --- argument sanity -------------------------------------------------------
    if (-not $AVScan -and [string]::IsNullOrWhiteSpace($YARARule)) {
        throw 'Nothing to scan: specify -AVScan, -YARARule, or both. Without a scan this would be a plain restore, which is not what this tool is for.'
    }
    if ($ToOriginalLocation -and $TargetServer) {
        throw 'Use either -ToOriginalLocation or -TargetServer, not both.'
    }
    if (-not $ToOriginalLocation -and [string]::IsNullOrWhiteSpace($TargetServer)) {
        throw 'Specify where to restore to: -ToOriginalLocation or -TargetServer.'
    }
    if ($QuickRollback -and -not $ToOriginalLocation) {
        throw '-QuickRollback only applies together with -ToOriginalLocation.'
    }

    $backups      = Get-TargetBackup
    $backupObject = Get-TargetBackupObject -Backup $backups[0]
    $platform     = Get-BackupPlatform -Backup $backups[0] -BackupObject $backupObject

    if ($platform -like 'Unsupported:*') {
        $seen = $platform -replace '^Unsupported:', ''
        throw ("Entire VM restore over PowerShell is available for VMware and Hyper-V only in v13.0.2 - this backup reports '$seen'. " +
               'Proxmox VE, Nutanix AHV, oVirt/RHV and Scale Computing have no restore cmdlet; restore those from the Veeam console. ' +
               'Scanning them does work - use vbr-scan-backups.ps1.')
    }
    Write-Status "Platform: $platform"

    if ($platform -eq 'HyperV' -and ($ResourcePool -or $Datastore -or $Folder)) {
        Write-Status 'Note: -ResourcePool, -Datastore and -Folder are VMware only and are ignored here.' 'Yellow'
    }
    if ($platform -eq 'VMware' -and $TargetPath) {
        Write-Status 'Note: -TargetPath is Hyper-V only and is ignored here.' 'Yellow'
    }

    $coibPoints = @(Get-CoibRestorePoint -Backups $backups)
    if ($coibPoints.Count -eq 0) {
        throw "No restore points found for '$VM' in job '$JobName'."
    }

    # --- pick the restore point ------------------------------------------------
    # The clean restore point search starts a real scan session, which -WhatIf is
    # supposed to prevent. ShouldProcess is only reached further down, so the
    # search has to be skipped here explicitly rather than left to run.
    if ($FindCleanRestorePoint -and $WhatIfPreference) {
        Write-Status 'Note: -WhatIf skips the clean restore point search, because that would start a real scan session. Showing the most recent restore point instead.' 'Yellow'
        $restorePoint = $coibPoints[0]
    } elseif ($FindCleanRestorePoint) {
        if ($RestorePointId) {
            Write-Status 'Note: -FindCleanRestorePoint overrides -RestorePointId.' 'Yellow'
        }
        $restorePoint = Find-CleanRestorePoint -Backup $backups[0] -BackupObject $backupObject -CoibPoints $coibPoints
    } elseif ($RestorePointId) {
        $restorePoint = @($coibPoints | Where-Object { [string]$_.Id -eq $RestorePointId }) | Select-Object -First 1
        if (-not $restorePoint) {
            throw "Restore point '$RestorePointId' not found for '$VM'. Use -ListRestorePoints to get the current ids."
        }
    } else {
        $restorePoint = $coibPoints[0]
    }

    $pointDate = Get-RestorePointDate $restorePoint
    $pointText = $pointDate.ToString('dd-MM-yyyy HH:mm:ss')
    $target    = if ($ToOriginalLocation) { 'the original location' } else { "'$TargetServer'" }

    Write-Status "Restore point: $pointText"

    $engines = @()
    if ($AVScan)   { $engines += 'signature' }
    if ($YARARule) { $engines += "YARA ($YARARule)" }

    if (-not $PSCmdlet.ShouldProcess("$VM ($pointText)", "Secure restore to $target")) {
        return [ordered]@{
            status       = 'Skipped'
            job          = $JobName
            vm           = $VM
            platform     = $platform
            restorePoint = $pointText
            target       = $target
            onThreat     = $OnThreat
            sessions     = @()
            events       = @()
            eventsTotal  = 0
            eventsScope  = ''
            findings     = @()
            message      = "Nothing was restored (-WhatIf). Would have run a $($engines -join ' + ') scan and restored to $target."
        }
    }

    # Clock skew and event write delay: look slightly before the actual start so
    # events belonging to this run are not filtered out.
    $runStart = (Get-Date).AddMinutes(-2)
    $snapshot = Get-MalwareEventSnapshot

    Write-ScanLog -Message ("Secure restore started - VM: {0} - Job: {1} - Restore point: {2} - Engines: {3} - Target: {4}" -f
        $VM, $JobName, $pointText, ($engines -join ' + '), $target)

    Invoke-Restore -RestorePoint $restorePoint -Platform $platform

    # --- evaluate --------------------------------------------------------------
    $outcome  = Get-RestoreOutcome -Since $runStart
    $events   = Get-NewMalwareEvent -Snapshot $snapshot -Since $runStart
    $findings = @(Get-ThreatLogFinding -Since $runStart)

    # -AllEvents shows the whole history, so the event count says nothing about
    # this run and must not be read as evidence.
    $threatEvidence = ($events.events.Count -gt 0 -and -not $AllEvents) -or $findings.Count -gt 0

    if ($outcome.result -match 'Success') {
        if ($threatEvidence) {
            # Should not normally happen, but a silent finding is worse than a noisy one.
            $status  = 'Threat'
            $summary = 'The restore session reported success, but malware events or log entries were created during this run. Check the details below before you trust the restored machine.'
        } else {
            $status  = 'Clean'
            $summary = ''
        }
    } elseif ($threatEvidence) {
        $status = 'Threat'
        $summary = if ($OnThreat -eq 'AbortRecovery') {
            'The scan found something and the restore was cancelled (-OnThreat AbortRecovery). Nothing was written to the target.'
        } else {
            'The scan found something. The machine was restored with its network adapters disconnected (-OnThreat DisableNetwork). Do not connect it before it has been cleaned.'
        }
    } else {
        # Not successful and no sign of a finding: a genuine failure, not a detection.
        $status  = 'Error'
        $summary = "The restore session ended with '$($outcome.result)' and no malware evidence was found. That points at a restore failure rather than a detection - check the session in the Veeam console."
    }

    $level = switch ($status) { 'Clean' { 'Info' } 'Error' { 'Error' } default { 'Warning' } }
    Write-ScanLog -Level $level -Message ("Secure restore ended - VM: {0} - Status: {1} - Session result: {2}" -f
        $VM, $status, $outcome.result)

    return [ordered]@{
        status       = $status
        job          = $JobName
        vm           = $VM
        platform     = $platform
        restorePoint = $pointText
        target       = $target
        onThreat     = $OnThreat
        sessions     = @([pscustomobject]@{
            engine        = ($engines -join ' + ')
            sessionName   = $outcome.name
            sessionResult = $outcome.result
            sessionState  = $outcome.state
        })
        events       = @($events.events)
        eventsTotal  = $events.total
        eventsScope  = $events.scope
        findings     = $findings
        message      = $summary
    }
}
#endregion

#region Output -----------------------------------------------------------------

function Write-Result {
    param ([Parameter(Mandatory = $true)] $Result)

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 6
        return
    }

    switch ($Result.status) {
        'Clean'   { Write-Host "`nResult: clean - restored." -ForegroundColor Green }
        'Threat'  { Write-Host "`nResult: THREAT FOUND." -ForegroundColor Red }
        'Skipped' { Write-Host "`nResult: nothing done." -ForegroundColor Yellow }
        default   { Write-Host "`nResult: $($Result.status)." -ForegroundColor Yellow }
    }

    Write-Host ''
    Write-Host ("  Machine      : {0} ({1})" -f $Result.vm, $Result.platform)
    Write-Host ("  Restore point: {0}" -f $Result.restorePoint)
    Write-Host ("  Target       : {0}" -f $Result.target)
    Write-Host ("  On threat    : {0}" -f $Result.onThreat)

    if ($Result.message) {
        Write-Host ''
        Write-Host $Result.message -ForegroundColor Yellow
    }

    $sessions = @($Result.sessions)
    if ($sessions.Count -gt 0) {
        Write-Host ''
        $sessions | Format-Table -AutoSize -Property engine, sessionResult, sessionState
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
        # No table at all rather than the history: a clean restore must not look
        # like a list of infections.
        Write-Host ''
        Write-Host ("No new malware events from this run ({0} in the machine's history - use -AllEvents to see them)." -f
            $Result.eventsTotal) -ForegroundColor DarkGray
    }
}
#endregion

#region Main -------------------------------------------------------------------

$exitCode = $script:ExitError

try {
    if (-not $AsJson) {
        # Both fail when there is no real console, e.g. launched from the web menu.
        try { $host.UI.RawUI.WindowTitle = 'VBR Secure Restore' } catch { }
        try { Clear-Host } catch { }
    }

    Connect-Veeam

    switch ($PSCmdlet.ParameterSetName) {
        'ListRestorePoints' {
            Invoke-ListRestorePoints
            $exitCode = $script:ExitClean
        }
        default {
            $result = Invoke-SecureRestore
            Write-Result -Result $result

            $exitCode = switch ($result.status) {
                'Clean'   { $script:ExitClean }
                'Skipped' { $script:ExitClean }
                'Error'   { $script:ExitError }
                default   { $script:ExitThreat }
            }
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
