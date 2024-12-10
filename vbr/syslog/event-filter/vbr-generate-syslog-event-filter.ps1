param (
    [Parameter(Mandatory = $false)]
    [string[]] $Category,              
    [Parameter(Mandatory = $true)]
    [string[]] $Filter,                
    [Parameter(Mandatory = $true)]
    [string] $InputCsv,                
    [Parameter(Mandatory = $true)]
    [string] $OutputFile,
    [Parameter(Mandatory = $false)]
    [int[]] $EventId                  
)

$data = Import-Csv -Path $InputCsv

if ($EventId) {
    $filteredData = $data | Where-Object { $EventId -contains $_.'Event ID' }
} elseif ($Category -and $Category -ne "All") {
    $filteredData = $data | Where-Object { $Category -contains $_.Category }
} elseif ($Category -eq "All") {
    $filteredData = $data
} else {
    Write-Host "You must specify either -Category or -EventId." -ForegroundColor Red
    exit 1
}

# Check if any data was filtered
$filteredCount = $filteredData.Count
if ($filteredCount -eq 0) {
    Write-Host "No matching data found for the specified filters." -ForegroundColor Yellow
    exit 0
}

Write-Host "Number of filtered events: $filteredCount"

# Generate XML output
$output = @("<SyslogFilteredEvents>")

foreach ($row in $filteredData) {
    $filterInfo    = if ($Filter -contains "Info") { "True" } else { "False" }
    $filterWarning = if ($Filter -contains "Warning") { "True" } else { "False" }
    $filterError   = if ($Filter -contains "Error") { "True" } else { "False" }
    $xmlEntry      = @"
    <FilteredEvent EventId="$($row.'Event ID')" FilterInfo="$filterInfo" FilterWarning="$filterWarning" FilterError="$filterError" />
"@
    $output += $xmlEntry
}

$output += "</SyslogFilteredEvents>"

# Save XML to file
try {
    $output | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "Filter list saved to $OutputFile"
} catch {
    Write-Host "Error: Unable to write to the output file. Please check the file path and permissions." -ForegroundColor Red
    exit 1
}

