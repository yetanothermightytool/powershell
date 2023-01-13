# Code example for registering an application and assigning the necessary permissions
# Application Name
$appName               = "exo_reporter"

#  Get the Microsoft 365 EXO API details
$api                   = (Get-AzureADServicePrincipal -Filter "AppID eq '00000002-0000-0ff1-ce00-000000000000'")

# Get the permission ID
$permission            = $api.AppRoles | Where-Object { $_.Value -eq 'MailboxSettings.Read' }

# Build the permission object
$apiPermission = [Microsoft.Open.AzureAD.Model.RequiredResourceAccess]@{
    ResourceAppId  = $api.AppId ;
    ResourceAccess = [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
        Id   = $permission.Id ;
        Type = "Role"
    }
}

# Register the newly created  Azure AD App with API Permissions
$myApp                 = New-AzureADApplication -DisplayName $appName -ReplyUrls 'http://localhost' -RequiredResourceAccess $apiPermission

# Enable the Service Principal
New-AzureADServicePrincipal -AppID $myApp.AppID
