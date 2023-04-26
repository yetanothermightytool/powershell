# Veeam Backup & Replication - Secure Restore for Linux and Windows VMs

## Description
~~~~
Version : 1.1 (April 26th 2023)
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

This script scans the Linux VM machine before running the restore. It leverages the Veeam Data Integration API: It presents the backup to the Linux server with ClamAV installed.
If a Virus is found, the script will be stopped. 

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


## Example: 
`PS>.\vbr-securerestore.ps1 -Mounthost ubuntusrv01 -Scanhost lnxvm01 -Jobname demo_vm -Keyfile .\key.key
  
## Notes

If the -Restore parameter is specified, the restore command is displayed only on the screen (line 77 of the code). You wonder why? Well, using the given restore command, the virtual machine would be overwritten without confirmation! 

This script has been tested with the following versions of Veeam Backup & Replication
- v12

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
* 1.1
   * Universal - Can also now be used with Windows VMs
   * Restore Point selection
   * Now uses clamdscan --multican (please provide performance feedback)
   * Output optimizations
*  1.0
    * Initial Release
