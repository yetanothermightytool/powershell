param (
    [Parameter(Mandatory = $true)]
    [String]$Organization,
    [Parameter(Mandatory = $true)]
    [String]$BackupJob,
    [Parameter(Mandatory = $true)]
    [String]$Filter,
    [Parameter(Mandatory = $false)]
    [Switch]$Sharepoint,
    [Parameter(Mandatory = $false)]
    [Switch]$MSTeams,
    [Parameter(Mandatory = $false)]
    [Switch]$URL
)
# Get general information
$vb365org      = Get-VBOOrganization -Name $Organization
$vb365job      = Get-VBOJob -Name $BackupJob

# Sharepoint filter
if ($Sharepoint){
    $spSites   = Get-VBOOrganizationSite -Organization $vb365org -IncludePersonalSite:$false -NotInJob

    ForEach ($spSite in $spSites) {
      $FilteredSite = $spSite.Name -match "$Filter"

  
      if ($FilteredSite) {
        $newSite = New-VBOBackupItem -Site $spSite
        Add-VBOBackupItem -Job $vb365job -BackupItem $newSite
      }
    }
}

## MSTeams filter
if ($MSTeams){
    $teams   = Get-VBOOrganizationTeam -Organization $vb365org -NotInJob

    ForEach ($team in $teams) {
      $filteredTeam = $team.DisplayName -match "$Filter"

  
      if ($filteredTeam) {
        $newTeam = New-VBOBackupItem -Team $team
        Add-VBOBackupItem -Job $vb365job -BackupItem $newTeam
      }
    }
}

# Sharepoint URL filter
if ($URL){
    $spSites   = Get-VBOOrganizationSite -Organization $vb365org -IncludePersonalSite:$false -NotInJob

    ForEach ($spSite in $spSites) {
      $FilteredSite = $spSite.URL -match "$Filter"

  
      if ($FilteredSite) {
        $newSite = New-VBOBackupItem -Site $spSite
        Add-VBOBackupItem -Job $vb365job -BackupItem $newSite
      }
    }
}
