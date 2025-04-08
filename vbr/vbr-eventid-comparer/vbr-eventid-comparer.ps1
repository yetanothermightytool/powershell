param (
   [Parameter(Mandatory = $true, HelpMessage = "Path to the first event definition JSON file.")]
   [string]$File1,
   [Parameter(Mandatory = $true, HelpMessage = "Path to the second event definition JSON file.")]
   [string]$File2
)
# Load JSON files
try {
   $old = Get-Content $File1 -Raw | ConvertFrom-Json
   $new = Get-Content $File2 -Raw | ConvertFrom-Json
} catch {
   Write-Host "Error reading JSON files: $_" -ForegroundColor Red
   exit 1
}
# Build hashtables by EventID
$oldMap = @{}
$newMap = @{}
foreach ($e in $old) { if ($e.EventID) { $oldMap[$e.EventID] = $e } }
foreach ($e in $new) { if ($e.EventID) { $newMap[$e.EventID] = $e } }

# Find added events
$added = $new | Where-Object { -not $oldMap.ContainsKey($_.EventID) }

# Find removed events
$removed = $old | Where-Object { -not $newMap.ContainsKey($_.EventID) }

# Find modified events (Name or Description changed)
$modified = @()
foreach ($id in $newMap.Keys) {
   if ($oldMap.ContainsKey($id)) {
       $oldEvent = $oldMap[$id]
       $newEvent = $newMap[$id]
       if ($oldEvent.Name -ne $newEvent.Name -or $oldEvent.Description -ne $newEvent.Description) {
           $modified += [PSCustomObject]@{
               EventID        = $id
               OldName        = $oldEvent.Name
               NewName        = $newEvent.Name
               OldDescription = $oldEvent.Description
               NewDescription = $newEvent.Description
           }
       }
   }
}
# Detect new fields in Data1–Data20
$fieldChanges = @()
foreach ($id in $newMap.Keys) {
   if ($oldMap.ContainsKey($id)) {
       $oldFields = 1..20 | ForEach-Object { $oldMap[$id]."Data$_" } | Where-Object { $_ -and $_ -ne "" }
       $newFields = 1..20 | ForEach-Object { $newMap[$id]."Data$_" } | Where-Object { $_ -and $_ -ne "" }
       $addedFields = $newFields | Where-Object { $_ -notin $oldFields }
       if ($addedFields.Count -gt 0) {
           $fieldChanges += [PSCustomObject]@{
               EventID   = $id
               EventName = $newMap[$id].Name
               NewFields = ($addedFields -join ", ")
           }
       }
   }
}

# Output 
Write-Host "`n=== Added Events ===" -ForegroundColor Green
$added | Sort-Object {[int]$_.EventID} | Select-Object EventID, @{Name="Name"; Expression = { $_.Name }} | Format-Table -AutoSize
Write-Host "`n=== Removed Events ===" -ForegroundColor Red
$removed | Sort-Object {[int]$_.EventID} | Select-Object EventID, @{Name="Name"; Expression = { $_.Name }} | Format-Table -AutoSize
Write-Host "`n=== Modified Events (Name or Description) ===" -ForegroundColor Yellow
$modified | Sort-Object {[int]$_.EventID} |  Format-Table EventID, OldName, NewName -AutoSize
Write-Host "`n=== Events with Newly Added Fields ===" -ForegroundColor Cyan
$fieldChanges | Sort-Object {[int]$_.EventID} | Format-Table EventID, EventName, NewFields -AutoSize 
