<# 
.NAME
    Veeam Backup for Microsoft 365 Exchange Online Mailbox ResTORer
.DESCRIPTION
    A Powershell script to recover certain mailboxes from the last VB365 Exchange Online Restore point to a local Exchange server.
    The mailboxes to be restored must be provided in a CSV file.
.NOTES  
    File Name  : vb365-exo-resTORer.ps1
    Author     : Stephan "Steve" Herzig, Veeam Software (stephan.herzig@veeam.com)
    Requires   : PowerShell, VB365 Exchange Online Backup, Configured Azure application in the target tenant, CSV file
.VERSION
    1.0
#>
param(
        [Parameter(Mandatory = $true)]
        [String] $SrcVB365Org,
        [String] $DstAppId,
        [String] $DstAppCertFile,
        [String] $RestoreList
       )
Clear-Host

# Prepare the environment
$vb365org       = Get-VBOOrganization -Name $SrcVB365Org
$csv            = Import-Csv $RestoreList -Delimiter ","
$creds          = Get-Credential -Message "Please enter your Exchange Admin (Local Server Credentials)" 
$exchangeCAS    = Read-Host -Prompt "Enter Local Exchange Server name" #ExchangeCAS.Domain.local
#$securePwd     = Read-Host -Prompt "Enter Certificate Password" -AsSecureString

# Start Exchange Restore Session using the latest backup state
Start-VBOExchangeItemRestoreSession -Organization $vb365org -LatestState | Out-Null

# Connect to the restore session
$session        = Get-VBOExchangeItemRestoreSession
$counter        = $session.count-1 
$database       = Get-VEXDatabase -Session $session[$counter] 

# Now loop through the csv document
foreach ($entry in $csv) {

# Get the Mailbox
$exmailbox     = Get-VEXMailbox -Database $database -Name $entry.SourceMbx

# resTORer
#$resTORer      = Restore-VEXItem -Mailbox $exmailbox -ApplicationId $DstAppId -ApplicationCertificatePath $DstAppCertFile -ApplicationCertificatePassword $securePwd -OrganizationName $entry.DestOrg -Region Worldwide -TargetMailbox $entry.DestMbxName -RestoreDeletedItem
$resTORer       = Restore-VEXItem -Mailbox $exmailbox -Server $exchangeCAS -Credential $creds -TargetMailbox $entry.DestMbxName -RestoreDeletedItem 
$processedMbx   = $processedMbx+1
$createdCount   = $createdCount+$resTORer.CreatedCount
$skippedCount   = $skippedCount+$resTORer.SkippedCount
$failedCount    = $failedCount+$resTORer.FailedCount
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
