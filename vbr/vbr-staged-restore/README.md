# Veeam Backup & Replication - Staged VM Restore

~~~~
Version : 1.1 (July 30th 2023)
Requires: Veeam Backup & Replication v12
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Overview
This PowerShell script is designed to perform a staged virtual machine (VM) restore using Veeam Backup & Replication. It connects to the Veeam server, retrieves the necessary information, lists the available VM restore points, allows the user to select a restore point, and initiates the staged VM restore process.

## Prerequisites

- Veeam Backup & Replication V12
- Access to the Veeam Backup & Replication server
- Properly configured credentials and virtual lab in Veeam Backup & Replication
- Windows PowerShell version 5 or later

## Parameters
The script accepts the following parameters:
 
  `ESXiServer`
_(mandatory)_ The name of the ESXi server where the VM will be restored.

  `VMName`
_(mandatory)_ The name of the VM to be restored.

  `Jobame`
_(mandatory)_ The name of the Veeam backup job that contains the VM

  `VirtualLab`
_(mandatory)_ The name of the virtual lab to use for staging the restore

  `StagingScript`
_(mandatory)_ The path to the script that will be executed during the staging process

  `Credentials`
_(mandatory)_ The name of the configured credentials for executing the staging script

  `LogFilePath`
_(optional)_ Logging the activities - Default is C:\Temp\log.txt

## Example: 
`PS>.\vbr-staged-restore.ps1 -ESXiServer "ESXiServerName" -VMName "VMName" -Jobname "BackupJobName" -VirtualLab "VirtualLabName" -StagingScript "Path\To\StagingScript.ps1" -Credentials "CredentialsName"

Replace the parameters in quotes with your values.
  
## Notes
Ensure that you have the necessary permissions and credentials to execute the script and perform the staged VM restore.
A sample script for an AV scan - WinAVDeepScan.ps1 - can be found in this directory as well (Windows VM)

If no restore point is selected in the selection menu, the last restore point is restored after 30 seconds.

This script has been tested with the following versions of Veeam Backup & Replication
- v12

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
*  1.1
    * Function to log the activities (Start the script)
    * Automatically selects the latest restore point after 30 seconds
*  1.0
    * Initial Release
