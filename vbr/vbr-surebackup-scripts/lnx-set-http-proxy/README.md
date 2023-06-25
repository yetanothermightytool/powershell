# Veeam Backup & Replication - SureBackup - HTTP Proxy Configuration for Linux Virtual Machines 

## Description
~~~~
Version : 1.1 (June 25th 2023)
Author  : Stephan "Steve" Herzig
GitHub  : ([YetAnotherMightyTool](https://www.github.com/yetanothermightytool))
~~~~

## Prerequisites

- Veeam Backup & Replication v12 or later
- PowerShell
- OpenSSH package installed on the host (refer to https://github.com/PowerShell/Win32-OpenSSH/releases)

Adjust the necessary parameters and file paths in the script to match your environment. Modify the following lines to match your environment:

- `$encryptedPassword = Get-Content "<path_to_password_file>"`: Replace `<path_to_password_file>` with the path to your password file.
- `$KeyFile           = "<path_to_key_file>"`: Replace `<path_to_key_file>` with the path to your SSH key file.
	

## Purpose
This script is designed to help you set the HTTP proxy on Linux VMs. It retrieves the HTTP port configuration from the specified virtual lab in Veeam Backup & Replication and uses SSH to connect to the target Linux VM. The script creates a shell script on the fly and uploads it to the VM, granting execute permission and running it to configure the HTTP proxy.


## Parameters
 
- `TestVmIP` (mandatory)   : %vm_ip% (this parameter retrieves the IP address assigned by SureBackup).
- `lnxUsername` (mandatory): Username of the Linux VM.
- `VirtualLab` (mandatory) : Name of the virtual lab containing the HTTP port configuration.

## Example: 
```powershell
PS>.\set-http-proxy.ps1 -TestVmIP %vm_ip% -lnxUsername admin -VirtualLab MyVirtualLab
```

## Notes
Ensure that you have the necessary permissions and connectivity to perform these actions on the target VM.
Tested with Veeam Backup & Replication V12 and Ubuntu Linux VM backups.

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
- 1.1 (June 25th 2023)
   - Parameter for Linux Username and Virtual Lab Name
   - Creating the Linux Shell script on-the-fly
   
- 1.0 (June 16th 2023)
   - Initial release  
