<#
.SYNOPSIS
    Expose an Application Backup Repository snapshot read-only via Instant
    Recovery, optionally mount it as a drive, tear everything down afterwards.

.DESCRIPTION
    Modes:

      Interactive     No -Abr: pick a repository, then a snapshot from a list.
      Non-interactive With -Abr <name>: runs without prompts.
      List only       -List: show repositories and exit.
      Dry run         -DryRun: show what would happen, change nothing.

    ACCESS CONTROL
    A snapshot exposed without permissions gets no NFS export at all - the ZFS
    clone exists but nothing can reach it. So -AllowFrom is required for a real
    run. Access defaults to 'Read', because analysis never needs to write and a
    read-only export cannot corrupt the clone.

    CLEANUP
    Unmount and stop both happen in the finally block, so they also run on error
    or Ctrl+C. A running Instant Recovery is an open data window. If the
    PowerShell process is killed outright nothing can help - tear the mount down
    from the Veeam console in that case.

    Every session is appended to -AuditLog as one JSON line. Veeam itself also
    records the -Reason string, so the trail exists on both sides.

.NOTES
    Run this on the Windows VBR server. Veeam PowerShell on Linux is not an
    option here: it only supports Kerberos, and a non-domain-joined backup
    server means NTLM. That is a hard limit, not a configuration issue.

    Mounting needs the NFS client feature:  Install-WindowsFeature NFS-Client
    Note that 'mount' in PowerShell is an alias for New-PSDrive - the script
    calls mount.exe and umount.exe explicitly for that reason.

    Verified object shapes and parameters:

      VBRApplicationBackupRepository
        Name, Id, Description, Server, ZFSPool, MountPath, RetentionDays,
        RepositoryPermissions[], KerberosPermissions[], ScheduleOptions

      VBRApplicationBackupSnapshot
        Name, Id, RepositoryId, CreationTime
        Nothing else - no size, no immutability state, no checksum. Anything
        content-related has to come from the mount.
        The snapshot name carries a UTC timestamp while CreationTime is local.

      Start-VBRApplicationBackupSnapshotInstantRecovery
        -Snapshot -MountPath -RepositoryPermissions -Reason -Force
        -EnableKerberosPermissions -KerberosPermissions
        Returns a VBRSession.

      Stop-VBRApplicationBackupSnapshotInstantRecovery -Session

      New-VBRApplicationBackupRepositoryPermission -ServerName -Mode
        Mode is 'Read' or 'ReadWrite'. There is no 'ReadOnly'.

.EXAMPLE
    .\vbr-abr-mount.ps1 -List

.EXAMPLE
    .\vbr-abr-mount.ps1 -Abr 'abr-repo01' -AllowFrom '10.10.11.0/24' -DryRun

.EXAMPLE
    .\vbr-abr-mount.ps1 -Abr 'abr-repo01' -AllowFrom '10.10.11.0/24' -MountDrive Z:
    Expose the newest snapshot read-only, mount it on Z:, wait for ENTER, then
    unmount and stop.

.EXAMPLE
    .\vbr-abr-mount.ps1 -Abr 'abr-repo01' -AllowFrom '10.10.11.15' -MountDrive Z: -AutoStopAfterSeconds 600 -Reason 'Weekly config diff'
    Unattended run, tears itself down after ten minutes.
#>

