<# 
.NAME
    Veeam Backup for Microsoft 365 - OneDrive for Business Backup Scanner
.DESCRIPTION
    This script restores the specified number file(s) from the latest OneDrive for Business Restore Point and scans them using Microsoft Defender Antivirus
.NOTES  
    File Name  : vb365-odb-single-scan.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup for Microsoft 365
.VERSION
    1.2
#>
param(
        [Parameter(Mandatory = $true)]
        [String] $User,
        [Parameter(Mandatory = $true)]
        [String] $MaxFiles,
        [String] $File,
        [String] $ScanPath   = "D:\Scripts\vb365\scanner\"
        )
Clear-Host
Connect-VBOServer -Server localhost

# Check if a restore session is running. If yes, stop script
$sessionChecker = Get-VEODRestoreSession

if ($sessionChecker.Count -gt 0) { 
  Write-Host "A Veeam Backup for Microsoft 365 restore process is already running. Stopping script." -ForegroundColor Yellow
  Exit
}

# Start Exchange Restore Session pointing to the latest backup state
Start-VEODRestoreSession -LatestState  | Out-Null

# Connect to the restore session 
$session        = Get-VEODRestoreSession

# Get specific User
$username       = Get-VEODUser -Session $session -Name $User

if ($File) 
    {
    $allfiles         = Get-VEODDocument -User $username -Name $File -Recurse
    }
elseif ([string]::IsNullOrEmpty($File))
    { 
    $allFiles       = Get-VEODDocument -User $username -Recurse
    Write-Host "Total files found in restore point" $allFiles.Count -ForegroundColor Cyan
    }

# Store the selected maximum number of files
if ($AllFiles.Count -lt $MaxFiles) {
    $filteredFiles  = $AllFiles
} else {
    $filteredFiles  = $AllFiles[0..($MaxFiles - 1)]
}

# Save file(s) in the ScanPath
Save-VEODDocument -Document $filteredFiles -Path $ScanPath | Out-Null

# Scan the files
$defenderFolder     = (Get-ChildItem "C:\ProgramData\Microsoft\Windows Defender\Platform\" | Sort-Object -Descending | Select-Object -First 1).fullname
$defender           = "$defenderFolder\MpCmdRun.exe"
$output             = & $defender -scan -scantype 3 -file $ScanPath

# Grep if found threats greater than 0
$threatCountPattern = "found (\d+) threats"
$threatCountMatch   = $output | Select-String -Pattern $threatCountPattern
$threatCount        = if ($threatCountMatch) { $threatCountMatch.Matches.Groups[1].Value } else { "0" }

# Present result / Windows Event Log entries
if ($threatCount -eq 0) {
    $output | ForEach-Object {Write-Verbose $_}
    $output
    Write-Host "No threats were found" -ForegroundColor Cyan
 
} else {
    $maxEvents = [Math]::Min([int]$threatCount, 3)
    $output | ForEach-Object {Write-Verbose $_}
    $output
    Write-Host "Threats found..." -ForegroundColor Yellow

    $events = Get-WinEvent -FilterHashtable @{
        LogName        = 'Microsoft-Windows-Windows Defender/Operational'
        ID             = 1116
    } -MaxEvents $maxEvents

    # Initialize an array to store custom objects with extracted information
    $eventObjects = @()

    foreach ($event in $events) {
        # Split the event message into individual lines
        $lines = $event.Message -split "`r`n"

        # Initialize variables to store the extracted info
        $names    = @()
        $category = $path = $null

        # Go through each line of the event message
        foreach ($line in $lines) {
            # Extract the name, category, and path if the line contains the corresponding information
            if ($line -match "Name:(.*)") {
                $names += $Matches[1].Trim()
            } elseif ($line -match "Category:(.*)") {
                $category = $Matches[1].Trim()
            } elseif ($line -match "Path:(.*)") {
                $paths = $Matches[1].Trim() -split ';'
                $paths = $paths | ForEach-Object { $_.Trim() }
            }
        }

        $eventObjects += foreach ($path in $paths) {
            [PSCustomObject]@{
                TimeCreated = $event.TimeCreated
                Names       = $names -join ', '
                Category    = $category
                Path        = $path
            }
        }
    }

    foreach ($obj in $eventObjects) {
    Write-Host $obj.TimeCreated -ForegroundColor White -NoNewline; Write-Host "`t" -NoNewline;
    Write-Host $obj.Names       -ForegroundColor White -NoNewline; Write-Host "`t" -NoNewline;
    Write-Host $obj.Category    -ForegroundColor White -NoNewline; Write-Host "`t" -NoNewline;
    Write-Host $obj.Path        -ForegroundColor White;
}
}

# Cleaning Up
Write-Host "Removing downloaded files..." -ForegroundColor Cyan
Remove-Item -Path $ScanPath\* -Recurse -Force

# Stop Restore session and disconnect from VB365 server
Stop-VEODRestoreSession -Session $session
Disconnect-VBOServer
