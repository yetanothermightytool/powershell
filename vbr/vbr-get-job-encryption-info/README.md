# Veeam Backup & Replication - Get Backup Job Encryption Information

## Version Information
~~~~
Version: 1.0 (Feb-6 2025)
Requires: Veeam Backup & Replication v12.3
Author: Stephan "Steve" Herzig
~~~~

## Description
`vbr-get-job-encryption-info` is a PowerShell script to retrieve and display configuration details for Veeam backup jobs, including **VMware Backup**, **Agent Backup**, and **File Backup** jobs. The script organizes and presents the information in a structured tabular format.

## Features
- **Supports multiple backup job types**: VMware, Agent, and File Backup.
- **Displays repository and encryption details**:
  - Repository name and path
  - Encryption status (Enabled/Unencrypted)
  - Key type and last modification date (if encryption is enabled)

## Usage
```powershell
# Retrieve VMware backup job information
vbr-get-job-encryption-info.ps1 -JobType 'VMware'

# Retrieve Agent backup job information
vbr-get-job-encryption-info.ps1 -JobType 'Agent'

# Retrieve File Backup job information
vbr-get-job-encryption-info.ps1 -JobType 'File Backup'
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
- 1.0
  - Initial Release

