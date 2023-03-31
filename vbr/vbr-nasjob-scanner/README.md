# VBR NAS Job Scanner

## Description
~~~~
Version : 1.0 (March 31 2023)
Requires: Veeam Backup & Replication
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Purpose

This script checks for an unexpectedly high number of files that have been backed up compared to the last times.

The vbr-nasjob-scanner-post-script.ps1 directly logs the information into your Veeam Backup and Replication file share job.


## Parameters
  
  `JobName`
_(mandatory)_ Backup Job name - Only necessary for the vbr-job-scanner.ps1 script

  `Depth`
_(mandatory)_ The number of incremental backups to be used for the analysis

  `Growth`
_(optional)_ Percentage as decimal number. Example: 1.7 equals 70 %

 
## Examples

Check if any of the last 5 incremental backups of Backup Job "demo_nas_job" transferred 50 % more files than the average.

`PS>.\vbr-nasjob-scanner.ps1 -JobName "demo_nas_job" -Depth 5 -Growth 1.5`

The same for a Veeam File Share Backup Job - Advanced Backup Settings/Scripts 
https://helpcenter.veeam.com/docs/backup/vsphere/file_share_backup_job_advanced_scripts.html

`<path to script>\vbr-job-scanner-post-script.ps1 -Depth 5 -Growth 1.5`

  
## Notes

Tested with Veeam Backup & Replication V12

There are two versions of this script:
- vbr-nasjob-scanner.ps1             - For manual execution
- vbr-nasjob-scanner-post-script.ps1 - For use in the Backup Job as post-script


**Please note this script is unofficial and is not created nor supported by Veeam Software.**


* 1.0
    * Initial Release
