<# 
.NAME
    Veeam Backup for Microsoft 365 Exchange Online Mailbox ResTORer
.DESCRIPTION
    A Powershell script to recover certain mailboxes from the last VB365 Exchange Online Restore point to another Microsoft organization or
    to a local Exchange server. The mailboxes to be restored must be provided in a CSV file and configured at the destination.
.NOTES  
    File Name  : vb365-exo-resTORer.ps1
    Author     : Stephan "Steve" Herzig, Veeam Software (stephan.herzig@veeam.com)
    Requires   : PowerShell, VB365 Exchange Online Backup, Configured Azure application in the target tenant or a local Exchange server, CSV file
.VERSION
    1.2
#>
param (
    [Parameter(Mandatory = $true)]
    [String] $SrcVB365Org,
    [Parameter(Mandatory = $true)]
    [String] $RestoreList,
    [Parameter(ParameterSetName='Local', Mandatory=$true)]
    [Switch]$RestoreLocal,
    [Parameter(ParameterSetName='Local', Mandatory=$true)]
    [String]$LocalExchangeSrv,
    [Parameter(ParameterSetName='M365', Mandatory=$true)]
    [Switch]$RestoreM365,
    [Parameter(ParameterSetName='M365', Mandatory=$true)]
    [String] $DstAppId,
    [Parameter(ParameterSetName='M365', Mandatory=$true)]
    [String] $DstAppCertFile
)
Clear-Host

# Prepare the environment
$vb365org       = Get-VBOOrganization -Name $SrcVB365Org
$csv            = Import-Csv $RestoreList -Delimiter ","

# Start Exchange Restore Session using the latest backup state
Start-VBOExchangeItemRestoreSession -Organization $vb365org -LatestState | Out-Null

# Connect to the restore session
$session        = Get-VBOExchangeItemRestoreSession
$counter        = $session.count-1 
$database       = Get-VEXDatabase -Session $session[$counter] 

# Restore to local Exchange Server
    if($RestoreLocal){
    $creds          = Get-Credential -Message "Please enter your Exchange Admin (Local Server) credentials)" 
    $exchangeCAS    = $LocalExchangeSrv
    
    # Now loop through the csv document
    foreach ($entry in $csv) {

    # Get the Mailbox
    $exmailbox     = Get-VEXMailbox -Database $database -Name $entry.SourceMbx

    # resTORer
    $resTORer       = Restore-VEXItem -Mailbox $exmailbox -Server $exchangeCAS -Credential $creds -TargetMailbox $entry.DestMbxName -RestoreDeletedItem 
    $processedMbx   = $processedMbx+1
    $createdCount   = $createdCount+$resTORer.CreatedCount
    $skippedCount   = $skippedCount+$resTORer.SkippedCount
    $failedCount    = $failedCount+$resTORer.FailedCount
    }

}

# Restore to M365 Organization
    if($RestoreM365){
    $securePwd     = Read-Host -Prompt "Enter Certificate Password" -AsSecureString

    # Now loop through the csv document
    foreach ($entry in $csv) {

    # Get the Mailbox
    $exmailbox     = Get-VEXMailbox -Database $database -Name $entry.SourceMbx

    # resTORer
    $resTORer       = Restore-VEXItem -Mailbox $exmailbox -ApplicationId $DstAppId -ApplicationCertificatePath $DstAppCertFile -ApplicationCertificatePassword $securePwd -OrganizationName $entry.DestOrg -Region Worldwide -TargetMailbox $entry.DestMbxName -RestoreDeletedItem
    $processedMbx   = $processedMbx+1
    $createdCount   = $createdCount+$resTORer.CreatedCount
    $skippedCount   = $skippedCount+$resTORer.SkippedCount
    $failedCount    = $failedCount+$resTORer.FailedCount
    }

}

# Build and show output
$hash           = @{"Processed Mailboxes"=$processedMbx;"Created Items"=$createdCount;"Skipped Items"=$skippedCount; "Failed Items"=$failedCount;}
$outtable       = New-Object PSObject -Property $hash
Write-Host "********************"
Write-Host "* ResTORation done *" 
Write-Host "********************"
$outtable |Format-Table -Wrap -AutoSize -Property @{Name='Processed Mailboxes';Expression={$_."Processed Mailboxes"};align='center'},
                                                  @{Name='Created Items';Expression={$_."Created Items"};align='center'},
                                                  @{Name='Skipped Items';Expression={$_."Skipped Items"};align='center'},
                                                  @{Name='Failed Items';Expression={$_."Failed Items"};align='center'}

#Stop Exchange Restore Session
Stop-VBOExchangeItemRestoreSession -Session $session[$counter]
