<# 
.SYNOPSIS
    Create an Entra application for authentication, backup and recovery from Veeam's Backup for Microsoft 365
.DESCRIPTION
    This script is meant to be used by a security or Entra administrator to provide the necessary Entra application to be used in Veeam Backup for Microsoft 365.

    Use this script only if you can't use the product's built-in functionality to create the application (which will require Global Admin permissions).

    The script will do the following and does not require any Veeam component to run:

    1. Connect to Entra with given admin credentials
    2. Create a public/private key-pair for app authentication and export the key to a file
    3. Create a new application registration within Entra
    4. Add the key for authentication to the app
    5. Assign the required permissions for VB365 to the application

    For a detailed list of permissions used in this script, please check
    https://helpcenter.veeam.com/docs/vbo365/guide/azure_ad_applications.html
     
    Created for and tested with Veeam Backup for Microsoft 365 v7

    Requires the the Microsoft.Graph Powershell Module - Tested with version 2.5.0
.NOTES
    Written by Stefan Zimmermann 
        v1.0.3, 14.01.2021
    Updated by Stephan "Steve" Herzig (Use Microsoft.Graph Cmdlets & update required permissions)
        v2.0.0  17.11.2023
#>
Param(
    # Tenant ID - can be found on the Entra admin center overview page
    [Parameter(Mandatory=$true)] 
    [string] $entraTenantId,

    # DisplayName for the app registration    
    [String] $appName = "VB365 - Azure Application",

    # Limit permissions to only those required for backup, InteractiveRestore (device authentication flow, e.g. Explorers) or ProgrammaticRestore (REST API-only), omitting this creates permissions for all usage types
    [String][ValidateSet("Backup", "InteractiveRestore", "ProgrammaticRestore")] $limitUsageTo,

    # Limit permissions to the following service(s). Omitting this creates permissions for all supported.
    [String[]][ValidateSet("Exchange", "SharePoint", "OneDrive", "Teams")] $limitServiceTo,

    # Path to the file where the public key will be stored (CRT)
    [string] $certificateFilePath = "$($PSScriptRoot)\veeam_backup_microsoft365_app_public.crt",

    # Path to the file where the private key will be exported (PFX)
    [string] $keyFilePath = "$($PSScriptRoot)\veeam_backup_microsoft365_app_private.pfx",

    # Lifetime of the key-pair in days
    [int] $keyLifeTimeDays = 3*365,

    # Password for exported key file
    [securestring] $keyPassword,

    # Overwrite/regenerate authentication key if exists
    [switch] $overwriteKey,

    # Overwrite/regenerate app registration if exists with same name
    [switch] $overwriteApp,

    # Use the following credentials to connect to Entra instead of asking. Can't be used for MFA
    [PSCredential] $entraCredential,

    # Keylength for generated RSA key pair
    [int] $keyLength = 4096
);
Clear-Host

$apiAppIds = @{
    Graph      = "00000003-0000-0000-c000-000000000000"; # Microsoft Graph
    Exchange   = "00000002-0000-0ff1-ce00-000000000000"; # Microsoft 365 Exchange Online
    SharePoint = "00000003-0000-0ff1-ce00-000000000000"; # Microsoft 365 SharePoint Online
}

$permissionTypes = @{
    Application = "Role";
    Delegated   = "Scope";
}

$usages = @{
    Backup              = "Backup";
    InteractiveRestore  = "InteractiveRestore";
    ProgrammaticRestore = "ProgrammaticRestore";
}

$services = @{
    Exchange   = "Exchange";
    SharePoint = "SharePoint";
    OneDrive   = "OneDrive";
    Teams      = "Teams";
}

