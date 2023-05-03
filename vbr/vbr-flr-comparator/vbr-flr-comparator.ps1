<# 
.NAME
    Veeam Backup & Replication - File Level Recovery - Compare with production)
.DESCRIPTION
    This script starts a FLR session, connects to the production VM and checks for changes using the given path.
    Only works with Windows VMs.
    
        Details can be found on GitHub https://github.com/yetanothermightytool/powershell/tree/master/vbr/vbr-flr-comparator
.EXAMPLE
    
    The following example starts a FLR session from backup job "vm_backup", connects to the VM "win-client-01" and scans
    for any changes of *.dll files in the C:\Windows\System32\ path.

    PS > .\vbr-flr-comparator.ps1 -VM win-client-01 -Drive "C:\" -ScanPath "C:\Windows\System32\*.dll"
.NOTES  
    File Name  : vbr-flr-comparator.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12
.VERSION
    1.1
#>
param(
[Parameter(Mandatory = $true)]
[String] $VM,
[Parameter(Mandatory = $true)]
[String] $Drive,
[Parameter(Mandatory = $true)]
[String] $ScanPath
      )
Clear-Host
# Set variables
$finalResult         = @()
$filterDate          = (Get-Date).AddDays(-$Daysback)

function rpLister {
Param (
    [Parameter(Position = 0,Mandatory = $False)]
    [PSObject]
$Output = $Result
    )
    begin {
        $Global:n = 0
    }
    process {
        $RestoreTable = @{ Expression={ $Global:n;$Global:n++ };Label="Id";Width=5;Align="center" }, `
        @{ Expression={ $_.VmName };Label="Server Name";Width=25;Align="left" }, `
        @{ Expression={ $_.CreationTime };Label="Creation Time";Width=25;Align="left" }, `
        @{ Expression={ $_.Type };Label="Type";Width=10;Align="left" }
    }
    end {
        Write-Host
        Write-Host "The following restore points were found...(newest first)"
        Write-Host
        return $Output | Format-Table $RestoreTable
    }
}


# Connect to the Veeam Backup & Replication server
Connect-VBRServer -Server localhost

# Define the backup job and restore point you want to use
$Result              = Get-VBRRestorePoint -Name $VM | Sort-Object -Property CreationTime -Descending 
#$Result = Get-VBRBackup | Where-Object { $_.jobname -eq $JobName } | Get-VBRRestorePoint -Name $VM | Sort-Object -Property CreationTime -Descending 

if ($Result.Count -eq 0) {
	Write-Host 'Unable to locate any restore points for' $Scanhost 'in backup job' $Jobname -ForegroundColor White
	Exit
} else {
    rpLister $Result
}

do { [int]$restorePointID = Read-Host "Please select restore point (Id)" } until (($restorePointID -lt $Result.Count) -and ($restorePointID -ge 0))

# Write selected Restore Point into a variable
$selectedRp          = $Result | Select-Object -Index $restorePointID 

# Define the virtual machine you want to scan for changed files
$VMName              = Find-VBRViEntity -Name $VM

# Start the Restore Session
Write-Progress "Start Restore Session..." -PercentComplete 75
$session             = Start-VBRWindowsFileRestore -RestorePoint $selectedRp -Reason "vbr-flr-comparator.ps1 - CompareWithOriginal"

# Define the credentials to use for the production machine connection
$cred                = Get-VBRCredentials -Name ".\Administrator"

# Connect to the production machine using the credentials and save the session object
Write-Progress "Connect to VM $VM..." -PercentComplete 90
$directConnect       = Connect-VBRWindowsGuestProductionMachine -FileRestore $session -GuestCredentials $cred

# Get the running Restore Session
$restoreSession      = Get-VBRRestoreSession | Where-Object {$_.State -eq "Working"}

# Get the mounted FLR volume information
$flrVolume           = Get-VBRWindowsGuestItem -Path $Drive -FileRestore $session

# Check for changes using the given ScanPath variable
Write-Progress "Looking for changes..." -PercentComplete 95
$files               = Get-VBRWindowsGuestItem -FileRestore $session -ParentItem $flrVolume -RecursiveSearch -ChangedOnly -CompareWithOriginal -Name $ScanPath -RunAsync

# Loop through each file and perform some action
foreach ($file in $files) {
    if($files.Count -gt 0){
    # Create table content
    $finalResult     += New-Object psobject -Property @{
    FileName          = $file.Name
    FileStatus        = $file.CompareState
    FileSize          = $file.Size
    ModificationDate  = $file.ModificationDate
    }
  }
}
# Print Table
Write-Progress "Generating Table..." -PercentComplete 100
$finalResult | Format-Table -Wrap -AutoSize -Property @{Name='File Name';Expression={$_.FileName}},
                                                      @{Name='File Status';Expression={$_.FileStatus};align='left'},
                                                      @{Name='File Size';Expression={$_.FileSize};align='left'},
                                                      @{Name='Modification Date';Expression={$_.ModificationDate}}
   


if($finalResult.Count -eq 0){
Write-Host ""
Write-Host "No changes found - $ScanPath"
   }
                                                     
# Stop Restore Session & Disconnect VBR Server
Stop-VBRWindowsFileRestore -FileRestore $session
Disconnect-VBRServer
