<#
.SYNOPSIS
    Extract structured facts from vzdump backups on a mounted ABR path.

.DESCRIPTION
    Reads a mounted Application Backup Repository (live export or an Instant
    Recovery snapshot) and turns each vzdump backup into one structured record.

    Deliberately cheap: it never opens the archive body. Everything comes from
    the file name, the file size, the .log written next to the dump, and the
    first four bytes of the archive. A 100 MB dump costs four bytes of reading.

    WHY THE .log MATTERS
    An Application Backup Repository has no job success event - the writing
    application does not know Veeam exists. Proxmox drops its own backup log
    next to each dump, which gives back exactly the success signal that ABR
    itself cannot provide.

    WHAT THE NUMBERS ARE GOOD FOR
      CompressionRatio  Uncompressed bytes over archive bytes. A container that
                        normally compresses 3.4:1 and suddenly manages 1.05:1
                        has encrypted content. This is the entropy signal
                        without reading the payload.
      MagicOk           First four bytes match the compression the file
                        extension claims. Catches truncated and rewritten files.
      DurationSeconds   Runtime drift.
      GuestStatus       A container that is suddenly 'stopped' when it usually
                        runs is worth a look.

    The output is one JSON file per run. Comparing snapshots means comparing
    these JSON files - not diffing filesystems. Two snapshots never need to be
    mounted at the same time.

.NOTES
    Only a successful vzdump log was available while writing this, so the
    success path is verified and the failure path is not. Failure detection
    keys on missing 'Finished Backup' plus any ERROR lines, which is
    conservative: an unparseable log is reported as Unknown, never as success.

    Note on timestamps: the vzdump file name carries local time and matches the
    log. That is the opposite of Veeam snapshot names, which are UTC.

.PARAMETER Path
    Mounted repository root, e.g. 'Y:\' or 'Z:\'. Dumps are expected under
    <Path>\dump, but the script searches recursively as a fallback.

.PARAMETER Source
    Free-text label stored in every record, identifying where this mount came
    from - 'live' for the repository export, or the snapshot name for an
    Instant Recovery mount. The drive letter is not enough: Z: is a different
    snapshot on every run, so the records need to say which one.

.EXAMPLE
    .\vbr-abr-inventory.ps1 -Path Y:\ -Source live
    Inventory of the live repository.

.EXAMPLE
    .\vbr-abr-inventory.ps1 -Path Z:\ -Source snapshot_20260808_101940 -OutputPath .\inv-20260808.json
    Inventory of a mounted Instant Recovery snapshot.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$Source = 'unspecified',

    # Directory holding one inventory per source. vbr-abr-inventory-diff reads it.
    [string]$InventoryStore = '.\inventory',

    # Overrides the store entirely. Normally leave this alone.
    [string]$OutputPath,

    # Print the table to the console as well as writing JSON.
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Format signatures. vzdump writes zstd by default; gzip and lzo are options.
# ---------------------------------------------------------------------------

$MagicBytes = @{
    'zst' = @(0x28, 0xB5, 0x2F, 0xFD)
    'gz'  = @(0x1F, 0x8B)
    'lzo' = @(0x89, 0x4C, 0x5A, 0x4F)
}

