param (
    [switch]$List,
    [switch]$Search,
    [String]$entryToCheck,
    [Switch]$Export
)
Clear-Host
# XML file handling - Default VBR intallation directory is the C: drive
$suspiciousXMLFile = "d:\Program Files\Veeam\Backup and Replication\Backup\SuspiciousFiles.xml"
$xmlContent        = Get-Content -Path $suspiciousXMLFile -Raw
$entries           = Select-String -InputObject $xmlContent -Pattern "<fileMask>.*?</fileMask>" -AllMatches | ForEach-Object { $_.Matches.Value }

# Function to check if a specific entry exists
function CheckIfEntryExists($entryToCheck)
 {
  
    $found = $entries -match "(?s)<FileMask>.*?$entryToCheck.*?</FileMask>"
        
    if ($found) {
        Write-Host "Entry '$entryToCheck' exists."
        Write-Host $found
    } else {
        Write-Host "Entry '$entryToCheck' does not exist."
    }
}

if($List){
Write-Host "Found entries:"
$entries | ForEach-Object { Write-Host $_ }
Write-Host "Total count: $($entries.Count)"
}

if($Search){
CheckIfEntryExists -entryToCheck $entryToCheck
}

if($Export){
$csvFilePath = "C:\Temp\SuspiciousFiles.csv"
$entries | ForEach-Object { $_ -replace "<fileMask>|</fileMask>" } | Out-File -FilePath $csvFilePath
Write-Host "Entries exported to $csvFilePath"
}
