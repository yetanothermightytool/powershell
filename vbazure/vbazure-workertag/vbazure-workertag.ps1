<#
.NAME
    Veeam Backup for Microsoft Azure - Modify/Set Worker tag
.SYNOPSIS
    Script to modify the Worker tag and query the tag informations 
.DESCRIPTION
    This script sets the Worker tag value which given as commandline parameter

    Example for setting the tag with the name "worker" and the value "bkp-department" 

     .\vbazure-workertag.ps1 -VBAzurehost <hostname> -Set -TagName worker -TagValue bkp-department

    Example for getting all tags

    .\vbazure-workertag.ps1 -VBAzurehost <hostname> -Get
        
    IMPORTANT: Tags are not applied to existing workers. They have to be removed in advance and the tags are applied during the next backup run. 
.NOTES  
    File Name  : vbazure-workertag.ps1  
    Author     : Stephan "Steve" Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell 
.VERSION
    1.0
#>

param(
    [Parameter(Mandatory = $true)]
    [String] $VBAzurehost,
    [Parameter(Mandatory = $false)]
    [Switch] $Get,
    [Switch] $Set,
    [String] $TagName,
    [String] $TagValue)
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
             }
        
        $body = @{
            "grant_type" = "Password"
            "Username" = $cred.UserName 
            "Password" = $cred.GetNetworkCredential().password
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

#Function for RestAPI PUT
function Put-VeeamRestAPI {
    [CmdletBinding()]
    param (
        [string] $AppUri,
        [string] $token,
        [string] $body
    )

    begin {
        $header = @{
            "accept" = "application/json"
            "Authorization" = "Bearer $Token"
        }
               
        $requestURI = $veeamAPI + $appUri
        $tokenRequest = Invoke-WebRequest -Uri $requestURI -Headers $header -Body $body -Method Put -ContentType "application/json"
        Write-Output $tokenRequest
    }
}
        
#Get VBAzure credentials - The ones you need to login to the Console
$veeamAPI = "https://$VBAzurehost"
$cred = Get-Credential -Message "Please enter your Veeam Backup for Azure credentials"

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

#Request Bearer Token
Write-Host "Get Bearer Token...."
Write-Host ""
$appURI             = "/api/oauth2/token"
$token              = Connect-VeeamRestAPI -AppUri $appURI -Cred $cred

if($Set){
#Create body - Please change the configuration parameters according to your environment
$body_json =  @”
   {
       "tags": [
       {
       "key": "$TagName",
       "value": "$TagValue",
       }
    ]
   }
”@

#Set Tag
Write-Host "Set Worker Tag"$Tag -ForegroundColor White
Write-Host ""
$appURI             = "/api/v3/configuration/workertags"
Put-VeeamRestAPI -AppUri $appURI -Token $token -body $body_json
        }

if($Get){
#Get Configured Tags - Currently all tags are returned - Investigating
Write-Host "Getting Tags...." -ForegroundColor White
Write-Host ""
$appURI             = "/api/v3/cloudInfrastructure/tags"
$vbazuretags        = Get-VeeamRestAPI -AppUri $appURI -Token $token
$vbazuretags.results
}
