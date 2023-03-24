<# 
.NAME
    Veeam Backup & Replication - Get Backup Job Settings
.DESCRIPTION
    Powershell script to display specific job configuration settings
.NOTES  
    File Name  : vbr-get-jobcfg.ps1
    Author     : Stephan Herzig, Veeam Software (stephan.herzig@veeam.com)
    Requires   : PowerShell, Veeam Backup & Replication v12

.VERSION
    1.1
#>
param(
[Parameter(Mandatory = $false)]
    [Switch] $Retention,
    [Switch] $Storage,
    [Switch] $NAS)

# Set Variables
$finalResult   = @()

# Connect to VBR Server
Connect-VBRServer -Server localhost

# $vbrJobs = Get-VBRBackup
$vbrJobs       = Get-VBRJob -WarningAction SilentlyContinue | Where-Object { $_.JobType -eq 'Backup'}
$vbrNASJobs    = Get-VBRNASBackupJob -WarningAction SilentlyContinue 

# Output Storage Related Settings
if($Storage){
foreach ($jobs in $vbrJobs) {
    
    $opt               = $jobs.Options.BackupStorageOptions.StgBlockSize
            
    $finalResult       += New-Object psobject -Property @{
    JobName            = $jobs.Name
    JobType            = $jobs.Jobtype
    RepoType           = $jobs.FindBackupTargetRepository().Type
    BackupType         = $jobs.Options.BackupTargetOptions.Algorithm
    Synthetic          = $jobs.Options.BackupTargetOptions.TransformToSyntheticFull
    SyntheticDay       = $jobs.Options.BackupTargetOptions.TransformToSyntethicDays
    ActiveFull         = $jobs.Options.BackupStorageOptions.EnableFullBackup
    FullBackupDay      = $jobs.Options.BackupTargetOptions.FullBackupDays 
    CompressionLevel   = $jobs.Options.BackupStorageOptions.CompressionLevel
    StorageOpt         = $opt -replace '^.*(?=.{4}$)'
    JobEncryption      = $jobs.Options.BackupStorageOptions.StorageEncryptionEnabled
      }   
    }
# Print Table
$finalResult | Format-Table -Wrap -AutoSize -Property @{Name='Job Name';Expression={$_.JobName}},
                                                      @{Name='Job Type';Expression={$_.JobType};align='left'},
                                                      @{Name='Repository Type';Expression={$_.RepoType};align='left'},
                                                      @{Name='Backup Type';Expression={$_.BackupType};align='left'},
                                                      @{Name='Synthetic';Expression={$_.Synthetic};align='left'},
                                                      @{Name='Synthetic on';Expression={$_.SyntheticDay};align='left'},
                                                      @{Name='Active Full';Expression={$_.ActiveFull};align='left'},
                                                      @{Name='Active Full on';Expression={$_.FullBackupDay};align='left'},
                                                      @{Name='Compression Level';Expression={$_.CompressionLevel};align='center'},
                                                      @{Name='Storage Optimization';Expression={$_.StorageOpt};align='center'},
                                                      @{Name='Backup Encryption';Expression={$_.JobEncryption};align='left'}
                                                      


}

# Output Retention Related Settings
if($Retention){
foreach ($jobs in $vbrJobs) {
    $finalResult       += New-Object psobject -Property @{
    JobName            = $jobs.Name
    JobType            = $jobs.Jobtype
    RetentionPolicy    = $jobs.Options.BackupStorageOptions.RetentionType
    BasicRetention     = $jobs.Options.BackupStorageOptions.RetainDaysToKeep
    WeeklyGFSEnabled   = $jobs.Options.GfsPolicy.Weekly.IsEnabled
    WeeklyRetention    = $jobs.Options.GfsPolicy.Weekly.KeepBackupsForNumberOfWeeks
    MonthlyGFSEnabled  = $jobs.Options.GfsPolicy.Monthly.IsEnabled
    MonthlyRetention   = $jobs.Options.GfsPolicy.Monthly.KeepBackupsForNumberOfMonths
    YearlyGFSEnabled   = $jobs.Options.GfsPolicy.Yearly.IsEnabled
    YearlyRetention    = $jobs.Options.GfsPolicy.Yearly.KeepBackupsForNumberOfYears
      }   
    }
# Print Table
$finalResult | Format-Table -Wrap -AutoSize -Property @{Name='Job Name';Expression={$_.JobName}},
                                                      @{Name='Job Type';Expression={$_.JobType};align='left'},
                                                      @{Name='Retention Type';Expression={$_.RetentionPolicy};align='left'},
                                                      @{Name='Retention';Expression={$_.BasicRetention};align='center'},
                                                      @{Name='GFS Weekly Enabled';Expression={$_.WeeklyGFSEnabled};align='left'},
                                                      @{Name='GFS Weekly';Expression={$_.WeeklyRetention};align='center'},
                                                      @{Name='GFS Monthly Enabled';Expression={$_.MonthlyGFSEnabled};align='left'},
                                                      @{Name='GFS Monthly';Expression={$_.MonthlyRetention};align='center'},
                                                      @{Name='GFS Yearly Enabled';Expression={$_.YearlyGFSEnabled};align='left'},
                                                      @{Name='GFS Yearly';Expression={$_.YearlyRetention};align='center'}
}

# Output NAS Backup Job Parameters

if($NAS){
foreach ($jobs in $vbrNASJobs) {
    $finalResult       += New-Object psobject -Property @{
    JobName            = $jobs.Name
    Path               = $jobs.BackupObject.Path
    BackupIOControl    = $jobs.BackupObject.Server.BackupIOControlLevel
    Repository         = $jobs.ShortTermBackupRepository.Name
    RepositoryType     = $jobs.ShortTermBackupRepository.Type
    RetentionType      = $jobs.ShortTermRetentionType
    RetentionPeriod    = $jobs.ShortTermRetentionPeriod
    JobEncryption      = $jobs.StorageOptions.EncryptionEnabled   
      }   
    }
# Print Table
$finalResult | Format-Table -Wrap -AutoSize -Property @{Name='Job Name';Expression={$_.JobName}},
                                                      @{Name='Protected Path';Expression={$_.Path};align='left'},
                                                      @{Name='BackupIOControl';Expression={$_.BackupIOControl};align='left'},
                                                      @{Name='Repository';Expression={$_.Repository};align='left'},
                                                      @{Name='Repository Type';Expression={$_.RepositoryType};align='left'},
                                                      @{Name='Retention Type';Expression={$_.RetentionType};align='left'},
                                                      @{Name='Retention';Expression={$_.RetentionPeriod};align='center'},
                                                      @{Name='Backup Encryption';Expression={$_.JobEncryption};align='left'}
}

# Disconnect VBR Server Session
Disconnect-VBRServer
