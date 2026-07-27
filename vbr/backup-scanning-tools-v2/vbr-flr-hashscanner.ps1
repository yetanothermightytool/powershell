<#
.SYNOPSIS
    Compares files inside a Windows backup against a list of known SHA256 hashes.

.DESCRIPTION
    Mounts a restore point through a Veeam file level recovery session and hashes the
    files in the interesting user profile folders, comparing them against a hash list
    (threat intel feed, known-bad hashes, licence-relevant binaries - whatever the
    list contains).

    Complements vbr-scan-backups.ps1 rather than duplicating it: Veeam's own scan
    engines do signatures and YARA, but not lookups against a large hash set. YARA's
    hash module is not a practical substitute at feed size (hundreds of thousands of
    entries).

    Runs non-interactive so it can be launched from the web menu or a scheduled task.

.PARAMETER VM
    Name of the machine inside the backup.

.PARAMETER JobName
    Name of the backup job holding that machine.

.PARAMETER RestorePointId
    Restore point to mount. Defaults to the most recent one.
    Use -ListRestorePoints to get the available ids.

.PARAMETER HashFile
    Text file with one SHA256 hash per line. Blank lines and lines starting with #
    are ignored. Loaded once into a hash set, so list size barely affects runtime.

.PARAMETER FoundHashFile
    Matches are appended here with a timestamp. Nothing is overwritten.

.PARAMETER ScanFolder
    Folders to scan, relative to each user profile. Defaults to the usual suspects:
    Downloads, temp, browser caches and the startup folder.

.PARAMETER MaxFileSizeMB
    Skip files larger than this. 0 means no limit.

.PARAMETER MountHost
    Optional mount server for the restore session.

.EXAMPLE
    .\vbr-flr-hashscanner.ps1 -VM 'win-client-04' -JobName 'Demo Windows VM'

.EXAMPLE
    .\vbr-flr-hashscanner.ps1 -VM 'win-client-04' -JobName 'Demo Windows VM' -ListRestorePoints -AsJson

.OUTPUTS
    Exit code 0 = no matches, 2 = hash match found, 1 = error.

.NOTES
    Author   : Stephan "Steve" Herzig
    Requires : Veeam Backup & Replication v13, PowerShell 7
    Version  : 2.0

    Windows guest OS only.

    Restore point lookup is awkward for some backup types. Get-VBRRestorePoint
    -Backup fails on Proxmox backups with a misleading "encrypted or created by an
    enterprise application plug-in" message, so the script falls back to -Name.
    That searches the whole server, and the catalogue can still list backups whose
    restore points no longer exist, so results are narrowed by BackupId where
    possible and a warning is printed when they cannot be. See Get-TargetRestorePoint.
#>
#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Scan')]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VM,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$JobName,

    [Parameter(ParameterSetName = 'Scan')]
    [string]$RestorePointId,

    [Parameter(Mandatory = $true, ParameterSetName = 'ListRestorePoints')]
    [switch]$ListRestorePoints,

    [Parameter(ParameterSetName = 'Scan')]
    [ValidateNotNullOrEmpty()]
    [string]$HashFile = 'D:\Scripts\Filehashscanner\full_sha256.txt',

    [Parameter(ParameterSetName = 'Scan')]
    [string]$FoundHashFile = 'D:\Scripts\Filehashscanner\found_hashes.txt',

    [Parameter(ParameterSetName = 'Scan')]
    [string[]]$ScanFolder = @(
        'Downloads'
        'AppData\Local\Temp'
        'AppData\Local\Microsoft\Edge\User Data\Default\Cache\Cache_Data'
        'AppData\Local\Google\Chrome\User Data\Default\Cache'
        'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
    ),

    [Parameter(ParameterSetName = 'Scan')]
    [ValidateRange(0, 102400)]
    [int]$MaxFileSizeMB = 0,

    [Parameter(ParameterSetName = 'Scan')]
    [string]$MountHost,

    [Parameter(ParameterSetName = 'Scan')]
    [ValidateNotNullOrEmpty()]
    [string]$FlrRoot = 'C:\VeeamFLR',

    [switch]$AsJson,

    [ValidateNotNullOrEmpty()]
    [string]$Server = 'localhost',

    [switch]$ForceAcceptTlsCertificate,

    [ValidateNotNullOrEmpty()]
    [string]$LogFilePath = 'C:\Temp\log.txt'
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$script:ExitClean = 0
$script:ExitError = 1
$script:ExitMatch = 2

