# ABR Backup Compare

## Version Information
~~~~
Version : 1.1 (August 2026)
Requires: Veeam Backup & Replication v13.1
          Application Backup Repository
          Windows NFS Client
Author  : Steve Herzig
~~~~

## Description

A Veeam Application Backup Repository (ABR) has no job result for the data itself.
Veeam snapshots the volume on a schedule, and that snapshot succeeds whether the
application wrote anything or not. The application writes straight to an NFS
target and does not know Veeam exists. That is convenient, but it means nothing
tells you whether last night's backup actually happened, or whether what landed
there is worth restoring.

Official documentation:
https://helpcenter.veeam.com/docs/vbr/userguide/application_backup_repository.html?ver=13

This script closes that gap. It mounts the live repository and one of its
snapshots, reads what is in both, and reports what changed between them.

It never opens an archive. Everything comes from file names, file sizes, sibling
files such as the log written next to each dump, and the first 512 bytes. A
100 MB backup costs half a kilobyte of reading.

It works on any application writing into the export, not only on Proxmox. Files
are grouped into series by stripping timestamps out of their names, so
`switch-core-01-2026-08-01.cfg` and `switch-core-01-2026-08-02.cfg` become one
series without anything having to be configured. Recognised formats add what
only they can know: vzdump contributes the backup log result, the compression
ratio and the disk check.

What it reports, without knowing the source:

| Signal | Meaning |
|---|---|
| Overdue series | Written every 24 hours for weeks, then nothing for 70. The expected interval comes from the series itself, not from configuration. An ABR has no job event, so nothing else catches this. |
| Cadence gap | A stretched interval inside an otherwise regular series. |
| Write window | Always written around 02:00, now appearing at 14:00. Says nothing about the content, but says the schedule changed. |
| Size collapse | The newest file is an order of magnitude smaller than its predecessors. What a truncated or aborted write looks like. |
| Modified file | A finished backup file is written once and never touched again. A change in size or content format means someone rewrote it, and there is no benign explanation. |
| Format mismatch | The leading bytes disagree with what the extension claims, or the format changes inside a series. |
| Timestamp skew | A file named `...2026-08-01...` whose modification time is a week later was touched after the fact. |
| Series disappeared | A source that was there before and now writes nothing at all. |

And with a recognised format, currently Proxmox `vzdump`:

| Signal | Meaning |
|---|---|
| Compression anomaly | Encrypted data does not compress. Judged against everything the series has ever shown, which is what catches partial encryption. See the notes. |
| Backup with no data | A backup can report success and contain nothing. Exclude the disks and the job still goes green. |
| Failed backup | The result from the application's own log, which is the success signal an ABR itself cannot provide. |

When something does look wrong, the output also suggests where to restore from.
Every file in every snapshot is judged, per series, so the suggestion accounts
for the first bad backup rather than the one that finally crossed the threshold.
Those are usually not the same snapshot.

~~~
Possible clean restore point
----------------------------
Based on metadata only. A starting point for a look, not a verdict.

  dump/vzdump-lxc-601
      last unremarkable: snapshot_20260809_092451  (2026-08-09 09:24:51)
      2 later snapshot(s) look wrong, from vzdump-lxc-601-2026_08_09-11_31_18.tar.zst: ratio 2.17 against a history of 3.41
~~~

It rests on metadata alone. Nothing has opened an archive or looked at its
contents, so it says a snapshot looks unremarkable, not that it is clean. Verify
before restoring.


## Prerequisites

Install the NFS client on the machine that will mount the repository:

~~~powershell
Install-WindowsFeature NFS-Client
~~~

Note that `mount` in PowerShell is an alias for `New-PSDrive`. The scripts call
`mount.exe` and `umount.exe` directly for that reason.

The account needs the Backup Administrator role in Veeam.

## Best Practice

**Do not run this on the VBR server.** Use a separate machine.

The script mounts backup content and parses it. That content comes from systems
you do not fully control, and it may be exactly the thing you are investigating.
A host that parses untrusted data should not also hold Backup Administrator
rights over your entire backup infrastructure.

Running on a separate host:

~~~powershell
.\vbr-abr-compare.ps1 -VbrServer vbr-01.lab.local -Abr abr-repo01 -AllowFrom 10.10.11.55
~~~

The script asks for credentials and keeps them in memory for the session only,
nothing is written to disk.

Two things change when the client is separate:

- `-AllowFrom` must be the IP of the machine that mounts, not the VBR server
- The live export uses the permissions configured on the repository itself, so
  the client has to be inside one of those networks

