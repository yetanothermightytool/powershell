<# 
.NAME
    Veeam Backup & Replication - Active Directory Backup Comparator
.DESCRIPTION
    The script is helpful for tracking changes in Active Directory data over time, comparing specific OUs with previous backups,
    and identifying any discrepancies between backup points. When the script runs for the first time, it creates a baseline data
    file for comparison. After starting it gathers data from both the regular container (cn=Users) and a specific Organizational Unit (OU)
    within the Active Directory. The script then compares the current data with the baseline data, detects any differences, and saves the 
    comparison results to JSON files. 
.EXAMPLE
    Compare Active Directory data for the Organizational Unit "Sales".

    PS > .\vbr-get-adchanges.ps1 -OrganizationUnit Sales
.NOTES  
    File Name  : vbr-get-adchanges.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12
.VERSION
    1.0
#>
param(
[Parameter(Mandatory = $true)]
[String] $OrganizationUnit
)
# Variables
$host.ui.RawUI.WindowTitle     = "Active Directory Backup Comparator"
$host.UI.RawUI.ForegroundColor = "White"
$baselineJsonFilePath          = "C:\Temp"
$resultJsonFilePath            = "C:\Temp"

function rpLister {
Param (
    [Parameter(Position = 0,Mandatory = $False)]
    [PSObject]
$Output = $Result
    )
    begin {
        $Global:n = 0
    }
    process {
        $RestoreTable = @{ Expression={ $Global:n;$Global:n++ };Label="Id";Width=5;Align="center" }, `
        @{ Expression={ $_.Name };Label="Server Name";Width=25;Align="left" }, `
        @{ Expression={ $_.CreationTime };Label="Creation Time";Width=25;Align="left" }, `
        @{ Expression={ $_.Type };Label="Type";Width=10;Align="left" }
    }
    end {
 
        Write-Host
        Write-Host "The following restore points were found...(newest first)" -ForegroundColor White
        Write-Host
        return $Output  | Format-Table $RestoreTable
    }
}
# end function

function Compare-DataWithPrevious {
    param (
        [Parameter(Mandatory = $true)]
        [array]$container,
        [string]$baselineJsonFilePath,
        [string]$resultJsonFilePath,
        [switch]$OutputJson
    )

    # Create an empty hashtable to store the count per type
    $typeCount = @{}

    # Loop through the entries and count the occurrences of each type
    foreach ($entry in $container) {
        $entryType = $entry.Type
        if ($entryType) {
            if ($typeCount.ContainsKey($entryType)) {
                $typeCount[$entryType]++
            } else {
                $typeCount[$entryType] = 1
            }
        }
    }

    # Print the table
    Write-Host "Type/Count  " -ForegroundColor Cyan
    
    foreach ($entryType in $typeCount.Keys) {
        Write-Host "$entryType $($typeCount[$entryType])" -ForegroundColor Cyan
    }

    if (-not $baselineJsonFilePath -or -not (Test-Path $baselineJsonFilePath)) {
        # If the baseline file path is not provided or does not exist, create it with the current data
        $baselineJsonData = $typeCount | ConvertTo-Json
        $baselineJsonData | Set-Content -Path $baselineJsonFilePath -Force
        Write-Host "Baseline file created: $baselineJsonFilePath"
    } else {
        # Load the baseline JSON data from the file
        $baselineJsonData = Get-Content -Raw -Path $baselineJsonFilePath | ConvertFrom-Json

        # Compare the current data with the baseline data
        $hasDifference = $false
        foreach ($entryType in $typeCount.Keys) {
            $currentCount = $typeCount[$entryType]
            $baselineCount = $baselineJsonData.$entryType
            if ($currentCount -ne $baselineCount) {
                Write-Host "Difference detected in backup data for $entryType. Baseline count: $baselineCount, Current count: $currentCount" -ForegroundColor Yellow
                $hasDifference = $true
            }
        }

        if (-not $hasDifference) {
            Write-Host "No differences detected between the baseline and backup data in" -ForegroundColor Green
        }
    }

    # Save the current data to the result file
    if ($OutputJson) {
        $jsonData = $typeCount | ConvertTo-Json
        $jsonData | Set-Content -Path $resultJsonFilePath -Force
        Write-Host "Comparison results have been saved to $resultJsonFilePath." -ForegroundColor Cyan
        Write-Host
    }
}

# Start
Clear-Host
Write-Host "----------------------------------------"
Write-Host "|  Active Directory Backup Comparator  |" 
Write-Host "----------------------------------------"

# Connect to VBR Server and get $restorepoint
Connect-VBRServer -Server localhost
$result           = Get-VBRApplicationRestorePoint -ActiveDirectory | Sort-Object CreationTime -Descending

# If no restore points have been found
if ($Result.Count -eq 0) {
	Write-Host 'Unable to locate any restore points for' $Scanhost 'in backup job' $Jobname 
    Disconnect-VBRServer
	Exit
} else {
# Present the result using the function rpLister
rpLister $Result
}
# Ask for the restore point to be scanned - Automatically select latest restore points after 30 seconds
$stopTime       = [datetime]::Now.AddSeconds(30)
$restorePointID = 0
Write-Host -NoNewline "Please select restore point (Id) - Automatically selects the latest restore point after 30 seconds: " -ForegroundColor Cyan

while ([datetime]::Now -lt $stopTime -and -not [console]::KeyAvailable) {
    Start-Sleep -Milliseconds 50
}

if ([console]::KeyAvailable) {
    $restorePointID = [console]::ReadLine()
    while (!($restorePointID -lt $Result.Count -and $restorePointID -ge 0)) {
             $restorePointID = [console]::ReadLine()
    }
} 

while ([console]::KeyAvailable) {
       [console]::ReadKey($true) | Out-Null 
}

$restorePointID = [int]$restorePointID

# Get the selected restore point
$selectedRp       = $Result | Select-Object -Index $restorePointID 

# Store the restore point's creation time in a variable
$restorePointCreationTime = $selectedRp.CreationTime


# Start the restore session & get the session information
Clear-Host
Start-VEADRestoreSession -RestorePoint $selectedRp
$session           = Get-VEADRestoreSession

#Get the domain information
$domain            = Get-VEADDomain -Session $session

# First let's get the stored data within the regular cn=Users,dc=<domain>,dc=<top level domain>
$parentcontainer   = Get-VEADContainer -Domain $domain -Name Users
$childcontainer    = Get-VEADContainer -Container $parentcontainer
$usersContainer    = Get-VEADItem -Container $parentcontainer

# Now the users for a specific OU
$ouParentcontainer = Get-VEADContainer -Domain $domain -Name $OrganizationUnit
$ouChildcontainer  = Get-VEADContainer -Container $ouParentcontainer
$ouContainer       = Get-VEADItem -Container $ouChildcontainer

# Format restorepoint information for storing it as filename information
$fileRp            = $restorePointCreationTime -replace "[:/ ]", "-"  

# Use function - Compare Baseline and create new file with the used restore point information (date & time)
Write-Host "Comparison for Built-IN Users"
Write-Host "-----------------------------"
Compare-DataWithPrevious -container $usersContainer -baselineJsonFilePath "$baselineJsonFilePath\Users-Baseline.json"  -resultJsonFilePath "$resultJsonFilePath\Users-Comparison-$fileRp.json" -OutputJson
Write-Host
Write-Host "Comparison for Organization Unit $OrganizationUnit"
Write-Host "--------------------------------------------------"
Compare-DataWithPrevious -container $ouContainer -baselineJsonFilePath "$baselineJsonFilePath\OU-$OrganizationUnit-Baseline.json" -resultJsonFilePath "$resultJsonFilePath\OU-$OrganizationUnit-Comparison-$fileRp.json" -OutputJson
Write-Host
Write-Host

# Stop the restore session - If somebody could explain me how to suppress the output...I tried many options.
Stop-VEADRestoreSession -Session $session

# Disconnect from the VBR Server
Disconnect-VBRServer
