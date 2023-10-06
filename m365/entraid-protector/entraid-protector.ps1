<# 
.NAME
    Entra ID Protector
.DESCRIPTION,
    This Powershell script is designed to help export data from Microsoft Entra ID. It offers various functionalities to export and compare data.
    More details on the ReadMe page https://github.com/yetanothermightytool/powershell/blob/master/m365/entraid-protector/README.md
.NOTES  
    File Name  : entraid-protector.ps1
    Author     : Stephan "Steve" Herzig, (stephan.herzig@veeam.com)
    Requires   : PowerShell 5.1+, Powershell modules "EntraExporter" & "Microsoft Graph" (tested with version 2.5.0)
.VERSION
    1.2
#>

Param(
    [Switch]$Export,
    [Switch]$AuditExport,
    [Switch]$Users,
    [Switch]$Groups,
    [Switch]$SecurityGroups,
    [Switch]$DynamicGroups,
    [Switch]$Applications,
    [Switch]$Roles,
    [Switch]$GetRecycleBin,
    [Switch]$CompareUserCount,
    [String]$CompareSpecificUser,
       [Int]$ExportNo,
    [Switch]$CheckSignInAnomalies,
    [Switch]$CheckRoleActivities,
    [String]$OriginCountry,
    [Switch]$InstallModules,
    [String]$LogFilePath  = "C:\Temp\entra-id-protector-log.txt"
    )

Clear-Host
# Variables
$exportRootFolder          = "C:\Temp"
$exportFolder              = "$exportRootFolder\entraid-export"
$auditExportFolder         = "$exportRootFolder\entraid-export\AuditLogs"
$maxExportCount            = 4 # Retention

# General settings
$hostGui                   = $host.UI.RawUI
$host.ui.RawUI.WindowTitle = "Entra ID Protector"
$hostGui.foregroundcolor   = "white"

# Body for Security Group Import
$secGroupParam = @{
    DisplayName           = ""
    Description           = ""
    GroupTypes            = @()
    SecurityEnabled       = $true
    MailEnabled           = $false
    MailNickname          = (New-Guid).Guid.Substring(0, 10)
    "Members@odata.bind"  = @()
    "Owners@odata.bind"   = @()
}

# Body for Security Group Import
$dynGroupParam = @{
    DisplayName                   = ""
    Description                   = ""
    GroupTypes                    = @()
    SecurityEnabled               = $true
    membershipRuleProcessingState = 'On'
    MailEnabled                   = $false
    MailNickname                  = (New-Guid).Guid.Substring(0, 10)
    membershipRule                = ""
    "Owners@odata.bind"           = @()
}

# Start da script!
Write-Host "************************************"
Write-Host "*        Entra ID" -NoNewline -ForegroundColor Blue
Write-Host " Protector        *"
Write-Host "************************************"
Write-Host 

# Functions section
function AddLogEntry {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    $logEntry = "$timestamp - Entra ID Protector - $Message"
    Add-Content -Path $LogFilePath -Value $logEntry
}

function Rotate-ExportFolders {
    param (
        [string]$folderPath,
        [int]$maxCount
    )

    # Determine the highest numbered folder that exists
    $highestFolderNumber     = $maxCount
    while ($highestFolderNumber -ge 1 -and -not (Test-Path -Path (Join-Path -Path $folderPath -ChildPath "entraid-export-$highestFolderNumber"))) {
           $highestFolderNumber--
           }
    # Rename existing export folders in reverse order, up to $maxCount - this one took some time.
    for ($i = $highestFolderNumber; $i -ge 1; $i--) {
        $currentFolder        = Join-Path -Path $folderPath -ChildPath "entraid-export-$i"
        $newFolder            = Join-Path -Path $folderPath -ChildPath "entraid-export-$($i + 1)"

        if (Test-Path -Path $currentFolder) {
            if ($i -eq $maxCount) {
                Remove-Item -Path $currentFolder -Force -Recurse
            }
            else {
                Rename-Item -Path $currentFolder -NewName $newFolder -Force
            }
        }
    }

    # Rename the initial folder to "entraid-export-1" if it exists
    $initialFolder = Join-Path -Path $folderPath -ChildPath "entraid-export"
    $newFolder     = Join-Path -Path $folderPath -ChildPath "entraid-export-1"

    if (Test-Path -Path $initialFolder) {
        Rename-Item -Path $initialFolder -NewName $newFolder -Force
    }
}

