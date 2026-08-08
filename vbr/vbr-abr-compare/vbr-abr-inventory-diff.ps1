<#
.SYNOPSIS
    Compare two ABR inventory files and report what changed between them.

.DESCRIPTION
    Works on the JSON produced by vbr-abr-inventory.ps1, not on files.
    That means two snapshots never have to be mounted at the same time: mount,
    inventory, unmount, repeat - then compare the results.

    Three layers, because they answer different questions:

    1. ARCHIVE INTEGRITY
       A finished dump is immutable by nature - it is written once and never
       touched again. So an archive present in both inventories whose size,
       header or compression ratio changed has been rewritten. That is the
       strongest single signal this tool produces and it is never benign.

       Removed archives are reported too. Usually that is Proxmox retention
       doing its job, but deletion is also what an attacker does first.

    2. CONTENT DRIFT (per guest)
       Compares the newest backup of each guest in the baseline against the
       newest in the current inventory.

         Compression ratio collapse. Encrypted data does not compress, so a
         guest whose ratio has fallen to roughly 1.0 has encrypted content.
         The ransomware signal, obtained without ever reading the payload.

         This is judged on the absolute ratio, not on a percentage drop.
         Encryption is not gradual: either data has structure and compresses,
         or it does not. A guest that went from 3.24 to 2.20 is showing normal
         variation, while one that went from 1.15 to 1.02 has been encrypted
         even though the percentage barely moved.

         Guests that never compressed well, media stores and the like, sit
         near 1.0 permanently and would alert on every run. BaselineMinRatio
         excludes them. Compression is simply not a usable signal there, and
         saying so is more honest than reporting a number that means nothing.

         Size jump. Abrupt growth or shrinkage means the guest is no longer
         what it was, or the dump was truncated.

    3. COVERAGE
       Guests present in the baseline but missing from the current inventory.
       An ABR has no job success event, so a source that silently stopped
       writing looks exactly like one that is working. Nothing else catches it.

.PARAMETER Baseline
    The older side, given as a source name - 'snapshot_20260808_101940', not a
    file path. Also accepts:
        latest    the most recently scanned inventory other than -Current
        previous  same thing, kept as a readable alias
    Leave it empty to pick from a list.

.PARAMETER Current
    The newer side. Defaults to 'live'.

.PARAMETER List
    Show the available inventories and exit.

.PARAMETER MinRatio
    Alert when a guest's compression ratio falls below this. Default 1.2.
    Encrypted data lands between 1.0 and 1.05, and a real file system does not
    get there on its own.

.PARAMETER BaselineMinRatio
    Only alert when the baseline ratio was above this. Default 1.5. Keeps
    guests that never compressed well from alerting on every single run.

.PARAMETER RatioDropPercent
    Report a notice when the ratio falls by at least this much without dropping
    below MinRatio. Default 30. This is drift worth a look, not an alert.

.PARAMETER SizeChangePercent
    Flag a guest when its archive size changes by at least this much. Default 50.

.EXAMPLE
    .\vbr-abr-inventory-diff.ps1 -List

.EXAMPLE
    .\vbr-abr-inventory-diff.ps1
    Pick the baseline interactively, compare against 'live'.

.EXAMPLE
    .\vbr-abr-inventory-diff.ps1 -Baseline snapshot_20260808_101940

