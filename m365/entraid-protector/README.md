# Entra ID Protector

## Version Information
~~~~
Version: 1.1 (September 13th 2023)
Author: Stephan "Steve" Herzig
~~~~

**Entra ID Protector** is a versatile Powershell script designed to help export data from Microsoft Entra ID. It offers various functionalities to export and compare data, making it an essential tool for administrators looking to secure their organization's user and group data (& more).

## Features

- **Data Export**: Export user, group, application, and role data from your Microsoft 365 environment to maintain backups or perform data analysis. The Data Export uses the Entra Exporter Powershell Module.

- **Audit Log Export**: Retrieve and export audit logs for monitoring and compliance purposes.

- **User and Group Comparison**: Compare user and group data across multiple exports to identify changes and discrepancies.

- **Users Recycle Bin Management**: Manage deleted users in the Microsoft 365 Recycle Bin, allowing for easy restoration when needed.

## Requirements

- PowerShell 5.1 or higher.

- Microsoft 365 admin credentials with appropriate permissions for the actions you intend to perform.

  Permission details coming soon.

## Variables to be modified
- `$exportRootFolder ` : Specifies the path to the directory containing the exports.
- `$maxExportCount`    : The maximum number of export folders. This number ensures that the number of export folders in the $exportRootFolder does not exceed a specified maximum count. If the maximum export count is reached, a function removes the oldest folder to make space for a new one.

## Parameters
The script accepts the following parameters:

- `Export`              : Exports data related to Users, Groups, Applications, and Roles, rotates and renames existing export folders, and saves the exported data in JSON format.
- `AuditExport`         : (Optional) Exports audit logs, particularly Azure AD audit logs, for the last 24 hours and saves them in JSON format.
						  Parameter must be given together with -Export
- `Users`               : Displays export user data (such as UserPrincipalName, DisplayName) from the latest export
- `Groups`              : Displays group data, and if a specific group is selected, it also displays its members.
- `Applications`        : Displays application data, including certificate expiration dates if available.
- `Roles`               : Displays role data, and if a specific role is selected, it also displays its members.
- `CompareUserCount`    : Compares user count between latest export and older export folders.
- `CompareSpecificUser` : Searches for a user by UserPrincipalName, compares their data between different the latest export 
- `GetRecycleBin`       : Retrieves information about deleted users in the recycle bin. It allows restoring deleted users.
folder, and a given export folder (-ExportNo) and displays the differences.
- `ExportNo`            : Display data for a specific export folder. The export folders are numbered at the end of the folder name where 1 is the most recent export after the last export. Works with Users, Groups, Applications, and Roles parameter
- `InstallModules`      : Checks for the existence of certain PowerShell modules (EntraExporter, and AzureADPreview) and installs them if not found.

Examples:

Export data including Audit Logs

   ```powershell
   PS C:\> .\entraid-protector.ps1 -Export -AuditExport
   ```

Get all the exported user information from Export number 3
   ```powershell
   PS C:\> .\entraid-protector.ps1 -Users -ExportNo 3
   ```

## Notes

The AzureADPreview Powershell module is used for getting the Audit Directory & Audit Sign In Logs (Get-AzureADAuditDirectoryLogs & Get-AzureADAuditSignInLogs).

## Acknowledgments

Special thanks to the Powershell community for their valuable contributions and inspiration.

## Version History
* 1.1
    * Replacing MSOnline command with MS Graph Command
* 1.0
    * Initial Release 
