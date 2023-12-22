# Veeam Backup & Replication - Scan Backups

~~~~
Version : 1.1 (December 22, 2023)
Requires: Veeam Backup & Replication v12.1
Author  : Stephan "Steve" Herzig
~~~~

## Overview

This PowerShell script connects to a Veeam Backup & Replication server, retrieves information about a specified backup job,
and identifies backup objects for a target host. It prompts the user to select YARA rules for scanning, waits for input, 
and defaults to using all rules if none is provided within 30 seconds. The script then scans each backup object with the selected or all YARA rules.

The option to trigger an AV scan was introduced with version 1.1 of the script.

## Prerequisites

- Veeam Backup & Replication V12.1
- YARA rules stored in C:\Program Files\Veeam\Backup and Replication\Backup\YaraRules 

## Parameters
The script accepts the following parameters:
 
  `Jobname`
_(mandatory)_ The name of the Veeam backup job that contains the VM

  `HostToScan`
_(mandatory)_ The name of the Windows VM to be scanned.

  `YARAScan`
_(Option 1)_ Starts a YARA scan of the selected VM. Displays all available YARA rules, and automatically selects all after 30 seconds.

  `AVScan`
_(Option 2)_ Starts an AV scan of the selected VM

  
## Example: 
```Powershell
.\vbr-scan-backups.ps1 -Jobname <backup job name> -HostToScan <hostname> -YARAScan
```
	  
## Notes
Windows VMs only! For Linux VMs see [`here`](https://github.com/yetanothermightytool/powershell/blob/master/vbr/vbr-securerestore-lnx/README.md)

This script has been tested with the following versions of Veeam Backup & Replication
- v12.1

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
*  1.1
    * Added possibility to trigger an AV scan
*  1.0
    * Initial Release
