<#
.NAME
    Veeam Backup for Microsoft 365 - MS Teams Adder
.SYNOPSIS
    Script to add MS Teams sites to an existing Backup Job
.DESCRIPTION
  This script adds teams sites to an existing backup job. 
	The parameter -Filter defines the name or a part of the team name that will be added
	More information can be found in the readme file on github
	https://github.com/yetanothermightytool/powershell/tree/master/vbo/vbo-teams-adder#readme
.NOTES  
    File Name  : vbo-teams-adder.ps1  
    Author     : Stephan "Steve" Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell 
.VERSION
    1.0
#>
param(
    [Parameter(Mandatory = $true)]
    [String] $Filter,
    [String] $Backupjob)
Clear-Host

#Setting variables
# $organizationname = "<tenant>" 
$org = Get-VBOOrganization #-Name $organizationname
$job = Get-VBOJob -Name $Backupjob

# Credentials
$userName = "<username>"
$passwordText = Get-Content <path to secure.txt file>

# Convert to secure string
$securePwd = $passwordText | ConvertTo-SecureString

# Create credential object
$credObject = New-Object System.Management.Automation.PSCredential -ArgumentList $userName, $securePwd

# Check if necessary modules are present - Install if needed 
if ((Get-InstalledModule -Name "MicrosoftTeams" -ErrorAction SilentlyContinue) -eq $null) {
    Install-Module MicrosoftTeams
}
if ((Get-InstalledModule -Name "ExchangeOnlineManagement" -ErrorAction SilentlyContinue) -eq $null) {
    Install-Module ExchangeOnlineManagement
}
#Connect to M365
Connect-MicrosoftTeams -Credential $credObject 
Connect-ExchangeOnline -UserPrincipalName $userName -Credential $credObject -ShowBanner:$false

#Get the Teams
$Teams = (Get-Team |Select GroupId, DisplayName)

ForEach ($T in $Teams) {
  $TeamId = (Get-UnifiedGroup -ResultSize unlimited -Identity $T.GroupId | Select -ExpandProperty ExternalDirectoryObjectId)
        $Team = Get-VBOOrganizationTeam -Organization $org -id $TeamId
         $FilteredTeam = $Team.DisplayName -match "$Filter"
            if ($FilteredTeam) {
            $inclTeam = New-VBOBackupItem -Team $Team
            Add-VBOBackupItem -Job $Job -BackupItem $inclTeam
            Write-Host "Adding Team $inclTeam"
    }
}

#Disconnect from M365
Disconnect-MicrosoftTeams -Confirm:$false -InformationAction Ignore -ErrorAction SilentlyContinue 
Disconnect-ExchangeOnline -Confirm:$false -InformationAction Ignore -ErrorAction SilentlyContinue