# Permissions from Veeam Helpcenter (https://helpcenter.veeam.com/docs/vbo365/guide/azure_ad_applications.html)
$permissions = @(
    @{ 
        ApiAppId = $apiAppIds.Graph;
        Value    = "Directory.Read.All";
        id       = "7ab1d382-f21e-4acd-a863-ba3e13f7da61";
        Usage    = $usages.Backup;
        Service  = $services.Exchange, $services.SharePoint, $services.OneDrive, $services.Teams;
        Type     = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.Graph;
        Value    = "Group.Read.All";
        id       = "5b567255-7703-4780-807c-7be8301ae99b";
        Usage    = $usages.Backup;
        Service  = $services.Exchange, $services.SharePoint, $services.OneDrive, $services.Teams;
        Type     = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.Graph;
        Value    = "Sites.Read.All";
        id       = "332a536c-c7ef-4017-ab91-336970924f0d";
        Usage    = $usages.Backup;
        Service  = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type     = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.Graph;
        Value    = "TeamSettings.ReadWrite.All";
        id       = "bdd80a03-d9bc-451d-b7c4-ce7c63fe3c8f";
        Usage    = $usages.Backup;
        Service  = $services.Teams;
        Type     = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.Graph;
        Value    = "ChannelMessage.Read.All";
        id       = "7b2449af-6ccd-4f4d-9f78-e550c193f0d1";
        Usage    = $usages.Backup;
        Service  = $services.Teams;
        Type     = $permissionTypes.Application;
    },        
    @{
        ApiAppId = $apiAppIds.Exchange;
        Value    = "full_access_as_app";
        id       = "dc890d15-9560-4a4c-9b7f-a736ec74ec40";
        Usage    = $usages.Backup;
        Service  = $services.Exchange, $services.Teams;
        Type     = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.Exchange;
        Value    = "Exchange.ManageAsApp";
        id       = "dc50a0fb-09a3-484d-be87-e023b12c6440";
        Usage    = $usages.Backup;
        Service  = $services.Exchange;
        Type     = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.SharePoint;
        Value    = "Sites.FullControl.All";
        id       = "678536fe-1083-478a-9c59-b99265e6b0d3";
        Usage    = $usages.Backup, $usages.ProgrammaticRestore;
        Service  = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type     = $permissionTypes.Application;
    },
    @{
        ApiAppId = $apiAppIds.SharePoint;
        Value    = "User.Read.All";
        id       = "df021288-bdef-4463-88db-98f22de89214";
        Usage    = $usages.Backup, $usages.ProgrammaticRestore;
        Service  = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type     = $permissionTypes.Application;
    },
    @{ 
        ApiAppId = $apiAppIds.Graph;
        Value    = "Directory.Read.All";
        id       = "06da0dbc-49e2-44d2-8312-53f166ab848a";
        Usage    = $usages.InteractiveRestore;
        Service  = $services.Exchange, $services.SharePoint, $services.OneDrive, $services.Teams;
        Type     = $permissionTypes.Delegated;     
    },
    @{
        ApiAppId = $apiAppIds.Graph;
        Value    = "Group.ReadWrite.All";
        id       = "4e46008b-f24c-477d-8fff-7bb4ec7aafe0";
        Usage    = $usages.InteractiveRestore;
        Service  = $services.Teams;
        Type     = $permissionTypes.Delegated;
    },
	@{
        ApiAppId = $apiAppIds.Graph;
        Value    = "Sites.Read.All";
        id       = "205e70e5-aba6-4c52-a976-6d2d46c48043";
        Usage    = $usages.InteractiveRestore;
        Service  = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type     = $permissionTypes.Delegated;
    },
	@{
        ApiAppId = $apiAppIds.Graph;
        Value    = "Directory.ReadWrite.All";
        id       = "c5366453-9fb0-48a5-a156-24f0c49a4b84";
        Usage    = $usages.InteractiveRestore;
        Service  = $services.Teams;
        Type     = $permissionTypes.Delegated;
    },
    @{
        ApiAppId = $apiAppIds.Graph;
        Value    = "offline_access";
        id       = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182";
        Usage    = $usages.InteractiveRestore;
        Service  = $services.Exchange, $services.SharePoint, $services.OneDrive, $services.Teams;
        Type     = $permissionTypes.Delegated;     
    },
	@{
        ApiAppId = $apiAppIds.Exchange;
        Value    = "EWS.AccessAsUser.All";
        id       = "3b5f3d61-589b-4a3c-a359-5dd4b5ee5bd5";
        Usage    = $usages.InteractiveRestore;
        Service  = $services.Exchange;
        Type     = $permissionTypes.Delegated;     
    },
    @{
        ApiAppId = $apiAppIds.SharePoint;
        Value    = "AllSites.FullControl";
        id       = "56680e0d-d2a3-4ae1-80d8-3c4f2100e3d0";
        Usage    = $usages.InteractiveRestore;
        Service  = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type     = $permissionTypes.Delegated;     
    },
    @{
        ApiAppId = $apiAppIds.SharePoint;
        Value    = "User.Read.All";
        id       = "0cea5a30-f6f8-42b5-87a0-84cc26822e02";
        Usage    = $usages.InteractiveRestore;
        Service  = $services.OneDrive;
        Type     = $permissionTypes.Delegated;     
    },
    @{
        ApiAppId = $apiAppIds.Exchange;
        Value    = "full_access_as_app";
        id       = "dc890d15-9560-4a4c-9b7f-a736ec74ec40";
        Usage    = $usages.ProgrammaticRestore;
        Service  = $services.Exchange;
        Type     = $permissionTypes.Application;
    },
	@{ 
        ApiAppId = $apiAppIds.Graph;
        Value    = "Directory.Read.All";
        id       = "7ab1d382-f21e-4acd-a863-ba3e13f7da61";
        Usage    = $usages.ProgrammaticRestore;
        Service  = $services.Exchange, $services.Teams;
        Type     = $permissionTypes.Application;
    },
	@{ 
        ApiAppId = $apiAppIds.Graph;
        Value    = "Directory.ReadWrite.All";
        id       = "19dbc75e-c2e2-444c-a770-ec69d8559fc7";
        Usage    = $usages.ProgrammaticRestore;
        Service  = $services.Teams;
        Type     = $permissionTypes.Application;
    },
	@{
        ApiAppId = $apiAppIds.Graph;
        Value    = "Group.ReadWrite.All";
        id       = "62a82d76-70ea-41e2-9197-370581804d09";
        Usage    = $usages.ProgrammaticRestore;
        Service  = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type     = $permissionTypes.Application;
    },
        @{
        ApiAppId = $apiAppIds.Graph;
        Value    = "Sites.Read.All";
        id       = "332a536c-c7ef-4017-ab91-336970924f0d";
        Usage    = $usages.ProgrammaticRestore;
        Service  = $services.SharePoint, $services.OneDrive, $services.Teams;
        Type     = $permissionTypes.Application;
    }
)

