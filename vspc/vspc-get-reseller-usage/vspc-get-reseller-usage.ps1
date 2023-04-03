<# 
.NAME
    Veeam Service Provider Console - Reseller Reporting Script
.DESCRIPTION
This script reports the used space and licenses for all managed companies within a reseller	
    File Name  : vspc-reseller-report.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : Veeam Service Provider Console v7 / Powershell
.EXAMPLES

	PS> .\vspc-reseller-report -ResellerName <Reseller Name> (-ExportCSV)

.VERSION
    0.2 (pre-release - Tuning the output together with partner)
#>
Param(
     [Parameter(Mandatory=$true)]
     [String]$ResellerName,
     [Parameter(Mandatory=$false)]
     [Switch]$exportCSV
 )
Clear-Host
# Variables
$preResult     = @()
$usageReport   = @()
$licenseReport = @()

# Function for getting the Bearer Token
function Connect-VeeamRestAPI {
    [CmdletBinding()]
    param (
        [string] $AppUri,
        [pscredential] $Cred
    )

    begin {
        $header = @{
            "Content-Type" = "application/x-www-form-urlencoded"
            "accept" = "application/json"
        }
        
        $body = @{
            "grant_type"    = "password"
            "username"      = $cred.UserName 
            "password"      = $cred.GetNetworkCredential().password
            "refresh_token" = " "
            "rememberMe"    = " "
        }

        $requestURI = $veeamAPI + $appUri

        $tokenRequest = Invoke-RestMethod -Uri $requestURI -Headers $header -Body $body -Method Post 
        Write-Output $tokenRequest.access_token
    }
    
}

# Function GET RestAPI data
function Get-VeeamRestAPI {
    [CmdletBinding()]
    param (
        [string] $AppUri,
        [string] $Token
    )

    begin {
        $header = @{
            "accept" = "application/json"
            "Authorization" = "Bearer $Token"
        }
        $requestURI = $veeamAPI + $AppUri
        $results = Invoke-RestMethod -Method GET -Uri $requestUri -Headers $header
        Write-Output $results
    }
}

# Get credentials - The ones you need to login to the VSPC Server
####CHANGES HERE####
$veeamAPI = "https://win-vbr-01:1280/"

$cred = Get-Credential -UserName Administrator -Message "Please enter your VSPC credentials"
####CHANGES HERE####


# Ignore any self-signed certificate
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# Start the script
Write-Host "*******************************************************" -ForegroundColor Cyan
Write-Host "     VSPC Usage Report for Reseller $ResellerName"
Write-Host "*******************************************************" -ForegroundColor Cyan

# Request Bearer Token
Write-Progress "Get Bearer Token..." -PercentComplete 25
$appURI                 = "/api/v3/token"
$token                  = Connect-VeeamRestAPI -AppUri $appURI -Cred $cred

# Get all sites
Write-Progress "Get Sites..." -PercentComplete 50
$appURI                 = "/api/v3/infrastructure/sites"
$sites                  = Get-VeeamRestAPI -AppUri $appURI -Token $token
$siteUid                = $sites.data.siteUid

# Get all resellers
Write-Progress "Get Configured Resellers..." -PercentComplete 75
$appURI                 = "/api/v3/organizations/resellers"
$resellers              = Get-VeeamRestAPI -AppUri $appURI -Token $token

foreach ($resellerDetail in $resellers.data) {
      
    $preResult         += New-Object psobject -Property @{
    ResellerName        = $resellerDetail.name
    ResellerStatus      = $resellerDetail.status
    ResellerUID         = $resellerDetail.instanceUid
      }   
    }

# Extract the Reseller UID from result
$resellerInfo           = $preResult | Where-Object {$_.ResellerName -eq $ResellerName}
$resellerUID            = $resellerInfo.ResellerUID


# Get Reseller Total Storage Quota
Write-Progress "Generate Output..." -PercentComplete 80
$appURI                 = "/api/v3/organizations/resellers/$resellerUID /sites/$siteUid/backupResources"
$totalConfiguredQuota   = Get-VeeamRestAPI -AppUri $appURI -Token $token
$totalconfiguredQuotaGB = ($totalConfiguredQuota.data.storageQuota /1GB)

Write-Host "Storage Report" -ForegroundColor White
Write-Host "--------------" -ForegroundColor White
Write-Host "Total allocated Storage Quota (GB): "$totalconfiguredQuotaGB

