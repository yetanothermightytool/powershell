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
    param ([string]$AppUri, [pscredential]$Cred)
    $header = @{ "Content-Type" = "application/x-www-form-urlencoded"; "accept" = "application/json" }
    $body   = @{ "grant_type" = "password"; "username" = $Cred.UserName; "password" = $Cred.GetNetworkCredential().password; "refresh_token" = " " }
    $response = Invoke-RestMethod -Uri ($vroAPI + $AppUri) -Headers $header -Body $body -Method Post @skipCert
    Write-Output $response.access_token
}

function Get-VRORestAPI {
    [CmdletBinding()]
    param ([string]$AppUri, [string]$Token)
    $header = @{ "accept" = "application/json"; "Authorization" = "Bearer $Token" }
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

Write-Host "Get Bearer Token...." -ForegroundColor White
$token = Connect-VRORestAPI -AppUri "/token" -Cred $cred

Write-Host "Getting Plans..." -ForegroundColor White
$vroPlanStats = Get-VRORestAPI -AppUri "/api/v7.21/Plans" -Token $token

# Build detail HTML for enabled plans
$planDetailsHtml = ""

foreach ($plan in $vroPlanStats.data) {
    if ($plan.planMode -ne "Enabled") { continue }

    Write-Host "  Fetching details for plan: $($plan.name)" -ForegroundColor Cyan
    $planId = $plan.id
    $groups = Get-VRORestAPI -AppUri "/api/v7.21/Plans/$planId/Groups" -Token $token

    $groupsHtml = ""
    foreach ($group in ($groups.data | Sort-Object order)) {
        $groupId = $group.id
        $vms     = Get-VRORestAPI -AppUri "/api/v7.21/Plans/$planId/Groups/$groupId/VMs" -Token $token

        $vmsHtml = ""
        foreach ($vm in ($vms.data | Sort-Object number)) {
            $vmId  = $vm.id
            $steps = Get-VRORestAPI -AppUri "/api/v7.21/Plans/$planId/VMs/$vmId/Steps" -Token $token

            $stepsRows = ""
            foreach ($step in ($steps.data | Sort-Object order)) {
                $reqMark   = if ($step.requiredForSuccess) { "&#10004;" } else { "" }
                $stepsRows += "<tr><td>$($step.order)</td><td>$($step.name)</td><td>$($step.type)</td><td>$($step.state)</td><td style='text-align:center'>$reqMark</td><td>$($step.description)</td></tr>"
            }

            $critMark = if ($vm.isCritical) { " &#9888; <em>Critical</em>" } else { "" }
            $vmsHtml += @"
            <details>
                <summary><strong>VM $($vm.number): $($vm.name)</strong>$critMark</summary>
                <table style='margin:8px 0 8px 20px; width:95%'>
                    <tr><th>#</th><th>Step Name</th><th>Type</th><th>State</th><th>Required</th><th>Description</th></tr>
                    $stepsRows
                </table>
            </details>
"@
        }

        $parallelTag = if ($group.isParallel) { " [Parallel]" } else { "" }
        $groupsHtml += @"
        <details style='margin-left:16px'>
            <summary>Group $($group.order): $($group.name)$parallelTag ($($group.type))</summary>
            <div style='margin-left:16px'>$vmsHtml</div>
        </details>
"@
    }

    $planDetailsHtml += @"
    <div id="plan-$planId" style='margin-top:24px; border:1px solid #aaa; padding:12px; border-radius:4px'>
        <h2>$($plan.name) <span style='font-size:0.8em; color:#555'>[$($plan.planType)]</span></h2>
        <p>State: <strong>$($plan.stateName)</strong> | Verification: <strong>$($plan.planVerificationState)</strong> | Result: $($plan.resultName)</p>
        $groupsHtml
        <p><a href='#top'>&#8593; Back to overview</a></p>
    </div>
"@
}

# Build overview table rows
$overviewRows = $vroPlanStats.data | ForEach-Object {
    $linkOpen  = if ($_.planMode -eq "Enabled") { "<a href='#plan-$($_.id)'>" } else { "" }
    $linkClose = if ($_.planMode -eq "Enabled") { "</a>" } else { "" }
    "<tr>
        <td>$linkOpen$($_.name)$linkClose</td>
        <td>$($_.planType)</td>
        <td>$($_.stateName)</td>
        <td>$($_.planMode)</td>
        <td>$($_.planVerificationState)</td>
        <td>$($_.currentTestResult)</td>
        <td>$($_.currentCheckResult)</td>
        <td>$($_.resultName)</td>
    </tr>"
}

$htmlTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <style>
        body { font-family: Arial, sans-serif; margin: 24px; }
        h1   { color: #1a1a1a; }
        h2   { color: #333; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }
        th { background-color: #4a4a4a; color: white; }
        tr:nth-child(odd)  { background-color: #ffffff; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        details > summary { cursor: pointer; padding: 6px; background: #e8e8e8; border-radius: 3px; margin: 4px 0; }
        details > summary:hover { background: #d0d0d0; }
        a { color: #0066cc; }
    </style>
</head>
<body id='top'>
    <h1>Veeam Recovery Orchestrator - Plan Status Overview</h1>

    <table>
        <tr>
            <th>Name</th>
            <th>Plan Type</th>
            <th>State</th>
            <th>Mode</th>
            <th>Verification State</th>
            <th>Current Test Result</th>
            <th>Current Check Result</th>
            <th>Result Details</th>
        </tr>
        $($overviewRows -join "`n")
    </table>

    <h1 style='margin-top:40px'>Plan Details (Enabled Plans)</h1>
    $planDetailsHtml

</body>
</html>
"@

$htmlTemplate | Out-File -FilePath $ReportFilePath -Encoding UTF8
Write-Host "Report saved: $ReportFilePath" -ForegroundColor Green
