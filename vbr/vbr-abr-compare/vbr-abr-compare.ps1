<#
.SYNOPSIS
    One command: mount the live repository, pick a snapshot, mount that too,
    inventory both, compare them, clean everything up.

.DESCRIPTION
    This is the whole workflow. It orchestrates the other three scripts so you
    do not have to:

      1. Connect to the VBR server and find the repository
      2. Mount the live repository export read-only
      3. Inventory it
      4. List the available snapshots and pick one
      5. Expose that snapshot read-only via Instant Recovery and mount it
      6. Inventory it
      7. Unmount both, stop the Instant Recovery
      8. Compare the two inventories

    Snapshot selection works interactively or by parameter:
      -Snapshot <name>      exact name, wildcards allowed
      -Snapshot latest      the most recent snapshot
      (omitted)             pick from a list

    CLEANUP
    Both mounts and the Instant Recovery are torn down in the finally block, so
    it also happens on error or Ctrl+C. The comparison runs afterwards, on the
    inventory files - nothing needs to stay mounted for it.

.NOTES
    Run on the Windows VBR server. Needs the NFS client feature
    (Install-WindowsFeature NFS-Client) and the Backup Administrator role.

    The live export path is derived from the repository object:
        <repo host>:/<ZFSPool>/<MountPath>
    which matches what showmount reports.

.PARAMETER VbrServer
    The VBR server. Defaults to 'localhost' for a run on the backup server
    itself. When the client runs on a separate host - the recommended setup,
    since the machine parsing backup content should not be the backup server -
    give the server here. The script then prompts for credentials, which are
    kept in memory for the session and never written to disk. Pass -Credential
    instead when running unattended.

.PARAMETER AllowFrom
    Host or network permitted to mount the snapshot export, e.g. '10.10.11.240'.
    Without it Veeam creates the clone but no NFS export, leaving nothing to
    mount. The live export uses the permissions already configured on the
    repository, so this only affects the snapshot.

.EXAMPLE
    .\vbr-abr-compare.ps1 -Abr abr-repo01 -AllowFrom 10.10.11.240
    Interactive snapshot selection.

.EXAMPLE
    .\vbr-abr-compare.ps1 -Abr abr-repo01 -AllowFrom 10.10.11.240 -Snapshot latest

.EXAMPLE
    .\vbr-abr-compare.ps1 -Abr abr-repo01 -AllowFrom 10.10.11.240 -Snapshot 'snapshot_20260808_*'

.EXAMPLE
    .\vbr-abr-compare.ps1 -VbrServer vbr-01.lab.local -Abr abr-repo01 -AllowFrom 10.10.11.55
    Client on a separate host. Prompts for credentials; note that -AllowFrom
    must be the IP of the machine doing the mounting, not the VBR server.
#>

[CmdletBinding()]
param(
    # Defaults to localhost for a run on the backup server itself. Point it
    # elsewhere when the client runs on a separate host, which is the
    # recommended setup - the machine parsing backup content should not be the
    # backup server.
    [string]$VbrServer = 'localhost',

    # Optional. For a remote VbrServer the script prompts when this is omitted.
    # Nothing is stored: the credential exists in this session only and never
    # touches disk.
    [System.Management.Automation.PSCredential]$Credential,

    [string]$Abr,

    # Empty = interactive, 'latest', or a name/wildcard.
    [string]$Snapshot,

    [Parameter(Mandatory)]
    [string]$AllowFrom,

    [string]$LiveDrive = 'Y:',

    [string]$SnapshotDrive = 'Z:',

    # Name of the temporary NFS export. Defaults to "<repository>-ir".
    [string]$MountPath,

    [string]$Reason = 'Automated backup comparison',

    [string]$InventoryStore = '.\inventory',

    # Alert when a guest's compression ratio drops below this, but only if the
    # baseline was above BaselineMinRatio. Encryption pushes the ratio to about
    # 1.0; guests that never compressed well would otherwise alert every run.
    [double]$MinRatio = 1.2,

    [double]$BaselineMinRatio = 1.5,

    # Ratio drift that stays above MinRatio is reported as a notice, not an alert.
    [int]$RatioDropPercent = 30,

    [int]$SizeChangePercent = 50
)

$ErrorActionPreference = 'Stop'

$InventoryScript = Join-Path $PSScriptRoot 'vbr-abr-inventory.ps1'
$CompareScript   = Join-Path $PSScriptRoot 'vbr-abr-inventory-diff.ps1'

