# Veeam Backup & Replication - Restore Point Scan for Linux, Windows VM and Agent Backups - Veeam Data Platform v12.1 

~~~~
Version : 1.1 (March 15th 2024)
Requires: Veeam Backup & Replication v12.1
Author  : Stephan "Steve" Herzig
~~~~

## Purpose

This script presents all restore points from a Linux, Windows VM or Agent backup and then mounts the selected restore point to a Linux host, scans and marks it as infected if anything gets found. The script utilizes the Veeam Data Integration API and integrates with ClamAV for antivirus scans or YARA rules installed on the Linux host. 

The script displays all existing restore points for the selected host and starts the scan automatically after 15 seconds, using the last restore point.

## Prerequisites

- Install the latest Win OpenSSH package on the host where the script will be used (https://github.com/PowerShell/Win32-OpenSSH/releases)
- Generate a public/private key pair using PuTTYgen (More details https://community.veeam.com/script-library-67/vbr-securerestore-lnx-ps1-secure-restore-for-linux-vm-4617)
- A Linux server with ClamAV installed. This Linux server needs to be added to Veeam (https://helpcenter.veeam.com/docs/backup/vsphere/add_linux_server.html)
- A Linux server with the yara package installed and the yara rule stored in the home directory of the given user under ./yara-rules/rules/

## Parameters
 
  `HostToScan`
_(mandatory)_ Name of the system whose backups are to be scanned

  `Jobname`
_(mandatory)_ Name of the Backup Job

  `MountHost`
_(mandatory)_ Name of the Linux server with ClamAV and YARA installed

  `LinuxUser`
_(mandatory)_ User name with which the Linux host is accessed

  `Keyfile`
_(mandatory)_ Path to the key file for accessing the Linux host

  `AVScan`
_(mandatory)_ Starting an AV scan using the installed AV solution on the Linux server

OR

  `YARAScan`
_(mandatory)_ Starting a YARA scan using the given YARA stored in the users home directory under /yara-rules/rules/


## Examples: 
AV Scan of backed up virtual machine lnxvm01 on Linux host ubuntusrv01 from backup job demo_vm. Key file key.key used for authentication to Linux server ubuntusrv01
```Powershell
.\vbr-securerestore.ps1 -HostToScan lnxvm01 -Jobname demo_vm -Mounthost ubuntusrv01 -LinuxUser administrator  -Keyfile .\opensshkey.key -AVScan 
```

YARA scan of backed up virtual machine lnxvm01 on Linux host ubuntusrv01 from backup job demo_vm. Key file key.key used for authentication to Linux server ubuntusrv01
```Powershell
.\vbr-securerestore.ps1 -HostToScan lnxvm01 -Jobname demo_vm -Mounthost ubuntusrv01 -LinuxUser administrator  -Keyfile .\opensshkey.key -YARAScan 
```

## Notes

This script has been tested with the following versions of Veeam Backup & Replication
- v12.1

**Please note this script is unofficial and is not created nor supported by Veeam Software.**


## Version History
* 1.1
   * Malware Status (Infected/Clean) displayed in Restore Point selection menu 
* 1.0
   * Initial Release
