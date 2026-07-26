# ** WORK IN PROGRESS **

July 2026 / This folder holds the v13 rewrite of the Backup Scanning Tools. It is not finished.

Three components are available and working today:

- `backup-scanning-tools-webmenu.ps1`
- `vbr-scan-backups.ps1`
- `vbr-flr-hashscanner.ps1`

The remaining scanning scripts from the original collection will be updated where that still makes sense. Some of them may disappear instead of being ported, because Veeam Backup & Replication v13 now does natively what they used to do by hand. The web menu already lists the tools that have not been migrated yet and marks them clearly, so nobody starts a script that cannot work from there.

---

# Backup Scanning Tools v2

## Version Information
~~~~
Version: 2.0 (July 2026)
Requires: Veeam Backup & Replication v13, PowerShell 7
Author: Stephan "Steve" Herzig
~~~~

## Description

This is a rewrite of the Backup Scanning Tools for Veeam Backup & Replication v13, not a patch of the old scripts. The web console still gives you a menu-driven page for triggering backup scans, but almost everything behind it has changed.

The biggest change is what the scripts actually do. **The tools now lean heavily on Veeam's own built-in scanning features instead of building the same thing by hand.** v13 simply offers far more than v12 did, so a lot of the old machinery is no longer necessary:

- Antivirus and YARA scanning run through `Start-VBRScanBackup`, using Veeam Threat Hunter or whichever signature engine is configured under Malware Detection Settings. There is no need to mount a backup to a Linux host over the Data Integration API and drive ClamAV across SSH any more.
- Scan results end up in Veeam's malware detection state, not just in a text log. That means a scan feeds the machine status in the console, Secure Restore and the search for a clean restore point, instead of being a line in a file that nothing else reads.
- Finding the last clean restore point is a scan mode (`MostRecent`, `FirstInInterval`), not a loop that walks restore points itself.
- Malware events are read back through `Get-VBRMalwareDetectionEvent`, and the actual finding - including file names - is pulled from the Veeam scan session logs.

What Veeam does not cover is still done here. Hash lookups against a large threat intel feed are one example: YARA's hash module is not a practical substitute when the list holds hundreds of thousands of entries, so `vbr-flr-hashscanner.ps1` keeps doing that job with a file level recovery session.

The web console itself was rebuilt as well:

- Scans run in the background. The server stays responsive while a scan is going, and several scans can run at once. The old version blocked on every scan and froze the whole page.
- Every scan appears in a job table with its state, runtime and exit code, plus a button to read its full output. A finding shows up as **Threat** rather than a generic failure - Veeam reports a scan session that found something as "Failed", which looks like a broken script if you do not know that.
- Backup jobs, machines, restore points and YARA rules are picked from drop-down lists filled from the Veeam API instead of being typed in.
- Dashboard tiles for started scans, scan warnings, suspicious incremental backups and currently running scans.
- The last scan warnings from the log file.

## Prerequisites

- **Veeam Backup & Replication v13.** The scripts use cmdlets and parameters that do not exist in v12.
- **PowerShell 7.** Veeam PowerShell v13 dropped Windows PowerShell 5.1, so `powershell.exe` will not work - use `pwsh`. Scheduled tasks need to be changed accordingly.
- For the FLR hash scanner: a text file with SHA256 hashes, one per line.

## Installation

1. Create a folder for the scripts, for example `D:\Scripts\vbr\scanningtools`.
2. Copy `backup-scanning-tools-webmenu.ps1`, `vbr-scan-backups.ps1` and `vbr-flr-hashscanner.ps1` into it.
3. Optionally place a `scanner.png` in the same folder - the web console picks it up as a logo and simply leaves it out if it is not there.
4. Start the web console with `pwsh` (see below).

There is no installer script for v2 yet.

## Starting the web console

```powershell
PS C:\> pwsh -File .\backup-scanning-tools-webmenu.ps1
```

All parameters are optional:

| Parameter | Default | Description |
|---|---|---|
| `Port` | `8080` | Port the page listens on |
| `RefreshInterval` | `300` | Dashboard refresh in seconds; also the cache lifetime for the suspicious backup analysis |
| `LogFilePath` | `C:\Temp\log.txt` | Log file, passed through to every launched script so both sides use the same file |
| `ScanningToolsPath` | `D:\Scripts\vbr\scanningtools` | Folder holding the scanning scripts |
| `JobOutputPath` | `%ProgramData%\BackupScanningTools\jobs` | Where the output of each scan is written |
| `SuspiciousDepth` | `5` | Number of recent incremental sessions analysed per job |
| `SuspiciousGrowth` | `1.8` | A session is flagged when it is this much larger than the average of the others |
| `StatsWindowHours` | `168` | Time window for the scan counters |
| `PowerShellExecutable` | auto | Path to `pwsh` if it is not on `PATH` |
| `VbrServer` | `localhost` | Veeam backup server to connect to |
| `ForceAcceptTlsCertificate` | off | Accept the backup server's TLS certificate |

