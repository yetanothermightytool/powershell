<# 
.NAME
    Veeam Backup & Replication - Backups stored on tape information
.DESCRIPTION
    This script shows the Veeam backup data stored on a specified tape
.EXAMPLES
    Get the stored backup files on tape with barcode L00004L6
    .\vbr-get-tapeinfo.ps1 -Barcode H00004L5
    Get information from multiple tapes
    .\vbr-get-tapeinfo.ps1 -Barcode H00004L5,H00005L5

    Get information from all tapes (might be slow)
    .\vbr-get-tapeinfo.ps1
.NOTES  
    File Name  : vbr-get-tapeinfo.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell, Veeam Backup & Replication v12 - Uses undocumented functions/no support
.VERSION
1.0  
#>
param(
[Parameter(Mandatory = $false)]
[string[]]$Barcode
      )

# Preparations
$TapeList                 = @()

# Connect VBR Server
Connect-VBRServer -Server localhost

# Get the Tape Backups
$backups                  = Get-VBRTapeBackup -WarningAction Ignore| Where-Object {$_.VMCount -ne 0}
$backupJobs               = $backups.JobName

# Loop through the results
foreach ($backupJob in $backupJobs){
$rps                      = Get-VBRRestorePoint -Backup $backupJob
    # Loop through the Restore Points and build the result list
    foreach ($rp in $rps) {
    $dbTapeOib            = [Veeam.Backup.DBManager.CDBManager]::Instance.TapeOibs.GetMediaTapeNamesByOibs($rp.Id)
    $tapeName             = $dbTapeOib.Values
    $TapeList            += New-Object psobject -Property @{
                            JobName      = $backupJob #not used
                            VMName       = $rp.Name   #not used
                            Content      = ($rp.FindStorage() | Select-Object -Property FilePath).FilePath
                            TapeMedium   = $tapeName
                            CreationTime = $rp.CreationTime
                                         }
                    }
}

# Show result if a barcode has been passed as a parameter
if ($Barcode) {
               foreach ($b in $Barcode) {
               Write-Host "TapeMedium value: $b"
               $TapeList | Where-Object {$_.TapeMedium -like $b} | Group-Object TapeMedium | ForEach-Object {
               $_.Group | Select-Object TapeMedium, Content, CreationTime | Format-Table -AutoSize
               }
       }
}

# Show everything
else         {
$TapeList | Select-Object TapeMedium, Content, CreationTime
}

# Disconnect VBR Server
Disconnect-VBRServer
