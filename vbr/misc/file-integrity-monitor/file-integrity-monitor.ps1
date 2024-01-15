param (
    [switch]$Baseline,
    [switch]$Scan,
    [String]$Interval        = "30",
    [String]$ScriptToExecute = "demo-malware-detection-api.ps1",
    [int]$MaxExecutions      = 3
)
Clear-Host
# Credits to https://github.com/joshmadakor1/PowerShell-Integrity-FIM/blob/main/Fim.ps1

# Variables
$host.ui.RawUI.WindowTitle = "YAMT - File Integrity Monitor"
$executedScripts           = @{}
$global:executionsCount    = 0

Function Execute-Script {
    param (
        [string]$file,
        [string]$Action
    )

    if ($global:executionsCount -lt $MaxExecutions -and $executedScripts[$file] -lt $MaxExecutions) {
        Start-Process powershell.exe -ArgumentList "-File $ScriptToExecute -FileChanged $file -Action `"$Action`""
        Write-Host "Executing script for $file (Execution $($executedScripts[$file] + 1))"
        $executedScripts[$file]++
        $global:executionsCount++
    } else {
        Write-Host "Maximum executions reached for $file" -ForegroundColor Yellow
    }
}

Function Calculate-File-Hash {
    param (
        [string]$filepath
    )

    $filehash = Get-FileHash -Path $filepath -Algorithm SHA512
    return $filehash
}

Function Erase-Baseline-If-Already-Exists {
    $baselineExists = Test-Path -Path .\baseline.txt

    if ($baselineExists) {
        # Delete it
        Remove-Item -Path .\baseline.txt
    }
}

if ($Baseline) {
    # Delete baseline.txt if it already exists
    Erase-Baseline-If-Already-Exists

    # Read directory paths from the text file and store in $directories variable
    $directories = Get-Content -Path ".\path_list.txt" | Where-Object { $_ -ne '' }

    # For each directory, enumerate files, calculate the hash, and write to baseline.txt
    foreach ($dir in $directories) {
        $files = Get-ChildItem -Path $dir -File -Recurse
        foreach ($file in $files) {
            $hash = Calculate-File-Hash $file.FullName
            "$($file.FullName)|$($hash.Hash)" | Out-File -FilePath .\baseline.txt -Append
        }
    }
}

if ($Scan) {
    $fileHashDictionary = @{}

    # Load file|hash from baseline.txt and store them in a dictionary
    $filePathsAndHashes = Get-Content -Path .\baseline.txt

    foreach ($line in $filePathsAndHashes) {
        $splitLine = $line -split '\|'
        if ($splitLine.Count -eq 2) {
            $fileHashDictionary[$splitLine[0]] = $splitLine[1]
        }
    }

    # Begin (continuously) monitoring files with saved Baseline
    while ($true) {
        Start-Sleep -Seconds $Interval

        # Read directory paths from the text file and store in $directories variable
        $directories = Get-Content -Path ".\path_list.txt" | Where-Object { $_ -ne '' }

        # Detect deleted files
        foreach ($key in $fileHashDictionary.Keys) {
            if (-not (Test-Path -Path $key)) {
                # One of the baseline files must have been deleted, notify the user
                Write-Host "$($key) has been deleted!" -ForegroundColor DarkRed -BackgroundColor Gray
            
                Execute-Script -file $key -action "File deleted"
            }
        }

        foreach ($dir in $directories) {
            $files = Get-ChildItem -Path $dir -File -Recurse
            foreach ($file in $files) {
                $hash = Calculate-File-Hash $file.FullName

                # Notify if a new file has been created
                if ($hash -and $hash.Path -and -not $fileHashDictionary.ContainsKey($file.FullName)) {
                    Write-Host "$($file.FullName) has been created!" -ForegroundColor Green
                }
                else {
                    # Notify if a new file has been changed
                    if ($hash -and $hash.Path -and $fileHashDictionary.ContainsKey($file.FullName) -and $fileHashDictionary[$file.FullName] -ne $hash.Hash) {
                        # File has been compromised!, notify the user
                        Write-Host "$($file.FullName) has changed!!!" -ForegroundColor Yellow

                        # Check if the script has already been executed for this file
                        
                        Execute-Script -file $file.FullName -Action "File changed"
                    }
                }
            }
        }
    }
}
