# Veeam Backup & Replication - Get Object Storage Usage

This PowerShell script retrieves the used capacity in an object storage repository configured in Veeam Backup & Replication. It provides information about the repository name, usage in gigabytes (GB), and whether backup immutability is enabled.

## Features

- Retrieves object storage repository information from Veeam Backup & Replication
- Calculates and displays the used capacity in gigabytes (GB) for each repository
- Indicates whether backup immutability is enabled for each repository

## Usage

Ensure you have Veeam Backup & Replication v12 installed before using this script.

```powershell
.\vbr-get-objectstorageusage.ps1
```

The script will retrieve information for all object storage repositories configured in Veeam Backup & Replication.

Please note that this script requires PowerShell and Veeam Backup & Replication v12. 
Important: Using unofficial .NET method 

## Version History

- 1.0
  - Initial release

## Disclaimer

This script is not officially supported by Veeam Software. Use it at your own risk.
