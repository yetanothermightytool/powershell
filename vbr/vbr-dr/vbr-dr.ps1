param (
    [switch]$ServiceCheck,
    [switch]$Restore,
    [switch]$DBUpdate,
    [String]$cfgBackupPath      = "<path to the cfg .bco files>",
    [String]$unattendedXmlPath  = "<path to unattended.xml>",
    [String]$securePasswordPath = "<path to secure.txt>",
	[String]$srcBkpAdmin        = "Administrator"
	[String]$dstBkpAdmin        = "Administrator"
)
# General Script Settings
$vbrInstallDir     = "C:\Program Files\Veeam\Backup and Replication\Backup"
$bcoFile           = Get-ChildItem -Path $cfgBackupPath -Filter *.bco | Select-Object -Last 1
[xml]$xmlContent   = Get-Content -Path $unattendedXmlPath
$password          = Get-Content $securePasswordPath | ConvertTo-SecureString
$plainPassword     = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))

# PostgreSQL DB update parameters
$psqlPath          = "C:\Program Files\PostgreSQL\15\bin"
$psqlHost          = "localhost"
$serverName        = hostname
$database          = "VeeamBackup"
$dbUser            = "postgres"
$env:PGPASSWORD    = $plainPassword
$table             = "backup.security.accounts"
$userSID           = (Get-WmiObject Win32_UserAccount -Filter "name='$dstBkpAdmin'").sid

### VBR Service Check - Have just the necessary services running ###
function VBRServiceCheck{

$allServices     = Get-Service -Name "Veeam*"
# Specify the services for migrating/restoring the Configuration Backup
$servicesToCheck = @("VeeamTransportSvc", "VeeamDeploySvc")

    foreach ($service in $allServices) {
        
        if ($service.Status -eq 'Running') {
            Write-Host "$($service.DisplayName) is running."

            if ($service.Name -in $servicesToCheck) {
                Write-Host "$($service.DisplayName) is one of the services to check."
            
            } else {
                
                Write-Host "Stopping $($service.DisplayName)..."
                Stop-Service -Name $service.Name -Force
                Write-Host "$($service.DisplayName) stopped."
            }
        } else {
            Write-Host "$($service.DisplayName) is stopped."
        }
    }

    $runningServices = $allServices | Where-Object { $_.Name -in $servicesToCheck -and $_.Status -eq 'Running' }

    if ($runningServices.Count -ne $servicesToCheck.Count) {
        $servicesToStop = $allServices | Where-Object { $_.Name -notin $servicesToCheck -and $_.Status -eq 'Running' }

        foreach ($serviceToStop in $servicesToStop) {
            Write-Host "Stopping $($serviceToStop.DisplayName)..."
            Stop-Service -Name $serviceToStop.Name -Force
            Write-Host "$($serviceToStop.DisplayName) stopped."
        }
    }

    Write-Host "Service check complete."
    
}

