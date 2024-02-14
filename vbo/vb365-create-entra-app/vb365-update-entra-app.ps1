Param(
    # Tenant ID - can be found on the Entra ID admin center overview page
    [Parameter(Mandatory=$true)] 
    [string] $entraTenantId,

    # DisplayName for the app registration    
    [String] $appName,

    # Limit permissions to only those required for backup, InteractiveRestore (device authentication flow, e.g. Explorers) or ProgrammaticRestore (REST API-only), omitting this creates permissions for all usage types
    [String][ValidateSet("Backup", "InteractiveRestore", "ProgrammaticRestore")] $limitUsageTo,

    # Limit permissions to the following service(s). Omitting this creates permissions for all supported.
    [String[]][ValidateSet("Exchange", "SharePoint", "OneDrive", "Teams")] $limitServiceTo
    );
Clear-Host
# General 
if ($limitServiceTo) {
    $limitServiceTo = $limitServiceTo.Split(',')
}

# Graph API
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

# Connect to Microsoft Entra Id
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
    Write-Host -ForegroundColor White "Connected to Entra ID Tenant $($entraTenantId) as $($entraConnection.userPrincipalName)"
} catch {
    Write-Host -ForegroundColor Red "Connection to Entra ID Tenant ID $($entraTenantId) failed: $_"
    Write-Debug $_.Exception
    exit 1
}

Write-Host -ForegroundColor White "Building effective permissions list based on usage ($($limitUsageTo)) and service ($($limitServiceTo)) limitations (if any)"
Write-Host
$vboApp              = Get-MgApplication -Filter "DisplayName eq '$appName'"
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

# Retrieve existing permissions and display changes before applying them
$clientApp              = Get-MgApplication -ApplicationId $vboApp.Id
$existingResourceAccess = $clientApp.RequiredResourceAccess

foreach ($accessList in $requiredResourceAccessLists) {
    $existingPermissionsForAppID = $existingResourceAccess | Where-Object { $_.ResourceAppId -eq $accessList.ResourceAppID }
    Write-Host "Permissions to be applied for ResourceAppID $($accessList.ResourceAppID):" -ForegroundColor Cyan

    foreach ($newPermission in $accessList.ResourceAccess) {
        $applName           = ($apiAppIds.GetEnumerator() | Where-Object { $_.Value -eq $accessList.ResourceAppID }).Name
        $displayName        = ($permissions | Where-Object { $_.id -eq $newPermission.id }).Value
        $existing           = if ($existingPermissionsForAppID) { ($existingPermissionsForAppID.ResourceAccess | Where-Object { $_.id -eq $newPermission.id }) -ne $null } else { $false }
        $color              = if ($existing) { "White" } else { "DarkYellow" }
        $existsString       = if ($existing) { '(Already exists)' } else { '(To be added)' }
        $permissionType     = ($permissions | Where-Object { $_.id -eq $newPermission.id }).Type
        $permissionTypeName = $permissionTypes[$permissionType]
        Write-Host "Application: $applName, Permission: $displayName" $existsString -ForegroundColor $color
    }
}
    
$changesNeeded = $false
foreach ($accessList in $requiredResourceAccessLists) {
    $existingPermissionsForAppID = $existingResourceAccess | Where-Object { $_.ResourceAppId -eq $accessList.ResourceAppID }

    foreach ($newPermission in $accessList.ResourceAccess) {
        $existing = if ($existingPermissionsForAppID) { ($existingPermissionsForAppID.ResourceAccess | Where-Object { $_.id -eq $newPermission.id }) -ne $null } else { $false }
        if (!$existing) {
            $changesNeeded = $true
            break
        }
    }
}

    if (-not $changesNeeded) {
        Write-Host
        Write-Host "No changes need to be applied." -ForegroundColor White
        exit
    }

$confirmation = Read-Host "Do you want to apply the changes? (Y/N)" 
if ($confirmation.ToLower() -ne 'y') {
    Write-Host "Changes were not applied." -ForegroundColor White
    exit
}

# Update-MgApplication with each $requiredResourceAccessList
foreach ($accessList in $requiredResourceAccessLists) {
    try {
        $clientApp              = Get-MgApplication -ApplicationId $vboApp.Id
        $existingResourceAccess = $clientApp.RequiredResourceAccess

        # Check if an entry exists for the current ResourceAppID, create one if it doesn't
        $existingEntry = $existingResourceAccess | Where-Object { $_.ResourceAppId -eq $accessList.ResourceAppID }
        if (-not $existingEntry) {
            $existingEntry = @{
                ResourceAppId  = $accessList.ResourceAppID
                ResourceAccess = @()
            }
            $existingResourceAccess += $existingEntry
        }

        # Update the permissions for the current ResourceAppID
        $existingEntry.ResourceAccess = $accessList.ResourceAccess

        # Update the application with the modified RequiredResourceAccess
        $updateApp = Update-MgApplication -ApplicationId $vboApp.Id -RequiredResourceAccess $existingResourceAccess
        Write-Host -ForegroundColor White "Updated permissions for Entra ID application for ResourceAppID $($accessList.ResourceAppID)"
    } catch {
        Write-Host -ForegroundColor Red "Was not able to add/update permissions to Entra ID application for ResourceAppID $($accessList.ResourceAppID) - $_"
        Write-Debug $_.Exception
        Disconnect-MgGraph > $null
        exit 6
    }
}

# Add Global Reader role to application - Needed for Public Folder backup
if ($limitServiceTo -eq "Exchange"){
    $appObjectId        = (Get-MgServicePrincipal -Filter "DisplayName eq '$AppName'").Id
    $roleDefinitionId   = (Get-MgRoleManagementDirectoryRoleDefinition -Filter "DisplayName eq 'Global Reader'").Id
    $appRoleAssignments = Get-MgRoleManagementDirectoryRoleAssignment
    
    if (-not ($appRoleAssignments.PrincipalId -contains $appObjectId -and $appRoleAssignments.RoleDefinitionId -contains $roleDefinitionId)) {
        Write-Host "Adding Global Reader role to application $appName" -ForegroundColor White
        $addAppRole = New-MgRoleManagementDirectoryRoleAssignment -PrincipalId $appObjectId -RoleDefinitionId $roleDefinitionId -DirectoryScopeId "/"
    } else {
        Write-Host "Global Reader role already assigned to application $appName" -ForegroundColor Cyan
    }
}

Write-Host "Logging off Entra ID" -ForegroundColor White
Disconnect-MgGraph > $null
Write-Host
Write-Host -ForegroundColor White "***** Configuration end *****"
Write-Host

Write-Host -ForegroundColor Cyan "The following Entra ID application has been updated for the use with VB365:"
Write-Host -ForegroundColor Green "
App-ID:     $($vboApp.AppId)
App-Name:   $($vboApp.DisplayName)
"
Write-Host
Write-Host -ForegroundColor Cyan "The following manual steps are required from here:"
Write-Host -ForegroundColor Cyan "* Check the API permissions of the app in the Entra ID admin center and grant admin consent if needed."

