<# 
.NAME
    Veeam Backup & Replication - Offload Job Statistics (transfered size)
.DESCRIPTION
    Powershell script to display the offloaded capacity to an object storage.
.NOTES  
    File Name  : get-vbr-offloadstats.ps1
    Author     : Stephan Herzig, Veeam Software (stephan.herzig@veeam.com)
    Requires   : PowerShell, Veeam Backup & Replication v12
	Important  : Using unofficial .NET method 
.USAGE
	The following two parameter must be given: 
		-Scope   - Number of days back you want to 
		-Jobname - Name of the Backup Job pointing to a SOBR with a Capacity Tier
    
    .\get-vbr-offloadstats.ps1 -Scope 30 -Jobname "DEMO_LNX_SOBR-01"
.VERSION
    1.0
#>
param(
     [Parameter(mandatory=$true)]
     [String] $Scope,
     [String] $JobName
     )
# Start
Clear-Host

# Set Variables
$finalResult   = @()

# Define Job Types
$sobrOffload   = [Veeam.Backup.Model.EDbJobType]::ArchiveBackup 

# Get Sessions
$offloadJobs   = [Veeam.Backup.Core.CBackupSession]::GetByTypeAndTimeInterval($sobrOffload,(Get-Date).adddays(-$Scope), (Get-Date).adddays(0)) | Sort-Object CreationTimeUTC -Descending

# Get the capacities
foreach ($job in $offloadJobs) {
         if($job.Name -cmatch $JobName) {
            $finalResult      += New-Object psobject -Property @{
            Date              = $job.EndTime
            JobName           = $job.Name
            TransferedSizeGB  = [math]::round($job.Progress.TransferedSize / 1Gb, 2)
                                                                }
                                        }
                               }

# Print table
$finalResult 
