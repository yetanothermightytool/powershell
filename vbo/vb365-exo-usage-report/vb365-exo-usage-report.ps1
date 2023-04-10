<# 
.NAME
    Veeam Backup for Microsoft 365 Exchange Online Usage Report
.DESCRIPTION
    Powershell script that shows the total number of Exchange Online mailboxes, backed up mailboxes, the total mailbox size 
    in Microsoft 365 (incl. deleted items) and much more.
.NOTES  
    File Name  : vb365-exo-usage-report.ps1
    Author     : Stephan Herzig, Veeam Software (stephan.herzig@veeam.com)
    Requires   : PowerShell, Exchange Online Powershell Module, Application with appropriate rights
.VERSION
    1.2
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

# Application only login variables
$MSOrganization             = "<your org here>.onmicrosoft.com"
$applicationID              = "<your application ID here"
$certificateThumbPrint      = "<your certificate thumbprint here>"

# Check if ExchangeOnlineManagementModule is installed and Import-Module 
if ((Get-InstalledModule -Name "ExchangeOnlineManagement" -ErrorAction SilentlyContinue) -eq $null) {
    Install-Module -Name ExchangeOnlineManagement -RequiredVersion 3.0.0
}

# Connect to registered application
Connect-ExchangeOnline -CertificateThumbprint $certificateThumbPrint -AppId $applicationID -Organization $MSOrganization -ShowBanner:$false


# Get Repository Usage
$repoUsage                  = Get-VBOUsageData -Organization $org -Repository $repo
$objRepoUsageMB             = [math]::Round($repoUsage.ObjectStorageUsedSpace/1MB)
$locRepoUsageMB             = [math]::Round($repoUsage.UsedSpace/1MB)

# Get number of protected mailboxes on repository
$protectedMbx               = Get-VBOEntityData -Repository $repo -Organization $org -Type Mailbox | where-object {$_.displayname -notlike "*In-Place Archive*"}
$protectedMbxCount          = $protectedMbx.Count

# Fetch all Mailboxes
$mailboxes                  = Get-ExoRecipient -Resultsize Unlimited
$mailboxCount               = $mailboxes.Count

# Check only Mailboxes having backup data
$protectedMbx = Get-VBOEntityData -Organization $org -Repository $repo -Type Mailbox | Where-Object {$_.displayname -notlike "*In-Place Archive*"}

ForEach ($protMbx in $protectedMbx.Email) {

$actMbxSize                = ((Get-ExoRecipient -UserPrincipalName $protMbx | get-exomailboxstatistics).TotalItemSize.Value.ToMB()| measure-object -sum).sum
$delMbxSize                = ((Get-ExoRecipient -UserPrincipalName $protMbx | get-exomailboxstatistics).TotalDeletedItemSize.Value.ToMB()| measure-object -sum).sum
$totalMbxSize              += $actMbxSize + $delMbxSize
}

# Calculate Data Reduction and more
if ($objRepoUsageMB -gt 0) {

$reduction                 = ($totalMbxSize - $objRepoUsageMB) / $totalMbxSize * 100
$dataReduction             = $reduction = [math]::Round($reduction)
$calcAverage               = $objRepoUsageMB / $protectedMbxCount
$avgSizeMbx                = $calcAverage = [math]::Round($calcAverage)
}
else {
$reduction                 = ($totalMbxSize - $locRepoUsageMB) / $totalMbxSize * 100
$dataReduction             = $reduction = [math]::Round($reduction)
$calcAverage               = $locRepoUsageMB / $protectedMbxCount
$avgSizeMbx                = $calcAverage = [math]::Round($calcAverage)
}

# Build and show output
$hash                      = @{"M365 Mailboxes"=$mailboxCount;"Backed up Mailboxes on Repo"=$protectedMbxCount; "M365 Mailbox Size (MB)"=$totalMbxSize;"Stored on Local Repo (MB)"=$locRepoUsageMB ;"Stored on Object Repo (MB)"=$objRepoUsageMB;"Data Reduction in %"=$dataReduction;"Used Capacity per User (MB)"=$avgSizeMbx};
$outtable                  = New-Object PSObject -Property $hash

$outtable |Format-Table -Wrap -AutoSize -Property @{Name='M365 Mailboxes';Expression={$_."M365 Mailboxes"};align='center'},
                                                  @{Name='Backed up Mailboxes on Repo';Expression={$_."Backed up Mailboxes on Repo"};align='center'},
                                                  @{Name='M365 Mailbox Size (MB)';Expression={$_."M365 Mailbox Size (MB)"};align='center'},
		                                          @{Name='Stored on Local Repo (MB)';Expression={$_."Stored on Local Repo (MB)"};align='center'},
		                                          @{Name='Stored on Object Repo (MB)';Expression={$_."Stored on Object Repo (MB)"};align='center'},
                                                  @{Name='Data Reduction in %';Expression={$_."Data Reduction in %"};align='center'},
                                                  @{Name='Used Capacity per User (MB)';Expression={$_."Used Capacity per User (MB)"};align='center'}



# Disconnect from Exchange Online
Disconnect-ExchangeOnline -Confirm:$false