foreach ($required in @($InventoryScript, $CompareScript)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing helper script: $required"
    }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Head {
    param([string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('-' * $Text.Length) -ForegroundColor DarkGray
}

function Get-RepositoryHostName {
    param($Repository)
    $srv = $Repository.Server
    if ($srv) {
        if ($srv.Info -and $srv.Info.DnsName) { return "$($srv.Info.DnsName)" }
        if ($srv.Name)                        { return "$($srv.Name)" }
    }
    return $null
}

# 'mount' is an alias for New-PSDrive, hence mount.exe. A freshly created
# export is not reachable immediately, so retry briefly.
function Mount-NfsPath {
    param(
        [Parameter(Mandatory)][string]$NfsPath,
        [Parameter(Mandatory)][string]$Drive,
        [int]$MaxAttempts = 5
    )

    # 'anon,ro' must be quoted - unquoted it is a PowerShell array literal.
    $mountArgs = @('-o', 'anon,ro', $NfsPath, $Drive)
    Write-Host "  mount.exe $($mountArgs -join ' ')" -ForegroundColor DarkGray

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $output = & mount.exe @mountArgs 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  mounted on $Drive" -ForegroundColor Green
            return $true
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Host "  attempt $attempt failed, retrying in 3s ..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 3
        }
        else {
            Write-Warning "mount.exe failed after $MaxAttempts attempts (exit $LASTEXITCODE): $output"
        }
    }
    return $false
}

function Dismount-NfsDrive {
    param([string]$Drive)
    try {
        $output = & umount.exe -f $Drive 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  unmounted $Drive" -ForegroundColor Green
        }
        else {
            Write-Warning "umount.exe $Drive failed (exit $LASTEXITCODE): $output"
        }
    }
    catch {
        Write-Warning "umount $Drive failed: $($_.Exception.Message)"
    }
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
# Connect
# ---------------------------------------------------------------------------

$isLocalServer = $VbrServer -in @('localhost', '.', '127.0.0.1', $env:COMPUTERNAME)

# A remote server needs credentials. Ask up front instead of failing later with
# an opaque authentication error. Get-Credential keeps the password in memory
# for this session only - it is never written anywhere.
if (-not $Credential -and -not $isLocalServer) {
    $Credential = Get-Credential -Message "Credentials for VBR server $VbrServer"
    if (-not $Credential) { throw 'No credentials supplied.' }
}

try {
    if ($Credential) { Connect-VBRServer -Server $VbrServer -Credential $Credential -ErrorAction Stop }
    else             { Connect-VBRServer -Server $VbrServer -ErrorAction Stop }
}
catch {
    throw "Failed to connect to '$VbrServer': $($_.Exception.Message)"
}

$liveMounted     = $false
$snapMounted     = $false
$recoverySession = $null
$readyToCompare  = $false
$snapshotLabel   = $null

