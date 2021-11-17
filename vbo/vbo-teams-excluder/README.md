# VBO Teams Excluder
Powershell script exclude MS Teams sites from a VBO Backup Job using regular expressions

## Description
~~~~
Version : 1.1 (September 14th 2021)
Requires: Veeam Backup for Microsoft Office 365 v5 or later
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Purpose

Veeam Backup for Microsoft Office 365 v5 added purpose-built backup and recovery for Microsoft Teams. Since then many customer and partners asked me "How can we protect all of our teams and exclude specific teams objects based on names automatically?".
As there is no filter logic within the UI for the Backup Job object exclusion list, I solved this "problem" using this script.

## Prerequisites

 Step 1 - Store the credentials (encrypted) in a txt file:

`PS> .\$credential = Get-Credential`

`PS> .\$credential.Password | ConvertFrom-SecureString | Set-Content <path to secure.txt>`

Step 2 - Change values of the following variables

$organizationname     Name of the tenant - Only needed if more than one is configured
$backupjob            Name of existing the Backup Job
$filter               Name of the team that needs to be excluded. Regular expressions can be used
$userName             Username for retrieving the existing Teams in M365
$passwordText         Path to the secure.txt file that has been created in Step 1

## Parameters
`Filter`
_(optional)_ Team name or regular expression.
  
## Example: 

`PS> .\vbo-teams-excluder.ps1 -Filter Demo`  
  
## Notes

This script has been tested with the following versions of Veeam Backup for Office 365:
  - v5.0 - All updates


**Please note this script is unofficial and is not created nor supported by Veeam Software.**
