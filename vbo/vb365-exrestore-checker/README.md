# VBO Exchange Restore Checker
Powershell Script to check restored Exchange Online data backed up by Veeam Backup for Microsoft 365.

## Description
~~~~
Version : 1.1 (June 9th 2023)
Requires: Veeam Backup for Microsoft 365 v7
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites

Send an email with with a subject and text of your choice to a specific mailbox, which will then be backed up with Veeam Backup for Microsoft 365. This email can then be searched and restored using this script.

## Purpose

The script restores an e-mail to a local folder and checks if it can be read.

    - Latest backup state will be used for the restore
	- If the pattern can be read from the restored email LastExitCode will be 0 otherwise 1

## Parameters
  
  `Scanpath`
_(optional)_ The path and filename where the output gets written to.

 `Mailbox`
_(mandatory)_ Name of the mailbox where the e-mail item is stored

`Subject`
_(mandatory)_ Subject name of e-mail

 `Pattern`
_(mandatory)_ Search string (text) that should be found within the e-mail msg file


## Example: 
```powershell
.\vbo-exrestore-checker.ps1 -Mailbox Monitoring -Subject vbo-exchecker -Pattern VBO-EX`
```
## Notes

This script has been tested with the following versions of Veeam Backup for Microsoft Office 365:
- v7.0

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
* 1.1
    * Rename to VB365
    * Adjustments for VB365 v7
    * Adjustments to output
* 1.0
    * Initial Release
	
## Planned functions
- use a specific restore point
