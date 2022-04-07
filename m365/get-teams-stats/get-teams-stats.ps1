<#
.NAME
    Get MS Teams Chat & Private Chat Message Statistics
.DESCRIPTION
    Powershell script to list the maximum and average chat message numbers for the given report period.

    Switch '-Period' specifies the length of time over which the report is aggregated. Possible values are 7, 30, 90 or 180
	
.NOTES  
    File Name  : get-teams-stats.ps1 
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell and a registered app within the tenant
.VERSION
    1.0
#>
param(
        [Parameter(Mandatory = $true)]
        [String] $Period        
     )
#Variables
$ReportAPI          = "https://graph.microsoft.com"
$TenantID           = "<value here>"
$ClientID           = "<value here>"
$Secret             = "<value here>"
$uri                = "https://login.microsoftonline.com/$TenantID/oauth2/token"

#Get Access Token
$body        = @{
  grant_type = "Client_credentials"
  client_id  = $ClientID
  client_secret = $Secret
  resource   = "$ReportAPI"
}
$response    = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType "application/x-www-form-urlencoded"
$Token       = $response.access_token

#Get-RestAPI Function
function Get-RestAPI {
    [CmdletBinding()]
    param (
        [string] $AppUri,
        [string] $Token
    )

    begin {
        $header = @{
            "Authorization" = "Bearer $Token"
        }
        $requestURI = $ReportAPI + $AppUri
        $results    = Invoke-RestMethod -Method GET -Uri $requestUri -Headers $header
        Write-Output $results
    }
}

#getTeamsUserActivityCounts
$appURI             = "/v1.0/reports/getTeamsUserActivityCounts(period='D$Period')"
$TeamsStats         = Get-RestAPI -AppUri $appURI -Token $Token
$TeamsStats | Out-File "C:\Temp\TeamStats.csv"

#Generate Data
$TeamsTable         = Import-Csv -Path C:\Temp\TeamStats.csv
$tcmavg             = $TeamsTable."Team Chat Messages"  | Measure -Average | select Average | Format-Table -HideTableHeaders | out-string 
$tcmmax             = $TeamsTable."Team Chat Messages"  | Measure -Maximum | select Maximum | Format-Table -HideTableHeaders | out-string
$tpmavg             = $TeamsTable."Private Chat Messages"  | Measure -Average | select Average | Format-Table -HideTableHeaders | out-string
$tpmmax             = $TeamsTable."Private Chat Messages"  | Measure -Maximum | select Maximum | Format-Table -HideTableHeaders | out-string
Write-Host "*****************************" -ForegroundColor Cyan
Write-Host "*         Statistics        *" -ForegroundColor Cyan 
Write-Host "*****************************" -ForegroundColor Cyan
Write-Host "Average Team Chat Messages" -NoNewline -ForegroundColor Cyan
Write-Host "$tcmavg" -NoNewline
Write-Host "Maximum Team Chat Messages" -NoNewline -ForegroundColor Cyan
Write-Host "$tcmmax" -NoNewline
Write-Host "Average Private Chat Messages" -NoNewline -ForegroundColor Cyan
Write-Host "$tpmavg" -NoNewline
Write-Host "Maximum Private Chat Messages" -NoNewline -ForegroundColor Cyan
Write-Host "$tpmmax" -NoNewline