## Parameters

### vbr-abr-compare.ps1

The main script. It does the whole run: mount, inventory, compare, clean up.

- `VbrServer` - VBR server. Default `localhost`. Prompts for credentials when not local.
- `Credential` - Optional. Pass a credential object for unattended runs.
- `Abr` - Repository name. Wildcards allowed. Picks the only repository when there is just one.
- `Snapshot` - Snapshot to compare against. Omit for a selection list, or use `latest`, or a name with wildcards.
- `AllowFrom` _(mandatory)_ - Host or network allowed to mount the snapshot, e.g. `10.10.11.100`. Without it Veeam creates the clone but no NFS export, and there is nothing to mount.
- `LiveDrive` - Drive letter for the live repository. Default `Y:`.
- `SnapshotDrive` - Drive letter for the snapshot. Default `Z:`.
- `MountPath` - Name of the temporary NFS export. Default `<repository>-ir`.
- `Reason` - Recorded by Veeam in its own session log. Default `Automated backup comparison`.
- `InventoryStore` - Directory holding one inventory per source. Default `.\inventory`.
- `Retention` - Days to keep inventory files. Default `365`. Use `0` to keep everything.
- `MinHistoryPoints` - Past values a series needs before the history is used instead of the two-point comparison. Default `8`.
- `HistorySensitivity` - How far outside its own history a value has to sit before it is an alert, in robust standard deviations. Default `3`.
- `CadenceTolerance` - Report a series as overdue when the time since its last file exceeds its usual interval by this factor. Default `2.5`.
- `MinRatio` - Two-point fallback: alert when the ratio drops below this. Default `1.2`.
- `BaselineMinRatio` - Two-point fallback: only alert when the baseline was above this. Default `1.5`.
- `RatioDropPercent` - Two-point fallback: notice when the ratio falls by this much without crossing `MinRatio`. Default `30`.
- `SizeChangePercent` - Two-point fallback: flag a size change of this much. Default `50`.

### Supporting scripts

These are called by the main script. Use them directly only when you want to
inspect one step on its own.

- `vbr-abr-inventory.ps1` - Reads a mounted path and writes one inventory file.
- `vbr-abr-inventory-diff.ps1` - Compares two inventory files. Run with `-List` to see what is available.
- `vbr-abr-mount.ps1` - Exposes a snapshot and mounts it, without the comparison.

## Example

~~~powershell
.\vbr-abr-compare.ps1 -Abr abr-repo01 -AllowFrom 10.10.11.55
~~~

~~~
Repository : abr-repo01
Host       : abr-host-01.lab.local
ZFS pool   : veeam-stg-abr-a1B2c3D4e5

Mounting live repository on Y:
------------------------------
  mount.exe -o anon,ro abr-host-01.lab.local:/veeam-stg-abr-a1B2c3D4e5/abr-repo01 Y:
  mounted on Y:

Inventory: live
---------------

VmId CtName        BackupTime                  ArchiveBytes CompressionRatio MagicOk LogResult DurationSeconds
---- ------        ----------                  ------------ ---------------- ------- --------- ---------------
 600 ctr-alpine-01 2026-08-08T12:10:41.0000000    102291376 3.24                True Success                 2
 600 ctr-alpine-01 2026-08-08T14:05:09.0000000    102306474 3.24                True Success                 3
 601 ctr-main      2026-08-08T13:34:11.0000000    102360433 3.24                True Success                 3

3 backup(s) written to .\inventory\inv-live.json

Available snapshots
-------------------
  [ 1] snapshot_20260808_120322  (08/08/2026 14:03:22)
  [ 2] snapshot_20260808_112429  (08/08/2026 13:24:29)
  [ 3] snapshot_20260808_101940  (08/08/2026 12:19:40)

Select snapshot to compare against live (1-3, empty = cancel): 2

Exposing snapshot read-only to 10.10.11.55
-------------------------------------------
  NFS path: abr-host-01.lab.local:/veeam-stg-abr-a1B2c3D4e5/abr-repo01-ir
  mount.exe -o anon,ro abr-host-01.lab.local:/veeam-stg-abr-a1B2c3D4e5/abr-repo01-ir Z:
  attempt 1 failed, retrying in 3s ...
  attempt 2 failed, retrying in 3s ...
  mounted on Z:

Inventory: snapshot_20260808_112429
-----------------------------------