# vzdump-lxc-600-2026_08_08-12_10_41.tar.zst
# vzdump-qemu-100-2026_08_08-03_00_00.vma.zst
$DumpNamePattern = '^vzdump-(?<guest>lxc|qemu)-(?<vmid>\d+)-(?<stamp>\d{4}_\d{2}_\d{2}-\d{2}_\d{2}_\d{2})\.(?<ext>tar\.zst|tar\.gz|tar\.lzo|tar|vma\.zst|vma\.gz|vma)$'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Read only the leading bytes. The whole point is not to touch the payload.
function Get-LeadingBytes {
    param([string]$FilePath, [int]$Count = 4)

    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        $buffer = New-Object byte[] $Count
        $read = $stream.Read($buffer, 0, $Count)
        if ($read -lt $Count) { return $null }
        return $buffer
    }
    catch {
        return $null
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Test-MagicBytes {
    param([string]$FilePath, [string]$Extension)

    # Which compression does the extension claim?
    $claimed = switch -Regex ($Extension) {
        '\.zst$' { 'zst'; break }
        '\.gz$'  { 'gz';  break }
        '\.lzo$' { 'lzo'; break }
        default  { $null }
    }

    if (-not $claimed) {
        # Uncompressed tar: 'ustar' sits at offset 257, not at the start.
        return [ordered]@{ Claimed = 'none'; Ok = $null; Note = 'uncompressed, not checked' }
    }

    $expected = $MagicBytes[$claimed]
    $actual   = Get-LeadingBytes -FilePath $FilePath -Count $expected.Count

    if ($null -eq $actual) {
        return [ordered]@{ Claimed = $claimed; Ok = $false; Note = 'file too short or unreadable' }
    }

    for ($i = 0; $i -lt $expected.Count; $i++) {
        if ($actual[$i] -ne $expected[$i]) {
            $hex = ($actual | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            return [ordered]@{ Claimed = $claimed; Ok = $false; Note = "header mismatch, found: $hex" }
        }
    }

    return [ordered]@{ Claimed = $claimed; Ok = $true; Note = $null }
}

function ConvertFrom-VzdumpLog {
    param([string]$LogPath)

    $result = [ordered]@{
        LogPresent      = $false
        LogResult       = 'Unknown'
        CtName          = $null
        GuestStatus     = $null
        BackupMode      = $null
        BytesWritten    = $null
        ReportedSize    = $null
        StartTime       = $null
        EndTime         = $null
        DurationSeconds = $null
        # A backup can succeed and still contain nothing: set backup=no on the
        # disks and vzdump writes a config-only archive, reports success, and
        # nobody notices until the restore.
        ContainsDisks   = $null
        ExcludedDisks   = @()
        ErrorLines      = @()
        WarningLines    = @()
    }

    if (-not (Test-Path -LiteralPath $LogPath)) { return $result }
    $result.LogPresent = $true

    try {
        $lines = Get-Content -LiteralPath $LogPath -ErrorAction Stop
    }
    catch {
        $result.ErrorLines += "log unreadable: $($_.Exception.Message)"
        return $result
    }

    $sawFinished = $false

    foreach ($line in $lines) {
        # 2026-08-08 12:10:41 INFO: <message>
        if ($line -match '^(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(?<level>\w+):\s*(?<msg>.*)$') {
            $timestamp = $Matches['ts']
            $level     = $Matches['level']
            $message   = $Matches['msg']
        }
        else {
            # Lines without the standard prefix still matter if they scream.
            if ($line -match 'ERROR') { $result.ErrorLines += $line }
            continue
        }

        if (-not $result.StartTime) { $result.StartTime = $timestamp }
        $result.EndTime = $timestamp

        switch -Regex ($message) {
            '^CT Name:\s*(.+)$'                  { $result.CtName      = $Matches[1].Trim() }
            '^status\s*=\s*(.+)$'                { $result.GuestStatus = $Matches[1].Trim() }
            '^backup mode:\s*(.+)$'              { $result.BackupMode  = $Matches[1].Trim() }
            '^Total bytes written:\s*(\d+)'      { $result.BytesWritten = [int64]$Matches[1] }
            '^archive file size:\s*(.+)$'        { $result.ReportedSize = $Matches[1].Trim() }
            "^exclude disk '(?<disk>[^']+)'(?<rest>.*)" {
                $result.ExcludedDisks += "$($Matches['disk'])$($Matches['rest'])".Trim()
            }
            '^backup contains no disks'          { $result.ContainsDisks = $false }
            '^including mount point'             { $result.ContainsDisks = $true }
            '^ *scsi\d+:|^ *virtio\d+:|^ *sata\d+:|^ *ide\d+:' { $result.ContainsDisks = $true }
            '^Finished Backup of VM \d+\s*\((?<dur>\d+:\d{2}:\d{2})\)' {
                $sawFinished = $true
                $parts = $Matches['dur'] -split ':'
                $result.DurationSeconds = [int]$parts[0] * 3600 + [int]$parts[1] * 60 + [int]$parts[2]
            }
        }

        if ($level -eq 'ERROR') { $result.ErrorLines   += $message }
        if ($level -eq 'WARN')  { $result.WarningLines += $message }
    }

    # Conservative: only call it a success when the log says so and nothing
    # errored. Anything unclear stays Unknown rather than being assumed good.
    if ($result.ErrorLines.Count -gt 0) {
        $result.LogResult = 'Failed'
    }
    elseif ($sawFinished) {
        $result.LogResult = 'Success'
    }
    else {
        $result.LogResult = 'Incomplete'
    }

    return $result
}

# ---------------------------------------------------------------------------
# Collect
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Path '$Path' not found. Is the repository mounted?"
}

# Proxmox puts backups under dump/ on the storage root.
$dumpDir = Join-Path $Path 'dump'
$searchRoot = if (Test-Path -LiteralPath $dumpDir) { $dumpDir } else { $Path }

Write-Verbose "Scanning $searchRoot"

$archives = @(
    Get-ChildItem -LiteralPath $searchRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $DumpNamePattern }
)

$records = @()

