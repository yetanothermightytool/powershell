# Veeam Backup for Microsoft 365 Exchange Online Mailbox Recovery Tool
A Powershell script to recover items from specified mailboxes from the lastest VB365 Exchange Online Restore point to another Microsoft organization.


## Description
~~~~
Version : 1.1 (January 23, 2023)
Requires: Veeam Backup for Microsoft 365 v6 or later
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites

- The mailboxes to be restored must be provided in a CSV file and present on the destination tenant - See CSV File Structure
- An configured Azure AD application at the destination M365 tenant with the appropriate rights
  See https://helpcenter.veeam.com/docs/vbo365/guide/ad_app_permissions_sd.html
- The exported certificate (.pfx) of the Azure AD application


## CSV File Structure - Example with two entries
SourceMbx | DestMbxName | DestOrg
| :---:   | :---:       | :---: 
"Joe Doe" | joed@M365x123456.onmicrosoft.com | M365x123456.onmicrosoft.com
"Monitoring" | monitoring@M365x123456.onmicrosoft.com |M365x123456.onmicrosoft.com

## Parameters
`SrcVB365Org`
_(mandatory)_ Source VB365 Organization name

`DstAppId`
_(mandatory)_ Destination Microsoft Azure tenant Application (client)ID

`DstAppCertFile`
_(mandatory)_ Path and file name .pfx file (Application certificate)

`RestoreList`
_(mandatory)_ Path and file name .csv file.
  
## Example

`PS> .\vb365-exo-recovery.ps1 -SrcVB365Org Organization -DstAppId <your-id> -DstAppCertFile C:\temp\cert.pfx -RestoreList C:\Temp\migrator.csv`  

Note: After you have executed the command, you must enter the certificate password!

## Output - Example with Backup Data on Object Storage Repository

| Processed Mailboxes | Created Items | Skipped Items  | Failed Items
| :---:               | :---:         | :---:          | :---: 
| 2                   | 42            | 493            | 0                         

Created Items = Restored Items 
Skipped Items = Items that were already present in destination mailbox
Failed Items  = Something went wrong. Please check the Exchange Explorer Log Files

## Considerations

- Your destination organization belongs to the Worldwide Microsoft Azure region.
- The cmdlet will restore mailbox items that are missing in the target location.

## Notes

This script has been tested with the following versions of Veeam Backup for Office 365:
  - v6.0 (latest)
  - v7.0 (BETA)

## Version History

* 1.1
    * Use modern authentication only
        
* 1.0
    * Inital version using basic authentication

**Please note this script is unofficial and is not created nor supported by Veeam Software.**
