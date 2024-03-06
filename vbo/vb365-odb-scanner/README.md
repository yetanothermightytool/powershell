# Veeam Backup for Microsoft 365 - OneDrive for Business Backup Scanner


## Version
~~~~
Version : 1.2 (March 6th, 2024)
Requires: Veeam Backup for Microsoft 365 v7 or later
Author  : Steve Herzig
~~~~

## Description
This Powershell script restores files from the lastest OneDrive for Business restore point and scans them for threats using Windows Defender. It requires parameters such as the target user and maximum number of files to scan. 

The script connects to the local Veeam Backup for Microsoft 365 server, restores files for the specified user, scans them for threats using Windows Defender, and provides detailed threat information if any are found. Finally, it cleans up the scanned files and disconnects 

## Parameters
`User`
_(mandatory)_ Username User name from which the data is to be restored

`MaxFiles`
_(mandatory)_ Maximum number of files to be restored. Default C:\Scripts\vb365\scanner\

`File`
_(optional)_ File name or file extension (e. g. .exe) for single or specific files scan.

`ScanPath`
_(optional)_ Restore path. Default C:\Scripts\vb365\scanner\

**Make sure that there is sufficient disk space in the directory where the files are to be restored. Also use an empty directory to save the data, as the script cleans everything up after execution**

## Example - Restore 100 files from the backup data of John Doe  :

```powershell
.\vb365-odb-single-scan.ps1 -User "John Doe" -MaxFiles 100
```

## Notes

This script has been tested with the following versions of Veeam Backup for Office 365:
  - v7.1 (latest)
  - v7.0 (latest)

## Version History
* 1.2
    * Single File or specific file extension scan
    * Colorized output
* 1.1
    * Fixing Defender Output when no threads have been found
    * Current version only restores data from the latest restore point
    * Checks if a retore session is already running. If yes, the scan will not start.
    * General fixes / Code cleanup       
* 1.0
    * Inital version using basic authentication

**Please note this script is unofficial and is not created nor supported by Veeam Software.**
