<#
.SYNOPSIS
    Extract structured facts from the files on a mounted ABR path.

.DESCRIPTION
    Reads a mounted Application Backup Repository (live export or an Instant
    Recovery snapshot) and turns every file into one structured record.

    Two layers:

      GENERIC LAYER, always runs
        Path, name, size, modification time, series key, and the format taken
        from the leading bytes rather than the extension. This works for any
        application writing into the export, without knowing the format.

      FORMAT HANDLERS, optional
        A recognised format adds what only it can know. vzdump contributes the
        backup log result, the compression ratio and the disk check. New
        handlers plug in at Get-FileFormat and Add-FormatFacts.

    Deliberately cheap: the archive body is never read. Everything comes from
    the file name, the file size, sibling files such as the log Proxmox writes,
    and the first 512 bytes.

    WHY THE SERIES KEY MATTERS
    An ABR has no backup job, so there is no job name to group by. The series
    key is derived by stripping timestamps out of the file name, which turns
    switch-core-01-2026-08-01.cfg and switch-core-01-2026-08-02.cfg into one
    series without anything having to be configured. Everything the comparison
    does - cadence, gaps, size plausibility - is keyed on it.

.NOTES
    Schema version 2. Version 1 inventories, written before the generic mode
    existed, are not readable and will be skipped by the comparison. Rebuild the
    store by scanning the sources again.

    Timestamps: vzdump file names carry local time and match their log. Veeam
    snapshot names are UTC. Do not mix the two.

.PARAMETER Path
    Mounted repository root, e.g. 'Y:\' or 'Z:\'. Searched recursively.

.PARAMETER Source
    Label identifying where this mount came from: 'live' for the repository
    export, or the snapshot name. The drive letter is not enough, because Z: is
    a different snapshot on every run.

.PARAMETER Retention
    Delete inventories in the store older than this many days. Default 365.
    Use 0 to keep everything.

    Inventories are tiny: roughly 800 bytes per record, so a year of daily
    snapshots across 50 sources costs about 15 MB. They also outlive the
    snapshots themselves, which makes them the only remaining evidence that a
    source was backed up on a given day. Keep them generously.

.EXAMPLE
    .\vbr-abr-inventory.ps1 -Path Y:\ -Source live

.EXAMPLE
    .\vbr-abr-inventory.ps1 -Path Z:\ -Source snapshot_20260808_101940
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$Source = 'unspecified',

    # Directory holding one inventory per source. vbr-abr-inventory-diff reads it.
    [string]$InventoryStore = '.\inventory',

    [int]$Retention = 365,

    # Overrides the store entirely. Normally leave this alone.
    [string]$OutputPath,

    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$SchemaVersion = 2

# ---------------------------------------------------------------------------
# Signatures. Used to determine what a file actually is, independent of what
# its extension claims.
# ---------------------------------------------------------------------------

$Signatures = @(
    @{ Name = 'zstd';  Bytes = @(0x28, 0xB5, 0x2F, 0xFD) }
    @{ Name = 'gzip';  Bytes = @(0x1F, 0x8B) }
    @{ Name = 'lzo';   Bytes = @(0x89, 0x4C, 0x5A, 0x4F) }
    @{ Name = 'xz';    Bytes = @(0xFD, 0x37, 0x7A, 0x58, 0x5A) }
    @{ Name = 'bzip2'; Bytes = @(0x42, 0x5A, 0x68) }
    @{ Name = 'zip';   Bytes = @(0x50, 0x4B, 0x03, 0x04) }
)

# What each extension claims to be, so a mismatch can be spotted.
$ExtensionClaims = @{
    '.zst'  = 'zstd'
    '.gz'   = 'gzip'
    '.tgz'  = 'gzip'
    '.lzo'  = 'lzo'
    '.xz'   = 'xz'
    '.bz2'  = 'bzip2'
    '.zip'  = 'zip'
}

# vzdump-lxc-600-2026_08_08-12_10_41.tar.zst
# vzdump-qemu-100-2026_08_08-03_00_00.vma.zst
$VzdumpPattern = '^vzdump-(?<guest>lxc|qemu)-(?<vmid>\d+)-(?<stamp>\d{4}_\d{2}_\d{2}-\d{2}_\d{2}_\d{2})\.(?<ext>tar\.zst|tar\.gz|tar\.lzo|tar|vma\.zst|vma\.gz|vma)$'