try {
    # -----------------------------------------------------------------------
    # 1. Repository
    # -----------------------------------------------------------------------

    $repositories = @(Get-VBRApplicationBackupRepository -ErrorAction Stop)
    if ($repositories.Count -eq 0) { throw 'No Application Backup Repositories found.' }

    $selectedRepo = $null
    if ($Abr) {
        $hits = @($repositories | Where-Object { $_.Name -like $Abr })
        if ($hits.Count -eq 0) {
            throw "No repository matches '$Abr'. Available: $((($repositories | ForEach-Object { $_.Name }) -join ', '))"
        }
        if ($hits.Count -gt 1) {
            throw "'$Abr' is ambiguous: $((($hits | ForEach-Object { $_.Name }) -join ', '))"
        }
        $selectedRepo = $hits[0]
    }
    elseif ($repositories.Count -eq 1) {
        $selectedRepo = $repositories[0]
    }
    else {
        Write-Head 'Application Backup Repositories'
        $selectedRepo = Select-FromList -Items $repositories -Prompt 'Select repository' -Formatter {
            param($r) "{0}  [retention {1}d]" -f $r.Name, $r.RetentionDays
        }
        if (-not $selectedRepo) { Write-Host 'Cancelled.'; return }
    }

    $repoHost = Get-RepositoryHostName -Repository $selectedRepo
    if (-not $repoHost) { throw 'Could not determine the repository host name.' }

    Write-Host ''
    Write-Host "Repository : $($selectedRepo.Name)"
    Write-Host "Host       : $repoHost"
    Write-Host "ZFS pool   : $($selectedRepo.ZFSPool)"

    # -----------------------------------------------------------------------
    # 2. Mount the live export
    # -----------------------------------------------------------------------

    Write-Head "Mounting live repository on $LiveDrive"

    $livePath = "${repoHost}:/$($selectedRepo.ZFSPool)/$($selectedRepo.MountPath)"
    $liveMounted = Mount-NfsPath -NfsPath $livePath -Drive $LiveDrive

    if (-not $liveMounted) {
        throw "Could not mount the live repository. Do the repository permissions cover this machine?"
    }

    # -----------------------------------------------------------------------
    # 3. Inventory live
    # -----------------------------------------------------------------------

    Write-Head 'Inventory: live'
    & $InventoryScript -Path "$LiveDrive\" -Source 'live' -InventoryStore $InventoryStore

    # -----------------------------------------------------------------------
    # 4. Pick a snapshot
    # -----------------------------------------------------------------------

    $snapRepoParam = $null
    $getSnapCmd = Get-Command 'Get-VBRApplicationBackupSnapshot'
    foreach ($candidate in @('Repository', 'ApplicationBackupRepository', 'InputObject')) {
        if ($getSnapCmd.Parameters.ContainsKey($candidate)) { $snapRepoParam = $candidate; break }
    }
    if (-not $snapRepoParam) {
        $snapRepoParam = $getSnapCmd.Parameters.Keys | Where-Object { $_ -match 'Repositor' } | Select-Object -First 1
    }

    $getSnapSplat = @{ $snapRepoParam = $selectedRepo; ErrorAction = 'Stop' }
    $snapshots = @(Get-VBRApplicationBackupSnapshot @getSnapSplat | Sort-Object CreationTime -Descending)

    if ($snapshots.Count -eq 0) { throw 'No snapshots in this repository - nothing to compare against.' }

    $snapFormatter = { param($s) "{0}  ({1})" -f $s.Name, $s.CreationTime }

    $selectedSnapshot = $null
    if (-not $Snapshot) {
        Write-Head 'Available snapshots'
        $selectedSnapshot = Select-FromList -Items $snapshots -Prompt 'Select snapshot to compare against live' -Formatter $snapFormatter
        if (-not $selectedSnapshot) { Write-Host 'Cancelled.'; return }
    }
    elseif ($Snapshot -eq 'latest') {
        $selectedSnapshot = $snapshots[0]
        Write-Host ''
        Write-Host "Snapshot   : $(& $snapFormatter $selectedSnapshot)"
    }
    else {
        $selectedSnapshot = $snapshots | Where-Object { $_.Name -like $Snapshot } | Select-Object -First 1
        if (-not $selectedSnapshot) {
            throw "No snapshot matches '$Snapshot'. Available: $((($snapshots | ForEach-Object { $_.Name }) -join ', '))"
        }
        Write-Host ''
        Write-Host "Snapshot   : $(& $snapFormatter $selectedSnapshot)"
    }

    $snapshotLabel = $selectedSnapshot.Name

    # -----------------------------------------------------------------------
    # 5. Expose and mount the snapshot
    # -----------------------------------------------------------------------

    if (-not $MountPath) { $MountPath = "$($selectedRepo.Name)-ir" }
    if ($MountPath -eq $selectedRepo.MountPath) {
        throw "MountPath '$MountPath' collides with the live repository export."
    }

    Write-Head "Exposing snapshot read-only to $AllowFrom"

    $permission = New-VBRApplicationBackupRepositoryPermission -ServerName $AllowFrom -Mode Read

    $recoverySession = Start-VBRApplicationBackupSnapshotInstantRecovery `
        -Snapshot              $selectedSnapshot `
        -MountPath             $MountPath `
        -RepositoryPermissions $permission `
        -Reason                $Reason `
        -Force `
        -ErrorAction Stop

    $snapPath = "${repoHost}:/$($recoverySession.Name)"
    Write-Host "  NFS path: $snapPath"

    $snapMounted = Mount-NfsPath -NfsPath $snapPath -Drive $SnapshotDrive
    if (-not $snapMounted) { throw 'Could not mount the snapshot export.' }

    # -----------------------------------------------------------------------
    # 6. Inventory the snapshot
    # -----------------------------------------------------------------------

    Write-Head "Inventory: $snapshotLabel"
    & $InventoryScript -Path "$SnapshotDrive\" -Source $snapshotLabel -InventoryStore $InventoryStore

    $readyToCompare = $true
}
finally {
    Write-Head 'Cleanup'

    if ($snapMounted) { Dismount-NfsDrive -Drive $SnapshotDrive }
    if ($liveMounted) { Dismount-NfsDrive -Drive $LiveDrive }

    if ($recoverySession) {
        try {
            Stop-VBRApplicationBackupSnapshotInstantRecovery -Session $recoverySession -ErrorAction Stop
            Write-Host '  Instant Recovery stopped' -ForegroundColor Green
        }
        catch {
            Write-Warning "STOP FAILED: $($_.Exception.Message)"
            Write-Warning "Session id $($recoverySession.Id) may still be exposed - check the Veeam console."
        }
    }

    try { Disconnect-VBRServer -ErrorAction SilentlyContinue } catch { }
}

# ---------------------------------------------------------------------------
# 7. Compare - runs on the inventory files, nothing needs to stay mounted
# ---------------------------------------------------------------------------

if ($readyToCompare) {
    Write-Head "Comparing $snapshotLabel against live"

    & $CompareScript `
        -Baseline          $snapshotLabel `
        -Current           'live' `
        -InventoryStore    $InventoryStore `
        -MinRatio          $MinRatio `
        -BaselineMinRatio  $BaselineMinRatio `
        -RatioDropPercent  $RatioDropPercent `
        -SizeChangePercent $SizeChangePercent
}
