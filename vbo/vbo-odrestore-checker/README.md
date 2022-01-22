# VBO OneDrive for Business Restore Checker
Powershell Script to check restored OneDrive for Business data backed up by Veeam Backup for Microsoft Office 365.

## Description
~~~~
Version : 1.0 (January 21st 2022)
Requires: Veeam Backup for Microsoft Office 365 v5 or later
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites

Save a file in OneDrive for Business and back it up with Veeam Backup for Microsoft Office 365.
Get the hash value with the Powershell command "Get-FileHash".

## Purpose

The script restores the file to a local folder and compares the hash values (SHA-256)

  - Latest backup state will be used for the restore
  - If the compared hash values match the LastExitCode will be 0 otherwise 1

## Parameters
  
  `Scanpath`
_(optional)_ The path and filename where the output gets written to.

 `User`
_(mandatory)_ Name of the User where the OneDrive data is stored.

 `Documentname`
_(mandatory)_ Name of the document.

 `Originalhash`
_(mandatory)_ Hash value (SHA-256) from the original file.


## Example: 
`PS> .\vbo-odrestore-checker.ps1 -User "Hans Dampf" -Documentname Text-File.docx -Originalhash <hashvalue>`
  
## Notes

This script has been tested with the following versions of Veeam Backup for Microsoft Office 365:
- v5.0 latest
- v6.0beta 

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History

* 1.0
    * Initial Release
	
## Planned functions

- Use a specific restore point
- Online analysis of restored file
