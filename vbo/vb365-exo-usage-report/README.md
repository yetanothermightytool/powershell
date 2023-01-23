# Veeam Backup for Microsoft 365 Exchange Online Usage Report
Powershell script that shows the total number of Exchange Online mailboxes, backed up mailboxes, the total mailbox size in Microsoft 365 (incl. deleted items) and the stored backups on the Local or Object Storage Repository.

## Description
~~~~
Version : 1.2 (January 13th 2023)
Requires: Veeam Backup for Microsoft 365 v6 or later
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites *** Update Userguide Link ***

- Exchange Online Powershell Module V3 (Script installs it, when missing)
- An Azure AD application with the appropriate rights. How-to guide: https://community.veeam.com/discussion-boards-66/configure-exchange-online-certificate-based-authentication-to-automate-the-exchange-online-powershell-scripts-4039
- Change values of the following variables:

`$MSOrganization`               M365 Organization name

`$applicationID`                Application ID of the required Application within Microsoft Azure AD. 

`$certificationThumbPrint`      Thumbrpint of the uploaded certificate for accessing the application

## Parameters
`Organization`
_(mandatory)_ Name of the VB365 Organization

`Reponame`
_(mandatory)_ Name of the VB365 Repository where Exchange Online Data is stored
  
## Example

`PS> .\vb365-exo-usage-report.ps1 -Organization Organization01 -Reponame "Object Repository 01"`  

## Output - Example with Backup Data on Object Storage Repository

| M365 Mailboxes | Backed up Mailboxes on Repo | M365 Mailbox Size (MB)  | Stored on Local Repo (MB) | Stored on Object Repo (MB) | Data Reduction in % | Used Capacity per User (MB)
| :---:          | :---:                       | :---:                   | :---:                     | :---:                      | :---:               | :---:
| 28             | 6                           | 142                     | 0                         | 116                        | 22                  | 19


## Notes

This script has been tested with the following versions of Veeam Backup for Office 365:
  - v6.0 (latest)
  - v7.0 (BETA)

## Version History

* 1.2
    * Using application authentication with certificate
    * Calculation of used capacity per stored mailbox/user (average value)
    * The old script using the basic authentication method is renamed to vb365-exo-usage-report-basicauth.ps1

* 1.1
    * Only the size of the protected mailboxes gets reported in column "M365 Mailbox Size"
    * Group Mailbox Support (Thanks Mildur for the feedback)
    * Round up Repository values
    * Added Data Reduction Percentage column

## Planned functions

- OneDrive for Business (Checking possibilites)

**Please note this script is unofficial and is not created nor supported by Veeam Software.**
