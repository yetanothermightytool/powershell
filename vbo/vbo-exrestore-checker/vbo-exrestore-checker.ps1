<# 
.NAME
    Veeam Backup for Microsoft Office 365 - Exchange Mailbox Item Restore Content Checker
.SYNOPSIS
    Script to restore an Exchange mailbox item to a local folder and then search for a specific search string
.DESCRIPTION
    This script restores a specific mail item from the last restore point to a local folder checks if the .msg file can be read given a specific search string
    The purpose is to check if the data in the restorepoint is consitent - Think of SureBackup Light  
.NOTES  
    File Name  : vbo-exrestore-checker.ps1 
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell
.VERSION
    1.0        : Version history on github
#>
param(
        [String] $Scanpath = "C:\Scripts\vbo\vbo-checker\",
        [Parameter(Mandatory = $true, Position = 0)]
        [String] $Mailbox,
        [String] $Subject,
        [String] $Pattern
     )
Clear-Host

#Impot Veeam Archiver Module
Import-Module "C:\Program Files\Veeam\Backup365\Veeam.Archiver.PowerShell\Veeam.Archiver.PowerShell.psd1"

#Start Exchange Restore Session pointing to the latest backup state
Start-VBOExchangeItemRestoreSession -LatestState | Out-Null

#Connect to the restore session and search for the test mail to be scanned in the given mailbox
$session        = Get-VBOExchangeItemRestoreSession
$counter        = $session.count-1 
$database       = Get-VEXDatabase -Session $session[$counter] 

#Mailbox where the email is stored
$exmailbox      = Get-VEXMailbox -Database $database -Name $Mailbox

#Mailbox folder where the email is stored
$inbox          = Get-VEXFolder -Mailbox $exmailbox -Name "Inbox"

#Search for the email (Subject)
$checkedmail    = Get-VEXItem -Folder $inbox -Query $Subject

#Restore the the most recent email with the search string
Export-VEXItem -Item $checkedmail[0] -To $Scanpath | Out-Null

#Scan the .msg file - yes, I know, there is only one available 
$FullFileName = Get-ChildItem -Path $Scanpath -Filter *.msg | Where-Object {!$_.PSIsContainer} | Sort-Object {$_.LastWriteTime} -Descending | Select-Object -First 1
  ForEach ($File in $FullFileName)
        {
        $FilePath = $File.DirectoryName
        $FileName = $File.Name
        $entry = Select-String -Path $FilePath"\"$FileName -Pattern $Pattern # "VBO-Exchange-Mailbox-Item" 
        Write-Host "The email contains the searched string" $entry.count "times"
        if ($entry.count -eq 0) { 
            $LastExitCode = 1}
        elseif ($entry.count -gt 0) { 
            $LastExitCode = 0}
        Write-Host ""
        Write-Host "Cleaning up"
        Remove-Item -Path $FilePath"\"$FileName
        }

#Stop Exchange Restore Session
Stop-VBOExchangeItemRestoreSession -Session $session[$counter]

#Give back the exit code
EXIT $LastExitCode
