<#
.SYNOPSIS
    Compare ABR inventories and report what is wrong or has changed.

.DESCRIPTION
    Works on the JSON written by vbr-abr-inventory.ps1, never on mounted files.
    Two snapshots therefore never have to be mounted at the same time: mount,
    inventory, unmount, repeat, then compare the results.

    Three layers, because they answer different questions.

    1. SERIES HEALTH (current inventory alone)
       Is the application writing into this export still writing, and does what
       it writes look plausible? Needs no baseline and no format knowledge.

         Cadence      Twelve writes 24 hours apart and then nothing for 70
                      hours is a finding. The expected interval comes from the
                      history of the series itself, not from configuration.
         Gaps         A missing interval in an otherwise regular series.
         Write window Always written around 02:00, now appearing at 14:00.
         Size         Not "is this normal", which cannot be answered without
                      knowing the source, but whether the file is plausible at
                      all: empty, or smaller than its predecessors by an order
                      of magnitude, which is what a truncated write looks like.
         Content      Format taken from the leading bytes disagrees with what
                      the extension claims, or changes within a series.

    2. CHANGE (baseline against current)
       A finished backup file is written once and never touched again. So an
       archive present in both inventories whose size or content format changed
       has been rewritten, and there is no benign explanation for that.

       Removed files are reported too. Usually that is the application's own
       retention, but deletion is also what an attacker does first.

    3. HISTORY (every inventory in the store)
       Compression ratio against everything that series has ever shown, rather
       than against a single earlier point.

       This matters because of partial encryption. Ransomware often encrypts
       only part of a file to work faster and stay under detection thresholds.
       Starting from a 3.24 baseline, encrypting 30% of the content lands at
       1.94 and encrypting 70% still only reaches 1.26, so an absolute
       threshold of 1.2 catches almost none of it. A series that sat between
       3.20 and 3.28 twelve times running and now shows 1.94 is far outside
       anything it has ever done, even though 1.94 looks harmless on its own.
       The tighter the history, the smaller the deviation that means something,
       and no fixed threshold can express that.

       The floor stays: below roughly 15 to 20% encrypted content, compression
       says nothing useful at all.

       Falls back to the two-point comparison while the store holds fewer than
       MinHistoryPoints inventories for a series.

    4. POSSIBLE CLEAN RESTORE POINT
       The question that matters during an incident: how far back do I have to
       go? Immutability guarantees the backups are still there but says nothing
       about which of them is worth restoring.

       Every file in every snapshot is judged, not only the newest one, and the
       answer is given per series. The first bad backup is usually a few
       snapshots older than the one that finally crossed the alert threshold,
       so restoring the snapshot just before the alert is not enough.

       Deliberately worded as a suggestion. This rests on metadata alone, so it
       says a snapshot looks unremarkable, not that it is clean. Nothing here
       has opened an archive or inspected its contents. Treat it as where to
       start looking, and verify before restoring.

.NOTES
    Reads schema version 2 inventories. Version 1 files, written before the
    generic mode existed, are skipped with a warning. Rebuild them by scanning
    the sources again.

.PARAMETER Baseline
    The older side, given as a source name such as 'snapshot_20260808_101940',
    not a file path. Also accepts 'latest' for the most recently scanned
    inventory other than -Current. Leave empty to pick from a list.

.PARAMETER Current
    The newer side. Defaults to 'live'.

.PARAMETER List
    Show the available inventories and exit.

.PARAMETER MinRatio
    Two-point fallback: alert when the compression ratio drops below this.
    Default 1.2. Only fires at roughly 75% encrypted content and above, which
    is why the history in layer 3 matters.

.PARAMETER BaselineMinRatio
    Two-point fallback: only alert when the baseline was above this. Default
    1.5. Keeps series that never compressed well from alerting on every run.

.PARAMETER RatioDropPercent
    Two-point fallback: notice when the ratio falls by this much without
    crossing MinRatio. Default 30.

.PARAMETER MinHistoryPoints
    How many past values a series needs before the history is used instead of
    the two-point fallback. Default 8.

.PARAMETER HistorySensitivity
    How far outside its own history a value has to sit before it is an alert,
    in robust standard deviations. Default 3.