.EXAMPLE
    .\vbr-abr-inventory-diff.ps1 -Baseline latest
    Compare 'live' against whichever snapshot was inventoried most recently.
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

    [int]$SizeChangePercent = 50,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Inventory store
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
            $source  = if ($records.Count) { $records[0].Source } else { $file.BaseName -replace '^inv-', '' }
            $scanned = if ($records.Count) { $records[0].ScannedAt } else { $null }

            $entries += [pscustomobject][ordered]@{
                Source      = $source
                BackupCount = $records.Count
                ScannedAt   = $scanned
                Path        = $file.FullName
                Records     = $records
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

$catalog = Get-InventoryCatalog -StorePath $InventoryStore

$entryFormatter = {
    param($e)
    "{0,-32} {1,2} backup(s)   scanned {2}" -f $e.Source, $e.BackupCount, $e.ScannedAt
}

if ($List -or $catalog.Count -eq 0) {
    Write-Host ''
    Write-Host "Inventories in $InventoryStore" -ForegroundColor Cyan
    if ($catalog.Count -eq 0) {
        Write-Host '  (none - run vbr-abr-inventory.ps1 first)' -ForegroundColor Yellow
    }
    else {
        foreach ($e in $catalog) { Write-Host "  $(& $entryFormatter $e)" }
    }
    return
}

# ---------------------------------------------------------------------------
# Resolve both sides
# ---------------------------------------------------------------------------

$currentEntry = $catalog | Where-Object { $_.Source -eq $Current } | Select-Object -First 1
if (-not $currentEntry) {
    throw "No inventory for '$Current'. Available: $((($catalog | ForEach-Object { $_.Source }) -join ', '))"
}

$candidates = @($catalog | Where-Object { $_.Source -ne $currentEntry.Source })
if ($candidates.Count -eq 0) {
    throw "Only '$($currentEntry.Source)' exists - nothing to compare against."
}

$baselineEntry = $null

if (-not $Baseline) {
    Write-Host ''
    Write-Host "Compare against '$($currentEntry.Source)'" -ForegroundColor Cyan
    $baselineEntry = Select-FromList -Items $candidates -Prompt 'Select baseline' -Formatter $entryFormatter
    if (-not $baselineEntry) { Write-Host 'Cancelled.'; return }
}
elseif ($Baseline -in @('latest', 'previous')) {
    # Catalog is sorted newest first.
    $baselineEntry = $candidates[0]
}
else {
    $baselineEntry = $candidates | Where-Object { $_.Source -like $Baseline } | Select-Object -First 1
    if (-not $baselineEntry) {
        throw "No inventory matches '$Baseline'. Available: $((($candidates | ForEach-Object { $_.Source }) -join ', '))"
    }
}

$baseRecords = $baselineEntry.Records
$currRecords = $currentEntry.Records

$baseLabel = $baselineEntry.Source
$currLabel = $currentEntry.Source

Write-Host ''
Write-Host "Baseline: $baseLabel  ($($baseRecords.Count) backup(s))" -ForegroundColor Cyan
Write-Host "Current : $currLabel  ($($currRecords.Count) backup(s))" -ForegroundColor Cyan

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
# 1. Archive integrity - keyed on file name
# ---------------------------------------------------------------------------

$baseByFile = @{}
foreach ($r in $baseRecords) { $baseByFile[$r.FileName] = $r }

$currByFile = @{}
foreach ($r in $currRecords) { $currByFile[$r.FileName] = $r }

foreach ($name in $currByFile.Keys) {
    if (-not $baseByFile.ContainsKey($name)) {
        Add-Finding -Severity 'Info' -Category 'ArchiveAdded' -Subject $name `
            -Message "new backup, $([math]::Round($currByFile[$name].ArchiveBytes / 1MB, 1)) MB"
    }
}

foreach ($name in $baseByFile.Keys) {
    if (-not $currByFile.ContainsKey($name)) {
        Add-Finding -Severity 'Notice' -Category 'ArchiveRemoved' -Subject $name `
            -Message 'present in baseline, gone now - retention, or deletion'
        continue
    }

    # Present in both. A finished dump is never rewritten, so any difference
    # here means someone touched it.
    $b = $baseByFile[$name]
    $c = $currByFile[$name]

    if ($b.ArchiveBytes -ne $c.ArchiveBytes) {
        Add-Finding -Severity 'Alert' -Category 'ArchiveModified' -Subject $name `
            -Message "size changed $($b.ArchiveBytes) -> $($c.ArchiveBytes) bytes on an archive that should be immutable"
    }
    if ($b.MagicOk -ne $c.MagicOk) {
        Add-Finding -Severity 'Alert' -Category 'ArchiveModified' -Subject $name `
            -Message "header validity changed $($b.MagicOk) -> $($c.MagicOk)"
    }
    if ($b.CompressionRatio -and $c.CompressionRatio -and $b.CompressionRatio -ne $c.CompressionRatio) {
        Add-Finding -Severity 'Alert' -Category 'ArchiveModified' -Subject $name `
            -Message "compression ratio changed $($b.CompressionRatio) -> $($c.CompressionRatio)"
    }
    if ($b.LogResult -ne $c.LogResult) {
        Add-Finding -Severity 'Alert' -Category 'LogModified' -Subject $name `
            -Message "log result changed $($b.LogResult) -> $($c.LogResult)"
    }
}

# ---------------------------------------------------------------------------
# 2. Content drift - newest backup per guest
# ---------------------------------------------------------------------------

function Get-NewestPerGuest {
    param([array]$Records)
    $map = @{}
    foreach ($r in $Records) {
        $key = "$($r.VmId)"
        if (-not $map.ContainsKey($key) -or $r.BackupTime -gt $map[$key].BackupTime) {
            $map[$key] = $r
        }
    }
    return $map
}

$baseNewest = Get-NewestPerGuest -Records $baseRecords
$currNewest = Get-NewestPerGuest -Records $currRecords

foreach ($vmid in $currNewest.Keys) {
    if (-not $baseNewest.ContainsKey($vmid)) {
        $c = $currNewest[$vmid]
        Add-Finding -Severity 'Info' -Category 'GuestAdded' -Subject "VM $vmid ($($c.CtName))" `
            -Message 'not in baseline - new guest, or newly backed up'
        continue
    }

    $b = $baseNewest[$vmid]
    $c = $currNewest[$vmid]
    $subject = "VM $vmid ($($c.CtName))"

    # Same backup on both sides means nothing new was written for this guest.
    if ($b.FileName -eq $c.FileName) {
        Add-Finding -Severity 'Notice' -Category 'NoNewBackup' -Subject $subject `
            -Message "newest backup is still $($b.BackupTime) - nothing written since the baseline"
        continue
    }

    # The ransomware signal: compression stops working because the content is
    # already encrypted.
    #
    # Judged on the absolute ratio rather than a percentage drop. A fall from
    # 3.24 to 2.20 is 32% and completely normal; a fall from 1.15 to 1.02 is
    # 11% and means the data was encrypted. BaselineMinRatio keeps guests that
    # never compressed well from alerting on every run.
    if ($b.CompressionRatio -and $c.CompressionRatio) {
        $drop = (1 - ($c.CompressionRatio / $b.CompressionRatio)) * 100

        if ($c.CompressionRatio -lt $MinRatio -and $b.CompressionRatio -ge $BaselineMinRatio) {
            Add-Finding -Severity 'Alert' -Category 'CompressionCollapse' -Subject $subject `
                -Message "compression ratio $($b.CompressionRatio) to $($c.CompressionRatio). The data no longer compresses, which is what encryption looks like"
        }
        elseif ($drop -ge $RatioDropPercent) {
            Add-Finding -Severity 'Notice' -Category 'CompressionDrop' -Subject $subject `
                -Message "compression ratio fell $([math]::Round($drop))% ($($b.CompressionRatio) to $($c.CompressionRatio)), still above $MinRatio"
        }
    }

    if ($b.ArchiveBytes -gt 0) {
        $change = (($c.ArchiveBytes - $b.ArchiveBytes) / $b.ArchiveBytes) * 100
        if ([math]::Abs($change) -ge $SizeChangePercent) {
            $direction = if ($change -gt 0) { 'grew' } else { 'shrank' }
            Add-Finding -Severity 'Notice' -Category 'SizeJump' -Subject $subject `
                -Message "archive $direction by $([math]::Round([math]::Abs($change)))% ($($b.ArchiveBytes) -> $($c.ArchiveBytes) bytes)"
        }
    }

    if ($c.LogResult -ne 'Success') {
        Add-Finding -Severity 'Alert' -Category 'BackupFailed' -Subject $subject `
            -Message "newest backup log result: $($c.LogResult)"
    }

    if ($c.MagicOk -eq $false) {
        Add-Finding -Severity 'Alert' -Category 'BadHeader' -Subject $subject `
            -Message "newest backup has an invalid header: $($c.MagicNote)"
    }

    if ($c.ContainsDisks -eq $false -and $b.ContainsDisks -ne $false) {
        Add-Finding -Severity 'Alert' -Category 'EmptyBackup' -Subject $subject `
            -Message 'backup no longer contains data, but still reports success'
    }
}

# ---------------------------------------------------------------------------
# 3. Coverage - who stopped writing
# ---------------------------------------------------------------------------

foreach ($vmid in $baseNewest.Keys) {
    if (-not $currNewest.ContainsKey($vmid)) {
        $b = $baseNewest[$vmid]
        Add-Finding -Severity 'Alert' -Category 'GuestDisappeared' -Subject "VM $vmid ($($b.CtName))" `
            -Message 'was backed up in the baseline, has no backup at all now'
    }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

Write-Host ''

if ($findings.Count -eq 0) {
    Write-Host 'No differences.' -ForegroundColor Green
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

if (-not $OutputPath) {
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $OutputPath = ".\abr-compare-$stamp.json"
}

[pscustomobject][ordered]@{
    Baseline     = $baseLabel
    Current      = $currLabel
    ComparedAt   = (Get-Date).ToString('o')
    AlertCount   = @($findings | Where-Object { $_.Severity -eq 'Alert'  }).Count
    NoticeCount  = @($findings | Where-Object { $_.Severity -eq 'Notice' }).Count
    Findings     = $findings
} | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding utf8

Write-Host "Written to $OutputPath"
