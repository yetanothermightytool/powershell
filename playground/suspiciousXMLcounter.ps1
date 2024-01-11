# XML file handling - Default VBR intallation directory is the C: drive
$suspiciousXMLFile = "C:\Program Files\Veeam\Backup and Replication\Backup\SuspiciousFiles.xml"
$xmlContent        = Get-Content -Path $suspiciousXMLFile -Raw

# Get and count entries
$entries           = Select-String -InputObject $xmlContent -Pattern "<fileMask>.*?</fileMask>" -AllMatches | ForEach-Object { $_.Matches.Value }
Write-Host "Found entries:"
$entries | ForEach-Object { Write-Host $_ }
Write-Host "Total count: $($entries.Count)"
