# Veeam Backup & Replication - File Level Restore - Hash Scanner

## Version Information
~~~~
Version: 1.0 (August 2023)
Requires: Veeam Backup & Replication v12
Author: Stephan "Steve" Herzig
~~~~

## Description
This Powershell script scans specific subfolders within a Veeam File Level Recovery session and checks if any of the scanned files match a SHA256 value by comparing the values to a list of known hash values. Common locations for Internet files in Windows systems are scanned. The list can be supplemented at any time.

The vbr-flr-auto-hashscanner.ps1 script automates the process of automatically scanning the Windows VMs included in a VM backup job. The number of VMs to be scanned simultaneously can be specified. The script tracks whether the VM from the job has already been scanned and tests the remaining VMs that have not yet been scanned (function from the dynamic SureBackup Job Script). If all VMs have been scanned, the script starts again from the beginning.
