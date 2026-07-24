<# 
.NAME
    Veeam Backup & Replication - Tape Verification in Veeam Backup & Replication
.DESCRIPTION
    This script helps you to regularly check the status of tape backups, marks them as checked with time stamps and
    checks the tapes again after a certain time (default 270 days).
.NOTES  
    File Name  : vbr-tape-verification.ps1
    Author     : Stephan "Steve" Herzig
    Edited by Creatronics: Added check for online only Tapes
.VERSION
    1.0
#>
Param(
    [Parameter(Mandatory=$true)]
    $MediaPool,
    [Parameter(Mandatory=$false)]
    [int]$NumberofTapes = 1,
    [Parameter(Mandatory=$false)]
    [int]$CheckInterval = 270
)
Clear-Host
Connect-VBRServer -Server localhost

# Load tape information from JSON file or create new JSON file
$FilePath = "$($MediaPool).json"
if (-not (Test-Path $FilePath)) {
    $initialTapeInfo = Get-VBRTapeMedium -MediaPool $MediaPool | ForEach-Object {
        [PSCustomObject]@{
            TapeId                 = $_.Name
            MediaPool              = $MediaPool
            Verified               = $false
            LastVerificationDate   = $null
        }
    }
    $initialTapeInfo | ConvertTo-Json | Set-Content $FilePath
}

$tapeInfo = Get-Content $FilePath | ConvertFrom-Json

# Functions section
function Save-TapeInfo {
    param (
        [string]$FilePath,
        [string]$TapeId,
        [bool]$Verified,
        [datetime]$LastVerificationDate
    )

    $existingTape = $tapeInfo | Where-Object { $_.TapeId -eq $TapeId }
    if ($existingTape) {
        $existingTape.Verified             = $Verified
        $existingTape.LastVerificationDate = $LastVerificationDate
    } else {
        $tapeInfo += [PSCustomObject]@{
            TapeId                 = $TapeId
            MediaPool              = $MediaPool
            Verified               = $Verified
            LastVerificationDate   = $LastVerificationDate
        }
    }

    $tapeInfo | ConvertTo-Json | Set-Content $FilePath
}

function NeedsVerification {
    param (
        [string]$TapeId
    )

    $tape = $tapeInfo | Where-Object { $_.TapeId -eq $TapeId }
    Write-Host "Tape: $($tape)"
    Write-Host "Type: $($tape.Location.Type)"
    
    if ((-not $tape.Verified -or ((Get-Date) - $tape.LastVerificationDate).Days -ge $CheckInterval ) -and $tape.Location.Type -ne "None") {
        return $true
    }

    return $false
}

# Start script
$vbrTapes = Get-VBRTapeMedium -MediaPool $MediaPool

# Check for removed tapes
$tapeIdsInPool = $vbrTapes.Name
$tapesToRemove = @()

foreach ($tapeEntry in $tapeInfo) {
     if ($tapeEntry.MediaPool -eq $MediaPool -and $tapeEntry.TapeId -notin $tapeIdsInPool) {
        $tapesToRemove += $tapeEntry
    }
}

# Remove tapes that no longer exist in the specified media pool from the .json file
foreach ($tapeToRemove in $tapesToRemove) {
    $tapeInfo = $tapeInfo | Where-Object { $_ -ne $tapeToRemove }
}

$tapeInfo | ConvertTo-Json | Set-Content $FilePath

# Add new tapes to tape information
foreach ($tape in $vbrTapes) {
    $loc = $tape.Location
    $existingTape = $tapeInfo | Where-Object { $_.TapeId -eq $tape.Name }
    if (-not $existingTape) {
        $tapeInfo += [PSCustomObject]@{
            TapeId                 = $tape.Name
            MediaPool              = $MediaPool
            Verified               = $false
            LastVerificationDate   = $null
            Location               = $tape.Location
        }
    }else{
        #Write-Host ($existingTape | Format-List | Out-String) 
        if(-not $existingTape.Location){
            Add-Member -InputObject $existingTape -NotePropertyName Location -NotePropertyValue $tape.Location
        }else{
            $existingTape.Location = $tape.Location
        }
    }
}

$tapeInfo | ConvertTo-Json | Set-Content $FilePath

# Get tapes to verify
$tapesToVerify = $vbrTapes | Where-Object { NeedsVerification -TapeId $_.Name }

if ($tapesToVerify.Count -eq 0) {
    Write-Host "All tapes have been verified. Nothing to process." -ForegroundColor White
    
    $closestTapes = $tapeInfo | Where-Object { $_.LastVerificationDate -ne $null } | Sort-Object { (Get-Date) - $_.LastVerificationDate } | Select-Object -First 3
    if ($closestTapes.Count -gt 0) {
        Write-Host "Tapes closest to CheckInterval:"
        $closestTapes | Format-Table -AutoSize

        $closestTapes | Select-Object -First 3 | ForEach-Object {
            $nextVerificationDate = $_.LastVerificationDate.AddDays($CheckInterval)
            Write-Host "Next verification for tape $($_.TapeId) is due on $nextVerificationDate." -ForegroundColor Cyan
        }
    } else {
        Write-Host "No tapes have been verified yet." -ForegroundColor Yellow
    }
} else {
    # Verify tape(s)
    foreach ($tape in $tapesToVerify | Select-Object -First $NumberofTapes) {
        Write-Host "Starting Verification of Tape $($tape.Name)"
        Start-VBRTapeVerification -Medium $tape.Name
        Save-TapeInfo -FilePath $FilePath -TapeId $tape.Name -Verified $true -LastVerificationDate (Get-Date)
    }
}

#Disconnect-VBRServer