### Restore Configuration Backup ###
function cfgRestore{

# XML File check and adjustments if necessary
$unattendedElement = $xmlContent.SelectSingleNode('//unattendedConfigurationRestore')
    
    if ($unattendedElement -ne $null) {
        $modeAttributeValue = $unattendedElement.GetAttribute('mode')

        if ($modeAttributeValue -ne 'migrate') {
            $unattendedElement.SetAttribute('mode', 'migrate')
        }
    }

    $encPassword = $xmlContent.SelectNodes('//property[@name="BACKUP_PASSWORD"]')
	    if ($encPassword -ne $null) {
		    $encPassword.SetAttribute('value', $plainPassword)
	    }
    
    $dbEngine = $xmlContent.SelectNodes('//property[@name="SQLSERVER_ENGINE"]')
	    if ($dbEngine -ne $null) {
		    $dbEngine.SetAttribute('value', 'postgresql')
	    }

    $dbServer = $xmlContent.SelectNodes('//property[@name="DATABASE_SERVER"]')
	    if ($dbServer -ne $null) {
		    $dbServer.SetAttribute('value', 'localhost:5432')
	    }

    $cfgFile = $xmlContent.SelectNodes('//property[@name="CONFIGURATION_FILE"]')
	    if ($cfgFile -ne $null) {
		    $cfgFile.SetAttribute('value', $bcoFile.FullName)
	    }

    $restoreMode = $xmlContent.SelectNodes('//property[@name="SWITCH_TO_RESTORE_MODE"]')
	    if ($restoreMode -ne 0) {
		    $restoreMode.SetAttribute('value', 0)
	    }

    $restoreBkp = $xmlContent.SelectNodes('//property[@name="RESTORE_BACKUPS"]')
	    if ($restoreBkp -ne 0) {
		    $restoreBkp.SetAttribute('value', 1)
	    }

    $restoreSess = $xmlContent.SelectNodes('//property[@name="RESTORE_SESSIONS"]')
	    if ($restoreSess -ne 0) {
		    $restoreSess.SetAttribute('value', 1)
	    }

    $bkpExisting = $xmlContent.SelectNodes('//property[@name="BACKUP_EXISTING_DATABASE"]')
	    if ($bkpExisting -ne 0) {
		    $bkpExisting.SetAttribute('value', 0)
	    }

    $svcAutostart = $xmlContent.SelectNodes('//property[@name="SERVICES_AUTOSTART"]')
	    if ($svcAutostart -ne 0) {
		    $svcAutostart.SetAttribute('value', 0)
	    } 

    $overwriteExisting = $xmlContent.SelectNodes('//property[@name="OVERWRITE_EXISTING_DATABASE"]')
	    if ($overwriteExisting -ne 1) {
		    $overwriteExisting.SetAttribute('value', 1)
	    }

    $stopProc = $xmlContent.SelectNodes('//property[@name="STOP_PROCESSES"]')
	    if ($stopProc -ne 1) {
		    $stopProc.SetAttribute('value', 1)
	    } 
 
    $xmlContent.Save($unattendedXmlPath)

    # Execute restore
    & "$vbrInstallDir\Veeam.Backup.Configuration.UnattendedRestore.exe" /file:$unattendedXmlPath
    
    $resetPassword = $xmlContent.SelectNodes('//property[@name="BACKUP_PASSWORD"]')
	    if ($resetPassword -ne $null) {
		    $resetPassword.SetAttribute('value', "dummy")
	    }
    $xmlContent.Save($unattendedXmlPath)

}

### Update DB
function dbUpdate{


    $sqlQueryId     = "SELECT * FROM \`"$table\`" WHERE name = '$srcBkpAdmin';"
    $queryResult    = & "$psqlPath\psql.exe" -h $psqlHost -d $database -U $dbUser -t -A -c $sqlQueryId


    if ($queryResult.Count -gt 0) {
            
        $updateUserName       = "UPDATE \`"$table\`" SET nt4_name = '$serverName\$dstBkpAdmin' WHERE name = '$srcBkpAdmin';"
        & "$psqlPath\psql.exe" -h $psqlHost -d $database -U $dbUser -c $updateUserName

        $updateSID       = "UPDATE \`"$table\`" SET sid = '$userSID' WHERE name = '$srcBkpAdmin';"
        & "$psqlPath\psql.exe" -h $psqlHost -d $database -U $dbUser -c $updateSID
    }
    else {
        Write-Host "No matching rows found for '$specificValue'." -ForegroundColor Yellow
    }

}

### Script
Clear-Host
if($ServiceCheck){
Write-Host "###################################" -ForegroundColor White
Write-Host "#        Checking Services        #" -ForegroundColor White
Write-Host "###################################" -ForegroundColor White
VBRServiceCheck
}
if($Restore){
Write-Host "###################################" -ForegroundColor White
Write-Host "#        Config DB Restore        #" -ForegroundColor White
Write-Host "###################################" -ForegroundColor White
Write-Host 
Write-Host "Using configuration backup $bcoFile.Name"
cfgRestore
}
if($DBUpdate){
Write-Host "###################################" -ForegroundColor White
Write-Host "#         Update Database         #" -ForegroundColor White
Write-Host "###################################" -ForegroundColor White
dbUpdate
}

