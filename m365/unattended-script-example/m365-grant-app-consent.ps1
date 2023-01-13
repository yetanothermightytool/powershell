# Get the TenantID
$tenantID = (Get-AzureADTenantDetail).ObjectID

# URL to be used
$consentURL = "https://login.microsoftonline.com/$tenantID/adminconsent?client_id=$($myApp.AppId)"

# Launch the browser using the consent URL
Start-Process $consentURL