VmId CtName        BackupTime                  ArchiveBytes CompressionRatio MagicOk LogResult DurationSeconds
---- ------        ----------                  ------------ ---------------- ------- --------- ---------------
 600 ctr-alpine-01 2026-08-08T12:10:41.0000000    102291376             3.24    True Success                 2

1 backup(s) written to .\inventory\inv-snapshot_20260808_112429.json

Cleanup
-------
  unmounted Z:
  unmounted Y:
  Instant Recovery stopped

Comparing snapshot_20260808_112429 against live
-----------------------------------------------

Baseline: snapshot_20260808_112429  (1 backup(s))
Current : live  (3 backup(s))

Info (3)
  [ArchiveAdded] vzdump-lxc-601-2026_08_08-13_34_11.tar.zst
      new backup, 97.6 MB
  [ArchiveAdded] vzdump-lxc-600-2026_08_08-14_05_09.tar.zst
      new backup, 97.6 MB
  [GuestAdded] VM 601 (ctr-main)
      not in baseline - new guest, or newly backed up

Written to .\abr-compare-20260808-141035.json
~~~

The retry on the snapshot mount is normal. A freshly created NFS export needs a
few seconds before it can be reached.

## How it works

1. Connect to the VBR server and find the repository
2. Mount the live repository export read-only
3. Read every backup into an inventory file
4. List the snapshots and pick one
5. Expose that snapshot read-only via Instant Recovery, restricted to `-AllowFrom`, and mount it
6. Read it into a second inventory file
7. Unmount both and stop the Instant Recovery
8. Compare the two inventory files

Both mounts and the Instant Recovery are torn down in a `finally` block, so it
also happens on error or Ctrl+C. A running Instant Recovery is an open data
window and should not be left behind.

Inventories are cached per source. A snapshot never changes, so scanning it twice
gives the same result - the file is simply overwritten instead of piling up.

They are also kept far longer than the snapshots themselves. A record is about
800 bytes, so a year of daily snapshots across 50 sources costs roughly 15 MB.
Once Veeam drops a snapshot after its retention period, the inventory is the
only remaining evidence that a source was backed up on that day, which is why
the default is 365 days and why the script warns when `-Retention` is set
shorter than the repository's own retention.

## Notes

Access is requested as `Read`, and the mount adds `ro` on top. The script never
needs write access to anything.

The comparison runs on inventory files, not on live mounts. Two snapshots never
have to be mounted at the same time.

Failure detection is deliberately conservative. A log that cannot be parsed is
reported as `Incomplete`, never as `Success`. The script will not tell you a
backup is fine when it does not know.

### About the compression signal

Encrypted data does not compress, which makes the compression ratio a ransomware
indicator that costs nothing to obtain. It has limits, and they are worth
knowing before relying on it.

**Partial encryption is the reason the history matters.** Ransomware often
encrypts only part of a file, to work faster and stay under detection
thresholds. Starting from a 3.24 baseline:

| Encrypted | Resulting ratio |
|---|---|
| 10% | 2.65 |
| 30% | 1.94 |
| 50% | 1.53 |
| 70% | 1.26 |
| 90% | 1.07 |

A fixed threshold of 1.2 only fires at roughly 75% encrypted content and above.
That is why the script compares against everything a series has ever shown
instead. A series that sat between 3.20 and 3.28 twelve times running and now
shows 1.94 is far outside anything it has ever done, even though 1.94 looks
harmless on its own. The tighter the history, the smaller the deviation that
means something, and no fixed threshold can express that.

The PowerShell script documentation was prepared with AI assistance. The scripts were reviewed for common security issues.

---

## Version History
- 1.1
  - Generic file mode. Any application writing into the export is covered, not
    only Proxmox. Files are grouped into series by stripping timestamps out of
    their names.
  - Format detection from the leading bytes rather than the extension, with
    vzdump as the first specific handler. The detected format is stored per
    file, which makes coverage visible and format drift inside a series
    detectable.
  - Cadence, gap, write window and size plausibility checks that need no
    knowledge of the source.
  - Compression judged against the full history of a series instead of a single
    earlier point, which is what catches partial encryption. Falls back to the
    two-point comparison until enough history exists.
  - Suggests a possible clean restore point per series, judging every file in
    every snapshot rather than only the newest one.
  - Inventory retention with `-Retention`, default 365 days.
  - Inventory schema version 2. Version 1 files are skipped with a warning.
- 1.0
  - Initial version

**Please note this script is unofficial and is not created nor supported by
Veeam Software.**
