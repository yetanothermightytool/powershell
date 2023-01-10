<# 
.NAME
    Veeam Backup for Microsoft 365 Exchange Online Usage Report
.DESCRIPTION
    Powershell script that shows the total number of Exchange Online mailboxes, backed up mailboxes, the total mailbox size 
    in Microsoft 365 (incl. deleted items) and the stored backups on the Local or Object Storage Repository.
.NOTES  
    File Name  : vb365-exo-usage-report.ps1
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell, Exchange Onlin Powershell Module
.VERSION
    1.1
#>
param(
    [Parameter(mandatory=$true)]
    [String] $Organization,
    [String] $Reponame)
Clear-Host

# Set variables
$hash                       = @{}
$org                        = Get-VBOOrganization -Name $Organization 
$repo                       = Get-VBORepository -Name $Reponame

# Get Repository Usage
$repoUsage                  = Get-VBOUsageData -Organization $org -Repository $repo
$objRepoUsageMB             = [math]::Round($repoUsage.ObjectStorageUsedSpace/1MB)
$locRepoUsageMB             = [math]::Round($repoUsage.UsedSpace/1MB)


# Get number of protected mailboxes on repository
$protectedMbx               = Get-VBOEntityData -Repository $repo -Organization $org -Type Mailbox
$protectedMbxCount          = $protectedMbx.Count

# Now heading to MS365
# Credentials - Change $userName and password file location
$userName                   = "<your username here>"
$passwordText               = Get-Content <your path to the pwd file here - and yes, changes are coming soon>

# Convert to secure string
$securePwd                  = $passwordText | ConvertTo-SecureString

# Create credential object
$credObject                 = New-Object System.Management.Automation.PSCredential -ArgumentList $userName, $securePwd

# Check if ExchangeOnlineManagementModule is installed and Import-Module 
if ((Get-InstalledModule -Name "ExchangeOnlineManagement" -ErrorAction SilentlyContinue) -eq $null) {
    Install-Module -Name ExchangeOnlineManagement -RequiredVersion 3.0.0
}

Connect-ExchangeOnline -UserPrincipalName $userName -Credential $credObject -ShowBanner:$false

# Fetch all Mailboxes
$mailboxes                  = Get-EXOMailbox -Resultsize Unlimited
$mailboxCount               = $mailboxes.Count

# Check only Mailboxes having backup data
$protectedMbx = Get-VBOEntityData -Repository $repo -Type Mailbox

ForEach ($protMbx in $protectedMbx.Email) {

$actMbxSize                = ((get-exomailbox -UserPrincipalName $protMbx | get-exomailboxstatistics).TotalItemSize.Value.ToMB()| measure-object -sum).sum
$delMbxSize                = ((get-exomailbox -UserPrincipalName $protMbx | get-exomailboxstatistics).TotalDeletedItemSize.Value.ToMB()| measure-object -sum).sum
$totalMbxSize              += $actMbxSize + $delMbxSize
}

# Get sizes of all Mailboxes - Version 1.0
#$actMbxSize                = ((get-exomailbox -ResultSize Unlimited | get-exomailboxstatistics).TotalItemSize.Value.ToMB()| measure-object -sum).sum
#$delMbxSize                = ((get-exomailbox -ResultSize Unlimited | get-exomailboxstatistics).TotalDeletedItemSize.Value.ToMB()| measure-object -sum).sum
#$totalMbxSize              = $actMbxSize + $delMbxSize

# Calculate Data Reduction
if ($objRepoUsageMB -gt 0) {

$reduction                 = ($totalMbxSize - $objRepoUsageMB) / $totalMbxSize * 100
$dataReduction             = $reduction = [math]::Round($reduction)
}
else {
$reduction                 = ($totalMbxSize - $locRepoUsageMB) / $totalMbxSize * 100
$dataReduction             = $reduction = [math]::Round($reduction)
}

# Build and show output
$hash                      = @{"M365 Mailboxes"=$mailboxCount;"Backed up Mailboxes on Repo"=$protectedMbxCount; "MS365 Mailbox Size (MB)"=$totalMbxSize;"Stored on Local Repo (MB)"=$locRepoUsageMB ;"Stored on Object Repo (MB)"=$objRepoUsageMB;"Data Reduction in %"=$dataReduction};
$outtable                  = New-Object PSObject -Property $hash

$outtable |Format-Table -Wrap -AutoSize -Property @{Name='M365 Mailboxes';Expression={$_."M365 Mailboxes"};align='center'},
                                                  @{Name='Backed up Mailboxes on Repo';Expression={$_."Backed up Mailboxes on Repo"};align='center'},
                                                  @{Name='MS365 Mailbox Size (MB)';Expression={$_."MS365 Mailbox Size (MB)"};align='center'},
		                                  @{Name='Stored on Local Repo (MB)';Expression={$_."Stored on Local Repo (MB)"};align='center'},
		                                  @{Name='Stored on Object Repo (MB)';Expression={$_."Stored on Object Repo (MB)"};align='center'},
                                          @{Name='Data Reduction in %';Expression={$_."Data Reduction in %"};align='center'}



# Disconnect from Exchange Online
Disconnect-ExchangeOnline -Confirm:$false
