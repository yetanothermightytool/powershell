# Instant VM Disk Recovery

## Version Information
~~~~
Version: 1.1 (July 30th 2023)
Requires: Veeam Backup & Replication v12 
Author: Stephan "Steve" Herzig 
GitHub: [https://www.github.com/yetanothermightytool](https://www.github.com/yetanothermightytool)
~~~~

## Overview

This PowerShell script performs an Instant VM Disk Recovery using Veeam Backup & Replication. The script allows you to select a restore point from a specified backup job, and then starts an Instant VM Disk Recovery session for the selected restore point. The recovered VM is mounted and started in the vSphere environment using vCenter Server.

## Prerequisite

Before you run this script, make sure that a "Mounthost" is preconfigured as a virtual machine that boots from an ISO image with the desired scan software and whose boot order is configured to boot from the ISO image.

> VM Settings will be added soon
> Also the registration for the Powercli Commands

## Script Parameters

The script accepts the following parameters:

- `Mounthost`  (mandatory): The name of the target VM where the recovered disks will be mounted.
- `Scanhost`   (mandatory): The name of the VM for which the restore point will be selected.
- `Jobname`    (mandatory): The name of the Veeam backup job that contains the restore point of the host to scan.
- `vCenter`    (mandatory): The hostname or IP address of the vCenter Server managing the target VM.
- `LogFilePath` (optional): Logging the activities. Default C:\Temp\log.txt

## Usage

Execute the script with the required parameters:

```powershell
.\InstantVMRecovery.ps1 -Mounthost "TargetVM" -Scanhost "VMtoScan" -Jobname "BackupJob" -vCenter "vCenterServer" -LogfilePath D:\Temp
```

Replace the values with your specific VM names, backup job name, vCenter Server hostname or IP address, and log file path.

## Note

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
* 1.1
    * Logging function to log the activities
    * Manual confirmation if malware was found after the manual scan was performed
* 1.0
    * Initial Release
