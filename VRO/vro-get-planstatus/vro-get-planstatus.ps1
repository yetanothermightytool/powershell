<# 
.NAME
    Veeam Recovery Orchestrator - Get Plan Status
.DESCRIPTION
    This PowerShell script retrieves data from the Veeam Recovery Orchestrator API and generates an HTML report.
.NOTES  
    File Name  : vro-get-planstatus.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Recovery Orchestrator v6
.VERSION
    1.0
#>
Param(
     [Parameter(Mandatory=$true)]
     $ReportFilePath
 )
Clear-Host
# Variables

# Function for getting the Bearer Token
function Connect-VRORestAPI {
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
            }

        $requestURI = $vroAPI + $appUri

        $tokenRequest = Invoke-RestMethod -Uri $requestURI -Headers $header -Body $body -Method Post 
        Write-Output $tokenRequest.access_token
    }
    
}

# Function GET RestAPI data
function Get-VRORestAPI {
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
        $requestURI = $vroAPI + $AppUri
        $results = Invoke-RestMethod -Method GET -Uri $requestUri -Headers $header
        Write-Output $results
    }
}

# Get credentials - The ones you need to login to the VRO
$vroAPI = "https://yourip:9898"
$cred = Get-Credential -UserName youruser@yourdomain.tld -Message "Please enter your VRO credentials"

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
Write-Host "Get Bearer Token...."
Write-Host ""
$appURI             = "/token"
$token              = Connect-VRORestAPI -AppUri $appURI -Cred $cred

# Get-Proxy ID
Write-Host "Getting Orchestration Plan Information...." -ForegroundColor White
Write-Host ""
$appURI             = "/api/v6/Plans"
$vroPlanStats       = Get-VRORestAPI -AppUri $appURI -Token $token

# Create an HTML template for the report
$htmlTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body {
            font-family: Arial, sans-serif;
        }
        table {
            border-collapse: collapse;
        }
        th, td {
            border: 1px solid black;
            padding: 8px;
        }
        tr:nth-child(odd) {
            background-color: white;
        }
        tr:nth-child(even) {
            background-color: lightgray;
        }
    </style>
</head>
<body>
    <h1>Veeam Recovery Orchestrator - Orchestration Plan Status Overview</h1>
    <table>
        <tr>
            <th>Name</th>
            <th>Plan Type</th>
            <th>State</th>
            <th>Last Test Time</th>
            <th>Last Test Result</th>
            <th>Last Check Time</th>
            <th>Last Check Result</th>
        </tr>
        $($vroPlanStats.data | ForEach-Object {
            $name = $_.name
            $planType = $_.planType
            $state = $_.state
            $lastTestTime = [DateTime]::Parse($_.lastTestTime).ToString("dd-MM-yyyy HH:mm:ss")
            $lastTestResult = $_.lastTestResult
            $lastCheckTime = [DateTime]::Parse($_.lastCheckTime).ToString("dd-MM-yyyy HH:mm:ss")
            $lastCheckResult = $_.lastCheckResult
            $rowColor = if ($counter % 2 -eq 0) { "white" } else { "lightgray" }
            $counter++

            "<tr style='background-color: $rowColor;'>
                <td>$name</td>
                <td>$planType</td>
                <td>$state</td>
                <td>$lastTestTime</td>
                <td>$lastTestResult</td>
                <td>$lastCheckTime</td>
                <td>$lastCheckResult</td>
            </tr>"
        })
    </table>
</body>
</html>
"@


# Save the HTML report to a file
$htmlTemplate | Out-File -FilePath $ReportFilePath -Encoding UTF8

Write-Host "HTML report generated successfully at $ReportFilePath" -ForegroundColor White
