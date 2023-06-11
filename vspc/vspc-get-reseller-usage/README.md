# Veeam Service Provider Console - Reseller Reporting Script

This PowerShell script generates a usage report for all managed companies within a reseller in Veeam Service Provider Console (VSPC). It provides information about the used space and licenses for each company. The report includes details such as allocated storage quota, used storage quota, archive tier usage, capacity tier usage, and backup counts for servers, workstations, and virtual machines.

## Features

- Retrieves usage and license information for all managed companies within a reseller in VSPC
- Generates a storage report with details on allocated storage quota and used storage quota
- Provides information on archive tier usage, capacity tier usage, and backup counts
- Displays the report in a tabular format
- Optionally exports the usage and license report to CSV files

## Usage

Ensure you have Veeam Service Provider Console v7 and PowerShell installed before using this script.

```powershell
.\vspc-reseller-report.ps1 -ResellerName <Reseller Name> [-ExportCSV]
```

- `-ResellerName`: Specifies the name of the reseller for which the report needs to be generated.
- `-ExportCSV`: Optional switch to export the usage and license report to CSV files.

## Version History

- 0.2 (pre-release - Tuning the output together with partner)

## Prerequisites

- Veeam Service Provider Console v7
- PowerShell

## Disclaimer

This script is not officially supported by Veeam Software. Use it at your own risk.
