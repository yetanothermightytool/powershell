# Veeam Backup & Replication - File Level Recovery - Compare with Production

This PowerShell script enables file level recovery (FLR) for Windows virtual machines using Veeam Backup & Replication. It starts an FLR session, connects to the production VM, and checks for changes in a specified path.

## Features

- Initiates a file level recovery session using Veeam Backup & Replication
- Connects to the production VM and scans for changes in a specified path
- Compares files in the specified path with the original backup to identify changes
- Displays the file name, status, size, and modification date of the changed files
- Works with Windows VMs only

## Usage

Ensure you have Veeam Backup & Replication v12 installed before using this script.

```powershell
.\vbr-flr-comparator.ps1 -VM <VMName> -Drive <DriveLetter> -ScanPath <FolderPath>
```

- `VMName`: The name of the virtual machine to perform FLR on
- `DriveLetter`: The drive letter of the mounted FLR volume (e.g., "C:")
- `FolderPath`: The path to the folder to be scanned for changes (supports wildcards)

Please note that this script requires PowerShell and Veeam Backup & Replication v12.

## Version History

- 1.1
  - Added support for comparing files with the original backup
  - Improved scanning performance
  - Bug fixes

## Disclaimer

This script is not officially supported by Veeam Software. Use it at your own risk.
