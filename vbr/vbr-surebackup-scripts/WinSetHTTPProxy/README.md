# Veeam Backup & Replication - SureBackup - HTTP Proxy Configuration for Windows Virtual Machines 

## Description
~~~~
Version : 1.0 (June 25th 2023)
Author  : Stephan "Steve" Herzig
GitHub  : [https://www.github.com/yetanothermightytool]
~~~~

## Prerequisites

- Veeam Backup & Replication V12

## Purpose
This PowerShell script is designed to configure the HTTP proxy settings on Windows VMs within the Veeam Backup & Replication virtual lab. By specifying the IP address of the target Windows VM and the name of the virtual lab, the script retrieves the HTTP port configuration and applies the necessary changes to enable and set the proxy server settings on the Windows VM.

## Parameters
 
- `TestVmIP`   (mandatory): %vm_ip% (this parameter retrieves the IP address assigned by SureBackup).
- `VirtualLab` (mandatory): Name of the virtual lab containing the HTTP port configuration.


## Notes
Ensure that you have the necessary permissions and connectivity to perform these actions on the target Windows VM.
Tested with Veeam Backup & Replication V12.

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
- 1.0 (June 25th 2023)
   - Initial release
