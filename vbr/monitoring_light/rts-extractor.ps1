param(
    [Parameter(Mandatory = $false)]
    [String] $DaysBack   = "30"
)

# Variables
$logFilePath             = "C:\ProgramData\Veeam\Backup\RTS.ResourcesUsage.log"
$resourceUsages          = @{}
$usageLinePattern        = "\[.*?\] <.*?> .*? \| (.*?) +\| (\d+) +\| .*? \| (.*?) +\|"
$dateTimePattern         = "\[(\d{2}.\d{2}.\d{4} \d{2}:\d{2}:\d{2}.\d{3})\]"

# Read the log file line by line
foreach ($line in Get-Content -Path $logFilePath) {
    if ($line -match $usageLinePattern) {
        $resourceName = $matches[1].Trim()
        $usage = $matches[2].Trim()
        $resourceType = $matches[3].Trim()

        if (![string]::IsNullOrWhiteSpace($resourceName) -and ![string]::IsNullOrWhiteSpace($usage)) {
            $usageValue = 0

            if ([int]::TryParse($usage, [ref]$usageValue) -and $line -match $dateTimePattern) {
                $dateTime = [DateTime]::ParseExact($matches[1], "dd.MM.yyyy HH:mm:ss.fff", $null)

                # Filter by date within the last xx days (Default is 30)
                if ($dateTime -ge (Get-Date).AddDays(-$DaysBack)) {
                    $hourKey = $dateTime.ToString("yyyy-MM-dd HH")

                    # Create or update the cumulative usage for the hour and resource
                    if ($resourceUsages.ContainsKey($hourKey)) {
                        if ($resourceUsages[$hourKey].ContainsKey($resourceName)) {
                            $resourceUsages[$hourKey][$resourceName] += $usageValue
                        }
                        else {
                            $resourceUsages[$hourKey][$resourceName] = $usageValue
                        }
                    }
                    else {
                        $resourceUsages[$hourKey] = @{
                            $resourceName = $usageValue
                        }
                    }
                }
            }
        }
    }
}

# Output the resource usages
$resourceUsages.GetEnumerator() | ForEach-Object {
    $hourKey   = $_.Key
    $hourUsage = $_.Value

    foreach ($resourceEntry in $hourUsage.GetEnumerator()) {
        $resourceName  = $resourceEntry.Key
        $usageValue    = $resourceEntry.Value

        $resourceUsage = [PSCustomObject]@{
            Date       = $hourKey.Substring(0, 10)
            Hour       = $hourKey.Substring(11)
            Resource   = $resourceName
            Usage      = $usageValue
            Type       = ""
        }
        $resourceUsage
    }
}