$script:WeConnected = $false
$script:LogPrefix   = 'FLR Hash Scanner'

#region Helpers ----------------------------------------------------------------

# Same format the other scanning tools and the web menu dashboard use.
function Write-ScanLog {
    param (
        [Parameter(Mandatory = $true)] [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error')] [string]$Level = 'Info'
    )

    try {
        $directory = Split-Path -Path $LogFilePath -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        Add-Content -LiteralPath $LogFilePath -Value ("{0} - {1} - {2} - {3}" -f
            (Get-Date -Format 'dd-MM-yyyy HH:mm:ss'), $Level, $script:LogPrefix, $Message)
    } catch {
        Write-Warning "Could not write to '$LogFilePath': $($_.Exception.Message)"
    }
}

# Status goes to stderr in JSON mode so it cannot corrupt the JSON on stdout.
function Write-Status {
    param (
        [Parameter(Mandatory = $true)] [string]$Message,
        [string]$Color = 'Gray'
    )

    if ($AsJson) { [Console]::Error.WriteLine($Message) }
    else         { Write-Host $Message -ForegroundColor $Color }
}

function Get-SafeProperty {
    param (
        $InputObject,
        [Parameter(Mandatory = $true)] [string]$Name,
        $Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    try {
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -eq $property -or $null -eq $property.Value) { return $Default }
        return $property.Value
    } catch {
        return $Default
    }
}

# Veeam hands out some timestamps as UTC. Everything printed here is local.
function ConvertTo-LocalDateTime {
    param ($Value)

    if ($Value -isnot [datetime]) { return [datetime]::MinValue }
    if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value.ToLocalTime() }
    return $Value
}

function Get-RestorePointDate {
    param ($RestorePoint)

    foreach ($name in @('CreationTime', 'CreationDate')) {
        $value = Get-SafeProperty -InputObject $RestorePoint -Name $name
        if ($value -is [datetime]) { return ConvertTo-LocalDateTime $value }
    }
    return [datetime]::MinValue
}
#endregion

#region Hash set ---------------------------------------------------------------

<#
    Loads the hash list into a hash set.

    The previous version re-read the file inside the per folder loop and then
    searched it with -contains, i.e. linearly. At feed size (hundreds of thousands
    of entries) that is hundreds of millions of string comparisons per run, plus
    dozens of re-reads of a large file. Loading once into a HashSet turns every
    lookup into a constant time operation.

    ReadLines streams the file instead of materialising an array of every line.
#>
function Import-HashSet {
    param ([Parameter(Mandatory = $true)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Hash file not found: $Path"
    }

    # Get-FileHash returns upper case; feeds are often lower case.
    $set     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $skipped = 0

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $value = $line.Trim()
        if ($value.Length -eq 0 -or $value.StartsWith('#')) { continue }

        # Tolerate "<hash>  <filename>" style lists.
        $token = ($value -split '\s+')[0]
        if ($token -match '^[0-9a-fA-F]{64}$') {
            # Normalise explicitly rather than relying on the set's comparer:
            # Get-FileHash and BitConverter produce upper case, feeds are usually
            # lower case, and a comparer that silently does not apply turns every
            # scan into a false negative.
            [void]$set.Add($token.ToUpperInvariant())
        }
        else { $skipped++ }
    }

    if ($skipped -gt 0) {
        Write-Status "Ignored $skipped line(s) in the hash file that are not SHA256 values." 'Yellow'
    }
    if ($set.Count -eq 0) {
        throw "No usable SHA256 hashes found in '$Path'."
    }

    return $set
}

# One reusable SHA256 instance instead of the per-call setup Get-FileHash does.
function Get-Sha256 {
    param (
        [Parameter(Mandatory = $true)] $Algorithm,
        [Parameter(Mandatory = $true)] [string]$Path
    )

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        return [System.BitConverter]::ToString($Algorithm.ComputeHash($stream)).Replace('-', '')
    } finally {
        if ($stream) { $stream.Dispose() }
    }
}
#endregion