function Compare-UserCounts {
    # Get the path of the latest export folder
    $latestExportFolder       = Join-Path -Path $exportRootFolder -ChildPath "entraid-export"

    # Initialize an array to store subfolders in previous export folders
    $previousUsersSubfolders  = @()

    # Initialize an array to store missing IDs
    $missingIDs               = @()

    # Loop through the previous export folders
    for ($i = 1; $i -le $maxExportCount; $i++) {
        $previousExportFolder = Join-Path -Path $exportRootFolder -ChildPath "entraid-export-$i"

        # Check if the previous export folder exists and contains a "Users" subfolder
        if ((Test-Path -Path $previousExportFolder) -and (Test-Path -Path (Join-Path -Path $previousExportFolder -ChildPath "Users"))) {
            $subfolders = Get-ChildItem -Path (Join-Path -Path $previousExportFolder -ChildPath "Users") -Directory | Select-Object -ExpandProperty Name
            $previousUsersSubfolders += @{
                FolderName    = "entraid-export-$i"
                Subfolders    = $subfolders
            }
        }
    }

    # Compare subfolders in the "Users" directory
    Write-Host "Subfolder comparison in 'Users' directory vs. latest export:" -ForegroundColor Cyan
    Write-Host
    # Display the nunber of user subfolders from the latest export
    $userCount = @(Get-ChildItem -Path $usersFolderPath -Directory).Count
    Write-Host "Current Export (entraid-export):" -ForegroundColor Cyan
    Write-Host "  Total Subfolders: $userCount" -ForegroundColor White

    # Get the subfolders from the latest and greatest export
    $latestUsersSubfolders = Get-ChildItem -Path (Join-Path -Path $latestExportFolder -ChildPath "Users") -Directory | Select-Object -ExpandProperty Name

    foreach ($previousSubfoldersInfo in $previousUsersSubfolders) {
        $folderName = $previousSubfoldersInfo.FolderName
        $subfolders = $previousSubfoldersInfo.Subfolders
        Write-Host "Previous Export ($folderName):" -ForegroundColor Cyan
        if ($subfolders.Count -gt 0) {
            Write-Host "  Total Subfolders: $($subfolders.Count)" -ForegroundColor White
            foreach ($subfolder in $subfolders) {
                if ($latestUsersSubfolders -notcontains $subfolder) {
                    Write-Host "  Missing subfolder in latest export: $subfolder" -ForegroundColor Yellow
                    $missingIDs += $subfolder
                }
            }
        } else {
            Write-Host "  No subfolders found." -ForegroundColor White
        }
    }

    # Return the array of missing IDs
    return $missingIDs
}

function Get-DisplayNameInSubfolder {
    param (
        [string]$id,
        [string]$checkExportFolder  
    )

    # Construct the path to the subfolder based on the provided ID
    $subfolderPath = Join-Path -Path (Join-Path -Path $checkExportFolder -ChildPath "Users") -ChildPath $id

    # Construct the path to the JSON file within the subfolder
    $jsonFilePath  = Join-Path -Path $subfolderPath -ChildPath "$id.json"

    
    if (Test-Path -Path $jsonFilePath -PathType Leaf) {
        $jsonContent = Get-Content -Path $jsonFilePath | ConvertFrom-Json
        return $jsonContent.displayName
    } else {
        return $null
    }
}
 
function Search-UserPrincipalName {
    param (
           [string]$searchValue
           )

    $jsonFiles = Get-ChildItem -Path "$exportFolder\Users" -Filter "*.json" -File -Recurse

    foreach ($jsonFile in $jsonFiles) {
        try {
            $jsonContent = Get-Content -Path $jsonFile.FullName -Raw | ConvertFrom-Json
            if ($jsonContent.userPrincipalName -eq $searchValue) {
                $id = $jsonFile.Directory.Name
                Write-Output $id
            }
        }
        catch {
            # troubleshooting - and yes I had some trouble
            Write-Warning "Error processing $($jsonFile.FullName): $_"
        }
    }
}

function Compare-ExportFile() {
    param(
        [Parameter(Mandatory = $true)]
        [string]$latestExportPath,
        [Parameter(Mandatory = $true)]
        [string]$selectedExportPath
    )

    try {
        $backupFile = Get-Content -LiteralPath $latestExportPath -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        Write-Error -Message "Could not retrieve JSON file from the latest export location." -ErrorAction Stop
    }

    try {
        $latestExportFile = Get-Content -LiteralPath $selectedExportPath -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        Write-Error -Message "Could not retrieve a JSON file from the given export folder $ExportNo." -ErrorAction Stop
    }
    
    function Invoke-FlattenExportObject() {
        param(
            [Parameter (Mandatory = $true)]
            [PSCustomObject]$PSCustomObject,
            [Parameter (Mandatory = $false)]
            [string]$KeyName
        )

        $flatObject = New-Object -TypeName PSObject

        $psCustomObject.PSObject.Properties | ForEach-Object {
            if ($null -eq $($_.Value)) {
                if ($KeyName) {
                    $flatObject | Add-Member -NotePropertyName "$KeyName-$($_.Name)" -NotePropertyValue 'null'
                }
                else {
                    $flatObject | Add-Member -NotePropertyName $_.Name -NotePropertyValue 'null'
                }
            }
            else {
                if (($_.Value).GetType().Name -eq 'PSCustomObject') {
                    Invoke-FlattenExportObject -PSCustomObject $_.Value -KeyName $_.Name
                }
                elseif (($_.Value).GetType().Name -eq 'Object[]') {
                    Invoke-FlattenExportObject -PSCustomObject $_.Value.GetEnumerator() -KeyName $_.Name
                }
                else {
                    if ($KeyName) {
                        $flatObject | Add-Member -NotePropertyName "$KeyName-$($_.Name)" -NotePropertyValue $_.Value
                    }
                    else {
                        $flatObject | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value
                    }
                }
            }
        }
        return $flatObject
    }

    $flattenExportArray        = Invoke-FlattenExportObject -PSCustomObject $backupFile
    $flattenLatestExportArray  = Invoke-FlattenExportObject -PSCustomObject $latestExportFile

    # Check if a JSON needs flattening - this was a hard one.
    if ($flattenExportArray -is [array]) {    
        $flattenExportObject = New-Object -TypeName PSObject
        for ($i=0; $i -le $flattenExportArray.Length; $i++) {
            foreach ($property in $flattenExportArray[$i].PSObject.Properties) {
                $flattenExportObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
            }
        }
    }
    else {
        $flattenExportObject = $flattenExportArray
    }

    # Check if the JSON needs flattening
    if ($flattenLatestExportArray -is [array]) {
        $flattenLatestExportObject = New-Object -TypeName PSObject
        for ($i=0; $i -le $flattenLatestExportArray.Length; $i++) {
            foreach ($property in $flattenLatestExportArray[$i].PSObject.Properties) {
                $flattenLatestExportObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
            }
        }
    }
    else {
        $flattenLatestExportObject = $flattenLatestExportArray
    }

    $backupComparison  = foreach ($latestExportFileProperty in $flattenExportObject.PSObject.Properties.Name) {
        $compareExport = Compare-Object -ReferenceObject $flattenExportObject -DifferenceObject $flattenLatestExportObject -Property $latestExportFileProperty
        if ($compareExport.SideIndicator) {
            # If the property exists in both export files locations
            if ($null -ne $flattenExportObject.$latestExportFileProperty) {
                New-Object PSCustomObject -Property @{
                    'JSON key'      = $latestExportFileProperty
                    'Current value' = $flattenExportObject.$latestExportFileProperty
                    'Old value'     = $flattenLatestExportObject.$latestExportFileProperty
                }
            }
            # If the property only exists in the latest export file location
            else {
                New-Object PSCustomObject -Property @{
                    'JSON key'      = $latestExportFileProperty
                    'Current value' = $null
                    'Old value    ' = $flattenLatestExportObject.$latestExportFileProperty
                }
            }
        }
    }

    return $backupComparison

}

