param(
[String] $DaysBack,
[Parameter(Mandatory = $true)]
[String] $JobName,
[Parameter(Mandatory = $true)]
[String] $VM,
[Parameter(Mandatory = $true)]
[String] $ScanPath
      )
Clear-Host
# Set variables
$finalResult   = @()
$filterDate            = (Get-Date).AddDays(-$Daysback)

# Connect to the Veeam Backup & Replication server
Write-Progress "Connect to VBR Server..." -PercentComplete 25
Connect-VBRServer -Server localhost

# Define the backup job and restore point you want to use
Write-Progress "Get Restore Point for VM $VM" -PercentComplete 50
$restorePoint          = Get-VBRRestorePoint -Name $VM | Where-Object {$_.CreationTime -ge $filterDate.Date} | sort -Property CreationTime -Descending | Select -First 1

# Define the virtual machine you want to scan for changed files
$VMName                = Find-VBRViEntity -Name $VM

# Start the Restore Session
Write-Progress "Start Restore Session..." -PercentComplete 75
$session               = Start-VBRWindowsFileRestore -RestorePoint $restorePoint -Reason "vbr-flr-comparator.ps1 - CompareWithOriginal"

# Define the credentials to use for the production machine connection
$cred                  = Get-VBRCredentials -Name ".\Administrator"

# Connect to the production machine using the credentials and save the session object
Write-Progress "Connect to VM $VM..." -PercentComplete 90
$directConnect         = Connect-VBRWindowsGuestProductionMachine -FileRestore $session -GuestCredentials $cred

# Get the running Restore Session
$restoreSession        = Get-VBRRestoreSession | Where-Object {$_.State -eq "Working"}

# Get the mounted FLR volume information
$flrVolume             = Get-VBRWindowsGuestItem -FileRestore $session

# Check for changes using the given ScanPath variable
Write-Progress "Looking for files..." -PercentComplete 95
$files                 = Get-VBRWindowsGuestItem -FileRestore $session -ParentItem $flrVolume -RecursiveSearch  -ChangedOnly -CompareWithOriginal -Name $ScanPath -RunAsync
#$files                 = Get-VBRWindowsGuestItem -FileRestore $session -RecursiveSearch -ChangedOnly -CompareWithOriginal -RunAsync


# Loop through each file and perform some action
foreach ($file in $files) {
    if($files.Count -gt 0){
    # Create table content
    $finalResult       += New-Object psobject -Property @{
    FileName            = $file.Name
    FileStatus          = $file.CompareState
    FileSize            = $file.Size
    ModificationDate    = $file.ModificationDate
    }
  }
}

# Print Table
$finalResult | Format-Table -Wrap -AutoSize -Property @{Name='File Name';Expression={$_.FileName}},
                                                      @{Name='File Status';Expression={$_.FileStatus};align='left'},
                                                      @{Name='File Size';Expression={$_.FileSize};align='left'},
                                                      @{Name='Modifictation Date';Expression={$_.ModificationDate}}
                                                     
# Stop Restore Session & Disconnect VBR Server
Stop-VBRWindowsFileRestore -FileRestore $session
Disconnect-VBRServer


#ModFileBackup       = (Compare-VBRWindowsGuestItemsAttributes -FileRestore $session -Item $file).BackupValue.ModificationDateU
#ModFileProduction   = (Compare-VBRWindowsGuestItemsAttributes -FileRestore $session -Item $file).ProductionValue.ModificationDateUtc
