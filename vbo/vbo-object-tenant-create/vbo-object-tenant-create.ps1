param(
    [String] $Customer,
    [String] $Proxy,
    [Switch] $AddObjectStorage
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

#Function for creating the Audit Items (POST)
function Post-VeeamRestAPI {
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
        #Write-Output $tokenRequest
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
Write-Host "*            VB365 Object Storage Creator             *"
Write-Host "**************************************************v1.0*" -ForegroundColor Cyan

#Request Bearer Token
Write-Host "Get Bearer Token...."
Write-Host ""
$appURI             = "/v6/token"
$token              = Connect-VeeamRestAPI -AppUri $appURI -Cred $cred

#Get Organization ID
Write-Host "Getting Organization Settings...." -ForegroundColor White
Write-Host ""
$appURI             = "/v6/Organizations/"
$vboorg             = Get-VeeamRestAPI -AppUri $appURI -Token $token
$vboorgid           = $vboorg.id

#Set Tenant Key Password

#Enter encryption key password and description for Tenant
Write-Host  "Enter Tenant Name and Encryption Password"
Write-Host  ""
$seccredential       = Get-Credential -Message "Please enter Tenant Name and Encryption Password"
$encdescription      = $seccredential.UserName
$encpassword         = $seccredential.GetNetworkCredential().Password

#Building Body for creating encryption password 
$body_json = @”
   {
     "password": "$encpassword",
     "description": "$encdescription"     
   }
”@
#Set the key password
Write-Host "Set encryption key for Tenant $encdescription" -ForegroundColor White
Write-Host ""
$appURI             = "/v6/EncryptionKeys"
Post-VeeamRestAPI -AppUri $appURI -Token $token -body $body_json

#Cloud Accounts
Write-Host "Getting VBO Cloud Accounts...." -ForegroundColor White
Write-Host ""
$appURI             = "/v6/Accounts/"
$vbocloudacct       = Get-VeeamRestAPI -AppUri $appURI -Token $token
$vbocloudacctid     = $vbocloudacct.id

###Add Object Storage
#Building Body for adding object storage
$body_json = @”
   {
     "name": "S3 $Customer",
     "description": "Kunde $Customer",
     "type": "AmazonS3Compatible",
     "accountId": "$vbocloudacctid",
      "amazonBucketS3Compatible": {
        "name": "<bucketname>",
        "servicePoint" : "<url>",
        "customRegionId": "us-east-1"
        },
     "s3Folder": "cust-$Customer",
     "sizeLimitEnabled": true,
     "sizeLimitGB": "1024"
     
   }
”@
#Create the object storage
Write-Host "Create Objectstorage for customer $Customer " -ForegroundColor White
Write-Host ""
$appURI             = "/v6/objectstoragerepositories"
Post-VeeamRestAPI -AppUri $appURI -Token $token -body $body_json

###Preparations for Repository Creation
#Get-Proxy ID
Write-Host "Getting proxy server id...." -ForegroundColor White
Write-Host ""
$appURI             = "/v6/Proxies/"
$vboproxyid         = Get-VeeamRestAPI -AppUri $appURI -Token $token
$vboproxyserver     = $vboproxyid | Where-Object {$_.hostName -eq $Proxy} 
$vboproxyserverid   = $vboproxyserver.id    

#Get object storage id
Write-Host "Getting object storage id...." -ForegroundColor White
Write-Host ""
$appURI             = "/v6/objectstoragerepositories/"
$vboobjectsid       = Get-VeeamRestAPI -AppUri $appURI -Token $token
$vboobjectstorage   = $vboobjectsid | Where-Object {$_.Name -eq "S3 $Customer"} 
$vboobjectstorageid = $vboobjectstorage.id

#Get Encryption Key ID
Write-Host "Getting encryption key id...." -ForegroundColor White
Write-Host ""
$appURI             = "/v6/EncryptionKeys/"
$vboenckey          = Get-VeeamRestAPI -AppUri $appURI -Token $token
$vboencryptionkey   = $vboenckey     | Where-Object {$_.Description -eq "$encdescription"}  
$vboencryptionkeyid = $vboencryptionkey.id

#Create Backup Repository
$body_json = @”
{
  "objectStorageId": "$vboobjectstorageid",
  "objectStorageCachePath": "D:\\<path on drive>\\cust-$Customer",
  "objectStorageEncryptionEnabled": true,
  "encryptionKeyId": "$vboencryptionkeyid",
  "name": "cust-$Customer",
  "description": "Customer Repository",
  "retentionType": "SnapshotBased",
  "retentionPeriodType": "Daily",
  "dailyRetentionPeriod": 30,
  "dailyType": "Weekends",
  "attachUsedRepository": true,
  "retentionFrequencyType": "Monthly",
  "monthlyTime": "08:00:00",
  "monthlyDaynumber": "First",
  "monthlyDayofweek": "Sunday",
  "proxyId": "$vboproxyserverid",
  "attachUsedRepository": true
}
”@
Write-Host "Creating Backup Repository for customer $customer"
Write-Host ""
$appURI             = "/v6/BackupRepositories/"
Post-VeeamRestAPI -AppUri $appURI -Token $token -body $body_json
