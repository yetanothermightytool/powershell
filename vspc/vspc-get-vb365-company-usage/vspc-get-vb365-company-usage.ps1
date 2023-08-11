Param(
     [Parameter(Mandatory=$true)]
     [String]$Company,
     [Parameter(Mandatory=$false)]
     [Switch]$exportCSV
 )
Clear-Host
# Variables
$apiVersion    = "/api/v3"
$preResult     = @()
$vb365report   = @()

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
$veeamAPI = "https://localhost:1280/"

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

# Request Bearer Token
Write-Progress "Get Bearer Token..." -PercentComplete 25
$appURI                 = "$apiVersion/token"
$token                  = Connect-VeeamRestAPI -AppUri $appURI -Cred $cred

# Get all Companies
Write-Progress "Get companies usage data..." -PercentComplete 50
$appURI                 = "$apiVersion/organizations/companies"
$companies              = Get-VeeamRestAPI -AppUri $appURI -Token $token

# Loop through each found company
foreach ($companiesDetail in $companies.data) {
      
    $preResult         += New-Object psobject -Property @{
    CompanyName         = $companiesDetail.name
    CompanyStatus       = $companiesDetail.status
    CompanyUID          = $companiesDetail.instanceUid
      }   
    }

# Extract the Compan UID from result
$companyInfo            = $preResult | Where-Object {$_.CompanyName -eq $Company}
$companyUID             = $companyInfo.CompanyUID

# Get company usage
Write-Progress "Generate Output..." -PercentComplete 95
$appURI                 = "$apiVersion/organizations/companies/$companyUID/usage"
$companyUsage           = Get-VeeamRestAPI -AppUri $appURI -Token $token
$companyUsageCounters   = $companyUsage.data.counters

# Specify the values
$specificTypes = @("ManagedUsers", "Vb365BackupSize","Vb365ProtectedGroups","Vb365ProtectedSites","Vb365ProtectedTeams","Vb365ProtectedUsers")

# Filter the usageCounter array based on specific types
$filteredUsage = $companyUsageCounters | Where-Object { $specificTypes -contains $_.type }

# Iterate through the filtered array and convert the "Vb365BackupSize" value to gigabytes
$filteredUsage | ForEach-Object {
    if ($_.type -eq "Vb365BackupSize") {
        $_.value = [math]::Round($_.value / 1GB, 2)  
    }
    $vb365report += $_  
}

# Print the table
$vb365report | Select-Object @{Name='Type'; Expression={$_.type}}, @{Name='Value'; Expression={$_.value}} | Format-Table -AutoSize

# Export usage  and license report into a CSV file
if ($exportCSV){
$vb365report   | Export-Csv -path D:\scripts\$Company-Usage-Export-$((Get-Date).ToString('dd-MM-yyyy')).csv -NoTypeInformation
}                                            
