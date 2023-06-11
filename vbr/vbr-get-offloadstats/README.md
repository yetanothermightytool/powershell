# Veeam Backup & Replication - Offload Job Statistics (Transferred Size)

This PowerShell script displays the offloaded capacity to an object storage repository for a specific backup job in Veeam Backup & Replication. It provides information about the date of offload, job name, and transferred size in gigabytes (GB).

## Features

- Retrieves offload job sessions from Veeam Backup & Replication
- Filters sessions based on the specified scope (number of days back)
- Retrieves the transferred size in gigabytes (GB) for the specified job
- Displays the offload statistics in a table format

## Usage

Ensure you have Veeam Backup & Replication v12 installed before using this script.

```powershell
.\vbr-get-offloadstats.ps1 -Scope <number_of_days> -JobName <job_name>
```

- `-Scope`: Number of days back you want to retrieve offload statistics.
- `-JobName`: Name of the backup job pointing to a Scale-out Backup Repository (SOBR) with a Capacity Tier.

Please note that this script requires PowerShell and Veeam Backup & Replication v12.
Important: Using unofficial .NET method 

## Version History

- 1.0
  - Initial release

## Disclaimer

This script is not officially supported by Veeam Software. Use it at your own risk.
