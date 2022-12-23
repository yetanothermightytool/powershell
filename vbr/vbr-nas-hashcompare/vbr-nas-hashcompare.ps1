<# 
.NAME
    NAS Share Hash Value Comparer
.DESCRIPTION
    This script starts an instant file share recovery for a given file share backup job and compares a given hash value (SHA-256) with a given file within the presented share.
	
    More details on Github - https://github.com/yetanothermightytool/powershell/vbr/vbr-nas-hashcompare/README.md
    
.NOTES  
    File Name  : vbr-nas-hashcompare.ps1  
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell 
.VERSION
    1.0
#>
param(
    [Parameter(mandatory=$true)]
    [String] $JobName,
    [String] $SourceHash,    
    [String] $FileToCompare) 

#Let's go
Clear-Host

#Get NAS Backup Job informations
$nasbackup         = Get-VBRNASBackup -Name $Jobname

#Get the latest restore point
$restorepoint      = Get-VBRNASBackupRestorePoint -NASBackup $nasbackup | Sort-Object -Property CreationTime | Select-Object -Last 1

#Set the permissions - Permissions can be adjusted
$permissions       = New-VBRNASPermissionSet -RestorePoint $restorepoint -Owner "Administrator" -AllowSelected -PermissionScope ("Administrator")

#Start the Instant NAS Recovery session - Reason can be changed
$restoresession    = Start-VBRNASInstantRecovery -RestorePoint $restorepoint -Permissions $permissions -Reason "Hash comparison"

#Comparing values
$fullPath          = $restoresession.SharePath+$FileToCompare
$hashBkp           = Get-FileHash $fullPath -Algorithm "SHA256"

If ($SourceHash -ne $hashBkp.Hash)
{
  Write-Host " Source File Hash: $SourceHash is not equal to stored file in the backup: $hashBkp - The files are NOT EQUAL."
}

#Stop Instant Recovery Session
Stop-VBRNASInstantRecovery -InstantRecovery $restoresession -Force
