# VBO Teams Adder
Powershell script for adding MS Teams sites to an existing Backup Job

## Description
~~~~
Version : 1.0 (March 3rd 2022)
Requires: Veeam Backup for Microsoft 365 v5 or later
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites

 Step 1 - Store the credentials (encrypted) in a txt file:

`PS> .\$credential = Get-Credential`

`PS> .\$credential.Password | ConvertFrom-SecureString | Set-Content <path to secure.txt>`

Step 2 - Change values of the following variables

$organizationname     Name of the M365 tenant - Only needed if more than one is configured
$userName             Username for retrieving the existing Teams in M365
$passwordText         Path to the secure.txt file that has been created in Step 1

## Parameters
`Backupjob`
_(mandatory)_ Name of the Backup Job.

`Filter`
_(mandatory)_ Part of the Team name to add.
  
## Example: 

`PS> .\vbo-teams-adder.ps1 -Backupjob "Demo Teams Backup" -Filter Demo`  
  
## Notes

This script has been tested with the following versions of Veeam Backup for Office 365:
  - v5.0 

**Please note this script is unofficial and is not created nor supported by Veeam Software.**