function SignInAnomalies {
    param (
        [string]$auditExportFolder,
        [string]$originCountry
    )

    Write-Host "Filtering anomalies for originCountry: $originCountry"

    if (-not (Test-Path -Path $auditExportFolder -PathType Container)) {
        Write-Host "Error: The specified folder '$auditExportFolder' does not exist."
        return
    }

    $jsonFiles = Get-ChildItem -Path $auditExportFolder -Filter 'SignInAuditLogs_*.json' -File
    $anomalies = @()

    foreach ($jsonFile in $jsonFiles) {
        try {
            $jsonContent = Get-Content -Path $jsonFile.FullName | ConvertFrom-Json

            # Check if the CountryOrRegion is not equal to originCountry
            if ($jsonContent.Location.CountryOrRegion -ne $originCountry) {
                $ExpectedCountry   = $originCountry
                $CountryOrRegion   = $jsonContent.Location.CountryOrRegion
                $CreatedDateTime   = $jsonContent.CreatedDateTime
                $UserDisplayName   = $jsonContent.UserDisplayName
                $UserPrincipalName = $jsonContent.UserPrincipalName

                for ($i = 0; $i -lt $CountryOrRegion.Count; $i++) {
                    # Check if the current CountryOrRegion is not equal to originCountry
                    if ($CountryOrRegion[$i] -ne $originCountry) {
                        $anomalies += [PSCustomObject]@{
                            "CountryOrRegion"   = $CountryOrRegion[$i]
                            "ExpectedCountry"   = $ExpectedCountry
                            "CreatedDateTime"   = $CreatedDateTime[$i]
                            "UserDisplayName"   = $UserDisplayName[$i]
                            "UserPrincipalName" = $UserPrincipalName
                        }
                    }
                }
            }
        } catch {
            Write-Host "Error processing file $($jsonFile.FullName): $_"
        }
    }

    if ($anomalies.Count -gt 0) {
        $anomalies | Format-Table -AutoSize
    } else {
        Write-Host "No anomalies found in the audit logs. All logins are from the Expected Country $originCountry."
    }
}

function SuspiciousDirectoryRoleActivities {
    param (
        [string]$auditExportFolder
    )

    if (-not (Test-Path -Path $auditExportFolder -PathType Container)) {
        Write-Host "Error: The specified folder '$auditExportFolder' does not exist."
        return
    }

    $jsonFiles            = Get-ChildItem -Path $auditExportFolder -Filter 'DirectoryAuditLogs*.json' -File
    $suspiciousActivities = @()

    foreach ($jsonFile in $jsonFiles) {
        try {
            $jsonContent = Get-Content -Path $jsonFile.FullName -Raw | ConvertFrom-Json

            foreach ($entry in $jsonContent) {
                if ($entry.Result -eq "success" -and (
                        # Add more entries if needed
                        $entry.ActivityDisplayName -eq "Add member to role" -or
                        $entry.ActivityDisplayName -eq "Remove member from role" -or
                        $entry.ActivityDisplayName -eq "Add app role assignment grant to user" -or
                        $entry.ActivityDisplayName -eq "Add delegated permission grant"
                    )) {
                    $initiatedBy = $entry.InitiatedBy.User -match "UserPrincipalName:\s*(.+)"
                    if ($initiatedBy) {
                        $userPrincipalName = $matches[1].Trim()
                    } else {
                        $userPrincipalName = "N/A"
                    }

                    $targetResourceNames = @()
                    $targetResourceIds   = @()

                    $roleEntry = $entry.TargetResources | Where-Object { $_ -match "Type: Role" }
                    $userEntry = $entry.TargetResources | Where-Object { $_ -match "Type: User" }

                    if ($userEntry -match "UserPrincipalName:\s*(.+)") {
                        $upn = $matches[1].Trim()
                        $targetResourceNames += $upn
                    }

                    if ($roleEntry -match "Id:\s+([a-fA-F0-9-]+)") {
                        $id = $matches[1].Trim()
                        $targetResourceIds += $id
                    }

                    $suspiciousActivities += [PSCustomObject]@{
                        "ActivityDisplayName"          = $entry.ActivityDisplayName
                        "InitiatedByUserPrincipalName" = $userPrincipalName
                        "ActivityDateTime"             = $entry.ActivityDateTime
                        "TargetPrincipalNames"         = $targetResourceNames -join ', '
                        "TargetIds"                    = $targetResourceIds -join ', ' #Checking if join is needed
                    }
                }
            }
        } catch {
            Write-Host "Error processing file $($jsonFile.FullName): $_"
        }
    }

    if ($suspiciousActivities.Count -gt 0) {
        $suspiciousActivities | Format-Table -AutoSize
    } else {
        Write-Host "No activities found in the audit logs."
    }
}