[CmdletBinding()]
param(
    # Defaults to localhost for a run on the backup server itself. Point it
    # elsewhere when the client runs on a separate host.
    [string]$VbrServer = 'localhost',

    # Optional. For a remote VbrServer the script prompts when this is omitted.
    # Nothing is stored - the credential exists in this session only.
    [System.Management.Automation.PSCredential]$Credential,

    # Repository name. Empty means interactive selection. Wildcards allowed.
    [string]$Abr,

    # 'latest', or a snapshot name/id.
    [string]$Snapshot = 'latest',

    # Name of the temporary NFS export. Defaults to "<repository>-ir".
    [string]$MountPath,

    # Hosts or networks allowed to mount, e.g. '10.10.11.15' or '10.10.11.0/24'.
    # Without this no NFS export is created and nothing can be mounted.
    [string[]]$AllowFrom,

    # Veeam only offers these two. 'Read' is what analysis needs.
    [ValidateSet('Read', 'ReadWrite')]
    [string]$AccessMode = 'Read',

    # Recorded by Veeam in its own session log.
    [string]$Reason = 'Automated security analysis',

    # Drive letter to mount on, e.g. 'Z:'. Empty means print the command only.
    [string]$MountDrive,

    [switch]$List,

    [switch]$DryRun,

    # 0 waits for ENTER. Greater than 0 tears down after n seconds.
    [int]$AutoStopAfterSeconds = 0,

    [int]$ExpandDepth = 2,

    [string]$AuditLog = './abr-recovery-audit.jsonl'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Head {
    param([string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('-' * $Text.Length) -ForegroundColor DarkGray
}

function Get-FirstProperty {
    param($InputObject, [string[]]$Names)
    foreach ($name in $Names) {
        $prop = $InputObject.PSObject.Properties[$name]
        if ($prop -and $null -ne $prop.Value) { return $prop.Value }
    }
    return $null
}

function Get-DisplayName {
    param($InputObject)
    $value = Get-FirstProperty -InputObject $InputObject -Names @('Name', 'Id', 'Uid')
    if ($null -ne $value) { return "$value" }
    return "$InputObject"
}

function Test-IsVeeamObject {
    param($Value)
    if ($null -eq $Value) { return $false }
    return $Value.GetType().FullName.StartsWith('Veeam.')
}

# Veeam objects contain circular references, so ConvertTo-Json is not an option.
function Show-ObjectTree {
    param(
        $InputObject,
        [int]$Depth = 0,
        [int]$MaxDepth = 2,
        # The host object alone is ~40 lines that say nothing about the repository.
        [string[]]$NoExpand = @('Server')
    )

    $indent = '    ' + ('    ' * $Depth)
    Write-Host "$indent[$($InputObject.GetType().Name)]" -ForegroundColor DarkGray

    foreach ($prop in $InputObject.PSObject.Properties) {
        try {
            $value = $prop.Value

            if ($null -eq $value) {
                Write-Host ("{0}{1,-28} = <null>" -f $indent, $prop.Name)
                continue
            }

            if ($value -isnot [string] -and $value -is [System.Collections.IEnumerable]) {
                $items = @($value)
                Write-Host ("{0}{1,-28} = [{2}, Count={3}]" -f $indent, $prop.Name, $value.GetType().Name, $items.Count)

                if ($Depth -lt $MaxDepth -and $items.Count -gt 0 -and (Test-IsVeeamObject $items[0])) {
                    for ($i = 0; $i -lt $items.Count; $i++) {
                        Write-Host ("{0}    ({1})" -f $indent, $i) -ForegroundColor DarkGray
                        Show-ObjectTree -InputObject $items[$i] -Depth ($Depth + 2) -MaxDepth $MaxDepth -NoExpand $NoExpand
                    }
                }
                continue
            }

            if ((Test-IsVeeamObject $value) -and $Depth -lt $MaxDepth -and $prop.Name -notin $NoExpand) {
                Write-Host ("{0}{1,-28} =" -f $indent, $prop.Name)
                Show-ObjectTree -InputObject $value -Depth ($Depth + 1) -MaxDepth $MaxDepth -NoExpand $NoExpand
                continue
            }

            if (Test-IsVeeamObject $value) {
                Write-Host ("{0}{1,-28} = {2}" -f $indent, $prop.Name, (Get-DisplayName $value))
                continue
            }

            Write-Host ("{0}{1,-28} = {2}" -f $indent, $prop.Name, $value)
        }
        catch {
            Write-Host ("{0}{1,-28} = <not readable>" -f $indent, $prop.Name)
        }
    }
}

function Select-FromList {
    param(
        [Parameter(Mandatory)][array]$Items,
        [Parameter(Mandatory)][string]$Prompt,
        [scriptblock]$Formatter
    )

    if ($Items.Count -eq 0) { return $null }

    for ($i = 0; $i -lt $Items.Count; $i++) {
        $label = if ($Formatter) { & $Formatter $Items[$i] } else { Get-DisplayName $Items[$i] }
        Write-Host ("  [{0,2}] {1}" -f ($i + 1), $label)
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

function Write-AuditEntry {
    param([hashtable]$Entry)
    try {
        $Entry['User'] = "$([Environment]::UserName)"
        $Entry['Host'] = "$([Environment]::MachineName)"
        ([pscustomobject]$Entry | ConvertTo-Json -Depth 4 -Compress) |
            Out-File -FilePath $AuditLog -Append -Encoding utf8
    }
    catch {
        Write-Warning "Audit log not writable: $($_.Exception.Message)"
    }
}

# The repository host exports the NFS share - not the VBR server this runs on.
function Get-RepositoryHostName {
    param($Repository)
    $srv = $Repository.Server
    if ($srv) {
        if ($srv.Info -and $srv.Info.DnsName) { return "$($srv.Info.DnsName)" }
        if ($srv.Name)                        { return "$($srv.Name)" }
    }
    return $null
}

# Session.Name is the ZFS dataset path, e.g. 'pool-name/abr-repo01-ir'.
# The NFS export is that path with a leading slash.
#
# Use the Unix notation host:/path, not the UNC form \\host\a\b - Windows
# mount.exe fails with "Network Error - 53" on multi-level UNC export paths
# even when the export exists and permissions are correct.
function Get-NfsPath {
    param([string]$HostName, $Session)
    $dataset = "$($Session.Name)".Trim('/')
    if (-not $HostName -or -not $dataset) { return $null }
    return "${HostName}:/${dataset}"
}

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------

$isLocalServer = $VbrServer -in @('localhost', '.', '127.0.0.1', $env:COMPUTERNAME)

# Ask for credentials up front on a remote server rather than failing later
# with an opaque authentication error. Never stored, session only.
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

$recoverySession = $null
$mountedDrive    = $null
$startTime       = $null
$auditContext    = @{}

try {
    # -----------------------------------------------------------------------
    # 1. Repositories
    # -----------------------------------------------------------------------

    Write-Head 'Application Backup Repositories'

    $repositories = @(Get-VBRApplicationBackupRepository -ErrorAction Stop)

    if ($repositories.Count -eq 0) {
        Write-Host 'No repositories found.' -ForegroundColor Yellow
        return
    }

    $repoFormatter = {
        param($r)
        $parts = @()
        if ($null -ne $r.RetentionDays) { $parts += "retention $($r.RetentionDays)d" }
        if ($r.RepositoryPermissions)   { $parts += "$(@($r.RepositoryPermissions).Count) perm" }
        if ($r.MountPath)               { $parts += "mount: $($r.MountPath)" }
        "{0}  [{1}]" -f (Get-DisplayName $r), ($parts -join ', ')
    }

    if ($List) {
        foreach ($repo in $repositories) {
            Write-Host ''
            Write-Host (Get-DisplayName $repo) -ForegroundColor White
            Show-ObjectTree -InputObject $repo -MaxDepth $ExpandDepth
        }
        return
    }

    # -----------------------------------------------------------------------
    # 2. Pick a repository
    # -----------------------------------------------------------------------

    $selectedRepo = $null

    if ($Abr) {
        $hits = @($repositories | Where-Object { (Get-DisplayName $_) -like $Abr })
        if ($hits.Count -eq 0) {
            throw "No repository matches '$Abr'. Available: $((($repositories | ForEach-Object { Get-DisplayName $_ }) -join ', '))"
        }
        if ($hits.Count -gt 1) {
            throw "'$Abr' is ambiguous: $((($hits | ForEach-Object { Get-DisplayName $_ }) -join ', '))"
        }
        $selectedRepo = $hits[0]
        Write-Host "Repository: $(Get-DisplayName $selectedRepo)"
    }
    else {
        $selectedRepo = Select-FromList -Items $repositories -Prompt 'Select repository' -Formatter $repoFormatter
        if (-not $selectedRepo) { Write-Host 'Cancelled.'; return }
    }

    # -----------------------------------------------------------------------
    # 3. Snapshots
    # -----------------------------------------------------------------------

    Write-Head "Snapshots in '$(Get-DisplayName $selectedRepo)'"

    # This one parameter name is still unconfirmed, so resolve it at runtime.
    $snapRepoParam = $null
    $getSnapCmd = Get-Command 'Get-VBRApplicationBackupSnapshot'
    foreach ($candidate in @('Repository', 'ApplicationBackupRepository', 'InputObject')) {
        if ($getSnapCmd.Parameters.ContainsKey($candidate)) { $snapRepoParam = $candidate; break }
    }
    if (-not $snapRepoParam) {
        $snapRepoParam = $getSnapCmd.Parameters.Keys | Where-Object { $_ -match 'Repositor' } | Select-Object -First 1
    }
    if (-not $snapRepoParam) {
        throw "Cannot find a repository parameter on Get-VBRApplicationBackupSnapshot. Available: $(($getSnapCmd.Parameters.Keys | Sort-Object) -join ', ')"
    }

    $getSnapSplat = @{ $snapRepoParam = $selectedRepo; ErrorAction = 'Stop' }
    $snapshots = @(Get-VBRApplicationBackupSnapshot @getSnapSplat)

    if ($snapshots.Count -eq 0) {
        Write-Host 'No snapshots present.' -ForegroundColor Yellow
        return
    }

    $sorted = @($snapshots | Sort-Object -Property CreationTime -Descending)

    $snapFormatter = {
        param($s)
        "{0}  ({1})" -f $s.Name, $s.CreationTime
    }

    # -----------------------------------------------------------------------
    # 4. Pick a snapshot
    # -----------------------------------------------------------------------

    $selectedSnapshot = $null

    if ($Abr) {
        if ($Snapshot -eq 'latest') {
            $selectedSnapshot = $sorted[0]
        }
        else {
            $selectedSnapshot = $sorted | Where-Object { $_.Name -like $Snapshot } | Select-Object -First 1
            if (-not $selectedSnapshot) { throw "No snapshot matches '$Snapshot'." }
        }
        Write-Host "Snapshot: $(& $snapFormatter $selectedSnapshot)"
    }
    else {
        $selectedSnapshot = Select-FromList -Items $sorted -Prompt 'Select snapshot' -Formatter $snapFormatter
        if (-not $selectedSnapshot) { Write-Host 'Cancelled.'; return }
    }

    # -----------------------------------------------------------------------
    # 5. Build the export parameters
    # -----------------------------------------------------------------------

    if (-not $MountPath) {
        $MountPath = "$(Get-DisplayName $selectedRepo)-ir"
    }
    if ($MountPath -eq $selectedRepo.MountPath) {
        throw "MountPath '$MountPath' collides with the live repository export. Pick a different name."
    }

    $repoHost = Get-RepositoryHostName -Repository $selectedRepo

    $permissions = @()
    foreach ($allowed in $AllowFrom) {
        $permissions += New-VBRApplicationBackupRepositoryPermission -ServerName $allowed -Mode $AccessMode
    }

    if ($DryRun) {
        Write-Head 'DryRun - nothing will be exposed'
        Write-Host "Repository : $(Get-DisplayName $selectedRepo)"
        Write-Host "Repo host  : $repoHost"
        Write-Host "Snapshot   : $(& $snapFormatter $selectedSnapshot)"
        Write-Host "MountPath  : $MountPath"
        Write-Host "Access     : $AccessMode from $(if ($AllowFrom) { $AllowFrom -join ', ' } else { '<nobody - no export would be created>' })"
        Write-Host "Reason     : $Reason"
        Write-Host "Drive      : $(if ($MountDrive) { $MountDrive } else { '<none, command printed only>' })"
        return
    }

    # Without permissions Veeam creates the ZFS clone but no NFS export.
    if ($permissions.Count -eq 0) {
        throw 'No -AllowFrom given. Veeam would create the clone but no NFS export, leaving nothing to mount.'
    }

    # -----------------------------------------------------------------------
    # 6. Start Instant Recovery
    # -----------------------------------------------------------------------

    Write-Head 'Starting Instant Recovery'

    $startTime    = Get-Date
    $auditContext = @{
        Repository = "$(Get-DisplayName $selectedRepo)"
        Snapshot   = "$($selectedSnapshot.Name)"
        MountPath  = $MountPath
        AccessMode = $AccessMode
        AllowFrom  = ($AllowFrom -join ',')
        Reason     = $Reason
    }

    $recoverySession = Start-VBRApplicationBackupSnapshotInstantRecovery `
        -Snapshot              $selectedSnapshot `
        -MountPath             $MountPath `
        -RepositoryPermissions $permissions `
        -Reason                $Reason `
        -Force `
        -ErrorAction Stop

    Write-Host "Exposed as $AccessMode to $($AllowFrom -join ', ')" -ForegroundColor Green
    Show-ObjectTree -InputObject $recoverySession -MaxDepth $ExpandDepth

    Write-AuditEntry ($auditContext + @{
        Event     = 'InstantRecoveryStarted'
        SessionId = "$($recoverySession.Id)"
        StartedAt = $startTime.ToString('o')
    })

    # -----------------------------------------------------------------------
    # 7. Mount
    # -----------------------------------------------------------------------

    $nfsPath = Get-NfsPath -HostName $repoHost -Session $recoverySession

    Write-Head 'NFS export'
    if ($nfsPath) {
        Write-Host "NFS path : $nfsPath"
    }
    else {
        Write-Warning 'Could not derive the NFS path. Check the session object above.'
    }

    if ($MountDrive -and $nfsPath) {
        # 'mount' is an alias for New-PSDrive in PowerShell, hence mount.exe.
        # 'ro' on top of Veeam's Read permission - belt and braces.
        # 'anon,ro' must be quoted: unquoted it is a PowerShell array literal
        # and would reach mount.exe as two separate arguments.
        $mountArgs = @('-o', 'anon,ro', $nfsPath, $MountDrive)

        Write-Host "Mounting $nfsPath on $MountDrive ..."
        Write-Host "  mount.exe $($mountArgs -join ' ')" -ForegroundColor DarkGray

        # The export is not always reachable the instant the clone exists -
        # mounting too early fails with "Network Error - 53". Retry briefly.
        $maxAttempts = 5
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            $mountOutput = & mount.exe @mountArgs 2>&1

            if ($LASTEXITCODE -eq 0) {
                $mountedDrive = $MountDrive
                Write-Host "Mounted on $MountDrive" -ForegroundColor Green
                break
            }

            if ($attempt -lt $maxAttempts) {
                Write-Host "  attempt $attempt failed, retrying in 3s ..." -ForegroundColor DarkGray
                Start-Sleep -Seconds 3
            }
            else {
                Write-Warning "mount.exe failed after $maxAttempts attempts (exit $LASTEXITCODE): $mountOutput"
                Write-Warning "Try the exact command above by hand now - this script is still waiting, so the export is still up."
            }
        }
    }
    elseif ($nfsPath) {
        Write-Host ''
        Write-Host 'Mount it with:'
        Write-Host "  mount.exe -o anon,ro $nfsPath Z:" -ForegroundColor White
    }

    # -----------------------------------------------------------------------
    # 8. Wait
    # -----------------------------------------------------------------------

    Write-Host ''
    if ($AutoStopAfterSeconds -gt 0) {
        Write-Host "Tearing down in $AutoStopAfterSeconds seconds."
        Start-Sleep -Seconds $AutoStopAfterSeconds
    }
    else {
        Read-Host 'Press ENTER to unmount and stop the Instant Recovery'
    }
}
finally {
    # Runs on error and Ctrl+C too. Unmount first, then stop the recovery.

    if ($mountedDrive) {
        Write-Head "Unmounting $mountedDrive"
        try {
            $umountOutput = & umount.exe -f $mountedDrive 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host 'Unmounted.' -ForegroundColor Green
            }
            else {
                Write-Warning "umount.exe failed (exit $LASTEXITCODE): $umountOutput"
            }
        }
        catch {
            Write-Warning "Unmount failed: $($_.Exception.Message)"
        }
    }

    if ($recoverySession) {
        Write-Head 'Stopping Instant Recovery'
        try {
            Stop-VBRApplicationBackupSnapshotInstantRecovery -Session $recoverySession -ErrorAction Stop
            Write-Host 'Stopped.' -ForegroundColor Green

            Write-AuditEntry ($auditContext + @{
                Event           = 'InstantRecoveryStopped'
                SessionId       = "$($recoverySession.Id)"
                StoppedAt       = (Get-Date).ToString('o')
                DurationSeconds = if ($startTime) { [int]((Get-Date) - $startTime).TotalSeconds } else { $null }
            })
        }
        catch {
            Write-Host ''
            Write-Warning "STOP FAILED: $($_.Exception.Message)"
            Write-Warning "The export may still be open. Session id: $($recoverySession.Id)"
            Write-Warning 'Tear it down from the Veeam console.'

            Write-AuditEntry ($auditContext + @{
                Event     = 'InstantRecoveryStopFailed'
                SessionId = "$($recoverySession.Id)"
                Error     = "$($_.Exception.Message)"
                FailedAt  = (Get-Date).ToString('o')
            })
        }
    }

    try { Disconnect-VBRServer -ErrorAction SilentlyContinue } catch { }
}
