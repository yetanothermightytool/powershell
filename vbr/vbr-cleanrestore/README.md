# VBR Clean Restore - Data Integration API


## Version Information
~~~~
Version: 1.0 (July 31st 2023)
Requires: Veeam Backup & Replication v12
Author: Stephan "Steve" Herzig
~~~~


## Purpose
This script facilitates a clean restore process for virtual machine backup data using Veeam Backup & Replication and Data Integration API.
The script iterates through the restore points, attempting to find a clean restore point. If a clean restore point is found, 
it initiates the restore (if selected). If not, it stops after the specified number of iterations.


## Prerequisites
- Veeam Backup & Replication v12
- PowerShell 5.1 or higher.
- ClamAV installed on the target Linux server (mount host) for antivirus scanning 


## Parameters
The script accepts the following parameters:

- `Mounthost`      (mandatory): The Linux server where scanning will take place.
- `Scanhost`       (mandatory): The name of the server or VM to be scanned.
- `Jobname`        (mandatory): The name of the backup job from which to select restore points.
- `Keyfile`        (mandatory): The path to the SSH key file for accessing the mount host.
- `AVScan`         (mandatory): Enables the ClamAV malware scan.
- `MaxIterations`   (optional): The maximum number of iterations for scanning restore points. Default 5
- `Restore` 		  (optional): Enables restore using a clean restore point.
- `LogFilePath`     (optional): The path to the log file for tracking scan results. Default "C:\Temp\log.txt"

## Example

Start a clean restore process, scan 5 iteratins and restore if a clean restore point has been found.

```powershell
.\vbr-cleanrestore.ps1 -Mounthost "LinuxHost -Scanhost "VM_Name" -Jobname "Backup_Job_Name" -Keyfile "Path_To_Private_Key" -AVScan -MaxIterations 5 -Restore
```


## Notes
This script has been tested with the following versions of Veeam Backup & Replication
- v12

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
*  1.0
    * Initial Release
