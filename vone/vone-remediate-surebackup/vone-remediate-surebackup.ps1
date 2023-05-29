# Getting the parameter from Veeam ONE - %5
$parameter=$args[0]

# Extract the hostname
$pattern = 'VM\s(.*?)\)'
$vmName = [regex]::Match($parameter, $pattern).Groups[1].Value

# Display the extracted value
$vmName | Out-File D:\Scripts\log.txt -Append

# Set Variables - Change where necessary
$virtualLab           = "virtual-lab-location-a"
$appGroupName         = "VeeamONE Remediation Action"
$sbJobName            = "SureBackup Job initiated by Veeam ONE"
$sbJobDesc            = "Scanning VM - Triggered by Alert Suspicious incremental backup size - $parameter"
$VBRserver            = "win-vbr-01"

# Connect to the VBR Server
Connect-VBRServer -Server $VBRserver

# Create the Application Group
$scanVMObject         = Find-VBRViEntity -Name $vmName
$scanVMVBRJob         = foreach($Backup in Get-VBRBackup){
                        foreach($RestorePoint in $Backup | Get-VBRRestorePoint){
                        if($RestorePoint.Name -eq $vmName){
                        $Backup.getJob()
                        break;
                        }
             }
 }
 Add-VBRViJobObject -Job $scanVMVBRJob.Name -Entities $scanVMObject

# Set Startup Options - Change where necessary
$sbStartOptions       = New-VBRSureBackupStartupOptions -AllocatedMemory 100 -EnableVMHeartbeatCheck:$true -EnableVMPingCheck:$false -MaximumBootTime 1800 -ApplicationInitializationTimeout 0 -DisableWindowsFirewall:$true

# Workaround for Backup Jobs using VM tags
$vbrJobObject         = Get-VBRJobObject -Job $scanVMVBRJob.Name -Name $scanVMObject.Name | Where-Object {$_.type -eq "Include"}
$sbVM                += New-VBRSureBackupVM -VM $vbrJobObject -StartupOptions $sbStartOptions
Remove-VBRJobObject -Objects $vbrJobObject -Completely

# Finally, create the Application Group
$AppGroup             = Add-VBRApplicationGroup -Name $appGroupName -VM $SbVM

# Create the SureBackup Job
$virtualLab           = Get-VBRVirtualLab -Name $virtualLab   
$sbJob                = Add-VBRSureBackupJob -Name $sbJobName -VirtualLab $virtualLab -ApplicationGroup $AppGroup -Description $sbJobDesc -KeepApplicationGroupRunning:$false -WarningAction Ignore

# Start SureBackup Job
Start-VBRSureBackupJob -Job $sbJob | Out-Null

# Remove the SureBackup Job, the Applicatoin Group and disconnect from VBR Server
Remove-VBRSureBackupJob -Job $sbJob -Confirm:$false
Remove-VBRApplicationGroup -ApplicationGroup $AppGroup

Disconnect-VBRServer