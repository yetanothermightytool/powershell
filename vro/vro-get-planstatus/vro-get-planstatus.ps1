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

if ($PSVersionTable.PSVersion.Major -lt 6) {
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) { return true; }
}
"@
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $skipCert = @{}
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
    $response = Invoke-RestMethod -Uri ($vroAPI + $AppUri) -Headers $header -Body $body -Method Post @skipCert
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
    $results = Invoke-RestMethod -Method GET -Uri ($vroAPI + $AppUri) -Headers $header @skipCert
    Write-Output $results
}

function Format-Date {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "-" }
    try   { [DateTime]::Parse($Value).ToString("dd-MM-yyyy HH:mm:ss") }
    catch { $Value }
}

$vroAPI = "https://yourip:9898"
$cred   = Get-Credential -UserName youruser@yourdomain.tld -Message "Please enter your VRO credentials"

Write-Host "Get Bearer Token...."
Write-Host ""
$token = Connect-VRORestAPI -AppUri "/token" -Cred $cred

Write-Host "Getting Orchestration Plan Information...." -ForegroundColor White
Write-Host ""
$vroPlanStats = Get-VRORestAPI -AppUri "/api/v13/Plans" -Token $token

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
            <th>Name</th>
            <th>Plan Type</th>
            <th>State</th>
            <th>Plan Mode</th>
            <th>Verification State</th>
            <th>Current Test Result</th>
            <th>Current Check Result</th>
            <th>Next Test Schedule</th>
            <th>Result Details</th>
        </tr>
        $($vroPlanStats.data | ForEach-Object {
            $name                 = $_.name
            $planType             = $_.planType
            $state                = $_.stateName
            $planMode             = $_.planMode
            $verificationState    = $_.planVerificationState
            $currentTestResult    = $_.currentTestResult
            $currentCheckResult   = $_.currentCheckResult
            $nextTestSchedule     = Format-Date $_.nearestTestScheduleTime
            $resultName           = $_.resultName

            "<tr>
                <td>$name</td>
                <td>$planType</td>
                <td>$state</td>
                <td>$planMode</td>
                <td>$verificationState</td>
                <td>$currentTestResult</td>
                <td>$currentCheckResult</td>
                <td>$nextTestSchedule</td>
                <td>$resultName</td>
            </tr>"
        })
    </table>
</body>
</html>
"@

$htmlTemplate | Out-File -FilePath $ReportFilePath -Encoding UTF8
Write-Host "Report saved: $ReportFilePath" -ForegroundColor Green