# Connect to Microsoft Entra
try {
    if ($entraCredential) {
        $adConnection    = Connect-MgGraph -TenantId $entraTenantId -Credential $entraCredential -NoWelcome -ErrorAction SilentlyContinue
    } else {
        Write-Host -ForegroundColor Cyan "Please check for an opened window and log in to Entra ID"
        $adConnection    = Connect-MgGraph -TenantId $entraTenantId -NoWelcome -ErrorAction SilentlyContinue
        $entraConnection = Invoke-MgGraphRequest -Method GET https://graph.microsoft.com/v1.0/me
    }
    Write-Host
    Write-Host -ForegroundColor White "***** Configuration start *****"
    Write-Host
    Write-Host -ForegroundColor White "Connected to Entra tenant $($entraTenantId) as $($entraConnection.userPrincipalName)"
} catch {
    Write-Host -ForegroundColor Red "Connection to Entra tenant ID $($entraTenantId) failed: $_"
    Write-Debug $_.Exception
    exit 1
}

# Create new self-signed certificate or use existing one for key authentication with the app
$today = Get-Date
if (!(Test-Path $certificateFilePath) -or ($overwriteKey -eq $true)) {
    try {        
        $cert = New-SelfSignedCertificate -KeyAlgorithm RSA -KeyDescription "$appName" -KeyExportPolicy Exportable -KeyLength $keyLength -Subject "$appName"  -FriendlyName "$appName" -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter $today.AddDays($keyLifeTimeDays)
        Export-Certificate -Cert $cert -FilePath $certificateFilePath > $null

        Write-Host -ForegroundColor White "Created new certificate in $($certificateFilePath) with a lifetime of $($keyLifeTimeDays) days."

        if (!$keyPassword) {
            Write-Host -ForegroundColor Cyan "Please specify a password to encrypt the exported key: "
            $keyPassword = Read-Host -AsSecureString
        }

        Export-PfxCertificate -Cert $cert -FilePath $keyFilePath -Password $keyPassword > $null
        Write-Host -ForegroundColor White "Exported your key file to $($keyFilePath)."
    } catch {
        Write-Host -ForegroundColor Red "There was an error during the creation or export of the authentication certificate: $_"
        Write-Debug $_.Exception
        exit 2
    }
} else {
    try {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $cert.Import($certificateFilePath)
        Write-Host -ForegroundColor White "Using already present certificate from $($certificateFilePath)"
    } catch {
        Write-Host -ForegroundColor Red "Could not load already present certificate $($certificateFilePath): $_"
        Write-Debug $_.Exception
        exit 3
    }
}

