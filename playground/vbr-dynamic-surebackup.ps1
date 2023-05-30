# Variables for script
$AppGroupName                   = "Dynamic App Group"
$SbJobName                      = "Dynamic Surebackup Job"
$SbJobDesc                      = "Dynamic App Testing"
$Date                           = (Get-Date).AddDays(-2)
$VirtualLab                     = "your virtual lab here"
$eMail                          = "your email here"
$VBRserver                      = "localhost"
 
# Variables for function selectUntestedVMs
[string]$VeeamBackupCounterFile = "D:\Scripts\SureBackup\VMtable.xml"
# How many VMs should be tested at once?
[int]$NumberofVMs               = 1
 
 
# Functions
Function selectUntestedVMs
{
    param([string]$fVeeamBackupCounterFile,[int]$fNumberofVMs,$fVbrObjs)
  
    $fVMTable    = @()
    $fTestVMs    = [System.Collections.ArrayList]@()
    $fDeletedVMs = [System.Collections.ArrayList]@()
  
    # Import VMtable if exists from a previous iteration
    if(Test-Path $fVeeamBackupCounterFile)
    {
       $fVMTable = import-clixml $fVeeamBackupCounterFile
    }
  
    # Check if all VM's were tested / if so the VMTable is cleared
    if(!($fVMTable.Checked -contains 0)) {$fVMTable = @()}
  
    # Add newly created VM's from backup
    Foreach($fVbrObj in $fVbrObjs)
    {
      if(!(($fVMTable.VMname) -Contains ($fVbrObj.name)))
       {
           $fVMTable += [PSCustomObject] @{
                        VMname  = $fVbrObj.Name;
                        JobName = $fVbrObj.JobName;
                        Checked = 0;
                        Deleted = 0}
       }
    }
    
    # Remove old VM's from VMTable
    $fVMTable | ForEach-Object { if($fVbrObj.name -notcontains $_.VMname) {$_.Deleted = 1}}
  
    # Sort VMTable by Checked and VMname
    $fVMTable = $fVMTable | Where-Object {$_.Deleted -eq 0} | Sort-Object Checked, VMname
  
    # Select least tested VMs and set as Checked
    $fTestVMs = @()    
    for ($i = 0; $fTestVMs.Length -lt $fNumberofVMs; $i++)
    {
    # Check if backup job currently running. If so, skip VM for a later run
        if   ((Get-VBRBackupSession -Name ($fVMTable[$i].JobName + "*") | Where-Object {$_.state -ne "Stopped" -and $_.EndTime.Year -eq 1900}) -eq $null) { 
            $fTestVMs += [PSCustomObject] @{
                          VMName  = $fVMTable[$i].VMname;
                          JobName = $fVMTable[$i].JobName}
            $fVMTable[$i].Checked = 1
        }
    }
  
    # Save VMTable to file for the next iteration
    $fVMTable | Export-Clixml $fVeeamBackupCounterFile
  
    Return $fTestVMs

### END Function    
}

# Connect to VBR Server
Connect-VBRServer -Server $VBRserver
 
# Here all available Verification Options can be sete
$VbsStartOptions = New-VBRSureBackupStartupOptions -AllocatedMemory 100 -EnableVMHeartbeatCheck:$true -EnableVMPingCheck:$false -MaximumBootTime 1800 -ApplicationInitializationTimeout 0 -DisableWindowsFirewall:$true
 
#Check if Application Group exists
if(!(Get-VBRApplicationGroup -Name $AppGroupName -ErrorAction Ignore)) {
    # Find all VM objest successfully backed sind $Date
    $VbrObjs = (Get-VBRBackupSession | Where-Object  {$_.JobType -eq "Backup" -and $_.EndTime -ge $Date}).GetTaskSessions() | Where-Object {$_.Status -eq "Success" -or $_.Status -eq "Warning" }
    # Call function selectUntestedVMs
    $TestVMs = selectUntestedVMs -fVeeamBackupCounterFile $VeeamBackupCounterFile -fNumberofVMs $NumberofVMs -fVbrObjs $VbrObjs
 
    # Build VM list to test using new cmdlet New-VBRSureBackupVM
    $SbVMs   = @()
    foreach ($TestVM in $TestVMs) {
         
            $TestVMObject    = Find-VBRViEntity -Name $TestVM.VMname
            $TestVMVbrJob    = Get-VBRJob -Name $TestVM.Jobname
            $VbrJobObject    = Get-VBRJobObject -Job $TestVMVbrJob -name $TestVMObject.Name | Where-Object {$_.type -eq "Include"}
            [switch]$VmAdded = $false
                    if ($null -eq $VbrJobObject) {
                    Add-VBRViJobObject -Job $TestVMVbrJob -Entities $TestVMObject
                    $VbrJobObject    = Get-VBRJobObject -Job $TestVMVbrJob -name $TestVMObject.Name | Where-Object {$_.type -eq "Include"}
                    $VmAdded         = $true
                    }
            $SbVMs          += New-VBRSureBackupVM -VM $VbrJobObject -StartupOptions $VbsStartOptions
            if ($VmAdded) {Remove-VBRJobObject -Objects $VbrJobObject -Completely}
    }
    $AppGroup = Add-VBRApplicationGroup -Name $AppGroupName -VM $SbVMs}
 
 else {
       Write-Host "App Group" $AppGroupName "already exists, please clean up"
}

# Check if SureBackup job exists
if(!(Get-VBRSureBackupJob -Name $SbJobName -ErrorAction Ignore))  {
 
    $VirtualLab = Get-VBRVirtualLab -Name $VirtualLab   
    $VsbJob     = Add-VBRSureBackupJob -Name $SbJobName -VirtualLab $VirtualLab -ApplicationGroup $AppGroup -Description $SbJobDesc -KeepApplicationGroupRunning:$false -WarningAction Ignore
 
    if ($email -ne $null) {
        $SbJobVerficationOptions = New-VBRSureBackupJobVerificationOptions -Address $email -WarningAction Ignore
        Set-VBRSureBackupJob -Job $VsbJob -VerificationOptions $SbJobVerficationOptions -WarningAction Ignore
    }
    Start-VBRSureBackupJob -Job $VsbJob | Out-Null
    
    # Remove the old App Group, SureBackup Job, Disconnect from Server after running
    Remove-VBRSureBackupJob -Job $VsbJob -Confirm:$false
    Remove-VBRApplicationGroup -ApplicationGroup $AppGroup
 
    Disconnect-VBRServer
}
else {
      Write-Host "SureBackup Job" $SbJobName "already exists, please clean up"
}
