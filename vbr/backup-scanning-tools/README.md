# Backup Scanning Tools Menu

## Version Information
~~~~
Version: 1.0 (July 24th 2023)
Requires: Veeam Backup & Replication v12 / Scanning Tools downloaded (see Prerequisites)
Author: Stephan "Steve" Herzig and many others (See "Special thanks")
GitHub: [https://www.github.com/yetanothermightytool](https://www.github.com/yetanothermightytool)
~~~~

## Description
This script is designed to provide a user-friendly, menu-driven interface for triggering the various backup scan tools. It allows the user to choose from a number of options, each corresponding to a specific type of backup scan. The script contains detailed descriptions of each scan operation before prompting the user to enter the necessary parameters for its execution.

## Prerequisites

- PowerShell version 5.1
- Internet access to download the scripts from the YAMT (Yet Another Mighty Tool) Git repository.
- All prerequisites for the individual scanning scripts (see the corresponding readme)

## Installation 
1. **Download the Installer Script**

   Download the `backup-scanning-tools-installer.ps1` script from this repository to your local machine.

2. **Open PowerShell**

   Open a PowerShell terminal with administrator privileges.

3. **Run the Installer Script**

   Execute the `backup-scanning-tools-installer.ps1` script with the required parameter `-InstallDir`. This parameter specifies the directory where the backup scanning scripts will be installed.

   For example:
   ```powershell
   PS C:\> .\backup-scanning-tools-installer.ps1 -InstallDir "C:\Scripts\scanningtools"
   ```

   Replace `"C:\Scripts\scanningtools"` with the path to the directory where you want to install the backup scanning tools.

Once the installation is complete, you can use the backup scanning tools from the specified installation directory. Run the menu script, and it will call the required backup scanning scripts based on the user's selection from the menu.


## Variable to be modified in the "Backup-Scanning-Tools-Menu" script

- `$scanningToolsPath`: Specifies the path to the directory containing the scanning tools (scripts) used in the different scanning operations.

## Menu Options

The script presents the user with a menu of backup scanning options. The options are:

1. **Secure Restore - AV Scan**: This option performs an anti-virus file-level scan on a selected restore point of a Veeam VM or Agent backup using the ClamAV antivirus software. The user needs to provide details such as the host to attach the backup to, the host to perform the scan, the backup job name, and the SSH key path & file name for authentication.

2. **Secure Restore - YARA Scan**: This option performs a YARA scan on a selected restore point of a Veeam VM or Agent backup. YARA is a tool designed for identifying and classifying malware. Similar to the AV scan option, the user needs to provide the necessary details for the scanning process.

3. **Instant VM Disk Recovery Scan**: This option is specific to Instant VM Disk Recovery and allows the user to attach disk(s) to a virtual machine (VM) for scanning. The VM should start from the attached Rescue ISO rather than from its hard drive. The user is prompted to input the VM to attach disk(s) to, the host to perform the scan, and the backup job name.

4. **NAS Backup Scan**: This option initiates a scan on a NAS backup using a designated backup job name.

5. **Staged VM Restore**: This option triggers a staged VM recovery on a specified ESXi server. The script will then run the provided staging script. If the script runs successfully, the VM is restored into production. Users need to input details such as the target ESXi server, VM name, backup job name, virtual lab name, staging script (full path), and credentials for the script.

6. **Exit**: This option allows the user to - what a surprise - exit the script. Before exiting, it asks for confirmation.

## How to Use

The user needs to run the script, and the menu with the listed options will be displayed. To select an option, the user enters the corresponding number. Depending on the chosen option, the script will prompt for specific parameters to execute the selected scanning operation. After processing the scan, the script will return to the menu for further actions.

## Notes

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History

* 1.0
    * Initial Release
