param(
    [String] $VBAzurehost,
    [Parameter(Mandatory=$true)]
    [string]$Depth,
    [Parameter(Mandatory=$false)]
    [string]$Growth
    )
# Variables
$apiVersion = "v5"

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
             }
        
        $body = @{
            "grant_type" = "Password"
            "Username"   = $cred.UserName 
            "Password"   = $cred.GetNetworkCredential().password
        }

        $requestURI      = $veeamAPI + $appUri

        $tokenRequest    = Invoke-RestMethod -Uri $requestURI -Headers $header -Body $body -Method Post 
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
            "accept"        = "application/json"
            "Authorization" = "Bearer $Token"
        }
        $requestURI = $veeamAPI + $AppUri
        $results    = Invoke-RestMethod -Method GET -Uri $requestUri -Headers $header
        Write-Output $results
    }
}

# Get VBAzure credentials - The ones you need to login to the Console
Clear-Host
$veeamAPI = "https://$VBAzurehost"
$cred     = Get-Credential -Message "Please enter your Veeam Backup for Microsoft Azure credentials"

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
$appURI             = "/api/oauth2/token"
$token              = Connect-VeeamRestAPI -AppUri $appURI -Cred $cred

# Get protected virtual Machines
$appURI             = "/api/$apiVersion/protectedItem/virtualMachines"
$vms                = Get-VeeamRestAPI -AppUri $appURI -Token $token

# Get Job Session Ids
$appURI             = "/api/$apiVersion/jobSessions?Limit=$Depth&Types=PolicyBackup"
$jobSessions        = Get-VeeamRestAPI -AppUri $appURI -Token $token

# Build the result table
$result             = foreach ($jobSessionId in $jobSessions.results.id) {
    
    $appURI         = "/api/$apiVersion/jobSessions/$jobSessionId/protectedItems"
    $jobSessionInfo = Get-VeeamRestAPI -AppUri $appURI -Token $token

    foreach ($jobsessionInfoDetails in $jobSessionInfo.results) {
                     [PSCustomObject]@{
                     "Name"                   = $jobsessionInfoDetails.resource.name
                     "Start Time"             = $jobsessionInfoDetails.runs.startTime
                     "End Time"               = $jobsessionInfoDetails.runs.endTime
                     "Total Data (GB)"        = [math]::round(($jobsessionInfoDetails.runs.rates.totalDataBytes) / 1Gb, 2)
                     "Transferred Data (MB)"  = [math]::round(($jobsessionInfoDetails.runs.rates.transferredDataBytes) / 1Mb, 2)
        }
    }
}

Write-Host "Backup session information for the past $Depth backup jobs" -ForegroundColor White
$result | Format-Table

# Get Suspicious Growth (Number is percentage)
if ($Growth) {
    Write-Host "Checking backups..." -ForegroundColor White
    Write-Host ""

    $allVMData = @()

    foreach ($jobSessionId in $jobSessions.results.id) {
        $appURI         = "/api/$apiVersion/jobSessions/$jobSessionId/protectedItems"
        $jobSessionInfo = Get-VeeamRestAPI -AppUri $appURI -Token $token

        foreach ($jobsessionInfoDetails in $jobSessionInfo.results) {
            $VMData = [PSCustomObject]@{
                Name              = $jobsessionInfoDetails.resource.name
                TransferredData   = $jobsessionInfoDetails.runs.rates.transferredDataBytes / 1MB
                EndTime           = [datetime]$jobsessionInfoDetails.runs.endTime
                }
            $allVMData += $VMData
         }
    }

    $uniqueVMs = $allVMData | Group-Object Name | ForEach-Object {
        $_.Group | Sort-Object EndTime -Descending | Select-Object -First 1
    }

    foreach ($VMData in $uniqueVMs) {
        $average     = ($allVMData | Where-Object { $_.Name -eq $VMData.Name } | Measure-Object -Property TransferredData -Average).Average
        $growthCheck = [Math]::Round(($VMData.TransferredData / $average - 1) * 100, 2)

        if ($growthCheck -gt $Growth) {
            Write-Host "Suspicious growth detected in $($VMData.Name) backups! Growth: $($growthCheck)%." -ForegroundColor Yellow

        } elseif ($growthCheck -lt -$Growth) {
            Write-Host "Unexpected reduction detected in $($VMData.Name) backups! Reduction: $($growthCheck)%." -ForegroundColor Yellow

        } else {
            Write-Host "No unexpected growth or reduction detected in $($VMData.Name) backups." -ForegroundColor Cyan
        }
    }
}