# Get total usage of all companies managed by reseller
$appURI                 = "/api/v3/organizations/resellers/$resellerUID/sites/$siteUid/backupResources/usage"
$resellerUsageRAW       = Get-VeeamRestAPI -AppUri $appURI -Token $token

# Generate storage report
foreach ($resellerUsageDetail in $resellerUsageRAW.data) {
          
    $cfgStorageQuotaGB  = ($resellerUsageDetail.storageQuota /1GB)          #Configured Quotas over all configured companies
    $usedStorageQuotaGB = ($resellerUsageDetail.usedStorageQuota /1GB)      #Amount of space consumed by all companies of a reseller
    $archTierUsageGB    = ($resellerUsageDetail.archiveTierUsage /1GB)
    $capTierUsageGB     = ($resellerUsageDetail.capacityTierUsage /1GB)
    $perfTierUsageGB    = ($resellerUsageDetail.perfomanceTierUsage /1GB)

    $usageReport       += New-Object psobject -Property @{
    storageQuota        = $cfgStorageQuotaGB
    usedStorageQuota    = "{0:N2}" -f $usedStorageQuotaGB
    archiveTierUsage    = "{0:N2}" -f$archTierUsageGB
    capacityTierUsage   = "{0:N2}" -f$capTierUsageGB
    perfomanceTierUsage = "{0:N2}" -f$perfTierUsageGB
    serverBackups       = $resellerUsageDetail.serverBackups
    workstationBackups  = $resellerUsageDetail.workstationBackups 
    vmBackups           = $resellerUsageDetail.vmBackups
           }   
    }

$usageReport | Format-Table -AutoSize -Wrap -Property @{Name='Used Storage (GB)';Expression={$_.usedStorageQuota};align='right'},
                                                      @{Name='Configured Storage Quota (GB)';Expression={$_.storageQuota}},
                                                     #@{Name='Performance Tier Usage';Expression={$_.perfomanceTierUsage};align='right'},
                                                     #@{Name='Capacity Tier Usage';Expression={$_.capacityTierUsage};align='right'},
                                                     #@{Name='Archive Tier Usage';Expression={$_.archiveTierUsage};align='right'},
                                                      @{Name='Server Backups';Expression={$_.serverBackups}},
                                                      @{Name='Workstation Backups';Expression={$_.workstationBackups}},
                                                      @{Name='VM Backups';Expression={$_.vmBackups}}


# Get license usage
Write-Progress "Get Lincese Usage..." -PercentComplete 85
$appURI                 = "/api/v3/licensing/usage/organizations"
$siteLicenses           = Get-VeeamRestAPI -AppUri $appURI -Token $token

$licenseData            = $siteLicenses.data | Where-Object {$_.providerUid -eq $resellerUID}


# Generate license report
Write-Progress "Finalize Report..." -PercentComplete 100
foreach($licenseDetails in $licenseData){


$licenseReport.rentalUnits | Foreach-Object { $totalRentalUnits += $_ }

     $licenseReport       += New-Object psobject -Property @{
     description           = $licenseDetails.servers.workloads.description
     unitType              = $licenseDetails.servers.workloads.unitType
     rentalUnits           = $licenseDetails.servers.workloads.rentalUnits | Foreach-Object { $_ } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
     rentalCount           = $licenseDetails.servers.workloads.rentalCount | Foreach-Object { $_ } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
     }
}
Write-Host "License Report" -ForegroundColor White
Write-Host "--------------" -ForegroundColor White
$licenseReport | Format-Table -AutoSize -Wrap -Property @{Name='License Description';Expression={$_.description}},
                                                        @{Name='Unit Type';Expression={$_.unitType}},
                                                        @{Name='Rental Units';Expression={$_.rentalUnits}},
                                                        @{Name='Rental Count';Expression={$_.rentalCount};align='right'}

if ($exportCSV){
# Export usage  and license report into a CSV file
$usageReport   | Export-Csv -path D:\scripts\$ResellerName-Usage-Export-$((Get-Date).ToString('dd-MM-yyyy')).csv -NoTypeInformation
$licenseReport | Export-Csv -path D:\scripts\$ResellerName-License-Export-$((Get-Date).ToString('dd-MM-yyyy')).csv -NoTypeInformation
}                                               
