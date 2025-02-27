# Veeam Backup & Replication - Get Backup Job Encryption Information

## Version Information
~~~~
Version: 1.2 (Feb 27th 2025)
Requires: Veeam Backup & Replication v12.3
Author: Stephan "Steve" Herzig / David Domask
~~~~

## Description
`vbr-get-job-encryption-info` is a PowerShell script to retrieve and display the encryption configuration details for Veeam backup jobs, including **VMware Backup**, **Agent Backup**, **File Backup**  and **Object Storage Backup** jobs. The script organizes and presents the information in a structured tabular format.

## Features
- **Supports multiple backup job types**: VMware, Agent, File Backup, and Object Storage Backup.
- **Displays repository and encryption details**:
  - Repository name and path
  - Encryption status (Enabled/Unencrypted)
  - Key type and last modification date (if encryption is enabled)

## Usage
# Navigate to the directory where the script is saved
```powershell
cd "C:\Path\To\Your\Script"
```

# Dot-source the script to load the function
```powershell
. .\vbr-get-job-encryption-info.ps1
```

# Use the function
```powershell
# Retrieve VMware backup Job Information
Get-BackupJobEncryptionInfo -JobType 'VMware'

# Retrieve Agent backup Job Information
Get-BackupJobEncryptionInfo -JobType 'Agent'

# Retrieve File Backup Job Information
Get-BackupJobEncryptionInfo -JobType 'File Backup'

# Retrieve Object Storage Backup Job Information
Get-BackupJobEncryptionInfo -JobType 'Object Storage Backup'
```

## Example Output
```
Name                 : File Backup File Share
TargetRepository     : Scale-out Backup Repository ReFs
TargetRepositoryPath :
EncryptionStatus     : Enabled
KeyType              : Password
ModificationDateUtc  : 1/30/2023 3:02:47 PM

Name                 : Clean Room 
TargetRepository     : Clean Room
TargetRepositoryPath : D:\CR_Backups
EncryptionStatus     : Unencrypted
KeyType              :
ModificationDateUtc  :
```

## Requirements
- PowerShell
- Veeam Backup & Replication - Tested with version 12.3

## Version History
- 1.2
  - The code has been optimized/rewritten. Thanks to David Domask!
  - The information can now be retrieved with Get-BackupJobEncryptionInfo
  - The output format has been changed
- 1.1
  - Added Object Storage Backup type
- 1.0
  - Initial Release