# Timestamp shapes to strip when deriving a series key. Longest first, so that
# a full date-and-time is removed as one unit rather than leaving fragments.
$TimestampPatterns = @(
    '\d{4}[-_.]\d{2}[-_.]\d{2}[-_T ]\d{2}[-_.:]\d{2}[-_.:]\d{2}'  # 2026-08-08T12:10:41
    '\d{8}[-_]\d{6}'                                              # 20260808_121041
    '\d{4}[-_.]\d{2}[-_.]\d{2}'                                   # 2026-08-08
    '\d{2}[-_.]\d{2}[-_.]\d{4}'                                   # 08-08-2026
    '\d{10,13}'                                                   # epoch seconds or ms
    '\d{8}'                                                       # 20260808
    '\d{6}'                                                       # 121041
)

# ---------------------------------------------------------------------------
# Generic layer
# ---------------------------------------------------------------------------

# Read only the leading bytes. The whole point is never to touch the body.
function Get-LeadingBytes {
    param([string]$FilePath, [int]$Count = 512)

    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        $buffer = New-Object byte[] $Count
        $read = $stream.Read($buffer, 0, $Count)
        if ($read -le 0) { return @() }
        if ($read -lt $Count) { return $buffer[0..($read - 1)] }
        return $buffer
    }
    catch {
        return $null
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }
}

# Bytes above 127 are perfectly normal in UTF-8 and Latin-1, so an "ASCII only"
# rule turns any config file containing an umlaut into binary. The rule here:
# a byte order mark settles it, NUL bytes mean binary unless the pattern says
# UTF-16, and a small share of stray control characters is tolerated rather
# than one of them being fatal.
function Test-LooksLikeText {
    param([byte[]]$Bytes)

    if (-not $Bytes -or $Bytes.Count -eq 0) { return $false }

    # A byte order mark is decisive on its own.
    if ($Bytes.Count -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return $true }
    if ($Bytes.Count -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return $true }
    if ($Bytes.Count -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) { return $true }

    $nulCount     = 0
    $controlCount = 0

    for ($i = 0; $i -lt $Bytes.Count; $i++) {
        $b = $Bytes[$i]
        if ($b -eq 0) { $nulCount++; continue }
        # Backspace, tab, LF, form feed, CR and escape all occur in text files.
        if ($b -lt 32 -and $b -notin @(8, 9, 10, 12, 13, 27)) { $controlCount++ }
    }

    if ($nulCount -gt 0) {
        # UTF-16 without a BOM: for mostly ASCII content every other byte is
        # NUL, on even or odd positions depending on the endianness.
        $evenNul = 0
        $oddNul  = 0
        for ($i = 0; $i -lt $Bytes.Count; $i++) {
            if ($Bytes[$i] -eq 0) {
                if ($i % 2 -eq 0) { $evenNul++ } else { $oddNul++ }
            }
        }
        $expected = [math]::Floor($Bytes.Count / 2) * 0.8
        return ($evenNul -ge $expected -or $oddNul -ge $expected)
    }

    return (($controlCount / $Bytes.Count) -lt 0.05)
}

# Determine what the file actually is, from its content.
function Get-ContentFormat {
    param([byte[]]$Bytes)

    if ($null -eq $Bytes) { return 'unreadable' }
    if ($Bytes.Count -eq 0) { return 'empty' }

    foreach ($sig in $Signatures) {
        if ($Bytes.Count -lt $sig.Bytes.Count) { continue }
        $match = $true
        for ($i = 0; $i -lt $sig.Bytes.Count; $i++) {
            if ($Bytes[$i] -ne $sig.Bytes[$i]) { $match = $false; break }
        }
        if ($match) { return $sig.Name }
    }

    # Uncompressed tar carries 'ustar' at offset 257.
    if ($Bytes.Count -ge 262) {
        $magic = [System.Text.Encoding]::ASCII.GetString($Bytes[257..261])
        if ($magic -eq 'ustar') { return 'tar' }
    }

    if (Test-LooksLikeText -Bytes $Bytes) { return 'text' }

    return 'binary'
}

