# Veeam Backup for Microsoft 365 Exchange Online Mailbox Recovery Tool
A Powershell script to recover items from certain mailboxes from the last VB365 Exchange Online Restore point to another Microsoft organization.


## Description
~~~~
Version : 1.1 (January 23, 2023)
Requires: Veeam Backup for Microsoft 365 v6 or later
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites

- The mailboxes to be restored must be provided in a CSV file and present on the destination tenant - See CSV File Structure
- An Azure AD application at the destination M365 tenant with the appropriate rights. 
  See https://helpcenter.veeam.com/docs/vbo365/guide/adding_o365_organizations_sd.html
- The exported certificate (.pfx) of the Azure AD application


## CSV File Structure
SourceMbx | DestMbxName | DestOrg
| :---:   | :---:       | :---: 
"Joe Doe" | joed@M365x123456.onmicrosoft.com | M365x123456.onmicrosoft.com
| :---:   | :---:       | :---: 
"Monitoring" | monitoring@M365x123456.onmicrosoft.com |M365x123456.onmicrosoft.com

## Parameters
`SourceVB365Org`
_(mandatory)_ Name of the VB365 Organization 

`DestAppId`
_(mandatory)_ Application ID destination Microsoft Azure tenant

`DestCertPath`
_(mandatory)_ Path and file name of .pfx file (Application certificate)

`RestoreList`
_(mandatory)_ Path and file name of the csv file.
  
## Example

`PS> .\vb365-exo-recovery.ps1 -SourceVB365Org Organization -DestAppId <your-id> -DestAppCertPath C:\temp\cert.pfx -RestoreList C:\Temp\migrator.csv`  

## Output - Example with Backup Data on Object Storage Repository

| Processed Mailboxes | Created Items | Skipped Items  | Failed Items
| :---:               | :---:         | :---:          | :---: 
| 10                  | 42            | 493            | 0                         

## Considerations

- Your destination organization belongs to the Worldwide Microsoft Azure region.
- The cmdlet will restore mailbox items that are missing in the target location.

## Notes

This script has been tested with the following versions of Veeam Backup for Office 365:
  - v6.0 (latest)
  - v7.0 (BETA)

## Version History

* 1.1
    * Use modern authentication
        
* 1.0
    * Inital version using basic authentication

**Please note this script is unofficial and is not created nor supported by Veeam Software.**
