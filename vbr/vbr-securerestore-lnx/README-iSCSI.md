# Veeam Backup & Replication - Secure Restore using Data Integration API over iSCSI

## Description
~~~~
Version : 1.0 (August 4th 2023)
Requires: Veeam Backup & Replication v12 & Linux Host with ClamAV installed
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites
- Install the latest Win OpenSSH package on the host where the script will be used (https://github.com/PowerShell/Win32-OpenSSH/releases)
- Generate a public/private key pair using PuTTYgen (More details https://community.veeam.com/script-library-67/vbr-securerestore-lnx-ps1-secure-restore-for-linux-vm-4617)
- A Linux server with ClamAV installed. This Linux server needs to be added to Veeam (https://helpcenter.veeam.com/docs/backup/vsphere/add_linux_server.html)
- Appropriate permissions for the Linux user used to authenticate on the ClamAV host via SSH.

## Purpose
This script scans the selected system before performing the restore (restore for VMs only). It uses the Veeam Data Integration API and presents the backup on the Linux server with ClamAV installed. If a virus is found, the desired restore process is not executed. The script detects the file system type of each partition on the VM's disks and only proceeds to scan partitions with supported file systems (NTFS, XFS, or ext4). Any other file systems found will not be scanned.

## Parameters
 
  `Mounthost`
_(mandatory)_ The iSCSI Target (IP address or hostname) where the backup content is published.

  `Scanhost`
_(mandatory)_ The Linux host running ClamAV where the backup content is mounted via iSCSI for scanning.

 `HostToScan`
_(mandatory)_ The name of the virtual machine (VM) to be scanned from the backup restore points.

  `Jobname`
_(mandatory)_ Name of the Veeam Backup Job protecting the VM.

  `LinuxUser`
_(mandatory)_ The username of the Linux user with the required permissions to perform the scan.

  `Keyfile`
_(mandatory)_ Path to the key file

  `Restore`
_(optional)_ An optional switch indicating that the script should proceed with restoring the VM after the scan if no infections are found.

  `LogFilePath`
_(optional)_  The path where the scan log will be saved. If not provided, the default path "C:\Temp\log.txt" will be used.


## Examples: 
AV Scan of backed up virtual machine lnxvm01 on Linux host ubuntusrv01 from backup job demo_vm. Key file key.key used for authentication to Linux server ubuntusrv01
```Powershell
.\vbr-securerestore-iscsi.ps1 -Mounthost "mountsrv01" -Scanhost "lnxhost01" -HosttoScan "myVM01" -Jobname "myBackupJob" -LinuxUser "mylinuxuser" -Keyfile "C:\Path\to\private_key_of_linuxuser.pem" -Restore
```

## Notes
If the -Restore parameter is specified, the restore command is displayed only on the screen. You wonder why? Well, using the given restore command, the virtual machine would be overwritten without confirmation! 

This script has been tested with the following versions of Veeam Backup & Replication
- v12

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
*  1.0
    * Initial Release
  