The console prints what it found at startup - Veeam module, connection, missing scripts - so a misconfiguration shows up immediately rather than on the first scan.

## The scanning scripts

Both scripts run fully non-interactive and can be used on their own, from the web console, or from a scheduled task. They share the same exit codes:

| Exit code | Meaning |
|---|---|
| `0` | Clean - nothing found |
| `1` | Error |
| `2` | Threat or hash match found |

### vbr-scan-backups.ps1

Scans a backup with the configured signature engine and/or YARA rules. Works for VM backups (VMware, Hyper-V, AHV, RHV, Cloud Director, Proxmox), backup copy jobs and Veeam Agent backups for Windows and Linux.

```powershell
PS C:\> .\vbr-scan-backups.ps1 -JobName 'Demo VM Job' -ObjectName 'lnxvm01' -AVScan
PS C:\> .\vbr-scan-backups.ps1 -JobName 'Demo VM Job' -ObjectName 'lnxvm01' -YARARule 'ransomware.yar' -ScanMode AllInInterval
PS C:\> .\vbr-scan-backups.ps1 -JobName 'Demo VM Job' -ObjectName 'lnxvm01' -ListRestorePoints
```

Key parameters:

- `ScanMode` - `MostRecent` (newest first, stop at the first clean restore point), `FirstInInterval` (optimal order, stop at the first clean one) or `AllInInterval` (scan everything; needs a YARA rule)
- `AVScan` - scan with the engine configured in Malware Detection Settings
- `YARARule` - one or more rule file names, for example `ransomware.yar`. Use `-ListYARARules` to see what is available. A rule tagged `SuppressMalwareDetectionNotification` does not raise a malware event; its session ends with a warning instead
- `RestorePointId` - scan one specific restore point instead of letting the scan mode decide
- `AllEvents` / `EventLimit` - by default only malware events created by this run are reported, not the machine's whole history

Beyond the scan session result, the script reads the Veeam scan session logs and reports the actual findings, including the path of the infected file. That detail is not available through the malware detection API.

### vbr-flr-hashscanner.ps1

Mounts a restore point through a file level recovery session and compares the SHA256 values of the files in the user profile folders against a hash list. This is the part Veeam's own engines do not cover.

```powershell
PS C:\> .\vbr-flr-hashscanner.ps1 -VM 'win-client-04' -JobName 'Demo VM Job'
PS C:\> .\vbr-flr-hashscanner.ps1 -VM 'win-client-04' -JobName 'Demo VM Job' -ListRestorePoints
```

Key parameters:

- `HashFile` - text file with one SHA256 per line. Blank lines, `#` comments and `<hash>  <filename>` style lists are handled. The list is loaded once into a hash set, so its size barely affects runtime
- `FoundHashFile` - matches are appended here with a timestamp
- `ScanFolder` - folders to scan, relative to each user profile. Defaults to Downloads, the temp folder, the Edge and Chrome caches and the startup folder
- `MaxFileSizeMB` - skip files above this size; `0` means no limit
- `MountHost` - mount server for the restore session

The result lists every folder it actually visited and how many files were found there, plus any folder it could not read. A scan that finds nothing is therefore distinguishable from a scan that could not look - which matters more than it sounds for a malware tool.

The restore session is stopped in a `finally` block, so an error cannot leave disks mounted on the mount server.

## Notes

**The web console listens on localhost only and is not authenticated.** It is meant to be used interactively on the backup server console. Do not expose the port to a network.

A few limitations worth knowing:

- `vbr-flr-hashscanner.ps1` works with Windows guest operating systems only, because it uses `Start-VBRWindowsFileRestore`.
- Restore point selection in `vbr-scan-backups.ps1` is implemented through a narrow time window rather than the `-RestorePoint` parameter. That parameter expects a type that neither `Get-VBRRestorePoint` nor `Get-VBRObjectRestorePoint` returns.
- `Get-VBRRestorePoint` searches across all backups when queried by name, and the catalogue can still contain entries whose restore points no longer exist. The hash scanner narrows results by backup ID and warns when it cannot, so verify the mounted restore point if that warning appears.
- The suspicious incremental backup analysis needs at least three sessions per job to say anything useful.

**Please note these scripts are unofficial and are not created nor supported by Veeam Software.**

## Version History
* 2.0
    * Rewritten for Veeam Backup & Replication v13 and PowerShell 7
    * Scanning now uses Veeam Threat Hunter / YARA through `Start-VBRScanBackup` instead of ClamAV over SSH
    * Web console: background scans, job table with state and output, drop-downs fed from the Veeam API
    * `vbr-flr-hashscanner.ps1` rewritten - hash set lookup instead of a linear search, guaranteed cleanup of the restore session, per-folder reporting
    * `vbr-cleanrestore.ps1` is no longer needed; the `MostRecent` and `FirstInInterval` scan modes do the same thing natively
