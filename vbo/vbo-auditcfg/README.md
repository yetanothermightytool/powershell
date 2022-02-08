# VBO Audit Item Configurator
Powershell script to configure the audited items (user) and set the audit notification settings

## Description
~~~~
Version : 1.0 (Febuary 7th 2022)
Requires: Veeam Backup for Microsoft Office 365 v5
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Purpose

This script configures a user to be audited.
More information about this feature on https://helpcenter.veeam.com/docs/vbo365/rest/audititems.html
    
Optionally the email notification settings can be set. (See Parameters)


## Parameters
  
  `Username`
_(mandatory)_ Username of the user to be audited

 `SetAuditNotification`
_(optional)_ Configures the Audit Notification settings. Please change the SMTP server settings within the script.

  
## Example: 
`PS> .\vbo-auditcfg.ps1 -Username "username@abc.onmicrosoft.com"`
  
## Notes

This script has been tested with the following versions of Veeam Backup for Microsoft Office 365:
- v5.0 - All versions

 Script connects the the RestAPI service running on localhost. The URL can be changed on the line containing this variable:

`$veeamAPI = "https://localhost:4443"`

The script is still "work in progress". Feedback welcome.

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Roadmap
- Audit groups
- Pass the audit notification settings as parameters
- Remove Audit Item Settings

## Version History

* 1.0
    * Initial Release
