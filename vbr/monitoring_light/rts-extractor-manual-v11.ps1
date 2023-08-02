param(
    [Parameter(Mandatory = $false)]
    [String] $DaysBack = "30"
)

# Variables
$logFilePath = "RTS.ResourcesUsage.log"
$resourceUsages = @()

# Read the log file line by line
foreach ($line in Get-Content -Path $logFilePath) {
    $usageLinePattern = "\[.*?\] <.*?> .*? \| (.*?) +\| (\d+) +\| .*? \| (.*?) +\|"
    if ($line -match $usageLinePattern) {
        $resourceName = $matches[1].Trim()
        $usage = $matches[2].Trim()
        $resourceType = $matches[3].Trim()

        if (![string]::IsNullOrWhiteSpace($resourceName) -and ![string]::IsNullOrWhiteSpace($usage)) {
            $usageValue = 0

            if ([int]::TryParse($usage, [ref]$usageValue)) {
                # Extract the date and hour from the log line
                 $dateTimePattern = "\[(\d{2}.\d{2}.\d{4} \d{2}:\d{2}:\d{2})\]"
                if ($line -match $dateTimePattern) {
                    $dateTime = [DateTime]::ParseExact($matches[1], "dd.MM.yyyy HH:mm:ss", $null)

                    # Filter by date within the last xx days (Default is 30)
                    if ($dateTime -ge (Get-Date).AddDays(-$DaysBack)) {
                        $hourKey = $dateTime.ToString("yyyy-MM-dd HH")
                        $resourceUsage = [PSCustomObject]@{
                            Date = $dateTime.ToString("yyyy-MM-dd")
                            Hour = $dateTime.ToString("HH")
                            Resource = $resourceName
                            Usage = $usageValue
                            Type = $resourceType
                        }
                        $resourceUsages += $resourceUsage
                    }
                }
            }
        }
    }
}

# Output the resource usages
#$resourceUsages

# Define the path for the CSV file
$csvFilePath = "ResourceUsages.csv"

# Export the data to a CSV file
$resourceUsages | Export-Csv -Path $csvFilePath -NoTypeInformation
