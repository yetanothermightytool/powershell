# VBR Job Scanner (name not final yet)

## Description
~~~~
Version : 1.0 (March 24th 2023)
Requires: Veeam Backup & Replication
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Purpose

This script checks if any of the x incremental backups (Depth) is y% larger (Growth) than the average. 
The vbr-job-scanner-post-script.ps1 directly logs the information into your Veeam Backup and Replication job.

![alt text](https://github.com/yetanothermightytool/powershell/blob/master/vbr/vbr-job-scanner/pictures/job-bad.png)

## Parameters
  
  `JobName`
_(mandatory)_ Backup Job name - Only necessary for the vbr-job-scanner.ps1 script

  `Depth`
_(mandatory)_ The number of incremental backups to be used for the analysis

  `Growth`
_(mandatory)_ Percentage as decimal number. Example: 1.7 equals 70 %


## Examples

Check if any of the last 5 incremental backups of Backup Job "demo_job" is  50 % larger than the average

`PS>.\vbr-job-scanner.ps1 -JobName "demo_job" -Depth 5 -Growth 1.5`

The same for a Veeam Backup Job - Advanced Backup Settings/Scripts
https://helpcenter.veeam.com/docs/backup/vsphere/backup_job_advanced_scripts_vm.html

`<path to script>\vbr-job-scanner-post-script.ps1 -Depth 5 -Growth 1.5`

  
## Notes

Tested with Veeam Backup & Replication V12

There are two versions of this script:
- vbr-job-scanner.ps1             - For manual execution
- vbr-job-scanner-post-script.ps1 - For use in the Backup Job as post-script

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History

* 1.0
    * Initial Release
