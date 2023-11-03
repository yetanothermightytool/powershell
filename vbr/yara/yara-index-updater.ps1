<# 
.NAME
    YARA Index File Updater
.DESCRIPTION
    This script creates or updates the index.yar file, which can then be used for a YARA scan. It will include all
    YARA rules in the path C:\Program Files\Veeam\Backup and Replication\Backup\YaraRules\ (the index.yar file is stored in the same path)
.NOTES  
    File Name  : yara-index-updater.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell
.VERSION
    1.0
#>
$vbrYaraRulePath = "C:\Program Files\Veeam\Backup and Replication\Backup\YaraRules\"
$indexFile       = Join-Path -Path $vbrYaraRulePath -ChildPath "index.yar"
$yarFiles        = Get-ChildItem -Path $vbrYaraRulePath | Where-Object { $_.Extension -ne ".yar" -and $_.Name -ne "index.yar" }

Set-Content -Path $indexFile -Value $null

foreach ($yarFile in $yarFiles) {
        $includeStatement = 'include "{0}"' -f $yarFile.FullName
        Add-Content -Path $indexFile -Value $includeStatement
}

Write-Host "Index file created or updated: $indexFile"