#region Veeam ------------------------------------------------------------------

function Connect-Veeam {
    try {
        if (Get-VBRServerSession) { return }
    } catch {
        # No session yet - fall through and connect.
    }

    $arguments = @{ Server = $Server }
    if ($ForceAcceptTlsCertificate) { $arguments['ForceAcceptTlsCertificate'] = $true }

    Connect-VBRServer @arguments
    $script:WeConnected = $true
}

function Disconnect-Veeam {
    if (-not $script:WeConnected) { return }
    try { Disconnect-VBRServer } catch { }
    $script:WeConnected = $false
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
    Start-VBRWindowsFileRestore needs a COib restore point, which only
    Get-VBRRestorePoint produces - not Get-VBRObjectRestorePoint, which
    vbr-scan-backups.ps1 uses for Start-VBRScanBackup. The two cmdlets genuinely
    want different types.

    Two parameter sets, two behaviours:
      -Backup  fails outright on some backup types. Proxmox backups report
               "encrypted or created by an enterprise application plug-in", which
               is misleading - they are not encrypted.
      -Name    works there, but searches every backup on the server. The same
               machine name can live in several jobs, so the result has to be
               narrowed back down to the requested one before mounting anything.

    Veeam Agent jobs additionally only return restore points when the name
    contains a wildcard, hence the second filter.
#>
function Get-TargetRestorePoint {
    $backups = @(Get-VBRBackup -WarningAction SilentlyContinue |
        Where-Object { $_.JobName -eq $JobName } |
        Sort-Object CreationTime -Descending)

    if ($backups.Count -eq 0) { throw "No backup found for job '$JobName'." }

    # A job name can map to several backups (re-created jobs, imported copies), so
    # match against all of their ids rather than guessing at the newest one.
    $backup    = $backups[0]
    $backupIds = @($backups | ForEach-Object { ([string]$_.Id).ToLowerInvariant() })
    $points    = @()

    try {
        $points = @(Get-VBRRestorePoint -Backup $backup -ErrorAction Stop |
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
            # the newest point is normally the right one - but say it out loud so
            # the mounted restore point can be verified.
            Write-Status ("Warning: found {0} restore point(s) for '{1}' that could not be tied to job '{2}'. Using them anyway - verify the mounted restore point." -f
                $byName.Count, $VM, $JobName) 'Yellow'
            $points = $byName
        }
    }

    return @($points | Sort-Object -Property @{ Expression = { Get-RestorePointDate $_ } } -Descending)
}
#endregion

#region Scanning ---------------------------------------------------------------

<#
    Locates the folder the restore session mounted the disks into.

    The mount root holds one folder per session, named after the machine plus a
    suffix. Picking the newest one avoids grabbing a stale mount from an earlier
    session that failed to clean up.
#>
function Get-MountPath {
    param ([Parameter(Mandatory = $true)] [datetime]$Since)

    if (-not (Test-Path -LiteralPath $FlrRoot)) {
        throw "Mount root '$FlrRoot' does not exist - did the restore session start?"
    }

    $candidates = @(Get-ChildItem -LiteralPath $FlrRoot -Directory -Filter "$VM*" -ErrorAction SilentlyContinue |
        Sort-Object CreationTime -Descending)

    if ($candidates.Count -eq 0) {
        throw "No mounted folder for '$VM' found under '$FlrRoot'."
    }

    $fresh = @($candidates | Where-Object { $_.CreationTime -ge $Since.AddMinutes(-5) })
    if ($fresh.Count -gt 0) { return $fresh[0].FullName }

    Write-Status "Warning: using an existing mount folder, none was created by this session." 'Yellow'
    return $candidates[0].FullName
}

<#
    Walks a folder tree explicitly instead of using Get-ChildItem -Recurse.

    -Recurse proved unreliable on the VeeamFLR mount: a recursive search from the
    mount root returned nothing for a file that a direct listing of its folder shows
    immediately. Combined with -ErrorAction SilentlyContinue that produced the worst
    possible outcome - a scan that quietly found nothing and reported "no matches".

    This walk visits one directory at a time, counts the ones it cannot read instead
    of swallowing the error, and skips reparse points so the junctions inside a
    Windows user profile cannot send it in circles.
#>
function Get-FileTree {
    param ([Parameter(Mandatory = $true)] [string]$Path)

    $files      = [System.Collections.Generic.List[object]]::new()
    $pending    = [System.Collections.Generic.Stack[string]]::new()
    $failed     = 0
    $reparse    = [System.IO.FileAttributes]::ReparsePoint

    $pending.Push($Path)

    while ($pending.Count -gt 0) {
        $current = $pending.Pop()

        try {
            $entries = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)
        } catch {
            $failed++
            Write-Verbose "Cannot read '$current': $($_.Exception.Message)"
            continue
        }

        foreach ($entry in $entries) {
            if ($entry.PSIsContainer) {
                if (($entry.Attributes -band $reparse) -eq $reparse) { continue }
                $pending.Push($entry.FullName)
            } else {
                $files.Add($entry)
            }
        }
    }

    return [pscustomobject]@{ Files = $files; Failed = $failed }
}

