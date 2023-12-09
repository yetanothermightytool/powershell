# VBR DR - Restore Configuration Backup Database

## Version Information
~~~~
Version: 1.1 (December 9th 2023)
Requires: Veeam Backup & Replication v12.1
Author: Stephan "Steve" Herzig
~~~~

## Purpose
Let's prepare for the scenario where the primary Veeam Backup & Replication server is no longer available and the configuration database needs to be restored on another system with a different hostname (standby server). The script can also be run unattended to restore the configuration database at regular intervals.

## Prerequisites
- Veeam Backup & Replication v12.1
- Configuration database running on PostgreSQL
- Configuration Backup with encryption [`See Helcenter`](https://helpcenter.veeam.com/docs/backup/vsphere/vbr_config_schedule.html)
- File Copy Job [`See Helcenter`](https://helpcenter.veeam.com/docs/backup/vsphere/performing_file_copy.html)
- Exported configuration restore file (see Export Configuration Answer File)
- Stored passwords as a secure string in a txt file (see Store Passwords)

## Export Configuration Answer File

Run the following command to create a configuration restore answer file.
```powershell
C:\Program Files\Veeam\Backup and Replication\Backup\Veeam.Backup.Configuration.UnattendedRestore.exe /generate:c:\temp\unattended.xml
```

## Store Password
Run the following command to store the used password for the encryption of the configuration backup and run again for storing the password for accessing the database. 

```powershell
$credential = Get-Credential
$credential.Password | ConvertFrom-SecureString | Set-Content <path to db password|encryption password.txt>
```

## Script Parameters
The script accepts the following parameters:

- `ServiceCheck`		Checks if only the necessary Veeam Services for the configuration database restore are running
- `Restore`				Restores the configuration database (Restore Mode is migration)      
- `DBUpdate`         Updates the user and user SID on the standby VBR server (only when [`MFA`](https://forums.veeam.com/veeam-backup-replication-f2/issue-with-restoring-config-on-consoles-with-mfa-enabled-t89167.html) is enabled)

Optional parameters, whereby the default value can also be hard-coded in the script.

- `cfgBackupPath`		 Path to the configuration backups on the standby server (where the .bco files reside)
- `unattendedXmlPath` Path to the unattended response file
- `$decryptPasswordPath` Path to the password file for decrypting the configuration backup
- `$dbPasswordPath` 	 Path to the password file for accessing the PostgreSQL database
- `srcBkpAdmin`		 Backup administrator on the primary VBR server.
- `dstBkpAdmin`		 Backup administrator on the DR VBR server

## Examples

Example 1 - Check if only the needed Veeam services for the configuration database restore are running:
```powershell
.\vbr-dr.ps1 -ServiceCheck
```
Example 2 - Restore/Migrate the Configuration Database. Execute the script on the standby VBRserver
```powershell
.\vbr-dr.ps1 -Restore
```
Example 3 - Restore/Migrate the Configuration Database and update the necessary database fields for the user $srcBkpAdmin 
```powershell
.\vbr-dr.ps1 -Restore -DBUpdate
```

## Configuration Database Restore details
This script uses the migration mode for restoring the configuration database.
[`See Helpcenter`](https://helpcenter.veeam.com/docs/backup/vsphere/restore_vbr_mode.html)

The script also checks whether the unattended.xml file contains the required values so that the restore can take place on a regular base without starting the backup services themselves.

These values are checked and set if necessary. Adjustments can be made (simply add the corresponding node with the attribute).

- `BACKUP_PASSWORD` Set while script is running. After the script ended, a dummy value will be set
- `SQLSERVER_ENGINE` PostgreSQL will be used
- `DATABASE_SERVER`  localhost:5432 is used
- `CONFIGURATION_FILE` The latest backup will added
- `SWITCH_TO_RESTORE_MODE` Set to 0 (no)
- `RESTORE_BACKUPS` Set to 1 (yes)
- `RESTORE_SESSIONS` Set to 1 (yes)
- `OVERWRITE_EXISTING_DATABASE` Set to 1 (yes) The existing database will be overwritten!!
- `BACKUP_EXISTING_DATABASE` Set to 0 (no)
- `SERVICES_AUTOSTART` Set to 0 (no)
- `STOP_PROCESSES` Set to 1 (yes) Use the option "ServiceCheck" when executing the script

## Notes
Please do not run the script on the productive server. Use at your own risk.

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
*  1.1
    * Password separation. It might not be a good idea to have the same password for encryption and DB access
*  1.0
    * Initial Release
