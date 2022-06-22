# Get MS Teams Chat & Private Chat Message Statistics
Powershell script to list the maximum and average chat message numbers for the given report period.

## Description
~~~~
Version : 1.1 (June 22nd 2022)
Author  : Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites
This script requires a pre-registered app & secret within the MS tenant. The app needs "Reports.Read.All" API permissions.

The following IDs needs to be stored in the script

Tenant ID
Application (client) ID
Client Secret Value

## Parameters
  
  `Period`
_(mandatory)_ Report Period in days to be used - Possible values 7, 30, 90 or 180

  
## Example: 
`PS> .\get-teams-stats.ps1 -Period 30`
  
## Notes
The client secret value is only presented during creation and cannot be viewed afterwards. Be sure to save the secret when created before leaving the web page!

The script currently stores the report in the C:\Temp directory

The script is still "work in progress". Feedback welcome.

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
* 1.1
    * Cleanup and cost calculation
* 1.0
    * Initial Release