# What the extension claims, so it can be checked against the content.
function Get-ClaimedFormat {
    param([string]$FileName)
    $lower = $FileName.ToLowerInvariant()
    foreach ($ext in $ExtensionClaims.Keys) {
        if ($lower.EndsWith($ext)) { return $ExtensionClaims[$ext] }
    }
    return $null
}

# Strip timestamps out of the name. What remains identifies the source.
# The directory is included, since many applications write one folder per source.
function Get-SeriesKey {
    param([string]$RelativePath)

    $directory = [System.IO.Path]::GetDirectoryName($RelativePath)
    $name      = [System.IO.Path]::GetFileName($RelativePath)

    # Remove every extension, not just the last: .tar.zst has to go entirely.
    while ([System.IO.Path]::GetExtension($name)) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($name)
    }

    foreach ($pattern in $TimestampPatterns) {
        $name = $name -replace $pattern, ''
    }

    # Tidy up what the removal left behind: doubled and trailing separators.
    $name = $name -replace '[-_.]{2,}', '-'
    $name = $name.Trim('-', '_', '.', ' ')

    if (-not $name) { $name = '(unnamed)' }

    if ($directory) { return (Join-Path $directory $name) -replace '\\', '/' }
    return $name
}

# ---------------------------------------------------------------------------
# Format detection
#
# Specific first, generic last, first match wins. Detection may look at the
# name and sibling files, and at the leading bytes already read. Never at the
# body - that would defeat the point of the whole design.
#
# To add a format: return a new name here, and handle it in Add-FormatFacts.
# ---------------------------------------------------------------------------

function Get-FileFormat {
    param([System.IO.FileInfo]$File)

    if ($File.Name -match $VzdumpPattern) {
        return "vzdump-$($Matches['guest'])"
    }

    return 'generic'
}

# ---------------------------------------------------------------------------
# vzdump handler
# ---------------------------------------------------------------------------

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
            $level   = $Matches['level']
            $message = $Matches['msg']
        }
        else {
            if ($line -match 'ERROR') { $result.ErrorLines += $line }
            continue
        }

        switch -Regex ($message) {
            '^CT Name:\s*(.+)$'             { $result.CtName      = $Matches[1].Trim() }
            '^VM Name:\s*(.+)$'             { $result.CtName      = $Matches[1].Trim() }
            '^status\s*=\s*(.+)$'           { $result.GuestStatus = $Matches[1].Trim() }
            '^backup mode:\s*(.+)$'         { $result.BackupMode  = $Matches[1].Trim() }
            '^Total bytes written:\s*(\d+)' { $result.BytesWritten = [int64]$Matches[1] }
            '^archive file size:\s*(.+)$'   { $result.ReportedSize = $Matches[1].Trim() }
            "^exclude disk '(?<disk>[^']+)'(?<rest>.*)" {
                $result.ExcludedDisks += "$($Matches['disk'])$($Matches['rest'])".Trim()
            }
            '^backup contains no disks'     { $result.ContainsDisks = $false }
            '^including mount point'        { $result.ContainsDisks = $true }
            '^Finished Backup of VM \d+\s*\((?<dur>\d+:\d{2}:\d{2})\)' {
                $sawFinished = $true
                $parts = $Matches['dur'] -split ':'
                $result.DurationSeconds = [int]$parts[0] * 3600 + [int]$parts[1] * 60 + [int]$parts[2]
            }
        }

        if ($level -eq 'ERROR') { $result.ErrorLines   += $message }
        if ($level -eq 'WARN')  { $result.WarningLines += $message }
    }

    # Conservative on purpose. Only call it a success when the log says so and
    # nothing errored. Anything unclear stays Unknown rather than being assumed
    # good: a log parsed wrongly must never come out green.
    if ($result.ErrorLines.Count -gt 0)  { $result.LogResult = 'Failed' }
    elseif ($sawFinished)                { $result.LogResult = 'Success' }
    else                                 { $result.LogResult = 'Incomplete' }

    return $result
}

