param(
        [String] $scanpath = "D:\Scripts\vb365\scanner",
        [String] $daysback,
        [Parameter(Mandatory = $true)]
        [String] $account,
        [Parameter(Mandatory = $true)]
        [String] $filetype,
        [Parameter(Mandatory = $true)]
        [String] $maxfiles
        #[String] $APIKey        
     )
Clear-Host

# Set general variables
$filterDate       = (Get-Date).AddDays(-$Daysback)

# Start OneDrive Restore Session using the proper restore point
if ($daysback -gt "0") 
    {
    $restorePoint = Get-VBORestorePoint | Where-Object -Property isOneDrive | Where-Object {$_.BackupTime -ge $filterDate.Date} | sort -Property BackupTime | Select -First 1
    Start-VEODRestoreSession -RestorePoint $restorePoint
    }
elseif ([string]::IsNullOrEmpty($Daysback)) 
    { 
    Start-VEODRestoreSession -LatestState 
    }

# Connect to the VB365 restore session
$session          = Get-VEODRestoreSession
$counter          = $session.count-1
$username         = Get-VEODUser -Session $session[$counter] -Name $account

# Search for specified file type that will be scanned
$totalstored      = Get-VEODDocument -User $username -Recurse
$document         = Get-VEODDocument -User $username -Name $filetype -Recurse
Write-Host
Write-Host "Total files found in restore point" $totalstored.Count
Write-Host $maxfiles" out of" $document.Count $filetype" files will be scanned"
Write-Host 

if (!$document.Count) 
{
# The provided file extension could not be found
Write-Host "File type"$filetype "not found in backup" -ForegroundColor Yellow
# Stop Restore Session and exit
Stop-VEODRestoreSession -Session $session[$counter] 
exit
}

# Restore the document
Save-VEODDocument -Document $document -Path $scanpath | Out-Null


# Go through the file list - The number of selected files is random
$fullFileName     = Get-ChildItem -Path $scanpath | Where-Object {!$_.PSIsContainer} | Sort-Object {$_.LastWriteTime} -Descending | Select-Object -First $maxfiles
ForEach ($file in $fullFileName)
        {
        $filePath          = $file.DirectoryName
        $fileName          = $file.Name
        
        #Get SHA-256 hash value from file
        $hash = (Get-FileHash $FilePath"\"$FileName)
        $threats = Get-MpThreatCatalog
        $hashFound = $false

        foreach ($threat in $threats) {
        if ($threat.ThreatHash -eq $hash) {
        Write-Host "Hash found in Microsoft Defender Antivirus threat catalog"
        $hashFound = $true
        break
          }
        }

        if (!$hashFound) {
        Write-Host "Hash not found in Microsoft Defender Antivirus threat catalog"
        }

}

# Clean up the working directory - Warning all files with the given extension will be deleted!
ForEach ($file in $fullFileName)
        {
        $filePath          = $file.DirectoryName
        Remove-Item -Path $filepath"\"$filetype
        }      

# Stop Restore Session
Stop-VEODRestoreSession -Session $session[$counter] | Out-Null
