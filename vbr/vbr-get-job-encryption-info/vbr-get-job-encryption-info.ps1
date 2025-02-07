function Get-BackupJobEncryptionInfo {
    param (
        [string]$JobType
    )

    if ($JobType -eq 'VMware') {
        $jobs = Get-VBRJob -WarningAction SilentlyContinue |
            Where-Object { $_.TypeToString -eq 'VMware Backup' } |
            ForEach-Object {
                $cryptoKey = $_.UserCryptoKey
                
                $encryptionStatus = if (-not $cryptoKey -or -not $cryptoKey.Id) {
                    'Unencrypted'
                } else {
                    'Enabled'
                }

                $keyType = if ($cryptoKey -and $cryptoKey.Id) { $cryptoKey.KeyType } else { '' }
                $modificationDate = if ($cryptoKey -and $cryptoKey.Id) { $cryptoKey.ModificationDateUtc } else { '' }

                [PSCustomObject]@{
                    Name                 = $_.GetJobDisplayName()
                    Description          = $_.Description
                    TargetRepository     = ($_.GetBackupTargetRepository()).Name
                    TargetRepositoryPath = ($_.GetBackupTargetRepository()).Path
                    EncryptionStatus     = $encryptionStatus
                    KeyType              = $keyType
                    ModificationDateUtc  = $modificationDate
                }
            }
        
        if (-not $jobs) {
            Write-Host "No backup job type 'VMware' found."
        } else {
            $jobs | Format-Table -AutoSize
        }
    }
    elseif ($JobType -eq 'Object Storage Backup') {
        $jobs = Get-VBRJob -WarningAction SilentlyContinue |
            Where-Object { $_.TypeToString -eq 'Object Storage Backup' } |
            ForEach-Object {
                $cryptoKey = $_.UserCryptoKey
                
                $encryptionStatus = if (-not $cryptoKey -or -not $cryptoKey.Id) {
                    'Unencrypted'
                } else {
                    'Enabled'
                }

                $keyType = if ($cryptoKey -and $cryptoKey.Id) { $cryptoKey.KeyType } else { '' }
                $modificationDate = if ($cryptoKey -and $cryptoKey.Id) { $cryptoKey.ModificationDateUtc } else { '' }

                [PSCustomObject]@{
                    Name                 = $_.GetJobDisplayName()
                    Description          = $_.Description
                    TargetRepository     = ($_.GetBackupTargetRepository()).Name
                    TargetRepositoryPath = ($_.GetBackupTargetRepository()).Path
                    EncryptionStatus     = $encryptionStatus
                    KeyType              = $keyType
                    ModificationDateUtc  = $modificationDate
                }
            }
        
        if (-not $jobs) {
            Write-Host "No backup job type 'Object Storage' found."
        } else {
            $jobs | Format-Table -AutoSize
        }
    }
    elseif ($JobType -eq 'File Backup') {
        $jobs = Get-VBRJob -WarningAction SilentlyContinue |
            Where-Object { $_.TypeToString -eq 'File Backup' } |
            ForEach-Object {
                $cryptoKey = $_.UserCryptoKey
                
                $encryptionStatus = if (-not $cryptoKey -or -not $cryptoKey.Id) {
                    'Unencrypted'
                } else {
                    'Enabled'
                }

                $keyType = if ($cryptoKey -and $cryptoKey.Id) { $cryptoKey.KeyType } else { '' }
                $modificationDate = if ($cryptoKey -and $cryptoKey.Id) { $cryptoKey.ModificationDateUtc } else { '' }

                [PSCustomObject]@{
                    Name                 = $_.GetJobDisplayName()
                    Description          = $_.Description
                    TargetRepository     = ($_.GetBackupTargetRepository()).Name
                    TargetRepositoryPath = ($_.GetBackupTargetRepository()).Path
                    EncryptionStatus     = $encryptionStatus
                    KeyType              = $keyType
                    ModificationDateUtc  = $modificationDate
                }
            }
        
        if (-not $jobs) {
            Write-Host "No backup job type 'File Backup' found."
        } else {
            $jobs | Format-Table -AutoSize
        }
    }
    elseif ($JobType -eq 'Agent') {
        $jobs = Get-VBRComputerBackupJob |
            ForEach-Object {
                $encryptionStatus = if (-not $_.StorageOptions.EncryptionEnabled) {
                    'Unencrypted'
                } else {
                    'Enabled'
                }

                $cryptoKey = $_.StorageOptions.EncryptionKey
                $keyType = if ($cryptoKey) { $cryptoKey.KeyType } else { '' }
                $modificationDate = if ($cryptoKey) { $cryptoKey.ModificationDateUtc } else { '' }

                [PSCustomObject]@{
                    Name                 = $_.Name
                    Description          = $_.BackupRepository.Description
                    TargetRepository     = $_.BackupRepository.Name
                    TargetRepositoryPath = $_.BackupRepository.FriendlyPath
                    EncryptionStatus     = $encryptionStatus
                    KeyType              = $keyType
                    ModificationDateUtc  = $modificationDate
                }
            }
        
        if (-not $jobs) {
            Write-Host "No backup job type 'Agent' found."
        } else {
            $jobs | Format-Table -AutoSize
        }
    }
    else {
        Write-Host "Invalid job type specified. Use 'VMware', 'Agent', 'File Backup', or 'Object Storage Backup'."
    }
}
