# VBR NAS Share Scanner

## Description
~~~~
Version : 1.0 (August 22nd 2022)
Requires: Veeam Backup & Replication v11 and later
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites

A file share backup job protecting an SMB share needs to be configured and sucessfully executed.
Microsoft Defender on the system that scans the presented file share. 

## Purpose

This script launches a Instant File Share Recovery for a specified file share backup job and runs a MS Defender malware scan.

The share access permissions can be adjusted in line 31
The recovery reason can be adjusted in line 34
Any scanning tool can be used. Just replace lines 38 - 42

## Parameters
  
  `JobName`
_(mandatory)_ Name of the File Share Backup Job


## Example: 
`PS>.\vbr-nas-scanner.ps1 -JobName "Demo NAS to Local"
  
## Notes

This script has been tested with the following versions of Veeam Backup & Replication
- v11 latest
- v12 beta2

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History

* 1.0
    * Initial Release
	
## Roadmap
- Parameter to specify the mount server
- Parameter for reason
- Parameter for permissions and permission scope
