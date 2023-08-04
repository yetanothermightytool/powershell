# Veeam Backup & Replication - File Level Recovery - Compare with Production

## Description
~~~~
Version : 1.2 (August 4th 2023)
Requires: Veeam Backup & Replication v12
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Purpose 

This PowerShell script enables file level recovery (FLR) for Windows virtual machines using Veeam Backup & Replication. It starts an FLR session, connects to the production VM, and checks for changes in a specified path. 

- Initiates a file level recovery session using Veeam Backup & Replication
- Connects to the production VM and scans for changes in a specified path
- Compares files in the specified path with the original backup to identify changes
- Displays the file name, status, size, and modification date of the changed files
- Works with Windows VMs only

## Parameters

```powershell
.\vbr-flr-comparator.ps1 -VM <VMName> -RootDirectory <FolderName> -SearchPattern <check item>
```

- `VMName`
_(mandatory)_ The name of the virtual machine to perform FLR on
- `RootDirectory`
_(mandatory)_ The folder Name of one of the root directories. E. g. Windows or Users
- `SearchPattern`
_(mandatory)_ The item(s) be scanned for changes (supports wildcards) - E. g. *.xml
- `LogFilePath`
_(optional)_ Path where the activities should be stored - Defalt C:\Temp\log.txt

Please note that this script requires PowerShell and Veeam Backup & Replication v12.

## Version History
- 1.2
  - Bug fixes / Changed the parameters
  - Automatically selects the latest restore point after 30 seconds
  - Logging functionality
- 1.1
  - Added support for comparing files with the original backup
  - Improved scanning performance
  - Bug fixes

## Disclaimer

This script is not officially supported by Veeam Software. Use it at your own risk.
