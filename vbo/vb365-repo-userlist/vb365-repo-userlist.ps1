<# 
.NAME
    Veeam Backup for Microsoft 365 User List for Repository
.SYNOPSIS
    Script to get a list of user data stored in the given repository
.DESCRIPTION
    You can get a list of users whose data is stored in the given backup repository
    More details on on github 
.NOTES  
    File Name  : vbo-repo-userlist.ps1  
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell 
.VERSION
    1.1
#>
param(
    [Parameter(mandatory=$true)]
    [String] $RepoName
    )
Clear-Host
#Function for getting the Bearer Token
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

#Function GET RestAPI data
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

#Get VBO365 credentials - The ones you need to login to the VBO365 Management Console
$veeamAPI = "https://localhost:4443"
$cred = Get-Credential -Message "Please enter your VBO365 credentials"

#Ignore any self-signed certificate
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

#Start the script
Write-Host "*******************************************************" -ForegroundColor Cyan
Write-Host "*            VB365 Repository Statistics              *"
Write-Host "**************************************************v1.0*" -ForegroundColor Cyan

#Request Bearer Token
Write-Host "Get Bearer Token...."
Write-Host ""
$appURI             = "/v7/token"
$token              = Connect-VeeamRestAPI -AppUri $appURI -Cred $cred

#Get Proxy ID
Write-Host "Getting proxy server id...." -ForegroundColor White
Write-Host ""
$appURI             = "/v7/Proxies/"
$vboproxyid         = Get-VeeamRestAPI -AppUri $appURI -Token $token
$vboproxyserverid   = $vboproxyid.id     | Select-Object -Last 1 

#Get Repository
$appURI             = "/v7/BackupRepositories?proxyId=$vboproxyserverid&longTerm=false"
$vborepo            = Get-VeeamRestAPI -AppUri $appURI -Token $token
$vboreponame        = $vborepo | Where-Object {$_.name -eq "$RepoName"}
$vboreponameid      = $vboreponame.id

#Get Statistics
Write-Host "Getting Statistics..."
Write-Host ""       
Write-Host "*******************************************************" -ForegroundColor Cyan
$appURI             = "/v7/BackupRepositories/$vboreponameid/UserData"
$vborepostats       = Get-VeeamRestAPI -AppUri $appURI -Token $token
# ...

$vborepostatsresult = $vborepostats.results
Write-Host "Print table..." -ForegroundColor White
$statsTable           = @()
$exchangeCount        = 0
$exchangeArchiveCount = 0
$oneDriveCount        = 0
$sharepointCount      = 0

foreach ($r in $vborepostatsresult) {
    $exchange = if ($r.isMailboxBackedUp) {
        $exchangeCount++
        "Yes"
    } else {
        "No"
    }

    $exchangeArchive = if ($r.isArchiveBackedUp) {
        $exchangeArchiveCount++
        "Yes"
    } else {
        "No"
    }

    $oneDrive = if ($r.isOneDriveBackedUp) {
        $oneDriveCount++
        "Yes"
    } else {
        "No"
    }

    $sharepoint = if ($r.isPersonalSiteBackedUp) {
        $sharepointCount++
        "Yes"
    } else {
        "No"
    }

    $rowData = [PSCustomObject]@{
        'Username'             = $r.displayName
        'Exchange'             = $exchange
        'Exchange Archive'     = $exchangeArchive
        'OneDrive'             = $oneDrive
        'Sharepoint Personal'  = $sharepoint
    }
    $statsTable += $rowData
}

$separatorLine = [PSCustomObject]@{
    'Username'             = "---------"
    'Exchange'             = "---------"
    'Exchange Archive'     = "---------"
    'OneDrive'             = "---------"
    'Sharepoint Personal'  = "---------"
}

$totalsRow = [PSCustomObject]@{
    'Username'             = "Total"
    'Exchange'             = $exchangeCount
    'Exchange Archive'     = $exchangeArchiveCount
    'OneDrive'             = $oneDriveCount
    'Sharepoint Personal'  = $sharepointCount
}

$statsTable += $separatorLine
$statsTable += $totalsRow

Write-Host ""
$statsTable | Format-Table -AutoSize