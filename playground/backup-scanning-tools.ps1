# General variables
$host.ui.RawUI.WindowTitle = "Backup Scanning Tools"
$scanningToolsPath         = "D:\Scripts\vbr\scanningtools"

# Define the menu options
$menuOptions = @"

[42m╔═══════════════════════════════════════════╗
║           Backup Scanning Tools           ║
╚═══════════════════════════════════════════╝[0m

  1. Secure Restore - AV scan
  2. Secure Restore - YARA scan

  3. Instant VM Disk Recovery scan
  
  4. NAS Backup scan
  
  5. Staged VM Restore
  
  
  x. Exit
"@

# Function to display the menu options
function Show-Menu {
    [System.Console]::Clear()
    Write-Host $menuOptions -ForegroundColor White
    Write-Host
    Write-Host "Enter the option number or x for Exit:" -ForegroundColor White
}

# Loop to display the menu and process user input
do {
    Show-Menu
    $choice = Read-Host

    switch ($choice) {
        "1" {
            Clear-Host
            Write-Host "╔════════════════════════════════════════╗" -ForegroundColor White
            Write-Host "║     Start Secure Restore - AV Scan     ║" -ForegroundColor White
            Write-Host "╚════════════════════════════════════════╝" -ForegroundColor White
            Write-Host ""
            Write-Host "This script mounts the selected restore point of a Veeam VM or Agent backup using the Data Integration API function to a Linux server (mount server) and runs an anti-virus file-level scan using ClamAV." -ForegroundColor Cyan
            Write-Host ""
            $param1 = Read-Host "Host to attach backup to "
            $param2 = Read-Host "Host to scan             "
            $param3 = Read-Host "Backup Job Name          "
            $param4 = Read-Host "SSH key path & file name "
            $scriptPath = "$scanningToolsPath\vbr-securerestore.ps1"
            Write-Host ""
            Write-Host "Start script"  -ForegroundColor White
            Sleep 3
            & $scriptPath -Mounthost $param1 -Scanhost $param2 -Jobname $param3 -Keyfile $param4 -AVScan
            Write-Host ""
            Pause
            [System.Console]::Clear()
            }
        "2" {
            Clear-Host
            Write-Host "╔════════════════════════════════════════╗" -ForegroundColor White
            Write-Host "║   Start Secure Restore - YARA scan     ║" -ForegroundColor White
            Write-Host "╚════════════════════════════════════════╝" -ForegroundColor White
            Write-Host ""
            Write-Host "This script mounts the selected restore point of a Veeam VM or Agent backup using the Data Integration API function to a Linux server (mount server) and runs a YARA scan." -ForegroundColor Cyan
            Write-Host ""
            $param1 = Read-Host "Host to attach backup to "
            $param2 = Read-Host "Host to scan             "
            $param3 = Read-Host "Backup Job Name          "
            $param4 = Read-Host "SSH key path & file name "
            $scriptPath = "$scanningToolsPath\vbr-securerestore.ps1"
            Write-Host ""
            Write-Host "Start script"  -ForegroundColor White
            Sleep 3
            & $scriptPath -Mounthost $param1 -Scanhost $param2 -Jobname $param3 -Keyfile $param4 -YARAScan
            Write-Host ""
            Pause
            [System.Console]::Clear()
        }
        "3" {
            Clear-Host
            Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor White
            Write-Host "║          Start Instant VM Disk Recovery              ║" -ForegroundColor White
            Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor White
            Write-Host ""
            $param1 = Read-Host "VM to attach disk(s) to"
            Write-Host "Important! Make sure that this VM starts from the attached Rescue ISO and not from a hard drive" -ForegroundColor Yellow
            Write-Host ""
            $param2 = Read-Host "Host to scan            "
            $param3 = Read-Host "Backup Job Name         "
            $scriptPath = "$scanningToolsPath\vbr-instantdiskrecovery.ps1"
            Write-Host ""
            Write-Host "Start script"  -ForegroundColor White
            Sleep 3
            & $scriptPath -Mounthost $param1 -Scanhost $param2 -Jobname $param3
            Write-Host ""
            Pause
            [System.Console]::Clear()
        }
        "4" {
            Clear-Host
            Write-Host "╔════════════════════════════════════════╗" -ForegroundColor White
            Write-Host "║         Start NAS Backup scan          ║" -ForegroundColor White
            Write-Host "╚════════════════════════════════════════╝" -ForegroundColor White
            Write-Host ""
            $param1 = Read-Host "NAS Backup Job Name    "
            $scriptPath = "$scanningToolsPath\vbr-nas-avscanner.ps1"
            Write-Host ""
            Write-Host "Start script"  -ForegroundColor White
            Sleep 3
            & $scriptPath -Jobname $param1
            Write-Host ""
            Pause
            [System.Console]::Clear()
        }
        "5" {
            Clear-Host
            Write-Host "╔═════════════════════════════════════════════╗" -ForegroundColor White
            Write-Host "║          Start Staged VM Restore            ║" -ForegroundColor White
            Write-Host "╚═════════════════════════════════════════════╝" -ForegroundColor White
            Write-Host ""
            Write-Host "This script triggers a staged VM recovery on the specified ESXi server and runs the specified script. If the script runs successfully, the VM is restored into production." -ForegroundColor Cyan
            Write-Host ""
            $param1 = Read-Host "Target ESXi server          "
            $param2 = Read-Host "VM name                     "
            $param3 = Read-Host "Backup Job Name             "
            $param4 = Read-Host "Virtual Lab name            "
            $param5 = Read-Host "Staging script (full path)  "
            $param6 = Read-Host "Credentials for script      "
            $scriptPath = "$scanningToolsPath\vbr-staged-restore.ps1"
            Write-Host ""
            Write-Host "Start script"  -ForegroundColor White
            Sleep 3
            & $scriptPath -ESXiServer $param1 -VMName $param2 -Jobname $param3 -VirtualLab $param4 -StagingScript $param5 -Credentials $param6
            Write-Host ""
            Pause
            [System.Console]::Clear()
        }
        "x" {
            Write-Host ""
            Write-Host "Are you sure you want to exit? (Y/N)" -ForegroundColor "White"
            $confirm = Read-Host
            $confirmed = ($confirm -eq "Y" -or $confirm -eq "y")
            if ($confirmed) {
                exit
            } else {
                [System.Console]::Clear()
            }
        }
    }
} while ($true)
