# Veeam Backup & Replication - File Level Restore - Hash Scanner

## Version Information
~~~~
Version: 1.0 (August 19th 2023)
Requires: Veeam Backup & Replication v12
Author: Stephan "Steve" Herzig
~~~~

## Description
This Powershell script scans specific subfolders within a Veeam File Level Recovery session and checks if any of the scanned files match a SHA256 value by comparing the values to a list of known hash values. Common locations for temporary Internet files in Windows systems are scanned. The list can be supplemented at any time.

The following subdirectories in the Users folder are scanned

- Downloads
- AppData\Local\Temp
- AppData\Local\Microsoft\Edge\User Data\Default\Cache\Cache_Data
- AppData\Local\Google\Chrome\User Data\Default\Cache
- AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup

The vbr-flr-auto-hashscanner.ps1 script automates the process of automatically scanning the Windows VMs included in a VM backup job. The number of VMs to be scanned simultaneously can be specified. The script tracks whether the VM from the job has already been scanned and tests the remaining VMs that have not yet been scanned (function from the dynamic SureBackup Job Script). If all VMs have been scanned, the script starts again from the beginning.

## Prerequisites
- Veeam Backup & Replication V12 Windows VM Backup
- Hash list from Abuse.ch
- Memory (Around 2.5 GB per Job!)

## Source Data (Hash list)
A Hash list can be downloaded from the Abuse.ch website. Abuse.ch provides community-driven threat data on cyber threats. Their MalwareBazaar project offers export of hash lists. The extracted .txt file (full data dump) can be used for scanning (https://bazaar.abuse.ch/export/).

## Variables to be modified in the "vbr-flr-hashscanner.ps1" script
- `$hashesFile`:      Source path of the .txt file containing the hashes
- `$foundHashesFile`: Destination path where the hash matches are stored
- `$LogFilePath`:     Path for the log file (default is "C:\Temp\log.txt")

## Variable to be modified in the "vbr-flr-auto-hashscanner.ps1" script 
- `$VeeamBackupCounterFile`: Specify the file path for storing the VM table. (Which VM has been tested or not)
- `$LogFilePath`:            Path for the log file (default is "C:\Temp\log.txt")

## Parameters vbr-flr-hashscanner.ps1
  `VM`
_(mandatory)_ The Windows VM to be scanned

  `JobName`
_(mandatory)_ The Backup Job Name

  `Logname`
_(optional)_ Log file location

## Parametersvbr-flr-auto-hashscanner.ps1
`JobName`
_(mandatory)_ The Backup Job Name where the VMs reside

`FilterDaysBack`
_(mandatory)_ Days back for checking for the last successful backup

`MaxBackupScans`
_(mandatory)_ Number of simultaneous scans. A reserve of 30 seconds is added between scans.

**Important: Do not run too many scan jobs at the same time. The list consumes quite a bit of memoryImportant: Do not run too many scan jobs at the same time** 

  `Logname`
_(optional)_ Log file location

## Notes

- The script has been tested with Veeam Backup & Replication v12.

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
- 1.0
  - Initial Release
