# VBO Repo Userlist
Powershell script to get a list of user data stored in the given repository

## Description
~~~~
Version : 1.1 (June 9th 2023)
Requires: Veeam Backup for Microsoft 365 v7
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Parameters
  
  `RepoName`
_(mandatory)_ Name of the repository to be queried

  
## Example: 
```powershell
.\vbo-auditcfg.ps1 -RepoName "Local Repository"`
```
## Notes

This script has been tested with the following versions of Veeam Backup for Microsoft Office 365:
- v7.0

 Script connects the the RestAPI service running on localhost. The URL can be changed on the line containing this variable:

`$veeamAPI = "https://localhost:4443"`

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
* 1.1
    * Rename to VB365
    * v7 API endpoints
    * Output in table format with total
* 1.0
    * Initial Release
