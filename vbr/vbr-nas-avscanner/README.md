# VBR NAS Share Scanner

## Description
~~~~
Version : 1.4 (March 1st 2024)
Requires: Veeam Backup & Replication
Author  : Stephan "Steve" Herzig
~~~~

## Prerequisites

A file share backup job protecting an SMB share needs to be configured and sucessfully executed.
Microsoft Defender on the system that scans the presented file share. 

## Purpose

This script launches a Instant File Share Recovery for a specified file share backup job and runs a MS Defender malware scan.

The share access permissions can be adjusted in line 71
The recovery reason can be adjusted in line 74
Any scanning tool can be used. Just replace lines 78++ if you don't want to use Defender.

## Parameters
  
  `JobName`
_(mandatory)_ Name of the File Share Backup Job

 `LogFilePath`
_(optional)_ Default is C:\Temp\log.txt


## Example: 
`PS>.\vbr-nas-scanner.ps1 -JobName "Demo NAS to Local"
  
## Notes

This script has been tested with the following versions of Veeam Backup & Replication
- v12.1.1

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
* 1.4
    * New logger
    * Using new Powershell cmdlets for V12 (Get-VBRUnstructured*)
* 1.3
    * New function to log the activities - Parameter LogFilePath. Default C:\Temp\log.txt
    * Automatically selects restore point 0 after 30 seconds
* 1.2
    * Script now presents the Event Log entries done by Microsoft Defender
    * corrections
* 1.1
    * Restore Point selection
    * Bugfixes
* 1.0
    * Initial Release (Renamed to vbr-nas-avscanner on World Backup Day ;))
	
## Roadmap
- Parameter to specify the mount server
- Parameter for reason
- Parameter for permissions and permission scope
