function Get-BackupJobEncryptionInfo {
    param(
	[Parameter(Mandatory = $false)]
		[ValidateSet("Vmware","Object Storage Backup","File Backup","Agent")]
		[string]$JobType
	)
	
	switch ($JobType) {
		{$_ -like "*Vmware*"} {	$typeToString = "Vmware Backup"	}
		{$_ -like "*Object*"} {$typeToString = "Object Storage Backup"}
		{$_ -like "*File*"} {$typeToString = "File Backup"}
		{$_ -like "*Agent*"} {$typeToString = "Agent"}
	}	
	If($JobType -eq "Agent"){
		$jobs = Get-VBRComputerBackupJob
	} else {
		$jobs = Get-VBRJob -WarningAction SilentlyContinue | Where-Object {$_.TypeToString -eq $typeToString} 
	}
	If(-not($Jobs)){
		Write-Host "No backup of job type $($typeToString) found."
		Break
	}
	$encryptedReport = @()
	Foreach($j in $jobs){
		If($j.TargetType -eq "SanSnapshot"){Continue}
		If($typeToString -eq "Agent"){$cryptoKey = $j.StorageOptions.EncryptionKey} else {$cryptoKey = $j.UserCryptoKey}
		If(-not $cryptoKey -or -not $cryptoKey.id){
			$encryptionStatus = 'Unencrypted'
		} else { 
			$encryptionStatus = 'Enabled'
		}
		$keytype = $cryptoKey.KeyType
		$modificationDateUTC = $cryptoKey.ModificationDateUTC
		If($typeToString -eq "Agent"){
			$targetRepository = $j.BackupRepository.Name
			$targetPath = $j.BackupRepository.FriendlyPath
		} else {
			$targetRepository = $j.GetBackupTargetRepository().Name
			$targetPath = $j.GetBackupTargetRepository().Path
		}
		$data = [PSCustomObject]@{
                    Name                 = $j.Name
                    TargetRepository     = $targetRepository
                    TargetRepositoryPath = $targetPath
                    EncryptionStatus     = $encryptionStatus
                    KeyType              = $keyType
                    ModificationDateUtc  = $modificationDateUTC
				}
		$encryptedReport += $data
		}
		return $encryptedReport
	}
