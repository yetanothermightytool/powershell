<# 
.NAME
    Veeam Backup & Replication - Get Object Storage Usage
.DESCRIPTION
    Powershell script to display the used capacity in an object storage
.NOTES  
    File Name  : get-vbr-objectstorageusage.ps1
    Author     : Stephan Herzig, Veeam Software (stephan.herzig@veeam.com)
    Requires   : PowerShell, Veeam Backup & Replication v12
	Important  : Using unofficial .NET method 
.VERSION
    1.0
#>
# Start
Clear-Host

# Set Variables
$finalResult   = @()

# Get Object Storage Repository Information
$repo = Get-VBRObjectStorageRepository 

#foreach ($repoid in $repo) {
         $finalResult      += New-Object psobject -Property @{
         RepoName          =  $repoid.Name
         RepoUsageGB       =  [math]::round([Veeam.Backup.Core.CBackupRepository]::GetRepositoryBackupsSize($repoid.id) / 1Gb, 2)
         Immutability      =  $repoid.BackupImmutabilityEnabled
                                                             }
}

# Print Table
$finalResult
