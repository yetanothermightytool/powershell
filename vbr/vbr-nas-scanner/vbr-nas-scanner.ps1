<# 
.NAME
    NAS Share Scanner
.DESCRIPTION
    This script launches a Instant File Share Recovery for a given Backup Job and executes a MS Defender malware scan.
	Any program can be used to scan the presented share.
	
	More details on Github
    
.NOTES  
    File Name  : vbr-nas-scanner.ps1  
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell 
.VERSION
    1.0
#>
param(
    [Parameter(mandatory=$true)]
    [String] $JobName)

#Let's go
Clear-Host

#Get NAS Backup Job informations
$nasbackup         = Get-VBRNASBackup -Name $Jobname

#Get the latest restore point
$restorepoint      = Get-VBRNASBackupRestorePoint -NASBackup $nasbackup | Sort-Object -Property CreationTime | Select-Object -Last 1

#Set the permissions - Permissions can be adjusted
$permissions       = New-VBRNASPermissionSet -RestorePoint $restorepoint -Owner "Administrator" -AllowSelected -PermissionScope ("Administrator")

#Start the Instant NAS Recovery session - Reason can be changed
$restoresession    = Start-VBRNASInstantRecovery -RestorePoint $restorepoint -Permissions $permissions -Reason "Security Scan"

#Scan the Share using whatever you want - Sharepath is in variable $restoresession.SharePath
#Example with Microsoft Defender
$defenderFolder    = (Get-ChildItem "C:\ProgramData\Microsoft\Windows Defender\Platform\" | Sort-Object -Descending | Select-Object -First 1).fullname
$defender          = "$defenderFolder\MpCmdRun.exe"
$output            = & $defender -scan -scantype 3 -file $restoresession.SharePath

$output | ForEach-Object {Write-Verbose $_}

#Stop Instant Recovery Session
Stop-VBRNASInstantRecovery -InstantRecovery $restoresession -Force
