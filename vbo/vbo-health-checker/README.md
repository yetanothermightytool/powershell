# VBO Health Checker
Powershell script to quickly get some useful information about the health of a Veeam Backup for Microsoft Office 365 setup.

## Description
~~~~
Version : 1.3 (March 21 2022)
Requires: Veeam Backup for Microsoft Office 365 v5 or later
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Purpose

The script checks and reports possible issues/misconfigurations:

    - Backup Job Status per Job / Number of failed job
    - License expiration date
    - Check logs if throttling occured on MS side
    - Possible slow backup due to slow backup repository
    - Proxy stuff (min. recommended CPU and Memory)
    - Check Windows event log for low memory conditions    
    - Logfile with the findings
    - and more - See Version History

## Parameters
  
  `Organization`
_(mandatory)_ The name of the organization.
  
  `Logfile`
_(optional)_ The path and filename where the output gets written to.

 `Webcheck`
_(optional)_ Check if the latest releas is installed - https://www.veeam.com/kb4106

  
## Example: 
`PS> .\vbo-health-checker.ps1 -Organization ACMECompany -Logfile C:\Logfiles\output.txt -Webcheck`
  
## Notes

It's always recommended to open a support case as soon you're facing an issue with Veeam Backup for Microsoft Office 365. 

This script has been tested with the following versions of Veeam Backup for Microsoft Office 365:
- v5.0 - All versions
- v6.0 

The script is still "work in progress". Feedback welcome.

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History

* 1.3 
    * New parameter "Organization" for multi org setups (Thanks to azja09)
    * Script informs if any changes to the repository retentions have been applied during the current month
    * SP restore throttling information
    * Bottleneck for every Backup Job - v6+ only

* 1.2
    * Get available versions from https://www.veeam.com/kb4106 and display the latest available version - Optional prameter Webcheck
    * Last run of Backup Job
    * Bottleneck for every Backup Job - v6beta only
    * Fixed - Code cleanup - Some used commands (eg. clear) replaced

* 1.1
    * Fixed - Proxy Server Total Memory not displayed correctly (Thanks to K00laidIT)
    * Fixed - Low Memory Conditon on Proxy reported correctly
    * Added % free capacity for each local VBO repository 
    * Added output of Veeam Backup for Microsoft 365 Build Number - https://www.veeam.com/kb4106
    * Added output of Restore Sessions outside business hours (7 to 17) - Can be adjusted $vbo_restore variable  
    * Changed output order
* 1.0
    * Initial Release