# Add what only a recognised format can contribute.
function Add-FormatFacts {
    param(
        [System.Collections.Specialized.OrderedDictionary]$Record,
        [System.IO.FileInfo]$File,
        [string]$Format
    )

    if ($Format -notlike 'vzdump-*') { return }

    $null = $File.Name -match $VzdumpPattern
    $guest = $Matches['guest']
    $vmid  = [int]$Matches['vmid']
    $stamp = $Matches['stamp']
    $ext   = $Matches['ext']

    # vzdump knows its own series better than the generic heuristic does.
    $directory = [System.IO.Path]::GetDirectoryName($Record.RelativePath)
    $seriesKey = "vzdump-$guest-$vmid"
    if ($directory) { $seriesKey = (Join-Path $directory $seriesKey) -replace '\\', '/' }
    $Record.SeriesKey = $seriesKey

    try {
        $Record.BackupTime = ([datetime]::ParseExact($stamp, 'yyyy_MM_dd-HH_mm_ss', $null)).ToString('o')
    }
    catch { }

    $logPath   = Join-Path $File.DirectoryName (($File.Name -replace [regex]::Escape(".$ext"), '') + '.log')
    $notesPath = "$($File.FullName).notes"

    $log = ConvertFrom-VzdumpLog -LogPath $logPath

    $notes = $null
    if (Test-Path -LiteralPath $notesPath) {
        try { $notes = (Get-Content -LiteralPath $notesPath -Raw -ErrorAction Stop).Trim() } catch { }
    }

    # The headline number. Encrypted data does not compress, so a guest that
    # always managed 3.2:1 and now manages 1.05:1 has encrypted content.
    $ratio = $null
    if ($log.BytesWritten -and $File.Length -gt 0) {
        $ratio = [math]::Round($log.BytesWritten / $File.Length, 2)
    }

    $Record.VmId              = $vmid
    $Record.GuestType         = $guest
    $Record.GuestName         = if ($log.CtName) { $log.CtName } else { $notes }
    $Record.UncompressedBytes = $log.BytesWritten
    $Record.CompressionRatio  = $ratio
    $Record.LogPresent        = $log.LogPresent
    $Record.LogResult         = $log.LogResult
    $Record.ContainsDisks     = $log.ContainsDisks
    $Record.ExcludedDisks     = $log.ExcludedDisks
    $Record.DurationSeconds   = $log.DurationSeconds
    $Record.BackupMode        = $log.BackupMode
    $Record.GuestStatus       = $log.GuestStatus
    $Record.Notes             = $notes
    $Record.ErrorLines        = $log.ErrorLines
    $Record.WarningLines      = $log.WarningLines
}

# ---------------------------------------------------------------------------
# Retention
# ---------------------------------------------------------------------------

function Remove-ExpiredInventories {
    param([string]$StorePath, [int]$Days)

    if ($Days -le 0 -or -not (Test-Path -LiteralPath $StorePath)) { return }

    $cutoff  = (Get-Date).AddDays(-$Days)
    $removed = 0

    foreach ($file in Get-ChildItem -LiteralPath $StorePath -Filter 'inv-*.json' -File) {
        if ($file.LastWriteTime -lt $cutoff) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force
                $removed++
            }
            catch {
                Write-Warning "Could not remove $($file.Name): $($_.Exception.Message)"
            }
        }
    }

    if ($removed -gt 0 -and -not $Quiet) {
        Write-Host "Retention: removed $removed inventory file(s) older than $Days days"
    }
}

# ---------------------------------------------------------------------------
# Collect
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Path '$Path' not found. Is the repository mounted?"
}

$rootFull = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')

# Sibling files belong to their archive, not to a series of their own.
$SidecarPattern = '\.(log|notes|protected)$'

$files = @(
    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch $SidecarPattern }
)

$records = @()
$scannedAt = (Get-Date).ToString('o')

