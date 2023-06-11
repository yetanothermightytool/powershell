<# 
.NAME
    Veeam Backup for Microsoft 365 - Exchange Mailbox Item Restore Content Checker
.SYNOPSIS
    Script to restore an Exchange mailbox item to a local folder and then search for a specific search string
.DESCRIPTION
    This script restores a specific mail item from the last restore point to a local folder checks if the .msg file can be read given a specific search string
    The purpose is to check if the data in the restorepoint is consitent - Think of SureBackup Light  
.NOTES  
    File Name  : vb365-exrestore-checker.ps1 
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell
.VERSION
    1.1        
#>
param(
        [String] $Scanpath = "D:\Scripts\vb365\scanner",
        [Parameter(Mandatory = $true)]
        [String] $Mailbox,
        [Parameter(Mandatory = $true)]
        [String] $Subject,
        [Parameter(Mandatory = $true)]
        [String] $Pattern
     )
Clear-Host

#Start Exchange Restore Session pointing to the latest backup state
Start-VBOExchangeItemRestoreSession -LatestState | Out-Null

#Connect to the restore session and search for the test mail to be scanned in the given mailbox
$session        = Get-VBOExchangeItemRestoreSession
$database       = Get-VEXDatabase -Session $session

#Mailbox where the email is stored
$exmailbox      = Get-VEXMailbox -Database $database -Name $Mailbox

#Mailbox folder where the email is stored
$inbox          = Get-VEXFolder -Mailbox $exmailbox -Name "Inbox"

#Search for the email (Subject)
$checkedmail    = Get-VEXItem -Folder $inbox -Query $Subject

#Restore the the most recent email with the search string
Export-VEXItem -Item $checkedmail -To $Scanpath | Out-Null

#Scan the .msg file
Write-Host "*** Searching for pattern $Pattern ***" -ForegroundColor White
$FullFileName = Get-ChildItem -Path $Scanpath -Filter *.msg | Where-Object {!$_.PSIsContainer} | Sort-Object {$_.LastWriteTime} -Descending | Select-Object -First 1
  ForEach ($File in $FullFileName)
        {
        $FilePath = $File.DirectoryName
        $FileName = $File.Name
        $entry = Select-String -Path $FilePath"\"$FileName -Pattern $Pattern 
        Write-Host "Checking email $File"
        Write-Host "The email contains the searched string " -NoNewline
        Write-Host $entry.count -ForegroundColor Yellow -NoNewline
        Write-Host " times"
        if ($entry.count -eq 0) { 
            $LastExitCode = 1}
        elseif ($entry.count -gt 0) { 
            $LastExitCode = 0}
        Write-Host ""
        Write-Host "Cleaning up..."
        Write-Host ""
        Remove-Item -Path $FilePath"\"$FileName
        }

#Stop Exchange Restore Session
Stop-VBOExchangeItemRestoreSession -Session $session

#Give back the exit code
EXIT $LastExitCode