if ($InstallModules){
    # Check if Entra Exporter module is installed
    if ($null -eq (Get-InstalledModule -Name "EntraExporter" -ErrorAction SilentlyContinue)) {
        Write-Host "Installing EntraExporter module" -ForegroundColor Cyan
        Install-Module EntraExporter
    }
    # Check if Microsoft Graph module is installed
    if ($null -eq (Get-InstalledModule -Name "Microsoft.Graph" -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Microsoft Graph module" -ForegroundColor Cyan
        Install-Module Microsoft.Graph -AllowClobber -Verbose -Force
    }
}

if ($Export){
# Connect to the API
Connect-EntraExporter

# Rotate and rename existing export folders
Rotate-ExportFolders -folderPath $exportRootFolder -maxCount $maxExportCount

# Export the data
    # Check if the export folder exists
    if (-not (Test-Path -Path $exportFolder)) {
        New-Item -Path $exportFolder -ItemType Directory
    }
# Perform the export
Write-Host "Export Entra ID data." -ForegroundColor Cyan
AddLogEntry -Message "Export Entra ID data started."
Export-Entra -Path $exportFolder -Type Users,Groups,Applications,Roles 
Write-Host "Export completed." -ForegroundColor Cyan
Write-Host
AddLogEntry -Message "Export Entra ID data completed."
$null = Disconnect-MgGraph

if ($AuditExport){
   $null = Connect-MgGraph 
   # Check if the export folder exists
    if (-not (Test-Path -Path $auditExportFolder)) {
        New-Item -Path $auditExportFolder -ItemType Directory
    
    # Get the audit logs for the last 24 hours
    Write-Host "Export Directory and Sign-in Audit Logs of the last 24 hours." -ForegroundColor Cyan
    AddLogEntry -Message "Export Entra ID Directory and Sign-in Audit Logs started."
    $startTime          = (Get-Date).AddHours(-24)
    $startTimeFormatted = $startTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $auditDirectoryLogs = Get-MgAuditLogDirectoryAudit -Filter "ActivityDateTime ge $startTimeFormatted"
    $auditSignInLogs    = Get-MgAuditLogSignIn -Filter "CreatedDateTime ge $startTimeFormatted"

    $currentTimeFormatted = (Get-Date).ToString("yyyy-MM-dd-HH-mm-ss")
    $jsonDirectoryFile    = "DirectoryAuditLogs_$currentTimeFormatted.json"
    $jsonDirectoryPath    = Join-Path -Path $auditExportFolder -ChildPath $jsonDirectoryFile
    $jsonSignInFile       = "SignInAuditLogs_$currentTimeFormatted.json"
    $jsonSignInPath       = Join-Path -Path $auditExportFolder -ChildPath $jsonSignInFile
    
    # Convert the data to JSON format and save it to the file
    $auditDirectoryLogs | ConvertTo-Json | Set-Content -Path $jsonDirectoryPath
    $auditSignInLogs    | ConvertTo-Json | Set-Content -Path $jsonSignInPath
    Write-Host "Export Directory and Sign-in Audit Logs completed." -ForegroundColor Cyan
    AddLogEntry -Message "Export Entra ID Directory and Sign-in Audit Logs completed."
    $null = Disconnect-MgGraph
    }
  }
}

if ($ExportNo -eq ""){
    $usersFolderPath       = Join-Path -Path $exportFolder -ChildPath "Users"
    $groupsFolderPath      = Join-Path -Path $exportFolder -ChildPath "Groups"
    $appsFolderPath        = Join-Path -Path $exportFolder -ChildPath "Applications"
    $rolesFolderPath       = Join-Path -Path $exportFolder -ChildPath "DirectoryRoles"
    $auditExportFolderPath = $auditExportFolder
    # Get creation dates
    $usersFolderDate       = (Get-Item $usersFolderPath).CreationTime
    $groupsFolderDate      = (Get-Item $groupsFolderPath).CreationTime
    $appsFolderDate        = (Get-Item $appsFolderPath).CreationTime
    $rolesFolderDate       = (Get-Item $rolesFolderPath).CreationTime
    if (Test-Path -Path $auditExportFolderPath -PathType Container) {
    $auditFolderDate       = (Get-Item $auditExportFolderPath).CreationTime
    }
 }else {
    $usersFolderPath       = Join-Path -Path $exportFolder-$ExportNo -ChildPath "Users"
    $groupsFolderPath      = Join-Path -Path $exportFolder-$ExportNo -ChildPath "Groups"
    $appsFolderPath        = Join-Path -Path $exportFolder-$ExportNo -ChildPath "Applications"
    $rolesFolderPath       = Join-Path -Path $exportFolder-$ExportNo -ChildPath "DirectoryRoles"
    $auditExportFolderPath = Join-Path -Path $exportFolder-$ExportNo -ChildPath "AuditLogs"
    # Get creation dates
    $usersFolderDate       = (Get-Item $usersFolderPath).CreationTime
    $groupsFolderDate      = (Get-Item $groupsFolderPath).CreationTime
    $appsFolderDate        = (Get-Item $appsFolderPath).CreationTime
    $rolesFolderDate       = (Get-Item $rolesFolderPath).CreationTime
    if (Test-Path -Path $auditExportFolderPath -PathType Container) {
    $auditFolderDate       = (Get-Item $auditExportFolderPath).CreationTime
    }
}

if ($Users) {
    $userData = @()

    $userJsonFiles = Get-ChildItem -Path $usersFolderPath -Filter "*.json" -File -Recurse

    foreach ($userJsonFile in $userJsonFiles) {
        $userJsonContent = Get-Content -Path $userJsonFile.FullName | ConvertFrom-Json

        # Extract user information
        $userItem             = [PSCustomObject]@{
            Id                = $userJsonContent.id
            UserPrincipalName = $userJsonContent.userPrincipalName
            DisplayName       = $userJsonContent.displayName
        }

        # Add the user object to the array
        $userData += $userItem
    }

    # Display users
    if ($userData.Count -gt 0) {
        Write-Host "Users in export $ExportNo - $usersFolderDate" -ForegroundColor Cyan
        $userData | Out-GridView #Format-Table -AutoSize
        $totalUserCount  = ($userData | Measure-Object).Count
        Write-Host "Total Users: $totalUserCount"
        Pause
    } else {
        Write-Host "No user data found." -ForegroundColor Yellow
        Pause
    }
}

if ($Groups) {
    $groupData = @()

    $groupJsonFiles = Get-ChildItem -Path $groupsFolderPath -Filter "*.json" -File -Recurse | Where-Object { $_.DirectoryName -notmatch 'Members|Owners' }

    foreach ($groupJsonFile in $groupJsonFiles) {
        # Read the JSON content from the file
        $groupJsonContent = Get-Content -Path $groupJsonFile.FullName | ConvertFrom-Json

        # Extract group information
        $groupItem      = [PSCustomObject]@{
            Id          = $groupJsonContent.id
            DisplayName = $groupJsonContent.displayName
            Mail        = $groupJsonContent.mail
        }

        $groupData += $groupItem
    }

    if ($groupData.Count -gt 0) {
        # Display groups in Out-GridView and allow the user to select a group
        $selectedGroup = $groupData | Out-GridView -Title "Select a Group" -OutputMode Single

        if ($selectedGroup) {
            $groupId = $selectedGroup.Id

            $membersPath     = Join-Path -Path $groupsFolderPath -ChildPath "$groupId\Members"
            $memberData      = @()
            $memberJsonFiles = Get-ChildItem -Path $membersPath -Filter "*.json" -File -Recurse

            foreach ($memberJsonFile in $memberJsonFiles) {
                $memberJsonContent = Get-Content -Path $memberJsonFile.FullName | ConvertFrom-Json

                # Extract member information
                $memberItem = [PSCustomObject]@{
                    Id                = $memberJsonContent.id
                    UserPrincipalName = $memberJsonContent.userPrincipalName
                    DisplayName       = $memberJsonContent.displayName
                }

                $memberData += $memberItem
            }

            # Display member information for the selected group
            if ($memberData.Count -gt 0) {
                Write-Host "Members of $($selectedGroup.DisplayName):" -ForegroundColor Cyan
                $memberData | Format-Table -AutoSize
                $totalGroupCount = ($groupData | Measure-Object).Count
                Write-Host "Total Groups: $totalGroupCount" -ForegroundColor Cyan
                Pause
            } else {
                Write-Host "No members found for $($selectedGroup.DisplayName)." -ForegroundColor White
                Pause
            }
        } else {
            Write-Host "No group selected." -ForegroundColor White
            Pause
        }
    } else {
        Write-Host "No group data found." -ForegroundColor Yellow
    }
}

if ($Applications) {
    $appData       = @()
    $appsJsonFiles = Get-ChildItem -Path $appsFolderPath -Filter "*.json" -File -Recurse
  
    foreach ($appJsonFile in $appsJsonFiles) {
        $appJsonContent = Get-Content -Path $appJsonFile.FullName | ConvertFrom-Json

    # Check if 'keyCredentials' exists in JSON file (Certificate) and then extracts the Certificate expiration date
    if ($null -ne $appJsonContent.keyCredentials -and $appJsonContent.keyCredentials.Count -gt 0) {
        $endDateTime = $appJsonContent.keyCredentials[0].endDateTime
    }
    else {
          $endDateTime = $null  
    }
          $appItem              = [PSCustomObject]@{
            Id                = $appJsonContent.id
            DisplayName       = $appJsonContent.displayName
            CertExpiration    = $endDateTime 
        }
        $appData += $appItem
    }

    # Display applications
    if ($appData.Count -gt 0) {
        Write-Host "Applications in export $ExportNo - $appsFolderDate" -ForegroundColor Cyan
        $appData | Format-Table -AutoSize
        $totalAppsCount  = ($appData | Measure-Object).Count
        Write-Host "Total applications: $totalAppsCount" -ForegroundColor Cyan
        Pause
    } else {
        Write-Host "No applications found." -ForegroundColor Yellow
        Pause
    }
}

if ($CompareUserCount) {
    $missingIDs         = Compare-UserCounts
    $latestExportFolder = Join-Path -Path $exportRootFolder -ChildPath "entraid-export"

    Write-Host
    Write-Host "Compare exported user count.Checking missing items..." -ForegroundColor Cyan
    
    for ($i = 1; $i -le $maxExportCount; $i++) {
        $exportFolderToCheck = Join-Path -Path $exportRootFolder -ChildPath "entraid-export-$i"
        
        
        if (Test-Path -Path $exportFolderToCheck) {
            
            $missingIDsInFolder = @{}  
            
            $missingIDs | ForEach-Object {
                $missingID = $_
                $displayName = Get-DisplayNameInSubfolder -id $missingID -checkExportFolder $exportFolderToCheck

                # Check if the ID is not found in the latest export
                if (-not (Test-Path -Path (Join-Path -Path $latestExportFolder -ChildPath "Users\$missingID.json"))) {
                    
                    $missingIDsInFolder[$missingID] = [PSCustomObject]@{
                        ID           = $missingID
                        ExportFolder = "Export-$i"
                        DisplayName  = If ([string]::IsNullOrWhiteSpace($displayName)) { "Folder does not exist" } else { $displayName }
                    }
                }
            }

             # Display a summary of missing IDs / Current export folder
            if ($missingIDsInFolder.Count -gt 0) {
                Write-Host "Summary for Export-$i :" -ForegroundColor Cyan
                $missingIDsInFolder.Values | Format-Table -AutoSize
               } 
           }
      }
 Pause
}

if ($Roles) {
    $roleData      = @()
    $roleJsonFiles = Get-ChildItem -Path $rolesFolderPath -Filter "*.json" -File -Recurse | Where-Object { $_.DirectoryName -notmatch 'Members' }

    foreach ($roleJsonFile in $roleJsonFiles) {
        $roleJsonContent = Get-Content -Path $roleJsonFile.FullName | ConvertFrom-Json

        $roleItem      = [PSCustomObject]@{
            Id          = $roleJsonContent.id
            DisplayName = $roleJsonContent.displayName
            Mail        = $roleJsonContent.mail
        }

        $roleData += $roleItem
    }

    ###STOP
    if ($roleData.Count -gt 0) {
        Write-Host "Available Roles in export $ExportNo - $rolesFolderDate" -ForegroundColor Cyan
        Write-Host
        $roleIndex = 1
        foreach ($role in $roleData) {
            Write-Host "$roleIndex. $($role.DisplayName)" -ForegroundColor White
            $roleIndex++
        }

        # Prompt the user to select a role by index
        $selectedRoleIndex = Read-Host "Enter the number of the role you want to view members for"
        # Check if the selected value is valid
        if ($selectedRoleIndex -ge 1 -and $selectedRoleIndex -le $roleData.Count) {
            $selectedRole = $roleData[$selectedRoleIndex - 1]

            # Check if the 'Members' property exists in the selected role
            if ($selectedRole.PSObject.Properties["Id"]) {
                $roleId = $selectedRole.Id

                $membersPath     = Join-Path -Path $rolesFolderPath -ChildPath "$roleId\Members"
                $memberData      = @()

                $memberJsonFiles = Get-ChildItem -Path $membersPath -Filter "*.json" -File -Recurse
                foreach ($memberJsonFile in $memberJsonFiles) {
                    $memberJsonContent = Get-Content -Path $memberJsonFile.FullName | ConvertFrom-Json

                    $memberItem           = [PSCustomObject]@{
                        Id                = $memberJsonContent.id
                        UserPrincipalName = $memberJsonContent.userPrincipalName
                        DisplayName       = $memberJsonContent.displayName
                    }

                    $memberData += $memberItem
                }

                # Display member information for the selected role
                if ($memberData.Count -gt 0) {
                    Write-Host "Members of $($selectedRole.DisplayName):" -ForegroundColor Cyan
                    $memberData | Format-Table -AutoSize
                    $totalRoleCount = ($roleData | Measure-Object).Count
                    Write-Host "Total Roles: $totalRoleCount" -ForegroundColor Cyan
                    Pause
                } else {
                    Write-Host "No members found for $($selectedRole.DisplayName)." -ForegroundColor Yellow
                    Pause
                }
            } else {
                Write-Host "No members found for $($selectedRole.DisplayName)." -ForegroundColor Yellow
                Pause
            }
        } else {
            Write-Host "Invalid selection." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No Roles data found." -ForegroundColor Yellow
    }
}

if ($GetRecycleBin) {

Connect-MgGraph -NoWelcome
    
$deletedUsers = Get-MgDirectoryDeletedItemAsUser
    
    if ($deletedUsers.Count -gt 0) {
        Write-Host "Deleted users in Recycle Bin" -ForegroundColor Cyan
        $deletedUsers | Select-Object Id, DisplayName,UserPrincipalName | Format-Table

        $userToRestore = Read-Host "Enter the Id of the user to restore or type 'exit' to quit"
        
        if ($userToRestore -ne 'exit') {
            $userToRestoreInfo = $deletedUsers | Where-Object { $_.Id -eq $userToRestore }
            
            if ($null -ne $userToRestoreInfo) {
                # Start restore
                Restore-MgDirectoryDeletedItem -DirectoryObjectId $userToRestore
                Write-Host "User '$userToRestore' has been restored." -ForegroundColor Green
                $null = Disconnect-MgGraph
            } else {
                Write-Host "User '$userToRestore' not found in the list of deleted users." -ForegroundColor Yellow
            }
        } else {
            Write-Host "Exiting the script." -ForegroundColor White
            $null = Disconnect-MgGraph
        }
    } else {
        Write-Host "No deleted users found!" -ForegroundColor White
        $null = Disconnect-MgGraph
    }
}

if ($CompareSpecificUser) {
$compareID = Search-UserPrincipalName -searchValue $CompareSpecificUser
Compare-ExportFile -latestExportPath C:\Temp\entraid-export\Users\$compareID\$compareID.json -selectedExportPath C:\Temp\entraid-export-$ExportNo\Users\$compareID\$compareID.json | Out-Host
Pause
}

if ($CheckSignInAnomalies) {
Write-Host "Sign-in anomalies for the past 24 hours - Origin country not equal Expected Country $OriginCountry" -ForegroundColor Cyan
SignInAnomalies -auditExportFolder $auditExportFolder -originCountry $originCountry
}

if ($CheckRoleActivities){
Write-Host "Role activities - Export folder $auditExportFolderPath - $auditFolderDate" -ForegroundColor Cyan
SuspiciousDirectoryRoleActivities -auditExportFolder $auditExportFolderPath
}

if ($SecurityGroups) {
    $securityGroupData = @()

    $groupJsonFiles = Get-ChildItem -Path $groupsFolderPath -Filter "*.json" -File -Recurse | Where-Object { $_.DirectoryName -notmatch 'Members|Owners' }

    foreach ($groupJsonFile in $groupJsonFiles) {
        $groupJsonContent = Get-Content -Path $groupJsonFile.FullName | ConvertFrom-Json

        # Check if the group has securityEnabled set to true and "mailEnabled set to false
        if ($groupJsonContent.securityEnabled -eq $true -and $groupJsonContent.mailEnabled -eq $false) {
            
            $groupItem = [PSCustomObject]@{
                Id          = $groupJsonContent.id
                DisplayName = $groupJsonContent.displayName
                Description = $groupJsonContent.description
                
            }

            $securityGroupData += $groupItem
        }
    }
    if ($securityGroupData.Count -gt 0) {
        Write-Host "Available security groups in export $ExportNo - $groupsFolderDate" -ForegroundColor Cyan
        Write-Host
        $groupIndex = 1
        foreach ($group in $securityGroupData) {
            Write-Host "$groupIndex. $($group.DisplayName)" -ForegroundColor White
            $groupIndex++
        }

            $selectedGroupIndex = [int](Read-Host "Enter the number of the security group you want to view members for")

            if ($selectedGroupIndex -ge 1 -and $selectedGroupIndex -le $securityGroupData.Count) {
                $selectedGroup = $securityGroupData[$selectedGroupIndex - 1]

                # Check if the 'Id' property exists in the selected group
                if ($selectedGroup.PSObject.Properties["Id"]) {
                            $groupId = $selectedGroup.Id

                # Extract member information
                $membersPath     = Join-Path -Path $groupsFolderPath -ChildPath "$groupId\Members"
                $memberData      = @()
                $memberJsonFiles = Get-ChildItem -Path $membersPath -Filter "*.json" -File -Recurse

                foreach ($memberJsonFile in $memberJsonFiles) {
                    $memberJsonContent = Get-Content -Path $memberJsonFile.FullName | ConvertFrom-Json

                    $memberItem = [PSCustomObject]@{
                        Id                = $memberJsonContent.id
                        UserPrincipalName = $memberJsonContent.userPrincipalName
                        DisplayName       = $memberJsonContent.displayName
                    }

                    $memberData += $memberItem
                }

                # Extract owner information
                $ownersPath     = Join-Path -Path $groupsFolderPath -ChildPath "$groupId\Owners"
                $ownerData      = @()
                $ownerJsonFiles = Get-ChildItem -Path $ownersPath -Filter "*.json" -File -Recurse

                foreach ($ownerJsonFile in $ownerJsonFiles) {
                    $ownerJsonContent = Get-Content -Path $ownerJsonFile.FullName | ConvertFrom-Json

                    $ownerItem = [PSCustomObject]@{
                        Id                = $ownerJsonContent.id
                        UserPrincipalName = $ownerJsonContent.userPrincipalName
                        DisplayName       = $ownerJsonContent.displayName
                    }

                    $ownerData += $ownerItem
                }

                # Display member and owner information for the selected group
                Clear-Host
                if ($memberData.Count -gt 0) {
                    Write-Host "Members of $($selectedGroup.DisplayName):" -ForegroundColor Cyan
                    $memberData | Format-Table -AutoSize
                } else {
                    Write-Host "No members found for $($selectedGroup.DisplayName)." -ForegroundColor White
                }

                if ($ownerData.Count -gt 0) {
                    Write-Host "Owners of $($selectedGroup.DisplayName):" -ForegroundColor Cyan
                    $ownerData | Format-Table -AutoSize
                    # Build the Owners@odata.bind array if owners are found
                    $secGroupParam["Owners@odata.bind"] = @()
                    foreach ($owner in $ownerData) {
                        $secGroupParam["Owners@odata.bind"] += "https://graph.microsoft.com/v1.0/users/$($owner.UserPrincipalName)"
                    }
                }

                # Build the $secGroupParam hashtable
                $sgDisplayName = $selectedGroup.DisplayName
                $sgDescription = $selectedGroup.description
                $secGroupParam = @{
                    DisplayName           = $sgDisplayName
                    Description           = $sgDescription
                    GroupTypes            = @()
                    SecurityEnabled       = $true
                    MailEnabled           = $false
                    MailNickname          = (New-Guid).Guid.Substring(0, 10)
                    "Members@odata.bind"  = @()
                    "Owners@odata.bind"   = @() 
                }

                foreach ($member in $memberData) {
                    $secGroupParam["Members@odata.bind"] += "https://graph.microsoft.com/v1.0/users/$($member.UserPrincipalName)"
                }

                foreach ($owner in $ownerData) {
                    $secGroupParam["Owners@odata.bind"] += "https://graph.microsoft.com/v1.0/users/$($owner.UserPrincipalName)"
                }

                # Display the $secGroupParam variable
                Write-Host "Group Parameters:"
                $secGroupParam | Out-Host

                # Prompt the user for the next action
                $continue = Read-Host "Do you want to import the security group using those parameters? (Y/N)"

                if ($continue -eq "Y" -or $continue -eq "y") {
                    Connect-MgGraph -NoWelcome
                    New-MgGroup -BodyParameter $secGroupParam
                    $null = Disconnect-MgGraph
                } elseif ($continue -eq "N" -or $continue -eq "n") {
                    Write-Host "Exiting..."
                    exit
                }
                
            } else {
                Write-Host "No members found for $($selectedGroup.DisplayName)." -ForegroundColor White
            }
        } else {
            Write-Host "Invalid selection." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No group data found." -ForegroundColor Yellow
    }
}

if ($DynamicGroups) {
    $dynamicGroupData = @()

    $groupJsonFiles = Get-ChildItem -Path $groupsFolderPath -Filter "*.json" -File -Recurse | Where-Object { $_.DirectoryName -notmatch 'Members|Owners' }

    foreach ($groupJsonFile in $groupJsonFiles) {
        $groupJsonContent = Get-Content -Path $groupJsonFile.FullName | ConvertFrom-Json

        # Check if the group has membershipRuleProcessingState set to On and "mailEnabled set to false
        if ($groupJsonContent.membershipRuleProcessingState -eq "On" -and $groupJsonContent.mailEnabled -eq $false) {
            
            $groupItem = [PSCustomObject]@{
                Id             = $groupJsonContent.id
                DisplayName    = $groupJsonContent.displayName
                Description    = $groupJsonContent.description
                membershipRule = $groupJsonContent.membershipRule
                
            }

            $dynamicGroupData += $groupItem
        }
    }
    if ($dynamicGroupData.Count -gt 0) {
        Write-Host "Available dynamic groups in export $ExportNo - $groupsFolderDate" -ForegroundColor Cyan
        Write-Host
        $groupIndex = 1
        foreach ($group in $dynamicGroupData) {
            Write-Host "$groupIndex. $($group.DisplayName)" -ForegroundColor White
            $groupIndex++
        }

            $selectedGroupIndex = [int](Read-Host "Enter the number of the dynamic group you want to view the rules for")

            if ($selectedGroupIndex -ge 1 -and $selectedGroupIndex -le $dynamicGroupData.Count) {
                $selectedGroup = $dynamicGroupData[$selectedGroupIndex - 1]

                # Check if the 'Id' property exists in the selected group
                if ($selectedGroup.PSObject.Properties["Id"]) {
                            $groupId = $selectedGroup.Id
                
                # Extract owner information
                $ownersPath     = Join-Path -Path $groupsFolderPath -ChildPath "$groupId\Owners"
                $ownerData      = @()
                $ownerJsonFiles = Get-ChildItem -Path $ownersPath -Filter "*.json" -File -Recurse

                foreach ($ownerJsonFile in $ownerJsonFiles) {
                    $ownerJsonContent = Get-Content -Path $ownerJsonFile.FullName | ConvertFrom-Json

                    $ownerItem = [PSCustomObject]@{
                        Id                = $ownerJsonContent.id
                        UserPrincipalName = $ownerJsonContent.userPrincipalName
                        DisplayName       = $ownerJsonContent.displayName
                    }

                    $ownerData += $ownerItem
                }

                if ($ownerData.Count -gt 0) {
                    Write-Host "Owners of $($selectedGroup.DisplayName):" -ForegroundColor Cyan
                    $ownerData | Format-Table -AutoSize
                    
                    $dynGroupParam["Owners@odata.bind"] = @()
                    foreach ($owner in $ownerData) {
                        $dynGroupParam["Owners@odata.bind"] += "https://graph.microsoft.com/v1.0/users/$($owner.UserPrincipalName)"
                    }
                }

                # Build the $dynGroupParam hashtable
                $sgDisplayName    = $selectedGroup.DisplayName
                $sgDescription    = $selectedGroup.description
                $sgMembershipRule = $selectedGroup.membershipRule
                $dynGroupParam    = @{
                    DisplayName                   = $sgDisplayName
                    Description                   = $sgDescription
                    GroupTypes                    = @('DynamicMembership')
                    membershipRuleProcessingState = "On"
                    membershipRule                = $sgMembershipRule
                    SecurityEnabled               = $true
                    MailEnabled                   = $false
                    MailNickname                  = (New-Guid).Guid.Substring(0, 10)
                }
                if ($ownerData.Count -gt 0) {
                    $dynGroupParam["Owners@odata.bind"] = @()
                    foreach ($owner in $ownerData) {
                    $dynGroupParam["Owners@odata.bind"] += "https://graph.microsoft.com/v1.0/users/$($owner.UserPrincipalName)"
                    }
                }

                # Display the $dynGroupParam variable
                Write-Host "Group Parameters:"
                $dynGroupParam | Out-Host

                # Prompt the user for the next action
                $continue = Read-Host "Do you want to import the dynamic group using those parameters? (Y/N)"

                if ($continue -eq "Y" -or $continue -eq "y") {
                    Connect-MgGraph -NoWelcome
                    New-MgGroup -BodyParameter $dynGroupParam
                    $null = Disconnect-MgGraph
                } elseif ($continue -eq "N" -or $continue -eq "n") {
                    Write-Host "Exiting..."
                    exit
                }
                
            } else {
                Write-Host "No rules found $($selectedGroup.DisplayName)." -ForegroundColor White
            }
        } else {
            Write-Host "Invalid selection." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No group data found." -ForegroundColor Yellow
    }
}