foreach ($archive in $archives) {
    $null = $archive.Name -match $DumpNamePattern
    $guest = $Matches['guest']
    $vmid  = [int]$Matches['vmid']
    $stamp = $Matches['stamp']
    $ext   = $Matches['ext']

    # 2026_08_08-12_10_41 -> DateTime. Local time, matching the log.
    $backupTime = $null
    try {
        $backupTime = [datetime]::ParseExact($stamp, 'yyyy_MM_dd-HH_mm_ss', $null)
    }
    catch { }

    # vzdump-lxc-600-...tar.zst  ->  vzdump-lxc-600-....log
    $logPath   = Join-Path $archive.DirectoryName (($archive.Name -replace [regex]::Escape(".$ext"), '') + '.log')
    $notesPath = "$($archive.FullName).notes"

    $log   = ConvertFrom-VzdumpLog -LogPath $logPath
    $magic = Test-MagicBytes -FilePath $archive.FullName -Extension ".$ext"

    $notes = $null
    if (Test-Path -LiteralPath $notesPath) {
        try { $notes = (Get-Content -LiteralPath $notesPath -Raw -ErrorAction Stop).Trim() } catch { }
    }

    # The headline number: how well did this compress compared to usual?
    $ratio = $null
    if ($log.BytesWritten -and $archive.Length -gt 0) {
        $ratio = [math]::Round($log.BytesWritten / $archive.Length, 2)
    }

    $records += [pscustomobject][ordered]@{
        Source           = $Source
        VmId             = $vmid
        GuestType        = $guest
        CtName           = if ($log.CtName) { $log.CtName } else { $notes }
        BackupTime       = if ($backupTime) { $backupTime.ToString('o') } else { $null }
        ArchiveBytes     = $archive.Length
        UncompressedBytes= $log.BytesWritten
        CompressionRatio = $ratio
        Compression      = $magic.Claimed
        MagicOk          = $magic.Ok
        MagicNote        = $magic.Note
        LogPresent       = $log.LogPresent
        LogResult        = $log.LogResult
        ContainsDisks    = $log.ContainsDisks
        ExcludedDisks    = $log.ExcludedDisks
        DurationSeconds  = $log.DurationSeconds
        BackupMode       = $log.BackupMode
        GuestStatus      = $log.GuestStatus
        Notes            = $notes
        ErrorLines       = $log.ErrorLines
        WarningLines     = $log.WarningLines
        FileName         = $archive.Name
        FullName         = $archive.FullName
        ScannedAt        = (Get-Date).ToString('o')
    }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

if (-not $Quiet) {
    if ($records.Count -eq 0) {
        Write-Host "No vzdump backups found under $searchRoot" -ForegroundColor Yellow
    }
    else {
        $records |
            Sort-Object VmId, BackupTime |
            Format-Table VmId, CtName, BackupTime, ArchiveBytes, CompressionRatio,
                         MagicOk, LogResult, DurationSeconds -AutoSize

        # Anything that deserves a second look, stated plainly.
        $suspect = $records | Where-Object {
            $_.MagicOk -eq $false -or
            $_.LogResult -ne 'Success' -or
            -not $_.LogPresent -or
            $_.ContainsDisks -eq $false
        }
        if ($suspect) {
            Write-Host ''
            Write-Host 'Needs attention:' -ForegroundColor Yellow
            foreach ($item in $suspect) {
                $reasons = @()
                if (-not $item.LogPresent)         { $reasons += 'no log' }
                if ($item.LogResult -ne 'Success') { $reasons += "log result: $($item.LogResult)" }
                if ($item.MagicOk -eq $false)      { $reasons += "bad header ($($item.MagicNote))" }
                # Succeeds, reports green, contains nothing.
                if ($item.ContainsDisks -eq $false){ $reasons += 'backup contains no data' }
                Write-Host "  $($item.FileName): $($reasons -join '; ')"
            }
        }
    }
}

if (-not $OutputPath) {
    # One file per source, no scan timestamp in the name. A snapshot never
    # changes, so re-scanning it should overwrite rather than pile up copies.
    # 'live' is the exception - it moves, and overwriting is what you want there.
    if (-not (Test-Path -LiteralPath $InventoryStore)) {
        New-Item -ItemType Directory -Path $InventoryStore -Force | Out-Null
    }
    $safe = $Source -replace '[^\w\.-]', '_'
    $OutputPath = Join-Path $InventoryStore "inv-$safe.json"
}

$records | ConvertTo-Json -Depth 4 | Out-File -FilePath $OutputPath -Encoding utf8

if (-not $Quiet) {
    Write-Host ''
    Write-Host "$($records.Count) backup(s) written to $OutputPath"
}
