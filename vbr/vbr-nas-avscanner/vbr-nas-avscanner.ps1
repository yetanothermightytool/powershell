<# 
.NAME
    NAS Share Scanner
.DESCRIPTION
    This script launches a Instant File Share Recovery for a specified file share backup job and runs a MS Defender malware scan.
    Any program can be used to scan the presented share.
	
    More details on Github - https://github.com/yetanothermightytool/powershell/blob/master/vbr/vbr-nas-avscanner/README.md
    
.NOTES  
    File Name  : vbr-nas-avscanner.ps1  
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell 
.VERSION
    1.3
#>
param(
    [Parameter(mandatory=$true)]
    [String] $JobName,
    [Parameter(Mandatory = $false)]
    [String] $LogFilePath = "C:\Temp\log.txt"
    )

# Variables
$host.ui.RawUI.WindowTitle = "VBR NAS AV Scanner"

# Connect to the VBR Server
Connect-VBRServer -Server localhost

function BackupScan-Logentry {
    param (
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $Message"
    Add-Content -Path $LogFilePath -Value $logEntry
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
        @{ Expression={ $_.NASServerName };Label="Share Name";Width=50;Align="left" }, `
        @{ Expression={ $_.CreationTime };Label="Creation Time";Width=25;Align="left" }`
          }
    end {
 
        Write-Host
        Write-Host "The following restore points were found...(newest first)" -Foregroundcolor White
        Write-Host
        return $Output | Format-Table $RestoreTable
    }
}
# end function

#Let's go
Clear-Host

# Get NAS Backup Job informations
$nasbackup          = Get-VBRNASBackup -Name $Jobname

# Get the latest restore point
$restorepoint       = Get-VBRNASBackupRestorePoint -NASBackup $nasbackup | Sort-Object -Property CreationTime -Descending

# If no restore points have been found
if ($restorepoint.Count -eq 0) {
	Write-Host 'Unable to locate any restore points for backup job' $JobName -ForegroundColor White
	Exit
} else {
# Present the result using the function rpLister
   rpLister $restorepoint
}
$stopTime = [datetime]::Now.AddSeconds(30)
$restorePointID = 0

Write-Host -NoNewline "Please select restore point (Id) - Automatic selection of restore point 0 after 30 seconds:"
while ([datetime]::Now -lt $stopTime -and -not [console]::KeyAvailable) {
    Start-Sleep -Milliseconds 50
}
if ([console]::KeyAvailable) {
    $restorePointID = [console]::ReadLine()
    while (!($restorePointID -lt $restorepoint.Count -and $restorePointID -ge 0)) {
        $restorePointID = [console]::ReadLine()
    }
} 

while ([console]::KeyAvailable) {
    [console]::ReadKey($true) | Out-Null 
}

$restorePointID = [int]$restorePointID  
Write-Host ""

# Get the selected restore point
$selectedRp               = $restorepoint | Select-Object -Index $restorePointID 


# Set the permissions - Permissions can be adjusted
$permissions        = New-VBRNASPermissionSet -RestorePoint $restorepoint -Owner "Administrator" -AllowSelected -PermissionScope ("Administrator")

# Start the Instant NAS Recovery session - Reason can be changed
$restoresession     = Start-VBRNASInstantRecovery -RestorePoint $selectedRp -Permissions $permissions -Reason "Security Scan"

#Scan the Share using whatever you want - Sharepath is in variable $restoresession.SharePath
#Example with Microsoft Defender
BackupScan-Logentry -Message "Info - NAS AV Scanner - Scanning started"
$defenderFolder     = (Get-ChildItem "C:\ProgramData\Microsoft\Windows Defender\Platform\" | Sort-Object -Descending | Select-Object -First 1).fullname
$defender           = "$defenderFolder\MpCmdRun.exe"
$host.UI.RawUI.ForegroundColor = "White"
$output             = & $defender -scan -scantype 3 -file $restoresession.SharePath

# Grep if found threats greater than 0
$threatCountPattern = "found (\d+) threats"
$threatCountMatch   = $output | Select-String -Pattern $threatCountPattern
$threatCount        = if ($threatCountMatch) { $threatCountMatch.Matches.Groups[1].Value } else { "0" }

# Present result / Windows Event Log entries
if ($threatCount -eq 0) {
    $output | ForEach-Object {Write-Verbose $_}
    $output
    Write-Host "No threads were found"
    BackupScan-Logentry -Message "Info - NAS AV Scanner - Scanning ended - No threads were found"

} else {
    $maxEvents = [Math]::Min([int]$threatCount, 3)
    $output | ForEach-Object {Write-Verbose $_}
    $output
    BackupScan-Logentry -Message "Warning - NAS AV Scanner - Scanning ended - Result: $output"
    # Retrieve the last x Windows Defender events with ID 1116
$events            = Get-WinEvent -FilterHashtable @{
    LogName        = 'Microsoft-Windows-Windows Defender/Operational'
    ID             = 1116
} -MaxEvents $maxEvents

# Initialize an array to store custom objects with extracted information
$eventInfo         = @()

# Extract specific information from the event message and create custom objects
foreach ($event in $events) {
    # Split the event message into individual lines - that was a tough one ;)
    $lines = $event.Message -split "`r`n"

    # Initialize variables to store the extracted infos
    $names         = @()
    $category      = $path = $null

    # Go through each line of the event message
    foreach ($line in $lines) {
        # Extract the name, category, and path if the line contains the corresponding information
        if ($line -match "Name:(.*)") {
            $names   += $Matches[1].Trim()
        } elseif ($line -match "Category:(.*)") {
            $category = $Matches[1].Trim()
        } elseif ($line -match "Path:(.*)") {
            $paths    = $Matches[1].Trim() -split ';'
            $paths    = $paths | ForEach-Object { $_.Trim() }
        }
    }

    $eventObjects = foreach ($path in $paths) {
    [PSCustomObject]@{
        TimeCreated = $event.TimeCreated
        Names = $names -join ', '
        Category = $category
        Path = $path
     }
   }
 }   
# Display the extracted information in a table view
#$eventInfo | Format-Table -AutoSize
$eventObjects | Format-Table -Property TimeCreated, Names, Category, Path -AutoSize
}

# Text back to green
$host.UI.RawUI.ForegroundColor = "Green"

#Stop Instant Recovery Session
Stop-VBRNASInstantRecovery -InstantRecovery $restoresession -Force

# Disconnect VBR Server
Disconnect-VBRServer
