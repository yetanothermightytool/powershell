<# 
.NAME
    Veeam Backup & Replication - Guest Index Data Scan Manager
.DESCRIPTION
    This PowerShell script for Veeam Backup & Replication manages suspicious files and malware detection. 
    It includes functions to check, list, and export suspicious file entries, as well as the ability to 
    customize and import new entries into the malware detection settings.
 .NOTES  
    File Name  : vbr-guest-index-data-scan-manager.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12.1,ary-67/vbr-securerestore-lnx-ps1-secure-restore-for-linux-vm-4617
.VERSION
1.0
#>
param (
    [switch]$List,
    [switch]$Search,
    [String]$EntryToCheck,
    [String]$ExportPath = "C:\Temp",
    [Switch]$CustomInclude,
    [String]$AddEntry,
    [Switch]$CustomExclude,
    [Switch]$ExportCSV
)
Clear-Host
# XML file handling - Default VBR intallation directory is C: drive
$suspiciousXMLFile   = "D:\Program Files\Veeam\Backup and Replication\Backup\SuspiciousFiles.xml"
$xmlContent          = Get-Content -Path $suspiciousXMLFile -Raw
$entries             = Select-String -InputObject $xmlContent -Pattern "<fileMask>.*?</fileMask>" -AllMatches | ForEach-Object { $_.Matches.Value }

# Function to check if a specific entry exists
function CheckIfEntryExists($EntryToCheck)
 {
    $escapedEntry    = [Regex]::Escape($EntryToCheck)
    $found           = $entries -match "(?s)<FileMask>.*?$escapedEntry.*?</FileMask>"
            
    if ($found) {
        Write-Host "Entry '$EntryToCheck' exists." -ForegroundColor White
        Write-Host "$found" -ForegroundColor Cyan
    } else {
        Write-Host "Entry '$EntryToCheck' does not exist." -ForegroundColor Ye
    }
}

$customXMLPath       = "$ExportPath\CustomSuspiciousFiles.xml"
Export-VBRMalwareDetectionExtensionList -Path $customXMLPath

$customXmlContent    = [xml](Get-Content $customXMLPath)
$customIncludesCount = $customXmlContent.RansomwareExclusions.Includes.Item.Count
$customExcludesCount = $customXmlContent.RansomwareExclusions.Excludes.Item.Count

# Start
Write-Host "****************************************************" -ForegroundColor Cyan
Write-Host "*             Guest Indexing Data Scan             *" -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor Cyan
Write-Host
Write-Host "Number of malware signatures specified in the SuspiciousFiles.xml: $($entries.Count)" -ForegroundColor White
Write-Host "Number of custom entries added for suspicious files:               $customIncludesCount" -ForegroundColor White
Write-Host "Number of custom entries added for trusted files:                  $customExcludesCount" -ForegroundColor White
Write-Host

if($List){
    $entries | ForEach-Object { Write-Host "$_" -ForegroundColor White }
    Write-Host "Total count: $($entries.Count)" -ForegroundColor Cyan
}

if($Search){
    CheckIfEntryExists -entryToCheck $entryToCheck
}

if($ExportCSV){
    $csvFilePath = "$ExportPath\SuspiciousFiles.csv"
    $entries | ForEach-Object { $_ -replace "<fileMask>|</fileMask>" } | Out-File -FilePath $csvFilePath
    Write-Host "Entries exported to $csvFilePath" -ForegroundColor Cyan
}

if ($CustomInclude){
    $customXmlContent    = [xml](Get-Content $customXMLPath)
      
    $includesNode = $customXmlContent.SelectSingleNode("//RansomwareExclusions/Includes")

    if ($includesNode -eq $null) {
        $includesNode    = $customXmlContent.CreateElement("Includes")
        $customXmlContent.DocumentElement.AppendChild($includesNode)
    }

    # Create and add
    $newItem             = $customXmlContent.CreateElement("Item")
    $newItem.InnerText   = $AddEntry
    $add                 = $includesNode.AppendChild($newItem)
    $customXmlContent.Save($customXMLPath)
    Write-Host "New entry '$AddEntry' added to the Includes section." -ForegroundColor White
    
    # Import into VBR
    Write-Host "Import into Veeam Backup & Replication" -ForegroundColor White
    Import-VBRMalwareDetectionExtensionList -Path $customXMLPath
}

if ($CustomExclude){
    $customXmlContent    = [xml](Get-Content $customXMLPath)
      
    $excludesNode = $customXmlContent.SelectSingleNode("//RansomwareExclusions/Excludes")

    if ($excludesNode -eq $null) {
        $includesNode    = $customXmlContent.CreateElement("Excludes")
        $customXmlContent.DocumentElement.AppendChild($excludesNode)
    }

    # Create and add
    $newItem             = $customXmlContent.CreateElement("Item")
    $newItem.InnerText   = $AddEntry
    $add                 = $excludesNode.AppendChild($newItem)
    $customXmlContent.Save($customXMLPath)
    Write-Host "New entry '$AddEntry' added to the Excludes section." -ForegroundColor White
    
    # Import into VBR
    Write-Host "Import into Veeam Backup & Replication" -ForegroundColor White
    Import-VBRMalwareDetectionExtensionList -Path $customXMLPath
}

