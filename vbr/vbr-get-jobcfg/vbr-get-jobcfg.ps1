<# 
.NAME
    Veeam Backup & Replication - Get Backup Job Settings
.DESCRIPTION
    Powershell script to display specific job configuration settings
.NOTES  
    File Name  : vbr-get-jobcfg.ps1
    Author     : Stephan Herzig, Veeam Software (stephan.herzig@veeam.com)
    Requires   : PowerShell, Veeam Backup & Replication v12
	Important: : Uses Get-VBRJob. This command is no longer supported.

.VERSION
    1.0
#>
param(
[Parameter(Mandatory = $false)]
    [Switch] $Retention,
    [Switch] $Storage)

# Set Variables
$finalResult   = @()

# Connect to VBR Server
Connect-VBRServer -Server localhost

# $vbrJobs = Get-VBRBackup
$vbrJobs = Get-VBRJob -WarningAction SilentlyContinue | Where-Object { $_.JobType -eq 'Backup'}

# Output Storage Related Settings
if($Storage){
foreach ($jobs in $vbrJobs) {
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
    StorageOpt         = $opt = $jobs.Options.BackupStorageOptions.StgBlockSize
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
                                                      @{Name='Storage Optimization';Expression={$_.StorageOpt};align='left'},
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

# Disconnect VBR Server Session
Disconnect-VBRServer
