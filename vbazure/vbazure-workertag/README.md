# VBAzure - Worker "Tagger"
Powershell script to modify the Worker tag and query the tag informations 

## Description
~~~~
Version : 1.0 (Febuary 15th 2022)
Requires: Veeam Backup for Microsoft Azure v3 and Powershell
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Purpose

This script sets the Worker tag value which given as commandline parameter.

## Parameters
  
  `VBAzurehost`
_(mandatory)_ Hostname or IP address of the Veeam Backup for Microsoft Azure appliance

 `Get`
_(flag)_ Get flag

 `Set`
_(flag)_ Set flag

 `TagName`
_(value)_ Tag name to be applied

 `TagValue`
_(value)_ Tag value. Please consider the MS naming conventions.

## Examples:

#Set the tag name "worker" and the value "bkp-department
`PS> .\vbazure-workertag.ps1 -VBAzurehost veeambackup.domain.local -Set -TagName worker -TagValue bkp-department`

#Get all tags
`PS>     .\vbazure-workertag.ps1 -VBAzurehost veeambackup.domain.local -Get`
  
## Notes

This script has been tested with the following versions of Veeam Backup for Microsoft Azure
- v3.0
 
**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History

* 1.0
    * Initial Release
