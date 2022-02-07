<#
.NAME
    Veeam Backup for Microsoft Office 365 - Audit Item Configurator
.SYNOPSIS
    Script to configure the audited items (user) and set the audit notification settings
.DESCRIPTION
    This script configures the user to be audited.
    More information about this feature on https://helpcenter.veeam.com/docs/vbo365/rest/audititems.html
    
    The user to audited has to be passed as parameter (M365 username)

    Switch '-SetAuditNotification' will configure the audit notification settings.   
	
.NOTES  
    File Name  : vbo-auditcfg.ps1  
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell 
.VERSION
    1.0
#>
param(
    [Parameter(Mandatory = $true)]
    [String] $Username,
    [Parameter(Mandatory = $false)]
    [Switch] $SetAuditNotification)

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

#Function for creating the Audit Items (POST)
function Post-VeeamRestAPI-Audit {
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
        $tokenRequest = Invoke-RestMethod -Uri $requestURI -Headers $header -Body $body -Method Post -ContentType "application/json"
        Write-Output $tokenRequest
    }
}

#Function for editing the Audit Notification Settings (PUT)
function Put-VeeamRestAPI-Audit {
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
        
#Get VBO365 credentials - The ones you need to login to the VBO365 Management Console
$veeamAPI = "https://localhost:4443"
$cred = Get-Credential -Message "Please enter your VBO365 Credentials"

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
$appURI             = "/v5/token"
$token              = Connect-VeeamRestAPI -AppUri $appURI -Cred $cred

#Get Organization ID
Write-Host "Getting Organization Settings...." -ForegroundColor White
Write-Host ""
$appURI             = "/v5/Organizations/"
$vboorg             = Get-VeeamRestAPI -AppUri $appURI -Token $token
$vboorgid           = $vboorg.id

#Get user information
Write-Host "Get User Information...." -ForegroundColor White
Write-Host ""
$appURI             = "/v5/Organizations/$vboorgid/Users?username=$Username"
$vbouser            = Get-VeeamRestAPI -AppUri $appURI -Token $token
$vbouserid          = $vbouser.results.id
$vbodisplayname     = $vbouser.results.displayName
$vbousername        = $vbouser.results.name 

#Building Body for creating the Audit Items 
$body_json = @”
 [
   {
     "type": "user",
     "user": {
       "id": "$vbouserid",
       "displayName": "$vbodisplayname",
       "name": "$vbousername",      
       }
   }
”@
#Set the user to be audited
Write-Host "Set Audit Items Setting for user...." -ForegroundColor White
Write-Host ""
$appURI             = "/v5/Organizations/$vboorgid/AuditItems"
Post-VeeamRestAPI-Audit -AppUri $appURI -Token $token -body $body_json

#Set audit notification setting if Switch parameter given
if($SetAuditNotification){
#Create body - Please change the configuration parameters according to your environment
$body_json =  @”
{
 "enableNotification": true,
 "smtpServer": "smtp.office365.com",
 "port": 587,
 "useAuthentication": true,
 "username": "user@abc.onmicrosoft.com",
 "userpassword" : "!!!Don't store the password here. Yes, this process will be improved!!!",
 "useSSL": true,
 "from": "VBOserver@abc.onmicrosoft.com",
 "to": "SecurityOfficer@abc.onmicrosoft.com",
 "subject": "[Audit] %OrganizationName% - %DisplayName% - %Action% initiated by %InitiatedByUserName% at %StartTime%"
}
”@

#Set Audit Notification Settings
Write-Host "Set Audit Notificatoin Settings...." -ForegroundColor White
Write-Host ""
$appURI             = "/v5/AuditEmailSettings"
Put-VeeamRestAPI-Audit -AppUri $appURI -Token $token -body $body_json
                         }