# Check if app already exists
if ($vboApp = Get-MgApplication -Filter "DisplayName eq '$appName'" -ErrorAction SilentlyContinue) {
    if ($overwriteApp -eq $true) {
        try {
            $oldServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$($vboApp.Id)'"
            if ($oldServicePrincipal) {
                Remove-MgServicePrincipal -InputObject $oldServicePrincipal.ObjectId
            }
            Remove-MgApplication -ApplicationId $vboApp.Id
            Write-Host -ForegroundColor White "Found existing application with name $($appName) and removed it as configured"
        } catch {
            Write-Host -ForegroundColor Red "Could not remove Entra application $($appName): $_"
            Disconnect-MgGraph > $null
            Write-Debug $_.Exception
            exit 4
        }
    } else {
        Write-Host -ForegroundColor Red "Application '$($vboApp.Displayname)' (Application-ID: $($vboApp.Id)) already exists - please specify '-overwriteApp' or give another name with '-appName'"
        exit 4
    }
}

# Create the application, set owner and the redirectURI
try {    
    $vboApp     = New-MgApplication -DisplayName $appName -SignInAudience "AzureADMyOrg"
    $owner      = Get-MgUser -Filter "Id eq '$($entraConnection.id)'"
    $ownerId    = $owner.Id
    
    $newOwner   = @{
    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$ownerId}"
    }
    
    $RedirectURI = @()
    $RedirectURI += "http://localhost"
    
    $params = @{
    RedirectUris = @($RedirectURI)
    }
            
    New-MgApplicationOwnerByRef -ApplicationId $vboApp.Id -BodyParameter $newOwner
    New-MgServicePrincipal -AppId $vboApp.AppId
    Update-MgApplication -ApplicationId $vboApp.Id -PublicClient $params

    if ($limitUsageTo -eq "InteractiveRestore") {
        Update-MgApplication -ApplicationId $vboApp.Id -PublicClient $params
    }
    Write-Host -ForegroundColor White "Created new Entra application registration '$($appName)'"
} catch {
    Write-Host -ForegroundColor Red "Failed to create new app registration: $_"
    Write-Debug $_.Exception
    Disconnect-MgGraph > $null
    exit 5
}

# Certificate handling as per https://docs.microsoft.com/en-us/powershell/module/azuread/new-azureadapplicationkeycredential?view=azureadps-2.0
Write-Host -ForegroundColor White "Add certificate authentication to Entra application"
$binRaw      = $cert.GetRawCertData()
$base64Value = [System.Convert]::ToBase64String($binRaw)
$bin         = $cert.GetCertHash()

$keyCreds = @{ 
    Type  = "AsymmetricX509Cert";
    Usage = "Verify";
    key   = $binRaw
} 

Update-MgApplication -ApplicationId $vboApp.Id -KeyCredentials $keyCreds 

# Filter permissions based on limitations
Write-Host -ForegroundColor White "Building effective permissions list based on usage ($($limitUsageTo)) and service ($($limitServiceTo)) limitations (if any)"

$filteredPermissions = [System.Collections.ArrayList]@()
foreach ($permission in $permissions) {
    if (!$limitUsageTo -or ($limitUsageTo -in $permission.Usage)) {
        if (!$limitServiceTo -or ($limitServiceTo | Where-Object { $permission.Service -contains $_ })) {
            Write-Debug "Adding permission $(($apiAppIds.GetEnumerator() | Where-Object Value -eq $permission.apiAppId).Name)/$($permission.Value)"
            $filteredPermissions.Add($permission) > $null
        }
    }
}

