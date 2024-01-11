# Veeam Backup & Replication - Guest Index Data Scan Manager


## Description
~~~~
Version : 1.0 (January 11th 2024)
Requires: Veeam Backup & Replication v12.1
Author  : Stephan "Steve" Herzig
~~~~

## Purpose 

This PowerShell script is designed for Veeam Backup & Replication to manage suspicious files and malware detection settings (Guest Index Data Scan Manager). It provides functionalities for listing, searching, and customizing suspicious file entries, as well as exporting and importing settings.

## Features

- List and display suspicious file entries
- Check if a specific suspicious file entry exists
- Export suspicious file entries to a CSV file
- Add custom entries to the Includes or Excludes section
- Import custom settings into Veeam Backup & Replication

## Parameters



- `List`
List all entries in the C:\Program Files\Veeam\Backup and Replication\Backup\SuspiciousFiles.xml file
- `Search`
Search for a specific file name or file extension in C:\Program Files\Veeam\Backup and Replication\Backup\SuspiciousFiles.xml. Must be used with the EntryToCheck parameter
- `EntryToCheck`
The filename or file extension
- `CustomInclude`
Add a value into the suspicious files list. The AddEntry parameter is needed
- `CustomExclude`
Add avalue into the trusted files list. The AddEntry parameter is needed
- `ExportCSV`
Exports the entries from C:\Program Files\Veeam\Backup and Replication\Backup\SuspiciousFiles.xml into SuspiciousFiles.csv
- `ExportPath`
Path where the CSV and Custom Exclude/Include list should be stored. Default is C:\Temp

## Examples

Just display the number of entries
```powershell
.\vbr-guest-index-data-scan-manager.ps1
```

Search if chilli.exe is in the SuspiciousFiles.xml file
```powershell
.\vbr-guest-index-data-scan-manager.ps1 -Search -EntryToCheck chilli.exe
```

Add *.thisisnotOK into the suspicious files list
```powershell
.\vbr-guest-index-data-scan-manager.ps1 -CustomInclude -AddEntry *.thisisnotOK
```

## Version History
- 1.0
  - Intial version

## Disclaimer
This script is not officially supported by Veeam Software. Use it at your own risk.
