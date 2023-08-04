<# 
.NAME
    Veeam Backup & Replication - File Level Recovery - Compare with production)
.DESCRIPTION
    This script starts a FLR session, connects to the production VM and checks for changes using the given path.
    Only works with Windows VMs.
    
        Details can be found on GitHub https://github.com/yetanothermightytool/powershell/tree/master/vbr/vbr-flr-comparator
.EXAMPLE
    
    The following example starts a FLR session, connects to the VM "win-client-01" and scans
    for any changes of *.ps1 files in the C:\Users\ Folder (recursive search)

    PS > .\vbr-flr-comparator.ps1 -VM win-client-01 -RootFolder Users -SearchPattern *.ps1
.NOTES  
    File Name  : vbr-flr-comparator.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12
.VERSION
    1.2
#>
param(
    [Parameter(Mandatory = $true)]
    [String] $VM,
    [Parameter(Mandatory = $true)]
    [String] $RootDirectory,
    [Parameter(Mandatory = $true)]
    [String] $SearchPattern,
    [Parameter(Mandatory = $false)]
    [String] $LogFilePath = "C:\Temp\log.txt"
      )
Clear-Host
# Set variables
$finalResult         = @()

#Define logging function
function BackupScan-Logentry {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    $logEntry = "$timestamp - $Message - Scanning Restore Point $VM $($restorePointCreationTime.ToString("dd-MM-yyyy HH:mm:ss"))"
    Add-Content -Path $logFilePath -Value $logEntry
}

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

if ($Result.Count -eq 0) {
	Write-Host 'Unable to locate any restore points for' $Scanhost 'in backup job' $Jobname -ForegroundColor White
	Exit
} else {
    rpLister $Result
}
# Ask for the restore point to be scanned - Automatically select latest restore points after 30 seconds
$stopTime       = [datetime]::Now.AddSeconds(30)
$restorePointID = 0
Write-Host -NoNewline "Please select restore point (Id) - Automatically selects the latest restore point after 30 seconds: "

while ([datetime]::Now -lt $stopTime -and -not [console]::KeyAvailable) {
    Start-Sleep -Milliseconds 50
}

if ([console]::KeyAvailable) {
    $restorePointID = [console]::ReadLine()
    while (!($restorePointID -lt $Result.Count -and $restorePointID -ge 0)) {
    $restorePointID = [console]::ReadLine()
    }
} 

while ([console]::KeyAvailable) {
    [console]::ReadKey($true) | Out-Null 
}

# Write selected Restore Point into a variable
$selectedRp          = $Result | Select-Object -Index $restorePointID 

# Store the restore point's creation time in a variable
$restorePointCreationTime = $selectedRp.CreationTime

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

# Get the mounted FLR path information
$flrPath             = Get-VBRWindowsGuestItem -Name $RootDirectory -FileRestore $session

# Check for changes using the given ScanPath variable
Write-Progress "Looking for changes..." -PercentComplete 95
BackupScan-Logentry -Message "Info - File Level Recovery - Compare with Production - $VM - Scanning started"
$files               =  Get-VBRWindowsGuestItem -Session $restoreSession -ParentItem $flrPath -Name $SearchPattern -RecursiveSearch -ChangedOnly -CompareWithOriginal -RunAsync

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
Clear-Host
Write-Host "The following changes were found:"
Write-Host "---------------------------------"
BackupScan-Logentry -Message "Warning - File Level Recovery - Compare with Production - Changes in $SearchPattern found - $VM Restore Point $restorePointCreationTime"
Write-Progress "Generating Table..." -PercentComplete 100
$finalResult | Format-Table -Wrap -AutoSize -Property @{Name='File Name';Expression={$_.FileName}},
                                                      @{Name='File Status';Expression={$_.FileStatus};align='left'},
                                                      @{Name='File Size';Expression={$_.FileSize};align='left'},
                                                      @{Name='Modification Date';Expression={$_.ModificationDate}}

if($finalResult.Count -eq 0){
Write-Host ""
Write-Host "No changes found - $SearchPattern" -ForegroundColor White
BackupScan-Logentry -Message "Info - File Level Recovery - Compare with Production - No changes found - $SearchPattern - $VM Restore Point $restorePointCreationTime"
   }
                                                     
# Stop Restore Session & Disconnect VBR Server
Stop-VBRWindowsFileRestore -FileRestore $session
Disconnect-VBRServer	