# Create $requiredResourceAccessList for each unique ResourceAppID
$requiredResourceAccessLists = @()

foreach ($uniqueResourceAppID in ($filteredPermissions | ForEach-Object { $_.ApiAppId } | Get-Unique)) {
    $filteredPermissionsForAppID = $filteredPermissions | Where-Object { $_.ApiAppId -eq $uniqueResourceAppID }


    $requiredResourceAccessList = @{
        ResourceAppID  = $uniqueResourceAppID;
        ResourceAccess = @()
    }

    foreach ($permission in $filteredPermissionsForAppID) {
        $resourceAccess = @{
            id   = $permission.id;
            type = $permission.Type;
        }
        $requiredResourceAccessList['ResourceAccess'] += $resourceAccess
    }

    $requiredResourceAccessLists += $requiredResourceAccessList
}

# Update-MgApplication with each $requiredResourceAccessList
foreach ($accessList in $requiredResourceAccessLists) {
    try {
        $clientApp = Get-MgApplication -ApplicationId $vboApp.Id

        $existingResourceAccess = $clientApp.RequiredResourceAccess

        # If the app has no existing permissions
        if ([string]::IsNullOrEmpty($existingResourceAccess)) {
            Update-MgApplication -ApplicationId $vboApp.Id -RequiredResourceAccess $accessList
            Write-Host -ForegroundColor White "Added permissions to Azure AD application for ResourceAppID $($accessList.ResourceAppID)"
        } else {
            # Check if the app already has existing permissions for the current ResourceAppID
            $existingPermissionsForAppID = $existingResourceAccess | Where-Object { $_.ResourceAppId -eq $accessList.ResourceAppID }

            # If no existing permissions for the current ResourceAppID, add new permissions
            if ($existingPermissionsForAppID -eq $null) {
                $existingResourceAccess += $accessList
            } else {
                # If existing permissions exist, merge the new permissions
                foreach ($newPermission in $accessList.ResourceAccess) {
                    if ($existingPermissionsForAppID.ResourceAccess | Where-Object { $_.id -eq $newPermission.id } -eq $null) {
                        $existingResourceAccess.ResourceAccess += $newPermission
                    }
                }
            }

            # Update the application with the merged permissions
            Update-MgApplication -ApplicationId $vboApp.Id -RequiredResourceAccess $existingResourceAccess
            Write-Host -ForegroundColor White "Updated permissions for Azure AD application for ResourceAppID $($accessList.ResourceAppID)"
        }
    } catch {
        Write-Host -ForegroundColor Red "Was not able to add/update permissions to Azure AD app for ResourceAppID $($accessList.ResourceAppID) - $_"
        Write-Debug $_.Exception
        Disconnect-MgGraph > $null
        exit 6
    }
}

Write-Host "Logging off Entra" -ForegroundColor White
Disconnect-MgGraph > $null
Write-Host
Write-Host -ForegroundColor White "***** Configuration end *****"
Write-Host

Write-Host -ForegroundColor Cyan "The following Entra application has been created for the use with VB365:"
Write-Host -ForegroundColor Green "
App-ID:     $($vboApp.AppId)
App-Name:   $($vboApp.DisplayName)
Key-File:   $($keyFilePath)
"
Write-Host
Write-Host -ForegroundColor Cyan "The following manual steps are required from here:"

Write-Host -ForegroundColor Cyan "* Check the API permissions of the app in the Entra admin center and grant admin consent."
if (!$limitUsageTo) {
    Write-Host -ForegroundColor Cyan "* Manually enable the 'Allow public client flows' on the 'Authentication' page of the app details for interactive restores"
}
Write-Host -ForegroundColor Cyan "* Give the App-ID, the created private key file and it's password to the Veeam Backup for Microsoft 365 admin."
Write-Host -ForegroundColor Cyan "* Starting from version 7 CP4, Veeam Backup for Microsoft 365 supports backup of public folder and discovery search mailboxes. To back up these objects, Veeam Backup for Microsoft 365 needs access to Exchange Online PowerShell. To do this, the app needs the Global Reader role."
Write-Host

