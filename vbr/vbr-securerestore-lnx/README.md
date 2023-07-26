# Veeam Backup & Replication - Secure Restore for Linux and Windows VMs

## Description
~~~~
Version : 1.2a (July 26th 2023)
Requires: Veeam Backup & Replication v12
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites

- Install the latest Win OpenSSH package on the host where the script will be used (https://github.com/PowerShell/Win32-OpenSSH/releases)
- Generate a public/private key pair using PuTTYgen (More details https://community.veeam.com/script-library-67/vbr-securerestore-lnx-ps1-secure-restore-for-linux-vm-4617)
- A Linux server with ClamAV installed. This Linux server needs to be added to Veeam (https://helpcenter.veeam.com/docs/backup/vsphere/add_linux_server.html)
- A Backup Job protecting the Linux VM as well as a restore point (the script uses the latest for the Restore)

## Purpose

This script scans the selected system before performing the restore (restore for VMs only). It uses the Veeam Data Integration API and presents the backup on the Linux server with ClamAV installed. If a virus is found, the desired restore process is not executed.
## Parameters
 
  `Mounthost`
_(mandatory)_ Name of the Linux server with ClamAV installed

  `Scanhost`
_(mandatory)_ Name of the Linux VM to be scanned and restored

  `Jobname`
_(mandatory)_ Name of the Veeam Backup Job protecting the Linux VM

  `Keyfile`
_(mandatory)_ Path to the key file

  `Restore`
_(optional)_ Switch if Restore needs to be executed (see Notes)

  `AVScan`
_(mandatory)_ Switch if Restore needs to be executed (see Notes)

  `YARAScan`
_(mandatory)_ Switch if Restore needs to be executed (see Notes)


## Examples: 
AV Scan of backed up virtual machine lnxvm01 on Linux host ubuntusrv01 from backup job demo_vm. Key file key.key used for authentication to Linux server ubuntusrv01
```Powershell
.\vbr-securerestore.ps1 -Mounthost ubuntusrv01 -Scanhost lnxvm01 -Jobname demo_vm -Keyfile .\key.key -AVScan
```

AV Scan VM lnxvm01 on Linux host ubuntusrv01 from VM backup demo_vm resding on tape. Restore the backup data from tape onto Repository win_local_01
```Powershell
.\vbr-securerestore.ps1 -Mounthost ubuntusrv01 -Scanhost lnxvm01 -Jobname demo_vm -Keyfile .\key.key -VMTape -Repository win_local_01 -AVScan
```

Scan VM lnxvm01 on Linux host ubuntusrv01 from Agent backup demo_agent resding on tape. Restore the backup data from tape onto Repository win_local_01
```Powershell
.\vbr-securerestore.ps1 -Mounthost ubuntusrv01 -Scanhost lnxvm01 -Jobname demo_agent -Keyfile .\key.key -AgentTape -Repository win_local_01 -AVScan
```

## Notes

If the -Restore parameter is specified, the restore command is displayed only on the screen (line 151 of the code). You wonder why? Well, using the given restore command, the virtual machine would be overwritten without confirmation! 

This script has been tested with the following versions of Veeam Backup & Replication
- v12

**Please note this script is unofficial and is not created nor supported by Veeam Software.**


## Important - All tape related actions are to be used at your own risk
Command examples for scanning "from tape" are documented but not yet listed in the Parameters section. Tests are still ongoing (a bug for the restore job naming was found and confirmed), and I want to make sure the correct backup data gets deleted after the scan. 


## Version History
* 1.2a
   * YARA Scan (needs to be installed on the Linux host and rules needs to be triggered in /home/administrator/yara-rules/rules/index.yar)
   * Adjustments for the Backup Scanning Tools Menu script
* 1.2
   * Scanning of backups on tape (no worries, the data will be restored into a disk repository first)
* 1.1
   * Universal - Can now also be used with Windows VMs and Agent Backups (tests for Agents ongoing)
   * Restore Point selection
   * Now uses clamdscan --multican (please provide performance feedback)
   * Output optimizations
*  1.0
    * Initial Release
