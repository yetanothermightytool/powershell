Clear-Host
# Variables
$finalResult   = @()

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
            "grant_type" = "password"
            "username" = $cred.UserName 
            "password" = $cred.GetNetworkCredential().password
            "refresh_token" = " "
            "rememberMe" = " "
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

# Get credentials - The ones you need to login to the VONE
$veeamAPI = "https://localhost:1239"
$cred     = Get-Credential -Message "Please enter your VONE credentials"

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
Write-Host "*                    VONE Alerts                      *"
Write-Host "**************************************************v1.0*" -ForegroundColor Cyan

# Request Bearer Token
Write-Host "Get Bearer Token...."
Write-Host ""
$appURI             = "/api/token"
$token              = Connect-VeeamRestAPI -AppUri $appURI -Cred $cred

# Get-Proxy ID
Write-Host "Getting Alerts...." -ForegroundColor White
Write-Host ""
$appURI             = "/api/v2.1/alarms/triggeredAlarms"
$vonesalert           = Get-VeeamRestAPI -AppUri $appURI -Token $token
# $test = $vonesalert |  Where-Object {$_.items.status -eq "Error"}
For ($i = 0; $i -le $vonesalert.items.count; $i++) {
    foreach ($alerts in $vonesalert) {
      
    $finalResult       += New-Object psobject -Property @{
    AlertName          = $alerts.items.name[$i]
    AlertStatus        = $alerts.items.status[$i]
    AlertDesc          = $alerts.items.description[$i]
       }   
    }
}
$finalResult | Format-Table -Wrap -AutoSize -Property @{Name='Job Name';Expression={$_.AlertName}},
                                                      @{Name='Job Type';Expression={$_.AlertStatus};align='center'},
                                                      @{Name='Description';Expression={$_.AlertDesc}}
