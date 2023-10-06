# Entra ID Protector

## Version Information
~~~~
Version: 1.2 (October 1st 2023)
Author: Stephan "Steve" Herzig
~~~~

**Entra ID Protector** is a versatile Powershell script designed to help export data from Microsoft Entra ID. It offers various functionalities to export and compare data, making it an essential tool for administrators looking to secure their organization's user and group data (& more).

## Features

- **Data Export**: Export user, group, application, and role data from your Microsoft 365 environment to maintain backups or perform data analysis. The Data Export uses the Entra Exporter Powershell Module.

- **Audit Log Export**: Retrieve and export audit logs for monitoring and compliance purposes.

- **User and Group Comparison**: Compare user and group data across multiple exports to identify changes and discrepancies.

- **Users Recycle Bin Management**: Manage deleted users in the Microsoft 365 Recycle Bin, allowing for easy restoration when needed.

## Webmenu
The entraid-protector-webmenu.ps1 script offers a nice UI for using all the functions provided by the script.

Modify the following variables within the script

- `$scriptPath`        : Path where the entraid-protector.ps1 script is located.
- `$exportRootFolder`  : Path where the exports get stored.
- `$LogFilePath`       : Path of the log file where some of the activities are logged.

## Requirements

- PowerShell 5.1 or higher. (Test with version 7.x ongoing)

- Microsoft 365 admin credentials with appropriate permissions for the actions you intend to perform.

  Permission details coming soon.

## Variables to be modified
- `$exportRootFolder` : Specifies the path to the directory containing the exports.
- `auditExportFolder` : Path to the directory containing the audit log exports.
- `$maxExportCount`    : The maximum number of export folders. This number ensures that the number of export folders in the $exportRootFolder does not exceed a specified maximum count. If the maximum export count is reached, a function removes the oldest folder to make space for a new one. (Retention)
- `$LogFilePath`       : Path of the log file where some of the activities are logged.

## Parameters
The script accepts the following parameters:

- `Export`              : Exports data related to Users, Groups, Applications, and Roles, rotates and renames existing export folders, and saves the exported data in JSON format.
- `AuditExport`         : (Optional) Exports audit logs, particularly Azure AD audit logs, for the last 24 hours and saves them in JSON format.
						  Parameter must be given together with -Export
- `Users`               : Displays export user data (such as UserPrincipalName, DisplayName) from the latest export.
- `Groups`              : Displays group data, and if a specific group is selected, it also displays its members.
- `SecurityGroups`      : Displays security group data, and if a specific group is selected, it also displays its members and offers the option to import the data back into Entra ID (Experimental).
- `Applications`        : Displays application registration data, including certificate expiration dates if available.
- `Roles`               : Displays role data, and if a specific role is selected, it also displays its members.
- `CompareUserCount`    : Compares user count between latest export and older export folders.
- `CompareSpecificUser` : Searches for a user by UserPrincipalName, compares the data between the last and the specified export.
- `GetRecycleBin`       : Retrieves information about deleted users in the recycle bin. It allows restoring deleted users.
folder, and a given export folder (-ExportNo) and displays the differences.
- `ExportNo`            : Display data for a specific export folder. The export folders are numbered at the end of the folder name where 1 is the most recent export after the last export. Works with Users, Groups, SecurityGroups, Applications, and Roles parameter.
- `InstallModules`      : Checks for the existence of certain PowerShell modules (EntraExporter, and MSGraph) and installs them if not found.
- `LogFilePath`         : (Optional) Path to the log file. Default C:\Temp\entra-id-protector-log.txt"

Examples:

Export data including Audit Logs

   ```powershell
   PS C:\> .\entraid-protector.ps1 -Export -AuditExport
   ```

Get all the exported user information from Export number 3
   ```powershell
   PS C:\> .\entraid-protector.ps1 -Users -ExportNo 3
   ```

## Known Issues
If a smaller $maxExportCount value is specified after the script has already created exports, the older export directories may not be deleted.

When using the CompareSpecificUser function, no error message appears if an incorrect UPN is specified. Will be fixed in a later release.

## Experimental 
There is an option to import back the selected Security Group incl. their assigned members and owner configuration (-SecurityGroup). Here I need a more in-depth analysis and an exchange with experts to grasp the considerations and limitations.

## Acknowledgments

Special thanks to the Powershell community for their valuable contributions and inspiration.

## Version History
* 1.2
    * Replacing AzureADPreview commands with the equivalent Get-Mg command
    * Updating Check Module section
* 1.1
    * SecurityGroups option, incl. import function (experimental)
    * Replacing MSOnline command with MS Graph Command
    * Adding known issues
    * Logging function
* 1.0
    * Initial Release 
