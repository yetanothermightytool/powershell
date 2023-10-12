<# 
.NAME
    Veeam Backup & Replication - Detection Engine Includer
.DESCRIPTION
    This Powershell script removes the number of desired systems from the Detection Engine Exclusion list,
    so that they are scanned during the next backup run. On the next run, these systems will be added again. 
    This will continue until all excluded systems have been scanned at least once.
    
    Please add all systems to be scanned to the exclusion list manually before running the script for the first time.
 
.NOTES  
    File Name  : vbr-detection-engine-includer.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12.1
.VERSION
    1.0
#>
Param(
     [Parameter(Mandatory=$true)]
     $VMstoSCAN
     )

# Variables for script
$VBRserver                      = "localhost"
$csvFilePath                    = "D:\Scripts\vbr\object_status.csv"
$currentDateTime                = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Connect VBR Server
Connect-VBRServer -Server $VBRserver

# Get exclusion list. 
$objectNames     = @()
$excludedObjects = Get-VBRMalwareDetectionExclusion
foreach ($excludeObject in $excludedObjects) {
        $objectName = $excludeObject.name
        $objectNames += $objectName
      }

# Create the CSV file
if (!(Test-Path -Path $csvFilePath)) {
    $initialStatus = @()
    $objectNames | ForEach-Object {
        $initialStatus += [PSCustomObject]@{
            "ObjectName" = $_
            "Removed" = 0
            "Readded" = 0
        }
    }
    $initialStatus | Export-Csv -Path $csvFilePath -NoTypeInformation
}

# Import the CSV file
$objectStatus = Import-Csv -Path $csvFilePath

# Check if all removed and readded are 1 then reset the values
$allReady = ($objectStatus | Where-Object { $_.Removed -eq 1 -and $_.Readded -eq 1 }).Count -eq $objectStatus.Count

        if ($allReady) {
            # If all entries are "1","1," reset to "0","0"
            $objectStatus | ForEach-Object {
                $_.Removed = 0
                $_.Readded = 0
            }
        }

# Initialize counter
$scanCount = 0

# Check if object already got removed otherwise remove and have the VM scanned
foreach ($object in $objectStatus) {
    if ($object.Removed -eq 0 -and $scanCount -lt $VMstoSCAN) {
        
        Write-Host "Removing $($object.ObjectName)"
        $remove = Get-VBRMalwareDetectionExclusion | Where-Object { $_.Name -eq $($object.ObjectName) }
        Remove-VBRMalwareDetectionExclusion -Exclusion $remove      
        $object.Removed = 1

        # Increment the scan counter
        $scanCount++
    } elseif ($object.Removed -eq 1 -and $object.Readded -eq 0) {
        
        Write-Host "Readding $($object.ObjectName)"
        $readd = Find-VBRViEntity -Name $($object.ObjectName)
        Add-VBRMalwareDetectionExclusion -Entity $readd -Note "Readded by script - $currentDateTime"
        $object.Readded = 1
    }
}

# Save the updated status back to the CSV file
$objectStatus | Export-Csv -Path $csvFilePath -NoTypeInformation

Disconnect-VBRServer