# Each mounted volume appears as its own folder; only some carry a Users tree.
function Get-UserProfilePath {
    param ([Parameter(Mandatory = $true)] [string]$MountPath)

    $profiles = [System.Collections.Generic.List[string]]::new()

    foreach ($volume in @(Get-ChildItem -LiteralPath $MountPath -Directory -ErrorAction SilentlyContinue)) {
        $usersPath = Join-Path $volume.FullName 'Users'
        if (-not (Test-Path -LiteralPath $usersPath)) { continue }

        foreach ($user in @(Get-ChildItem -LiteralPath $usersPath -Directory -ErrorAction SilentlyContinue)) {
            $profiles.Add($user.FullName)
        }
    }

    return $profiles
}

function Invoke-HashScan {
    param (
        [Parameter(Mandatory = $true)] [string]$MountPath,
        [Parameter(Mandatory = $true)] $HashSet
    )

    # Not $matches: that is an automatic variable filled in by -match.
    $hashMatches  = [System.Collections.Generic.List[object]]::new()
    $folderReport = [System.Collections.Generic.List[object]]::new()
    $scanned      = 0
    $skipped      = 0
    $unreadable   = 0
    $maxBytes     = if ($MaxFileSizeMB -gt 0) { [long]$MaxFileSizeMB * 1MB } else { [long]0 }

    $profiles = Get-UserProfilePath -MountPath $MountPath
    if ($profiles.Count -eq 0) {
        Write-Status "No user profiles found under '$MountPath'." 'Yellow'
        return [pscustomobject]@{
            Matches = $hashMatches; Scanned = 0; Skipped = 0; Unreadable = 0
            Profiles = 0; Folders = $folderReport
        }
    }

    Write-Status "Found $($profiles.Count) user profile(s)." 'White'

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        # Not $profile: that is the automatic variable holding the profile script path.
        foreach ($profilePath in $profiles) {
            $userName = Split-Path -Leaf $profilePath

            foreach ($relative in $ScanFolder) {
                $folder = Join-Path $profilePath $relative

                if (-not (Test-Path -LiteralPath $folder)) {
                    $folderReport.Add([pscustomobject]@{
                        user = $userName; folder = $relative; files = 0; state = 'missing'
                    })
                    continue
                }

                $tree  = Get-FileTree -Path $folder
                $files = $tree.Files
                $unreadable += $tree.Failed

                # Recorded per folder so a scan that found nothing can be told apart
                # from a scan that could not look.
                $folderReport.Add([pscustomobject]@{
                    user   = $userName
                    folder = $relative
                    files  = $files.Count
                    state  = if ($tree.Failed -gt 0) { "$($tree.Failed) unreadable" } else { 'ok' }
                })

                foreach ($file in $files) {
                    if ($maxBytes -gt 0 -and $file.Length -gt $maxBytes) {
                        $skipped++
                        continue
                    }

                    try {
                        $hash = Get-Sha256 -Algorithm $algorithm -Path $file.FullName
                    } catch {
                        $unreadable++
                        continue
                    }

                    $scanned++

                    # Both sides normalised to upper case - see Import-HashSet.
                    if ($HashSet.Contains($hash.ToUpperInvariant())) {
                        $hashMatches.Add([pscustomobject]@{
                            user   = $userName
                            folder = $relative
                            file   = $file.FullName
                            size   = $file.Length
                            hash   = $hash
                        })
                        Write-Status ("  MATCH  {0}  [{1}]" -f $file.FullName, $hash) 'Red'
                    }
                }
            }
        }
    } finally {
        $algorithm.Dispose()
    }

    return [pscustomobject]@{
        Matches    = $hashMatches
        Scanned    = $scanned
        Skipped    = $skipped
        Unreadable = $unreadable
        Profiles   = $profiles.Count
        Folders    = $folderReport
    }
}