foreach ($file in $files) {

    $relative = $file.FullName
    if ($relative.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        $relative = $relative.Substring($rootFull.Length).TrimStart('\', '/')
    }
    $relative = $relative -replace '\\', '/'

    $leading       = Get-LeadingBytes -FilePath $file.FullName
    $contentFormat = Get-ContentFormat -Bytes $leading
    $claimed       = Get-ClaimedFormat -FileName $file.Name

    # Only meaningful where the extension actually claims something.
    $magicOk = $null
    if ($claimed) { $magicOk = ($claimed -eq $contentFormat) }

    $format = Get-FileFormat -File $file

    $record = [ordered]@{
        SchemaVersion     = $SchemaVersion
        Source            = $Source
        SeriesKey         = Get-SeriesKey -RelativePath $relative
        Format            = $format

        FileName          = $file.Name
        RelativePath      = $relative
        FullName          = $file.FullName
        FileSize          = $file.Length
        LastWriteTime     = $file.LastWriteTime.ToString('o')

        ContentFormat     = $contentFormat
        ClaimedFormat     = $claimed
        MagicOk           = $magicOk

        # Filled in by a format handler where one applies.
        BackupTime        = $null
        VmId              = $null
        GuestType         = $null
        GuestName         = $null
        UncompressedBytes = $null
        CompressionRatio  = $null
        LogPresent        = $null
        LogResult         = $null
        ContainsDisks     = $null
        ExcludedDisks     = @()
        DurationSeconds   = $null
        BackupMode        = $null
        GuestStatus       = $null
        Notes             = $null
        ErrorLines        = @()
        WarningLines      = @()

        ScannedAt         = $scannedAt
    }

    Add-FormatFacts -Record $record -File $file -Format $format

    # Without a format handler the write time is the only timestamp there is.
    if (-not $record.BackupTime) {
        $record.BackupTime = $record.LastWriteTime
    }

    $records += [pscustomobject]$record
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

if (-not $Quiet) {
    if ($records.Count -eq 0) {
        Write-Host "No files found under $Path" -ForegroundColor Yellow
    }
    else {
        $records |
            Sort-Object SeriesKey, BackupTime |
            Format-Table SeriesKey, Format, BackupTime, FileSize, CompressionRatio,
                         ContentFormat, LogResult -AutoSize

        # Coverage. Says at a glance whether the specific handlers are doing
        # anything, or whether the export holds something nobody planned for.
        Write-Host 'Formats:' -ForegroundColor Cyan
        $records | Group-Object Format | Sort-Object Count -Descending | ForEach-Object {
            Write-Host ("  {0,-16} {1}" -f $_.Name, $_.Count)
        }

        $suspect = $records | Where-Object {
            $_.MagicOk -eq $false -or
            $_.ContentFormat -in @('empty', 'unreadable') -or
            ($_.LogPresent -eq $true -and $_.LogResult -ne 'Success') -or
            $_.ContainsDisks -eq $false
        }
        if ($suspect) {
            Write-Host ''
            Write-Host 'Needs attention:' -ForegroundColor Yellow
            foreach ($item in $suspect) {
                $reasons = @()
                if ($item.ContentFormat -eq 'empty')      { $reasons += 'file is empty' }
                if ($item.ContentFormat -eq 'unreadable') { $reasons += 'file not readable' }
                if ($item.MagicOk -eq $false)             { $reasons += "claims $($item.ClaimedFormat), contains $($item.ContentFormat)" }
                if ($item.LogPresent -eq $true -and $item.LogResult -ne 'Success') { $reasons += "log result: $($item.LogResult)" }
                if ($item.ContainsDisks -eq $false)       { $reasons += 'backup contains no data' }
                Write-Host "  $($item.FileName): $($reasons -join '; ')"
            }
        }
    }
}

if (-not $OutputPath) {
    # One file per source, no scan timestamp in the name. A snapshot never
    # changes, so re-scanning it overwrites rather than piling up copies.
    if (-not (Test-Path -LiteralPath $InventoryStore)) {
        New-Item -ItemType Directory -Path $InventoryStore -Force | Out-Null
    }
    $safe = $Source -replace '[^\w\.-]', '_'
    $OutputPath = Join-Path $InventoryStore "inv-$safe.json"
}

$records | ConvertTo-Json -Depth 4 | Out-File -FilePath $OutputPath -Encoding utf8

if (-not $Quiet) {
    Write-Host ''
    Write-Host "$($records.Count) file(s) written to $OutputPath"
}

Remove-ExpiredInventories -StorePath $InventoryStore -Days $Retention
