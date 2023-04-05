<# 
.NAME
    Veeam Backup for Microsoft 365 - OneDrive Backup Scanner
.DESCRIPTION
    This script restores the specified file(s) from a OneDrive Restore Point and scans them using Windows Defender.
.EXAMPLE
        The following example restores a maximum of 10 *.docx files in the D:\Restore directory and scans them with the Windows Defender
        (Microsoft Antimalware Service Command Line MpCmdRun.exe)

    PS >.\vb365-od-scanner-msdefender.ps1 -VB365Server localhost -daysback 1 -account "Megan Bowen" -filetype "*.docx" -maxfiles 10 -scanpath "D:\Restore"
.NOTES  
    File Name  : vb365-od-scanner-defender.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12
.VERSION
    1.1
#>

param(
     [Parameter(Mandatory = $true)]
     [String] $VB365Server,
     [Parameter(Mandatory = $true)]
     [String] $daysback,
     [Parameter(Mandatory = $true)]
     [String] $account,
     [Parameter(Mandatory = $true)]
     [String] $filetype,
     [Parameter(Mandatory = $true)]
     [String] $maxfiles,
     [String] $scanpath = "D:\Scripts\vb365\scanner"
     )
Clear-Host

# Set general variables
$filterDate       = (Get-Date).AddDays(-$Daysback)

# Connect VB365 Server
Connect-VBOServer -Server $VB365Server

# Start OneDrive Restore Session using the proper restore point
if ($daysback -gt "0") 
    {
    $restorePoint = Get-VBORestorePoint | Where-Object -Property isOneDrive | Where-Object {$_.BackupTime -ge $filterDate.Date} | sort -Property BackupTime -Descending | Select -First 1
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
Write-Host 

if (!$document.Count) 
{
# The provided file extension could not be found
Write-Host "File type"$filetype "not found in backup" -ForegroundColor Yellow
Write-Host
# Stop Restore Session and exit
Stop-VEODRestoreSession -Session $session[$counter] 
Disconnect-VBOServer
exit
}

# Restore the document
Write-Host $maxfiles" out of" $document.Count $filetype" files will be scanned"
Write-Host
Save-VEODDocument -Document $document -Path $scanpath | Out-Null


# Go through the file list
$fullFileName     = Get-ChildItem -Path $scanpath | Where-Object {!$_.PSIsContainer} | Sort-Object {$_.LastWriteTime} -Descending | Select-Object -First $maxfiles
ForEach ($file in $fullFileName)
        {
        $filePath          = $file.DirectoryName
        $fileName          = $file.Name
        $defenderFolder    = (Get-ChildItem "C:\ProgramData\Microsoft\Windows Defender\Platform\" | Sort-Object -Descending | Select-Object -First 1).fullname
        $defender          = "$defenderFolder\MpCmdRun.exe"
        $output            = & $defender -scan -scantype 3 -file $FilePath"\"$FileName 
        $output | ForEach-Object {Write-Verbose $_}
        $output        
        #break
          }
     
# Clean up the working directory - Warning all files with the given extension in the scanpath will be deleted!
ForEach ($file in $fullFileName)
        {
        $filePath          = $file.DirectoryName
        Remove-Item -Path $filepath"\"$filetype
        }      

# Stop Restore Session
Stop-VEODRestoreSession -Session $session[$counter] -InformationAction SilentlyContinue | Out-Null

# Disconnect VB365 Server
Disconnect-VBOServer
