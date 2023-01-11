<# 
.NAME
    Veeam Backup for Microsoft Office 365 - OneDrive for Business File Restore Checker (Hash value)
.SYNOPSIS
    Script to restore an OneDrive File to a local folder and compare the hash values
.DESCRIPTION
    This script restores a specific file from the last restore point to a local folder checks if the file has the same hash value as the original uploaded file
    The purpose is to check if the data in the restorepoint is consitent 
.NOTES  
    File Name  : vbo-odrestore-checker.ps1 
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell
.VERSION
    1.0        : Version history on github 
#>
param(
        [String] $Scanpath = "C:\scripts\vbo\vbo-checker\",
        [Parameter(Mandatory = $true)]
        [String] $User,
        [Parameter(Mandatory = $true)]
        [String] $Documentname,
        [Parameter(Mandatory = $true)]
        [String] $Originalhash
     )
Clear-Host

#Start OneDrive Restore Session using the latest backup state
Start-VEODRestoreSession -LatestState | Out-Null

#Connect to the restore session
$session        = Get-VEODRestoreSession
$username       = Get-VEODUser -Session $session -Name $User

#Search for the doucment the document
$document       = Get-VEODDocument -User $username -Name $Documentname -Recurse

#Restore the document
Save-VEODDocument -Document $document -Path $Scanpath | Out-Null

#Get the hash of the stored file - yes, currently selecting only one file
$FullFileName   = Get-ChildItem -Path $Scanpath -Filter $Documentname | Where-Object {!$_.PSIsContainer} | Sort-Object {$_.LastWriteTime} -Descending | Select-Object -First 1
  ForEach ($File in $FullFileName)
      {
      $FilePath = $File.DirectoryName
      $FileName = $File.Name
        $entry  = Get-FileHash $FilePath"\"$FileName 
        if ($entry.Hash -eq $originalhash) { 
            Write-Host "Same Hash Value"
            $LastExitCode = 0}
        elseif ($entry.Hash -ne $originalhash) { 
            Write-Host "HUSH HUSH Baby"
            $LastExitCode = 1}
        Write-Host ""
        Write-Host "Cleaning up"
        Remove-Item -Path $FilePath"\"$FileName
        }

#Stop Restore Session
Stop-VEODRestoreSession -Session $session

#Give back the exit code
EXIT $LastExitCode
