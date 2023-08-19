param(
    [Parameter(Mandatory = $true)]
    [String] $VM,
    [Parameter(Mandatory = $true)]
    [String] $JobName,
    [Parameter(Mandatory = $false)]
    [String] $LogFilePath = "C:\Temp\log.txt"
      )
Clear-Host
# Set variables
$hashCodes          = @()
$foundHashes        = @()
$hashesFile         = "D:\Scripts\Filehashscanner\full_sha256.txt"
$foundHashesFile    = "D:\Scripts\Filehashscanner\found_hashes.txt"
$ProgressPreference = "SilentlyContinue"

#Define logging function
function BackupScan-Logentry {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    $logEntry  = "$timestamp - $Message - Scanning Restore Point $VM $($restorePointCreationTime.ToString("dd-MM-yyyy HH:mm:ss"))"
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
$Result              = Get-VBRRestorePoint -Name $VM -Backup $JobName  | Sort-Object -Property CreationTime -Descending 

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
$selectedRp               = $Result | Select-Object -Index $restorePointID 

# Store the restore point's creation time in a variable
$restorePointCreationTime = $selectedRp.CreationTime

# Start the Restore Session
$session             = Start-VBRWindowsFileRestore -RestorePoint $selectedRp -Reason "vbr-flr-filehashscanner.ps1" 

# Start the File Hash Scanning...
Clear-Host
Write-Host "Find Users folder in VeeamFLR..." -ForegroundColor White
Write-Host

# Find the User folder in a given path
$rootPath       = "C:\VeeamFLR\$VM*\"  
$userFolders    = Get-ChildItem $rootPath -Directory -Filter "Users" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Parent.Parent.Name -eq (Get-Item $rootPath).Name }
$userFolderPath = $null

if ($userFolders.Count -gt 0) {
    $userFolderPath  = $userFolders[0].FullName
    Write-Host "Found Users folder at: $userFolderPath" -ForegroundColor Cyan
    $userFolders     = Get-ChildItem $userFolderPath -Directory

    # Loop through each specified folder
    $cleanFilesCount = 0
    Write-Host
    Write-Host "Start scanning folders..." -ForegroundColor White
    BackupScan-Logentry -Message "Info - VBR FLR - Hash Scanner - Scanning started"
    Write-Host

    foreach ($userFolder in $userFolders) {
        $downloadsFolderPath   = Join-Path $userFolder.FullName "Downloads"
        $appDataTempFolderPath = Join-Path $userFolder.FullName "AppData\Local\Temp"
        $edgeCacheFolderPath   = Join-Path $userFolder.FullName "AppData\Local\Microsoft\Edge\User Data\Default\Cache\Cache_Data"
        $chromeCacheFolderPath = Join-Path $userFolder.FullName "AppData\Local\Google\Chrome\User Data\Default\Cache"
        $winStartupFolderPath  = Join-Path $userFolder.FullName "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"

        # Check if any of the folders exist
        if ((Test-Path $downloadsFolderPath) -or (Test-Path $appDataTempFolderPath) -or (Test-Path $edgeCacheFolderPath) -or (Test-Path $chromeCacheFolderPath) -or (Test-Path $winStartupFolderPath)) {
           $foldersToProcess = @($downloadsFolderPath, $appDataTempFolderPath, $edgeCacheFolderPath,$chromeCacheFolderPath,$winStartupFolderPath)

            foreach ($folderPath in $foldersToProcess) {
                if (Test-Path $folderPath) {
                    $files = Get-ChildItem $folderPath -File -Recurse

                    if ($files.Count -gt 0) {
                        if (Test-Path $hashesFile) {
                            $hashesInFile = Get-Content $hashesFile

                            foreach ($file in $files) {
                                $hash = Get-FileHash $file.FullName -Algorithm SHA256

                                # Check if the hash is in the hashes file
                                if ($hashesInFile -contains $hash.Hash) {
                                    Write-Host "User: $($userFolder.Name), Folder: $($folderPath), File: $($file.FullName), Hash: $($hash.Hash), Hash found in the list!" -ForegroundColor Yellow
                                    $foundHashes += $hash.Hash
                                    $foundHashesCount++
                                } else {
                                    #Write-Host "User: $($userFolder.Name), Folder: $($folderPath), File: $($file.FullName), Hash: $($hash.Hash), File clean. Hash not found in the list!" -ForegroundColor Cyan
                                    Write-Host "#" -NoNewline -ForegroundColor Cyan
                                    $cleanFilesCount++
                                }
                            }
                        } else {
                            Write-Host
                            Write-Host "Hash file not found at $hashesFile." -ForegroundColor Cyan
                        }
                    } else {
                        Write-Host
                        Write-Host
                        #Write-Host "No files found for user $($userFolder.Name)." -ForegroundColor Cyan
                    }
                } else {
                    # No folders found for a User
                    Write-Host
                    Write-Host "Folder $($folderPath) not found for user $($userFolder.Name)."
                 }
            }
        } else {
            # Another else.             
    }
}

# Display the count of clean files
Write-Host "Total matching hashes: $foundHashesCount" -ForegroundColor White
Write-Host "Total clean files:     $cleanFilesCount" -ForegroundColor White
Write-Host "End scanning" -ForegroundColor White
}

if ($foundHashes -eq 0 -or [string]::IsNullOrEmpty($foundHashes)){
BackupScan-Logentry -Message "Info - VBR FLR - Hash Scanner - Scanning ended - No hash matches"
}
else{
BackupScan-Logentry -Message "Warning - VBR FLR - Hash Scanner - Scanning ended - $foundHashesCount Hash matches"
}

# Storing found hashes
$foundHashes | Set-Content -Path $foundHashesFile

# Enable Progress Display again
$ProgressPreference = "Continue"                                                    

# Stop Restore Session & Disconnect VBR Server
Stop-VBRWindowsFileRestore -FileRestore $session
Disconnect-VBRServer
Pause
