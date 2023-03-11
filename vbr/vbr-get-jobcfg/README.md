# Veeam Backup & Replication - Get Backup Job Configuration Settings

## Description
~~~~
Version : 1.0 (March 10th 2023)
Requires: Veeam Backup & Replication v12
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites

Backup Jobs protecting virtual machines.

## Purpose

This script shows different job configuration settings based on the given switch.

When using the Storage switch, the following configuration settings are displayed:
Job Name, Job Type, Target Repository Type, Backup Type, Synthetic, Synthetic Day, Active Full, Active Full Day, Compression Level, Storage Optimization, Backup Encryption

When using the Retention, the following configuration settings are displayed:
Job Name, Job Type, Retention Type (Item/Days), Retention, GFS Weekly Enabled, GFS Weekly Retention, GFS Monthly Enabled, GFS Monthly Retention, GFS Yearly Enabled, GFS Yearly Retention.

This script can be used to quickly identify differences in job settings. 

## Parameters
One of the following switches has to be used.
 
  `Storage`
_(mandatory)_ 

  `Retention`
_(mandatory)_ 


## Example: 
`PS>.\vbr-get-jobcfg.ps1 -Storage
  
## Notes

Uses Get-VBRJob. This command is no longer supported. I check alternative possibilities.
Depending on the feedback, other options will be included (for example other job types like backup copy job).

This script has been tested with the following versions of Veeam Backup & Replication
- v12

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History

* 1.0
    * Initial Release