function Save-FoundHash {
    param ([Parameter(Mandatory = $true)] $Matches)

    if ($Matches.Count -eq 0 -or [string]::IsNullOrWhiteSpace($FoundHashFile)) { return }

    try {
        $directory = Split-Path -Path $FoundHashFile -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }

        # Append rather than overwrite: the previous version replaced the file on
        # every run, so earlier findings were lost.
        $stamp = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
        $lines = @($Matches | ForEach-Object { "{0}`t{1}`t{2}`t{3}" -f $stamp, $VM, $_.hash, $_.file })
        Add-Content -LiteralPath $FoundHashFile -Value $lines
    } catch {
        Write-Status "Could not write '$FoundHashFile': $($_.Exception.Message)" 'Yellow'
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

    Write-Host ''
    if ($Result.status -eq 'Match') {
        Write-Host "Result: $($Result.matchCount) HASH MATCH(ES) FOUND." -ForegroundColor Red
    } else {
        Write-Host 'Result: no hash matches.' -ForegroundColor Green
    }

    Write-Host ("Restore point : {0}" -f $Result.restorePoint)
    Write-Host ("Profiles      : {0}" -f $Result.profiles)
    Write-Host ("Files hashed  : {0}" -f $Result.scanned)
    if ($Result.skipped -gt 0)    { Write-Host ("Skipped (size): {0}" -f $Result.skipped) }
    if ($Result.unreadable -gt 0) { Write-Host ("Unreadable    : {0}" -f $Result.unreadable) }
    Write-Host ("Hash list     : {0} entries" -f $Result.hashListCount)
    Write-Host ("Duration      : {0}" -f $Result.duration)

    <#
        Which folders actually contained something, so that "no matches" cannot be
        confused with "nothing was looked at". Folders that simply do not exist in
        the backup are counted rather than listed - they are the majority and say
        nothing useful.
    #>
    $folders = @($Result.folders)
    if ($folders.Count -gt 0) {
        $interesting = @($folders | Where-Object { $_.files -gt 0 -or $_.state -ne 'missing' })
        $absent      = $folders.Count - $interesting.Count

        Write-Host ''
        if ($interesting.Count -gt 0) {
            Write-Host 'Folders with content:'
            $interesting | Format-Table -AutoSize -Property user, folder, files, state
        }
        if ($absent -gt 0) {
            Write-Host ("{0} configured folder(s) not present in this backup." -f $absent) -ForegroundColor DarkGray
        }
    }

    $found = @($Result.matches)
    if ($found.Count -gt 0) {
        Write-Host ''
        Write-Host 'Matching files:' -ForegroundColor Red
        $found | Format-Table -AutoSize -Property user, folder, file, hash
    }
}
#endregion

#region Main -------------------------------------------------------------------

$exitCode     = $script:ExitError
$restoreSession = $null

