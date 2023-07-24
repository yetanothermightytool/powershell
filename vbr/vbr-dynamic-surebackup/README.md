# Veeam Backup & Replication - Dynamic SureBackup

## Description
Version: 1.0 (May 30th 2023)
Requires: Veeam Backup & Replication v12
Author: Stephan "Steve" Herzig and many others (See "Special thanks")
GitHub: [yetanothermightytool](https://www.github.com/yetanothermightytool)

## Purpose
This PowerShell script automates the mass testing process using Veeam Backup & Replication. It creates and manages SureBackup jobs to facilitate efficient and scalable application testing in a virtual lab setup.

The script performs the following tasks:

1. Selects untested VMs based on the specified criteria.
2. Creates a SureBackup Application Group and adds the selected untested VMs.
3. Configures SureBackup startup options, such as allocated memory and timeout.
4. Executes a SureBackup job for the selected VMs.
4. Removes the application group, and SureBackup job after completion.

The script is designed to be scheduled or run manually to automate the SureBackup testing process.

## Prerequisites

- Veeam Backup & Replication v12
- Pre-Configured Virtual Lab
- Backup jobs protecting virtual machines

## Adjustments within the scripts

Modify the variables at the beginning of the script to suit your environment:

   - `$AppGroupName`: Specify the name of the application group.
   - `$SbJobName`   : Specify the name of the SureBackup job.
   - `$SbJobDesc`   : Provide a description for the SureBackup job.
   - `$Date`        : Specify the date to filter VMs that were successfully backed up since that date.
   - `$eMail`       : Provide an email address for SureBackup job verification (optional).
   - `$VBRserver`   : Specify the VBR server name.

Modify the variables for the `selectUntestedVMs` function if needed:
      - `$VeeamBackupCounterFile`: Specify the file path for storing the VM table.

The VM Startup Options can be adjusted in the variable $VbsStartOptions

## Parameters
  
  `FilterDaysBack`
_(mandatory)_ Specify the number of days back to filter VMs that were successfully backed up since that date.

  `NumberofVMs`
_(mandatory)_ The number of VMs to be added to the SureBackup Job setup for testing.

`VirtualLab`
_(mandatory)_ The Virtual Lab to be used.

## Examples

Start the script using virtual-lab-1 and scan through all the backups for the last 30 days and select 10 for the SureBackup Job
```powershell
.\vbr-dynamic-surebackup.ps1 -FilterDaysBack 30 -NumberofVMs 10 -VirtualLab virtual-lab-1
```

## Special thanks to
- Luca (The father of the script) [https://www.virtualtothecore.com/can-test-1000-vms-veeam-surebackup/]
- Hans (For the improvement with the hash table
- Wolfgang (for the v2 of the script) [https://vnote42.net/2022/05/04/how-to-surebackup-a-lot-of-vms-v2/]
- Customers giving feedback

## Notes

- The script has been tested with Veeam Backup & Replication v12.

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
- 1.0
  - Initial Release (Update for VBR V12 support and some adjustments and improvements)
