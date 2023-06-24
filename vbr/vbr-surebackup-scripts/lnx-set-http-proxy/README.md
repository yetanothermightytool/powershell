# Set HTTP Proxy Script

## Description
This script is designed to help you set the HTTP proxy on Linux VMs. It uses SSH and SCP to upload a shell script to the VM, set execute permissions, and then run the script to configure the HTTP proxy settings. 
~~~~
Version : 1.0 (June 16th 2023)
Requires: Veeam Backup & Replication V12 and later
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites

Before using this script, make sure that you meet the following requirements:

- Install the latest Win OpenSSH on the VBR server
- SSH access to the target Linux VM
- The SSH key file required for authentication on the Linux VM
- Add the Public Key to the known_hosts file of the user profile directory for the system account (Veeam Service runs under the system account)
- Store the Linux user password as a secure string on the VBR server

## Powershell Script Usage

Adjust the necessary parameters and file paths in the script to match your environment. Modify the following lines to match your environment:

- `$encryptedPassword = Get-Content "<path_to_password_file>"`: Replace `<path_to_password_file>` with the path to your password file.
- `$KeyFile           = "<path_to_key_file>"`: Replace `<path_to_key_file>` with the path to your SSH key file.
- `scp -i $Keyfile "<path_to_shell_script>" administrator@${TestVmIp}:/tmp/set-http-proxy.sh`: Replace `<path_to_shell_script>` with the path to your shell script file. This file will be uploaded to the VM.

## Linux Script
Adjust the user account in the set-http-proxy.sh script.

Locate the line that contains the references to the user account in the following sections:

   ```bash
   echo "export http_proxy=${http_proxy}" >> /home/administrator/.bashrc
   echo "export https_proxy=${http_proxy}" >> /home/administrator/.bashrc
   ```

   Replace both occurrences of "administrator" with the actual username of the desired user account.

**Notes** 
Ensure that you have the necessary permissions and connectivity to perform these actions on the target VM.
Tested with Veeam Backup & Replication V12 and Ubuntu Linux VM