try {
    if (-not $AsJson) {
        try { $host.UI.RawUI.WindowTitle = 'VBR FLR Hash Scanner' } catch { }
        try { Clear-Host } catch { }
    }

    Connect-Veeam

    $points = Get-TargetRestorePoint
    if ($points.Count -eq 0) {
        throw "No restore points found for '$VM' in job '$JobName'."
    }

    if ($ListRestorePoints) {
        $list = @($points | ForEach-Object {
            [ordered]@{
                id           = [string](Get-SafeProperty -InputObject $_ -Name 'Id')
                name         = [string](Get-SafeProperty -InputObject $_ -Name 'Name')
                creationTime = (Get-RestorePointDate $_).ToString('dd-MM-yyyy HH:mm:ss')
                type         = [string](Get-SafeProperty -InputObject $_ -Name 'Type')
            }
        })

        if ($AsJson) { $list | ConvertTo-Json -Depth 4 -AsArray }
        else         { $list | ForEach-Object { [pscustomobject]$_ } | Format-Table -AutoSize }

        $exitCode = $script:ExitClean
        return
    }

    if ([string]::IsNullOrWhiteSpace($RestorePointId)) {
        $selected = $points[0]
    } else {
        $selected = $points | Where-Object { [string]$_.Id -eq $RestorePointId } | Select-Object -First 1
        if (-not $selected) {
            throw "Restore point '$RestorePointId' not found. Use -ListRestorePoints to get the current ids."
        }
    }

    $pointDate = (Get-RestorePointDate $selected).ToString('dd-MM-yyyy HH:mm:ss')

    # Load the hash list before mounting, so a bad path fails without leaving a
    # restore session behind.
    Write-Status "Loading hash list from $HashFile ..." 'White'
    $hashSet = Import-HashSet -Path $HashFile
    Write-Status "Loaded $($hashSet.Count) hashes." 'White'

    Write-Status "Mounting restore point $pointDate for '$VM' ..." 'White'
    Write-ScanLog -Message "Scanning started - VM: $VM - Job: $JobName - Restore point: $pointDate"

    $started        = Get-Date
    $restoreArguments = @{
        RestorePoint = $selected
        Reason       = 'vbr-flr-hashscanner.ps1'
    }
    if (-not [string]::IsNullOrWhiteSpace($MountHost)) {
        $restoreArguments['MountHost'] = Get-VBRServer -Name $MountHost
    }

    $restoreSession = Start-VBRWindowsFileRestore @restoreArguments

    $mountPath = Get-MountPath -Since $started
    Write-Status "Mounted at $mountPath" 'White'

    $scan     = Invoke-HashScan -MountPath $mountPath -HashSet $hashSet
    $duration = (Get-Date) - $started
    $found    = @($scan.Matches)

    Save-FoundHash -Matches $found

    $status = if ($found.Count -gt 0) { 'Match' } else { 'Clean' }

    if ($found.Count -gt 0) {
        Write-ScanLog -Level Warning -Message "Scanning ended - $($found.Count) hash match(es) in $($scan.Scanned) files - VM: $VM"
    } else {
        Write-ScanLog -Message "Scanning ended - No hash matches in $($scan.Scanned) files - VM: $VM"
    }

    Write-Result -Result ([ordered]@{
        status        = $status
        vm            = $VM
        job           = $JobName
        restorePoint  = $pointDate
        matchCount    = $found.Count
        matches       = $found
        scanned       = $scan.Scanned
        skipped       = $scan.Skipped
        unreadable    = $scan.Unreadable
        profiles      = $scan.Profiles
        folders       = @($scan.Folders)
        hashListCount = $hashSet.Count
        duration      = '{0:hh\:mm\:ss}' -f $duration
    })

    $exitCode = if ($found.Count -gt 0) { $script:ExitMatch } else { $script:ExitClean }

} catch {
    $message = $_.Exception.Message
    Write-ScanLog -Level Error -Message "Aborted: $message"

    if ($AsJson) {
        [ordered]@{ status = 'Error'; message = $message } | ConvertTo-Json -Depth 3
    } else {
        Write-Host ''
        Write-Host "Error: $message" -ForegroundColor Red
        if ($_.InvocationInfo) { Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray }
    }
    $exitCode = $script:ExitError

} finally {
    # The restore session keeps disks mounted on the mount server. Without this it
    # survives any error and leaks until someone clears it by hand - the previous
    # version stopped the session only on the success path.
    if ($restoreSession) {
        try {
            Write-Status 'Stopping restore session ...' 'White'
            Stop-VBRWindowsFileRestore -FileRestore $restoreSession
        } catch {
            Write-Status "Could not stop the restore session: $($_.Exception.Message)" 'Yellow'
            Write-ScanLog -Level Warning -Message "Restore session could not be stopped - check for a stale mount under $FlrRoot"
        }
    }
    Disconnect-Veeam
}

exit $exitCode
#endregion
