<# 
.NAME
    Veeam Backup & Replication - Staged VM Restore
.DESCRIPTION
    This PowerShell script is designed to perform a staged virtual machine (VM) restore using Veeam Backup & Replication. 
    It connects to the Veeam server, retrieves the necessary information, lists the available VM restore points, allows the 
    user to select a restore point, and initiates the staged VM restore process.
.EXAMPLE
    .\vbr-staged-restore.ps1 -ESXiServer "ESXiServerName" -VMName "VMName" -Jobname "BackupJobName" -VirtualLab "VirtualLabName" -StagingScript "Path\To\StagingScript.ps1" -Credentials "CredentialsName"
 .NOTES  
    File Name  : vbr-staged-restore.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12, properly configured credentials and virtual lab in Veeam Backup & Replication
                 More details https://github.com/yetanothermightytool/powershell/blob/master/vbr/vbr-staged-restore/README.md
.VERSION
1.1
#>
Param(
    [Parameter(Mandatory=$true)]
    [string]$ESXiServer,
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    [Parameter(Mandatory=$true)]
    [string]$Jobname,
    [Parameter(Mandatory=$true)]
    [string]$VirtualLab,
    [Parameter(Mandatory=$true)]
    [string]$StagingScript,
    [Parameter(Mandatory=$true)]
    [string]$Credentials,
    [Parameter(Mandatory = $false)]
    [String] $LogFilePath = "C:\Temp\log.txt"
    )

# Variables
$host.ui.RawUI.WindowTitle = "VBR Staged Restore"

# Function for logging messages
function BackupScan-Logentry {
    param (
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $Message"
    Add-Content -Path $logFilePath -Value $logEntry
}


# Function to list restore points
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
# end function
Clear-Host
# Connect to Veeam Backup & Replication
Connect-VBRServer -Server localhost

# ESXi Server
$restoreServer     = Get-VBRServer -Name $ESXiServer

# Get the configured credentials for the specified host where the staging script will be executed
$creds             = Get-VBRCredentials -Name $Credentials

# Get the Virtual Lab informations
$vlab               = Get-VBRVirtualLab -Name $VirtualLab

# Get Backups
$Result = Get-VBRBackup | Where-Object { $_.jobname -eq $JobName } | Get-VBRRestorePoint | Where-Object { $_.name -eq $VMName } | Sort-Object CreationTime -Descending

# If no restore points have been found
if ($Result.Count -eq 0) {
	Write-Host 'Unable to locate any restore points for' $VMName 'in backup job' $Jobname -ForegroundColor White
    Disconnect-VBRServer
	Exit
} else {
# Present the result using the function rpLister
    rpLister $Result
}
# Ask for the restore point to be scanned - Automatically select latest restore points after 30 seconds
$stopTime = [datetime]::Now.AddSeconds(30)
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

$restorePointID = [int]$restorePointID  # Convert the restore point ID to an integer
Write-Host ""
# Selected Restore Point
$selectedRp               = $Result | Select-Object -Index $restorePointID 

# Start Staged Restore
Clear-Host
Write-Host "*** Start Staged Restore ***" -ForegroundColor White
$startupOptions           = New-VBRApplicationGroupStartupOptions -MaximumBootTime 300 -ApplicationInitializationTimeout 180 -MemoryAllocationPercent 100
BackupScan-Logentry -Message "Info - Staged VM Restore - Scanning started"
Start-VBRRestoreVM -RestorePoint $selectedRp -Server $restoreServer -StagingVirtualLab $vlab -StagingStartupOptions $startupOptions -StagingScript $StagingScript -EnableStagedRestore -StagingCredentials $creds | Out-Null

# Disconnect from VBR server
Disconnect-VBRServer