.PARAMETER CadenceTolerance
    Report a series as overdue when the time since its last file exceeds its
    usual interval by this factor. Default 2.5.

.EXAMPLE
    .\vbr-abr-inventory-diff.ps1 -List

.EXAMPLE
    .\vbr-abr-inventory-diff.ps1
    Pick the baseline interactively, compare against 'live'.

.EXAMPLE
    .\vbr-abr-inventory-diff.ps1 -Baseline latest
#>

[CmdletBinding()]
param(
    [string]$Baseline,

    [string]$Current = 'live',

    [string]$InventoryStore = '.\inventory',

    [switch]$List,

    [double]$MinRatio = 1.2,

    [double]$BaselineMinRatio = 1.5,

    [int]$RatioDropPercent = 30,

    [int]$MinHistoryPoints = 8,

    [double]$HistorySensitivity = 3,

    [double]$CadenceTolerance = 2.5,

    [int]$SizeChangePercent = 50,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$RequiredSchema = 2

# ---------------------------------------------------------------------------
# Store
# ---------------------------------------------------------------------------

# ConvertTo-Json emits a bare object rather than an array when there is exactly
# one record, so every load has to be wrapped.
function Import-InventoryFile {
    param([string]$FilePath)
    return @(Get-Content -LiteralPath $FilePath -Raw | ConvertFrom-Json)
}

function Get-InventoryCatalog {
    param([string]$StorePath)

    if (-not (Test-Path -LiteralPath $StorePath)) {
        throw "Inventory store '$StorePath' not found. Run vbr-abr-inventory.ps1 first."
    }

    $entries = @()
    foreach ($file in Get-ChildItem -LiteralPath $StorePath -Filter 'inv-*.json' -File) {
        try {
            $records = Import-InventoryFile -FilePath $file.FullName

            $schema = if ($records.Count) { $records[0].SchemaVersion } else { $null }
            if ($schema -ne $RequiredSchema) {
                Write-Warning "$($file.Name): schema version $schema, expected $RequiredSchema. Skipped. Re-scan the source to rebuild it."
                continue
            }

            $entries += [pscustomobject][ordered]@{
                Source     = $records[0].Source
                FileCount  = $records.Count
                ScannedAt  = $records[0].ScannedAt
                Path       = $file.FullName
                Records    = $records
            }
        }
        catch {
            Write-Warning "Skipping $($file.Name): $($_.Exception.Message)"
        }
    }

    return @($entries | Sort-Object -Property ScannedAt -Descending)
}

function Select-FromList {
    param(
        [Parameter(Mandatory)][array]$Items,
        [Parameter(Mandatory)][string]$Prompt,
        [scriptblock]$Formatter
    )

    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ("  [{0,2}] {1}" -f ($i + 1), (& $Formatter $Items[$i]))
    }

    while ($true) {
        Write-Host ''
        $answer = Read-Host "$Prompt (1-$($Items.Count), empty = cancel)"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $null }
        $index = 0
        if ([int]::TryParse($answer, [ref]$index) -and $index -ge 1 -and $index -le $Items.Count) {
            return $Items[$index - 1]
        }
        Write-Host 'Invalid input.' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Statistics
#
# Median and MAD rather than mean and standard deviation, because a single
# encrypted backup would drag a mean along with it and hide itself.
# ---------------------------------------------------------------------------

function Get-Median {
    param([double[]]$Values)
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $sorted = $Values | Sort-Object
    $mid = [math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) { return $sorted[$mid] }
    return ($sorted[$mid - 1] + $sorted[$mid]) / 2
}

# How far a value sits outside its own history, in robust standard deviations.
function Get-RobustDeviation {
    param([double[]]$History, [double]$Value)

    $median = Get-Median -Values $History
    if ($null -eq $median -or $median -eq 0) { return $null }

    $absolute = $History | ForEach-Object { [math]::Abs($_ - $median) }
    $mad = Get-Median -Values $absolute

    # 1.4826 puts MAD on the same scale as a standard deviation for normal data.
    $scale = $mad * 1.4826

    # A perfectly flat history would make every rounding difference infinitely
    # significant. Never let the tolerance fall below 10% of the median.
    $floor = [math]::Abs($median) * 0.10
    if ($scale -lt $floor) { $scale = $floor }

    return [pscustomobject]@{
        Median    = [math]::Round($median, 2)
        Deviation = [math]::Round([math]::Abs($Value - $median) / $scale, 1)
        Below     = ($Value -lt $median)
    }
}

# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------

$findings = @()

function Add-Finding {
    param(
        [string]$Severity,   # Alert | Notice | Info
        [string]$Category,
        [string]$Subject,
        [string]$Message
    )
    $script:findings += [pscustomobject][ordered]@{
        Severity = $Severity
        Category = $Category
        Subject  = $Subject
        Message  = $Message
    }
}

# ---------------------------------------------------------------------------
# Load and resolve
# ---------------------------------------------------------------------------

$catalog = Get-InventoryCatalog -StorePath $InventoryStore

$entryFormatter = {
    param($e)
    "{0,-32} {1,3} file(s)   scanned {2}" -f $e.Source, $e.FileCount, $e.ScannedAt
}

if ($List -or $catalog.Count -eq 0) {
    Write-Host ''
    Write-Host "Inventories in $InventoryStore" -ForegroundColor Cyan
    if ($catalog.Count -eq 0) {
        Write-Host '  (none, run vbr-abr-inventory.ps1 first)' -ForegroundColor Yellow
    }
    else {
        foreach ($e in $catalog) { Write-Host "  $(& $entryFormatter $e)" }
    }
    return
}

$currentEntry = $catalog | Where-Object { $_.Source -eq $Current } | Select-Object -First 1
if (-not $currentEntry) {
    throw "No inventory for '$Current'. Available: $((($catalog | ForEach-Object { $_.Source }) -join ', '))"
}

$candidates = @($catalog | Where-Object { $_.Source -ne $currentEntry.Source })

$baselineEntry = $null
if ($candidates.Count -eq 0) {
    Write-Warning "Only '$($currentEntry.Source)' exists. Running series health checks only."
}
elseif (-not $Baseline) {
    Write-Host ''
    Write-Host "Compare against '$($currentEntry.Source)'" -ForegroundColor Cyan
    $baselineEntry = Select-FromList -Items $candidates -Prompt 'Select baseline' -Formatter $entryFormatter
    if (-not $baselineEntry) { Write-Host 'Cancelled.'; return }
}
elseif ($Baseline -in @('latest', 'previous')) {
    $baselineEntry = $candidates[0]   # catalog is sorted newest first
}
else {
    $baselineEntry = $candidates | Where-Object { $_.Source -like $Baseline } | Select-Object -First 1
    if (-not $baselineEntry) {
        throw "No inventory matches '$Baseline'. Available: $((($candidates | ForEach-Object { $_.Source }) -join ', '))"
    }
}

$currRecords = $currentEntry.Records
$baseRecords = if ($baselineEntry) { $baselineEntry.Records } else { @() }
$currLabel   = $currentEntry.Source
$baseLabel   = if ($baselineEntry) { $baselineEntry.Source } else { '(none)' }

Write-Host ''
Write-Host "Baseline: $baseLabel  ($($baseRecords.Count) file(s))" -ForegroundColor Cyan
Write-Host "Current : $currLabel  ($($currRecords.Count) file(s))" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. Series health, from the current inventory alone
# ---------------------------------------------------------------------------

$currentSeries = $currRecords | Group-Object SeriesKey

foreach ($series in $currentSeries) {
    $subject = $series.Name
    $items   = @($series.Group | Sort-Object BackupTime)
    $newest  = $items[-1]

    # --- Content format problems, per file -------------------------------

    foreach ($item in $items) {
        if ($item.ContentFormat -eq 'empty') {
            Add-Finding -Severity 'Alert' -Category 'EmptyFile' -Subject $subject `
                -Message "$($item.FileName) is empty"
        }
        elseif ($item.ContentFormat -eq 'unreadable') {
            Add-Finding -Severity 'Alert' -Category 'UnreadableFile' -Subject $subject `
                -Message "$($item.FileName) could not be read"
        }

        if ($item.MagicOk -eq $false) {
            Add-Finding -Severity 'Alert' -Category 'FormatMismatch' -Subject $subject `
                -Message "$($item.FileName) claims $($item.ClaimedFormat) but contains $($item.ContentFormat)"
        }

        # A name saying 2026-08-01 with an mtime of 2026-08-09 means the file
        # was touched after it was written.
        if ($item.BackupTime -and $item.LastWriteTime) {
            try {
                $named   = [datetime]$item.BackupTime
                $written = [datetime]$item.LastWriteTime
                $skew = [math]::Abs(($written - $named).TotalHours)
                if ($skew -gt 24) {
                    Add-Finding -Severity 'Notice' -Category 'TimestampSkew' -Subject $subject `
                        -Message "$($item.FileName): name says $($named.ToString('yyyy-MM-dd HH:mm')), modified $($written.ToString('yyyy-MM-dd HH:mm'))"
                }
            }
            catch { }
        }
    }

    # --- Format consistency within the series -----------------------------

    $formats = @($items | Select-Object -ExpandProperty ContentFormat -Unique)
    if ($formats.Count -gt 1) {
        Add-Finding -Severity 'Alert' -Category 'FormatDrift' -Subject $subject `
            -Message "series contains mixed content formats: $($formats -join ', ')"
    }

    $handlers = @($items | Select-Object -ExpandProperty Format -Unique)
    if ($handlers.Count -gt 1) {
        Add-Finding -Severity 'Notice' -Category 'HandlerDrift' -Subject $subject `
            -Message "series recognised as more than one format: $($handlers -join ', ')"
    }

    # --- Cadence and gaps -------------------------------------------------
    # The expected interval comes from the series itself. Nothing is configured.

    if ($items.Count -ge 3) {
        $times = @()
        foreach ($item in $items) {
            try { $times += [datetime]$item.BackupTime } catch { }
        }
        $times = @($times | Sort-Object)

        if ($times.Count -ge 3) {
            $intervals = @()
            for ($i = 1; $i -lt $times.Count; $i++) {
                $intervals += ($times[$i] - $times[$i - 1]).TotalHours
            }

            $typical = Get-Median -Values $intervals

            if ($typical -and $typical -gt 0) {
                $sinceLast = ((Get-Date) - $times[-1]).TotalHours
                if ($sinceLast -gt ($typical * $CadenceTolerance)) {
                    Add-Finding -Severity 'Alert' -Category 'Overdue' -Subject $subject `
                        -Message "usually written every $([math]::Round($typical, 1))h, nothing for $([math]::Round($sinceLast, 1))h"
                }

                # A single stretched interval inside an otherwise regular series.
                for ($i = 0; $i -lt $intervals.Count; $i++) {
                    if ($intervals[$i] -gt ($typical * $CadenceTolerance)) {
                        Add-Finding -Severity 'Notice' -Category 'CadenceGap' -Subject $subject `
                            -Message "gap of $([math]::Round($intervals[$i], 1))h before $($times[$i + 1].ToString('yyyy-MM-dd HH:mm')), usual interval $([math]::Round($typical, 1))h"
                    }
                }
            }

            # Write window. Says nothing about content, but says the schedule
            # changed, which is worth knowing on its own.
            #
            # Hours are cyclic and this treats them as linear, so a series
            # running across midnight (23:50 one day, 00:10 the next) would look
            # like a huge swing. Skipped when the hours straddle midnight rather
            # than reporting something wrong. Reported as a notice either way.
            if ($times.Count -ge 4) {
                $hours = @($times | ForEach-Object { [double]$_.Hour })
                $straddlesMidnight = (($hours | Where-Object { $_ -le 2 }).Count -gt 0) -and
                                     (($hours | Where-Object { $_ -ge 22 }).Count -gt 0)

                if (-not $straddlesMidnight) {
                    $windowDeviation = Get-RobustDeviation -History $hours -Value ([double]$times[-1].Hour)
                    if ($windowDeviation -and $windowDeviation.Deviation -gt $HistorySensitivity) {
                        $usual = [int][math]::Round($windowDeviation.Median)
                        Add-Finding -Severity 'Notice' -Category 'WriteWindow' -Subject $subject `
                            -Message "last write at $($times[-1].ToString('HH:mm')), the series usually runs around $('{0:00}:00' -f $usual)"
                    }
                }
            }
        }
    }

    # --- Size plausibility ------------------------------------------------
    # Not "is this size normal", which needs knowledge of the source. Only
    # whether the newest file is plausible next to its own predecessors.

    if ($items.Count -ge 3) {
        $previousSizes = @($items[0..($items.Count - 2)] | ForEach-Object { [double]$_.FileSize })
        $typicalSize = Get-Median -Values $previousSizes

        if ($typicalSize -and $typicalSize -gt 0 -and $newest.FileSize -lt ($typicalSize / 10)) {
            Add-Finding -Severity 'Alert' -Category 'SizeCollapse' -Subject $subject `
                -Message "$($newest.FileName) is $($newest.FileSize) bytes, the series usually writes around $([int]$typicalSize). Looks truncated"
        }
    }

    # --- vzdump specific --------------------------------------------------

    if ($newest.LogPresent -eq $true -and $newest.LogResult -ne 'Success') {
        Add-Finding -Severity 'Alert' -Category 'BackupFailed' -Subject $subject `
            -Message "newest backup log result: $($newest.LogResult)"
    }

    if ($newest.ContainsDisks -eq $false) {
        Add-Finding -Severity 'Alert' -Category 'EmptyBackup' -Subject $subject `
            -Message 'backup reports success but contains no data'
    }
}

# ---------------------------------------------------------------------------
# 2. Change, baseline against current
# ---------------------------------------------------------------------------

if ($baselineEntry) {

    $baseByPath = @{}
    foreach ($r in $baseRecords) { $baseByPath[$r.RelativePath] = $r }

    $currByPath = @{}
    foreach ($r in $currRecords) { $currByPath[$r.RelativePath] = $r }

    foreach ($p in $currByPath.Keys) {
        if (-not $baseByPath.ContainsKey($p)) {
            $c = $currByPath[$p]
            Add-Finding -Severity 'Info' -Category 'FileAdded' -Subject $c.SeriesKey `
                -Message "$($c.FileName), $([math]::Round($c.FileSize / 1MB, 1)) MB"
        }
    }

    foreach ($p in $baseByPath.Keys) {
        if (-not $currByPath.ContainsKey($p)) {
            $b = $baseByPath[$p]
            Add-Finding -Severity 'Notice' -Category 'FileRemoved' -Subject $b.SeriesKey `
                -Message "$($b.FileName) present in baseline, gone now. Retention, or deletion"
            continue
        }

        # Present in both. A finished backup file is never rewritten, so any
        # difference here means someone touched it.
        $b = $baseByPath[$p]
        $c = $currByPath[$p]

        if ($b.FileSize -ne $c.FileSize) {
            Add-Finding -Severity 'Alert' -Category 'FileModified' -Subject $c.SeriesKey `
                -Message "$($c.FileName) changed size, $($b.FileSize) to $($c.FileSize) bytes, on a file that should never be rewritten"
        }
        if ($b.ContentFormat -ne $c.ContentFormat) {
            Add-Finding -Severity 'Alert' -Category 'FileModified' -Subject $c.SeriesKey `
                -Message "$($c.FileName) changed content format, $($b.ContentFormat) to $($c.ContentFormat)"
        }
        if ($b.CompressionRatio -and $c.CompressionRatio -and $b.CompressionRatio -ne $c.CompressionRatio) {
            Add-Finding -Severity 'Alert' -Category 'FileModified' -Subject $c.SeriesKey `
                -Message "$($c.FileName) changed compression ratio, $($b.CompressionRatio) to $($c.CompressionRatio)"
        }
        if ($b.LogResult -and $c.LogResult -and $b.LogResult -ne $c.LogResult) {
            Add-Finding -Severity 'Alert' -Category 'LogModified' -Subject $c.SeriesKey `
                -Message "$($c.FileName) log result changed, $($b.LogResult) to $($c.LogResult)"
        }
    }

    # Series level

    $baseSeries = @($baseRecords | Select-Object -ExpandProperty SeriesKey -Unique)
    $currSeries = @($currRecords | Select-Object -ExpandProperty SeriesKey -Unique)

    foreach ($s in $currSeries) {
        if ($s -notin $baseSeries) {
            Add-Finding -Severity 'Info' -Category 'SeriesAdded' -Subject $s `
                -Message 'not in baseline. New source, or an existing one that changed its naming'
        }
    }

    foreach ($s in $baseSeries) {
        if ($s -notin $currSeries) {
            Add-Finding -Severity 'Alert' -Category 'SeriesDisappeared' -Subject $s `
                -Message 'was present in the baseline, has no files at all now'
        }
    }
}

# ---------------------------------------------------------------------------
# 3. History, across every inventory in the store
# ---------------------------------------------------------------------------

# Collect every compression ratio ever recorded per series, excluding the
# current inventory so that the value being judged is not part of its own
# reference.
$ratioHistory = @{}
foreach ($entry in $catalog) {
    if ($entry.Source -eq $currLabel) { continue }
    foreach ($r in $entry.Records) {
        if ($null -eq $r.CompressionRatio) { continue }
        if (-not $ratioHistory.ContainsKey($r.SeriesKey)) { $ratioHistory[$r.SeriesKey] = @() }
        $ratioHistory[$r.SeriesKey] += [double]$r.CompressionRatio
    }
}

$historyUsed = 0
$fallbackUsed = 0

foreach ($series in $currentSeries) {
    $subject = $series.Name
    $newest  = @($series.Group | Sort-Object BackupTime)[-1]

    if ($null -eq $newest.CompressionRatio) { continue }
    $value = [double]$newest.CompressionRatio

    $history = @()
    if ($ratioHistory.ContainsKey($subject)) { $history = @($ratioHistory[$subject]) }

    if ($history.Count -ge $MinHistoryPoints) {
        # Enough history to ask the better question: is this value outside
        # anything this series has ever shown?
        $historyUsed++
        $stat = Get-RobustDeviation -History $history -Value $value

        if ($stat -and $stat.Below -and $stat.Deviation -gt $HistorySensitivity) {
            Add-Finding -Severity 'Alert' -Category 'CompressionAnomaly' -Subject $subject `
                -Message "ratio $value against a history of $($stat.Median) over $($history.Count) points, $($stat.Deviation) deviations below. Partial encryption looks like this"
        }
    }
    else {
        # Two-point fallback until the store has enough history.
        $fallbackUsed++

        if (-not $baselineEntry) { continue }
        $baseNewest = @($baseRecords | Where-Object { $_.SeriesKey -eq $subject } | Sort-Object BackupTime)
        if ($baseNewest.Count -eq 0) { continue }
        $b = $baseNewest[-1]
        if ($null -eq $b.CompressionRatio) { continue }

        $baseValue = [double]$b.CompressionRatio
        if ($baseValue -le 0) { continue }
        $drop = (1 - ($value / $baseValue)) * 100

        if ($value -lt $MinRatio -and $baseValue -ge $BaselineMinRatio) {
            Add-Finding -Severity 'Alert' -Category 'CompressionCollapse' -Subject $subject `
                -Message "ratio $baseValue to $value. The data no longer compresses, which is what encryption looks like"
        }
        elseif ($drop -ge $RatioDropPercent) {
            Add-Finding -Severity 'Notice' -Category 'CompressionDrop' -Subject $subject `
                -Message "ratio fell $([math]::Round($drop))%, $baseValue to $value, still above $MinRatio"
        }

        # Size drift between the two points, same fallback logic.
        if ($b.FileSize -gt 0) {
            $change = (([double]$newest.FileSize - [double]$b.FileSize) / [double]$b.FileSize) * 100
            if ([math]::Abs($change) -ge $SizeChangePercent) {
                $direction = if ($change -gt 0) { 'grew' } else { 'shrank' }
                Add-Finding -Severity 'Notice' -Category 'SizeJump' -Subject $subject `
                    -Message "newest archive $direction by $([math]::Round([math]::Abs($change)))%, $($b.FileSize) to $($newest.FileSize) bytes"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 4. Last clean restore point
#
# The question that actually matters during an incident: how far back do I have
# to go? Immutability guarantees the backups are still there, but says nothing
# about which of them is worth restoring.
#
# Every file in every inventory is judged here, not only the newest one. The
# first bad backup is usually a few snapshots older than the one that finally
# crossed the alert threshold, and restoring the snapshot before the alert is
# not enough.
# ---------------------------------------------------------------------------

# Snapshot names carry a UTC timestamp: snapshot_20260809_093246. The store is
# ordered by scan time, which is not the same thing.
function Get-SourceTime {
    param($Entry)
    if ($Entry.Source -match '(\d{8})[_-](\d{6})') {
        try {
            return [datetime]::ParseExact("$($Matches[1])$($Matches[2])", 'yyyyMMddHHmmss', $null)
        }
        catch { }
    }
    try { return [datetime]$Entry.ScannedAt } catch { return [datetime]::MinValue }
}

# Why this file cannot be trusted, or $null when nothing is wrong with it.
function Get-RecordProblem {
    param($Record, [double[]]$History)

    if ($Record.ContainsDisks -eq $false)       { return 'contains no data' }
    if ($Record.ContentFormat -eq 'empty')      { return 'file is empty' }
    if ($Record.ContentFormat -eq 'unreadable') { return 'file not readable' }
    if ($Record.MagicOk -eq $false)             { return "claims $($Record.ClaimedFormat), contains $($Record.ContentFormat)" }
    if ($Record.LogPresent -eq $true -and $Record.LogResult -ne 'Success') { return "log result $($Record.LogResult)" }

    if ($null -ne $Record.CompressionRatio -and $History.Count -ge 3) {
        $stat = Get-RobustDeviation -History $History -Value ([double]$Record.CompressionRatio)
        if ($stat -and $stat.Below -and $stat.Deviation -gt $HistorySensitivity) {
            return "ratio $($Record.CompressionRatio) against a history of $($stat.Median)"
        }
    }

    return $null
}

# 'live' is not a restore point, so it can never be the answer.
$restorePoints = @($catalog | Where-Object { $_.Source -ne 'live' } |
                   Sort-Object { Get-SourceTime $_ })

$cleanPoints        = @()
$standingConditions = @()

if ($restorePoints.Count -gt 0) {

    # Every series seen anywhere in the store, not only in the current inventory.
    $allSeries = @()
    foreach ($entry in $catalog) {
        $allSeries += @($entry.Records | Select-Object -ExpandProperty SeriesKey)
    }
    $allSeries = @($allSeries | Sort-Object -Unique)

    foreach ($seriesKey in $allSeries) {

        # Reference band from every ratio ever recorded for this series. The
        # median survives a few encrypted entries, a mean would be dragged along
        # by them and hide exactly what is being looked for.
        $history = @()
        foreach ($entry in $catalog) {
            foreach ($r in $entry.Records) {
                if ($r.SeriesKey -eq $seriesKey -and $null -ne $r.CompressionRatio) {
                    $history += [double]$r.CompressionRatio
                }
            }
        }

        $lastClean      = $null
        $problem        = $null
        $dirtyAfter     = 0
        $isFirstSeen    = $true
        $badFromTheStart = $false

        foreach ($entry in $restorePoints) {
            $records = @($entry.Records | Where-Object { $_.SeriesKey -eq $seriesKey })
            if ($records.Count -eq 0) { continue }   # series not in this snapshot

            $bad = $null
            foreach ($r in $records) {
                $why = Get-RecordProblem -Record $r -History $history
                if ($why) { $bad = "$($r.FileName): $why"; break }
            }

            # Was the oldest snapshot holding this series already affected?
            if ($isFirstSeen) {
                $isFirstSeen = $false
                if ($bad) { $badFromTheStart = $true }
            }

            if ($bad) {
                $dirtyAfter++
                if (-not $problem) { $problem = $bad }
            }
            else {
                # A later clean snapshot resets the count: whatever was wrong
                # has been superseded by something good.
                $lastClean  = $entry
                $problem    = $null
                $dirtyAfter = 0
            }
        }

        if ($dirtyAfter -gt 0) {
            # Never clean anywhere, and already affected in the oldest snapshot,
            # means nothing got worse. That is a standing condition, not an
            # incident, and mixing the two makes the incident harder to see.
            if ($badFromTheStart -and -not $lastClean) {
                $standingConditions += [pscustomobject][ordered]@{
                    Series   = $seriesKey
                    Problem  = $problem
                    Affected = $dirtyAfter
                }
            }
            else {
                $cleanPoints += [pscustomobject][ordered]@{
                    Series       = $seriesKey
                    LastClean    = if ($lastClean) { $lastClean.Source } else { $null }
                    CleanTime    = if ($lastClean) { (Get-SourceTime $lastClean).ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
                    AffectedFrom = $dirtyAfter
                    FirstProblem = $problem
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

Write-Host ''

if ($findings.Count -eq 0) {
    Write-Host 'No findings.' -ForegroundColor Green
}
else {
    foreach ($severity in @('Alert', 'Notice', 'Info')) {
        $group = @($findings | Where-Object { $_.Severity -eq $severity })
        if ($group.Count -eq 0) { continue }

        $colour = switch ($severity) {
            'Alert'  { 'Red' }
            'Notice' { 'Yellow' }
            default  { 'Gray' }
        }

        Write-Host "$severity ($($group.Count))" -ForegroundColor $colour
        foreach ($f in $group) {
            Write-Host ("  [{0}] {1}" -f $f.Category, $f.Subject)
            Write-Host ("      {0}" -f $f.Message) -ForegroundColor DarkGray
        }
        Write-Host ''
    }
}

if ($cleanPoints.Count -gt 0) {
    Write-Host 'Possible clean restore point' -ForegroundColor Cyan
    Write-Host '----------------------------' -ForegroundColor DarkGray
    Write-Host 'Based on metadata only. A starting point for a look, not a verdict.' -ForegroundColor DarkGray
    Write-Host ''

    foreach ($cp in $cleanPoints) {
        Write-Host "  $($cp.Series)"
        if ($cp.LastClean) {
            Write-Host ("      last unremarkable: {0}  ({1})" -f $cp.LastClean, $cp.CleanTime) -ForegroundColor Green
        }
        else {
            Write-Host '      nothing unremarkable found anywhere in the store' -ForegroundColor Red
        }
        Write-Host ("      {0} later snapshot(s) look wrong, from {1}" -f $cp.AffectedFrom, $cp.FirstProblem) -ForegroundColor DarkGray
    }
    Write-Host ''
}

# Kept apart from the restore points on purpose. These series were already
# affected in the oldest snapshot, so nothing got worse and there is nothing to
# go back to. Listing them alongside real incidents only makes those harder to
# see.
if ($standingConditions.Count -gt 0) {
    Write-Host 'Standing conditions' -ForegroundColor Cyan
    Write-Host '-------------------' -ForegroundColor DarkGray
    Write-Host 'Unchanged since the oldest snapshot. Not an incident, but worth fixing.' -ForegroundColor DarkGray
    Write-Host ''

    foreach ($sc in $standingConditions) {
        Write-Host "  $($sc.Series)"
        Write-Host ("      {0}" -f $sc.Problem) -ForegroundColor DarkGray
        Write-Host ("      affects all {0} snapshot(s) holding this series" -f $sc.Affected) -ForegroundColor DarkGray
    }
    Write-Host ''
}

# Be explicit about which method judged the ratios, so nobody assumes the
# history is in play when it is not.
if ($historyUsed -or $fallbackUsed) {
    Write-Host "Compression checked against history for $historyUsed series, two-point fallback for $fallbackUsed (needs $MinHistoryPoints past values)." -ForegroundColor DarkGray
}

if (-not $OutputPath) {
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $OutputPath = ".\abr-compare-$stamp.json"
}

[pscustomobject][ordered]@{
    Baseline    = $baseLabel
    Current     = $currLabel
    ComparedAt  = (Get-Date).ToString('o')
    AlertCount  = @($findings | Where-Object { $_.Severity -eq 'Alert'  }).Count
    NoticeCount = @($findings | Where-Object { $_.Severity -eq 'Notice' }).Count
    HistoryUsed = $historyUsed
    Fallback    = $fallbackUsed
    CleanPoints        = $cleanPoints
    StandingConditions = $standingConditions
    Findings           = $findings
} | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding utf8

Write-Host "Written to $OutputPath"
