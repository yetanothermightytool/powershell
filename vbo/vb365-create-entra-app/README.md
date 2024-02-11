# Veeam Backup for Microsoft 365 - Entra Application Creation Script

**Update February 2024 - Please note: The script does not work with the current release of the Microsoft.Graph Powershell Module v2.13.0/1. The last tested version with which the script works is v2.9.0**

This PowerShell script is designed to create an Entra/Azure application for authentication, backup, and recovery from Veeam's Backup for Microsoft 365. It is intended for use by a security or Entra administrator to provide the necessary Entra application for Veeam Backup for Microsoft 365.

**Note:** Use this script only if you cannot use the product's built-in functionality to create the application. 

## Description
~~~~
Version : 2.0.0 (Nov 17th, 2023)
Author  : Stefan Zimmermann & Steve Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Features
- Connect to Entra with given admin credentials
- Create a public/private key-pair for app authentication and export the key to a file
- Create a new application registration within Entra
- Add the key for authentication to the app
- Assign the required permissions for VB365 to the application

For a detailed list of permissions used in this script, please check [Veeam Helpcenter](https://helpcenter.veeam.com/docs/vbo365/guide/azure_ad_applications.html).

## Important
After executing the script, manual actions must still be performed in the Entra admin center. This information is also displayed after the script has been executed.

- Check the API permissions of the app in the Entra admin center and grant admin consent." (mandatory)
- Starting from version 7 CP4, Veeam Backup for Microsoft 365 supports backup of public folder and discovery search mailboxes. To back up these objects, Veeam Backup for Microsoft 365 needs access to Exchange Online PowerShell. (optional, if those needs to be protected)
- Manually enable the 'Allow public client flows' on the 'Authentication' page of the app details for interactive restores" (optional)

## Prerequisites

- Microsoft.Graph PowerShell Module (Tested with version 2.5.0 and 2.9.0)

## Parameters
The following parameters can be passed to the script. The optional specifications are predefined in the script, but can be customized.

`entraTenantId`
_(mandatory)_ Tenant ID - can be found on the Entra admin center overview page (Mandatory)

`appName`
_(optional)_ DisplayName for the app registration (Default: "VB365 - Azure Application")
 
`limitUsageTo`
_(optional)_ Limit permissions to only those required for backup, InteractiveRestore, or ProgrammaticRestore (Default: All)

`limitServiceTo`
_(optional)_ Limit permissions to the specified service(s) - Exchange, SharePoint, OneDrive, Teams (Default: All supported)

`certificateFilePath` 
_(optional)_ Path to the file where the public key will be stored (CRT) (Default: script directory)

`keyFilePath`
_(optional)_ Path to the file where the private key will be exported (PFX) (Default: script directory)

`keyLifeTimeDays` 
_(optional)_ Lifetime of the key-pair in days (Default: 3 years)

`keyPassword` 
_(optional)_ Password for exported key file (Mandatory - Script will ask for it if not given)

`overwriteKey`
_(optional)_ Overwrite/regenerate authentication key if exists

`overwriteApp` 
_(optional)_ Overwrite/regenerate app registration if exists with the same name

`entraCredential`
_(optional)_ Use the following credentials to connect to Entra instead of asking. Can't be used for MFA

`keyLength` 
_(optional)_ Keylength for generated RSA key pair (Default: 4096)


## Usage example
Create an application named "VB365 Backup Application" with the required permissions for backing up Exchange Online data. The key is valid for 1 year and will be stored in the default directory (where the script resides).

```powershell
.\Create-VeeamEntraApp.ps1 -entraTenantId <YourEntraTenantId> -appName "VB365 Backup Application" -limitUsageTo "Backup" -limitServiceTo "Exchange" -certificateFilePath -keyLifeTimeDays 365
```

## Notes

**Update February 2024 - Please note: The script does not work with the current release of the Microsoft.Graph Powershell Module v2.13.0/1. The last tested version with which the script works is v2.9.0**

- The authorizations correspond to the requirements for authorizations for Modern App-Only Authentication. [Veeam Helpcenter](https://helpcenter.veeam.com/docs/vbo365/guide/ad_app_permissions_sd.html)
- Requirements based on version 7.0 of Veeam Bakcup for Microsoft 365

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
* 2.0.0
    * Adding additional GraphAPI permissions
    * Use Microsoft.Graph Powershell Module
    * Optimize output
* 1.0.3
    * Original script by Stefan Zimmermann
	
