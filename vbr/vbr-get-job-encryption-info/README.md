# Veeam Backup & Replication - Get Backup Job Encryption Information

## Version Information
~~~~
Version: 1.1 (Feb 7th 2025)
Requires: Veeam Backup & Replication v12.3
Author: Stephan "Steve" Herzig
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
vbr-get-job-encryption-info.ps1 -JobType 'VMware'

# Retrieve Agent backup Job Information
vbr-get-job-encryption-info.ps1 -JobType 'Agent'

# Retrieve File Backup Job Information
vbr-get-job-encryption-info.ps1 -JobType 'File Backup'

# Retrieve Object Storage Backup Job Information
vbr-get-job-encryption-info.ps1 -JobType 'Object Storage Backup'
```

## Example Output
```
Name       Description  TargetRepository           TargetRepositoryPath  EncryptionStatus  KeyType   ModificationDateUtc  
----       -----------  ----------------          --------------------  ----------------  -------   -------------------  
Demo1      BackupJob1   Default Backup Repository  C:\Backup             Enabled           Password  02/06/2025 12:31:40  
Demo2      BackupJob2   Default Backup Repository  C:\Backup             Unencrypted       
```

## Requirements
- PowerShell
- Veeam Backup & Replication - Tested with version 12.3

## Version History
- 1.1
  - Added Object Storage Backup type
- 1.0
  - Initial Release

