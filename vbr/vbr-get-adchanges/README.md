# Veeam Backup & Replication - Active Directory Backup Comparator

## Description
~~~~
Version : 1.0 (August 4th 2023)
Requires: Veeam Backup & Replication v12
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Purpose

This script connects to a Veeam Backup & Replication server to retrieve Active Directory restore points. It allows users to compare the data from regular container (cn=Users) and a specified Organizational Unit (OU) in Active Directory with the baseline data. When the script runs for the first time, it creates a baseline data file for comparison.

## Prerequisites

- PowerShell 5.1 or later.
- Veeam Backup & Replication (VBR) server with Active Directory backup jobs configured.

Customize the following variables in the Variables section of the script:

`$baselineJsonFilePath` Location where to store the baseline json files.

`$resultJsonFilePath`   Location where to store the result json files.

## Parameters
 
  `OrganizationUnit`
_(mandatory)_ Name of the OU.


## Example
Compare Active Directory data for the Organization Unit "Sales".

```Powershell
.\vbr-get-adchanges.ps1 -OrganizationUnit "Sales"
```

## Output Files

- `Users-Baseline.json`: Baseline data file for comparison of the regular container (cn=Users).
- `Users-Comparison-<RestorePointDateTime>.json`: Comparison results for the regular container (cn=Users) using the selected restore point.

- `OU-<Your_OU_Name>-Baseline.json`: Baseline data file for comparison of the specified OU.
- `OU-<Your_OU_Name>-Comparison-<RestorePointDateTime>.json`: Comparison results for the specified OU using the selected restore point.

## Notes

This script has been tested with the following versions of Veeam Backup & Replication
- v12

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
*  1.0
    * Initial Release
