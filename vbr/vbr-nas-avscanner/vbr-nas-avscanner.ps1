<# 
.NAME
    NAS Share Scanner
.DESCRIPTION
    This script launches a Instant File Share Recovery for a specified file share backup job and runs a MS Defender malware scan.
    Any program can be used to scan the presented share.
	
    More details on Github - https://github.com/yetanothermightytool/powershell/blob/master/vbr/vbr-nas-avscanner/README.md
    
.NOTES  
    File Name  : vbr-nas-avscanner.ps1  
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell 
.VERSION
    1.1
#>
param(
    [Parameter(mandatory=$true)]
    [String] $JobName)

# Connect to the VBR Server
Connect-VBRServer -Server localhost

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
        @{ Expression={ $_.NASServerName };Label="Share Name";Width=50;Align="left" }, `
        @{ Expression={ $_.CreationTime };Label="Creation Time";Width=25;Align="left" }`
          }
    end {
 
        Write-Host
        Write-Host "The following restore points were found...(newest first)"
        Write-Host
        return $Output | Format-Table $RestoreTable
    }
}
# end function

#Let's go
Clear-Host

# Get NAS Backup Job informations
$nasbackup         = Get-VBRNASBackup -Name $Jobname

# Get the latest restore point
$restorepoint      = Get-VBRNASBackupRestorePoint -NASBackup $nasbackup | Sort-Object -Property CreationTime 

# If no restore points have been found
if ($restorepoint.Count -eq 0) {
	Write-Host 'Unable to locate any restore points for backup job' $JobName -ForegroundColor White
	Exit
} else {
# Present the result using the function rpLister
   rpLister $restorepoint
}
do { [int]$restorePointID = Read-Host "Please select restore point (Id)" } until (($restorePointID -lt $restorepoint.Count) -and ($restorePointID -ge 0))

# Get the selected restore point
$selectedRp        = $restorepoint | Select-Object -Index $restorePointID

# Set the permissions - Permissions can be adjusted
$permissions       = New-VBRNASPermissionSet -RestorePoint $restorepoint -Owner "Administrator" -AllowSelected -PermissionScope ("Administrator")

# Start the Instant NAS Recovery session - Reason can be changed
$restoresession    = Start-VBRNASInstantRecovery -RestorePoint $selectedRp -Permissions $permissions -Reason "Security Scan"

#Scan the Share using whatever you want - Sharepath is in variable $restoresession.SharePath
#Example with Microsoft Defender
$defenderFolder    = (Get-ChildItem "C:\ProgramData\Microsoft\Windows Defender\Platform\" | Sort-Object -Descending | Select-Object -First 1).fullname
$defender          = "$defenderFolder\MpCmdRun.exe"
$output            = & $defender -scan -scantype 3 -file $restoresession.SharePath
$output | ForEach-Object {Write-Verbose $_}
$output

#Stop Instant Recovery Session
Stop-VBRNASInstantRecovery -InstantRecovery $restoresession -Force

# Disconnect VBR Server
Disconnect-VBRServer
