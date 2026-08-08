# ABR Backup Compare

## Version Information
~~~~
Version : 1.0 (August 2026)
Requires: Veeam Backup & Replication v13.1
          Application Backup Repository
          Windows NFS Client
Author  : Steve Herzig
~~~~

## Description

A Veeam Application Backup Repository (ABR) has no backup job. The application writes
straight to an NFS target and does not know Veeam exists. That is convenient, but
it means there is no job result telling you whether last night's backup worked or whether anything was written at all.

Official documentation:
https://helpcenter.veeam.com/docs/vbr/userguide/application_backup_repository.html?ver=13

This script closes that gap. It mounts the live repository and one of its
snapshots, reads what is in both, and reports what changed between them.

It never opens an archive. Everything comes from file names, file sizes, the log
the application writes next to each dump, and the first four bytes of each
archive. A 100 MB backup costs four bytes of reading.

What it reports:

| Signal | Meaning |
|---|---|
| Compression ratio collapse | A guest that always compressed 3.2:1 and now manages 1.05:1 has encrypted content. Judged on the absolute ratio, not on a percentage drop. This is the ransomware signal, without reading the payload. |
| Modified archive | A finished dump is written once and never touched again. If its size or header changed, someone rewrote it. |
| Backup with no data | A backup can report success and contain nothing. Exclude the disks and the job still goes green. |
| Guest disappeared | A source that silently stopped writing looks exactly like one that works. Nothing else catches this. |
| Invalid header | The first bytes no longer match the format the file name claims. Truncated or overwritten. |

The current version reads Proxmox `vzdump` backups (LXC containers).

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
- `AllowFrom` _(mandatory)_ - Host or network allowed to mount the snapshot, e.g. `10.10.11.55`. Without it Veeam creates the clone but no NFS export, and there is nothing to mount.
- `LiveDrive` - Drive letter for the live repository. Default `Y:`.
- `SnapshotDrive` - Drive letter for the snapshot. Default `Z:`.
- `MountPath` - Name of the temporary NFS export. Default `<repository>-ir`.
- `Reason` - Recorded by Veeam in its own session log. Default `Automated backup comparison`.
- `InventoryStore` - Directory holding one inventory per source. Default `.\inventory`.
- `MinRatio` - Alert when a guest's compression ratio falls below this. Default `1.2`.
- `BaselineMinRatio` - Only alert when the baseline ratio was above this. Default `1.5`. Keeps guests that never compressed well from alerting on every run.
- `RatioDropPercent` - Report a notice when the ratio falls by this much without dropping below `MinRatio`. Default `30`.
- `SizeChangePercent` - Flag a guest when its archive size changes by this much. Default `50`.

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

## Notes

Access is requested as `Read`, and the mount adds `ro` on top. The script never
needs write access to anything.

The comparison runs on inventory files, not on live mounts. Two snapshots never
have to be mounted at the same time.

Failure detection is deliberately conservative. A log that cannot be parsed is
reported as `Incomplete`, never as `Success`. The script will not tell you a
backup is fine when it does not know.

The compression alert uses an absolute ratio rather than a percentage drop,
because encryption is not a gradual effect. Either data has structure and
compresses, or it does not. A guest that went from 3.24 to 2.20 lost 32 percent
and is perfectly normal, while one that went from 1.15 to 1.02 lost 11 percent
and was encrypted. `BaselineMinRatio` excludes guests that never compressed well
in the first place, such as media stores: they sit near 1.0 permanently and
would alert on every run. For those, compression is not a usable signal at all,
and the script stays quiet rather than reporting a number that means nothing.

---

## Version History
- 1.0
  - Initial version

**Please note this script is unofficial and is not created nor supported by
Veeam Software.**
