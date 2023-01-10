# Veeam Backup for Microsoft 365 Exchange Online Usage Report
Powershell script that shows the total number of Exchange Online mailboxes, backed up mailboxes, the total mailbox size in Microsoft 365 (incl. deleted items) and the stored backups on the Local or Object Storage Repository.

## Description
~~~~
Version : 1.1 (January 10th 2023)
Requires: Veeam Backup for Microsoft 365 v6 or later
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites

- Exchange Online Powershell Module V3 (Script installs it, when missing)
- Store the credentials (encrypted) in a txt file:

`PS> .\$credential = Get-Credential`

`PS> .\$credential.Password | ConvertFrom-SecureString | Set-Content <path to secure.txt>`

- Change values of the following variables

`$userName`             Username for retrieving Exchange Online Information (use the same username as in step 1)

`$passwordText`         Path to the secure.txt file that has been created in advance

## Parameters
`Organization`
_(mandatory)_ Name of the VB365 Organization

`Filter`
_(mandatory)_ Name of the VB365 Repository where Exchange Online Data is stored
  
## Example

`PS> .\vb365-exo-usage-report.ps1 -Organization Organization01 -Reponame "Object Repository 01"`  

## Output - Example with Backup Data on Object Storage Repository

| M365 Mailboxes | Backed up Mailboxes on Repo | MS365 Mailbox Size (MB) | Stored on Local Repo (MB) | Stored on Object Repo (MB) | Data Reduction in %
| :---:          | :---:                       | :---:                   | :---:                     | :---:                      | :---:
| 28             | 6                           | 363                     | 0                         | 115.71345                  | 22


## Notes

This script has been tested with the following versions of Veeam Backup for Office 365:
  - v6.0 (latest)
  - v7.0 (BETA)

## Version History

* 1.1
    * Only the size of the protected mailboxes gets reported in column "M365 Mailbox Size"
    * Round up Repository values
    * Added Data Reduction Percentage column

## Planned functions

- Switching to Application Authentication
- OneDrive for Business (Checking possibilites)

**Please note this script is unofficial and is not created nor supported by Veeam Software.**
