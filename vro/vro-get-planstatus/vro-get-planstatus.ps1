<# 
.NAME
    Veeam Recovery Orchestrator - Get Plan Status
.DESCRIPTION
    This PowerShell script retrieves data from the Veeam Recovery Orchestrator API and generates an HTML report.
.NOTES  
    File Name  : vro-get-planstatus.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Recovery Orchestrator v13
.VERSION
    1.1
#>
Param(
    [Parameter(Mandatory=$true)]
    $ReportFilePath
)
Clear-Host

# ── Certificate: PS 6+ uses -SkipCertificateCheck flag, PS 5.1 needs the type hack
if ($PSVersionTable.PSVersion.Major -lt 6) {
    add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) { return true; }
}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $skipCert = @{}          # empty — flag not supported in PS 5.1
} else {
    $skipCert = @{ SkipCertificateCheck = $true }
}

function Connect-VRORestAPI {
    [CmdletBinding()]
    param (
        [string]       $AppUri,
        [pscredential] $Cred
    )
    $header = @{
        "Content-Type" = "application/x-www-form-urlencoded"
        "accept"       = "application/json"
    }
    $body = @{
        "grant_type"    = "password"
        "username"      = $Cred.UserName
        "password"      = $Cred.GetNetworkCredential().password
        "refresh_token" = " "
    }
    $uri = $vroAPI + $AppUri
    $response = Invoke-RestMethod -Uri $uri -Headers $header -Body $body -Method Post @skipCert
    Write-Output $response.access_token
}

function Get-VRORestAPI {
    [CmdletBinding()]
    param (
        [string] $AppUri,
        [string] $Token
    )
    $header = @{
        "accept"        = "application/json"
        "Authorization" = "Bearer $Token"
    }
    $uri = $vroAPI + $AppUri
    $results = Invoke-RestMethod -Method GET -Uri $uri -Headers $header @skipCert
    Write-Output $results
}

# ── Helper: safe DateTime parse — returns "-" if null/empty/invalid
function Format-Date {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "-" }
    try   { [DateTime]::Parse($Value).ToString("dd-MM-yyyy HH:mm:ss") }
    catch { $Value }   # return raw string if parse fails
}

$vroAPI = "https://yourip:9898"
$cred   = Get-Credential -UserName youruser@yourdomain.tld -Message "Please enter your VRO credentials"

Write-Host "Get Bearer Token...."
$token = Connect-VRORestAPI -AppUri "/token" -Cred $cred

Write-Host "Getting Orchestration Plan Information...." -ForegroundColor White
$vroPlanStats = Get-VRORestAPI -AppUri "/api/v13/Plans" -Token $token   # ← v13

$counter = 0   # ← init before template

$htmlTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        table { border-collapse: collapse; }
        th, td { border: 1px solid black; padding: 8px; }
        tr:nth-child(odd)  { background-color: white; }
        tr:nth-child(even) { background-color: lightgray; }
    </style>
</head>
<body>
    <h1>Veeam Recovery Orchestrator - Orchestration Plan Status Overview</h1>
    <table>
        <tr>
            <th>Name</th><th>Plan Type</th><th>State</th>
            <th>Last Test Time</th><th>Last Test Result</th>
            <th>Last Check Time</th><th>Last Check Result</th>
        </tr>
        $($vroPlanStats.data | ForEach-Object {
            $name            = $_.name
            $planType        = $_.planType
            $state           = $_.state
            $lastTestTime    = Format-Date $_.lastTestTime
            $lastTestResult  = $_.lastTestResult
            $lastCheckTime   = Format-Date $_.lastCheckTime
            $lastCheckResult = $_.lastCheckResult

            "<tr>
                <td>$name</td><td>$planType</td><td>$state</td>
                <td>$lastTestTime</td><td>$lastTestResult</td>
                <td>$lastCheckTime</td><td>$lastCheckResult</td>
            </tr>"
        })
    </table>
</body>
</html>
"@

$htmlTemplate | Out-File -FilePath $ReportFilePath -Encoding UTF8
Write-Host "Report saved: $ReportFilePath" -ForegroundColor Green
