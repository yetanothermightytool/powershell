<# 
.NAME
    Veeam Backup & Replication - Backups stored on tape information
.DESCRIPTION
    This script shows the Veeam backup data stored on a specified tape
.EXAMPLES
    Get the stored backup files on tape with barcode L00004L6
    .\vbr-get-tapeinfo-v13.ps1 -Barcode H00004L5
    Get information from multiple tapes
    .\vbr-get-tapeinfo-v13.ps1 -Barcode H00004L5,H00005L5

    Get information from all tapes (might be slow)
    .\vbr-get-tapeinfo-v13.ps1
.NOTES  
    File Name  : vbr-get-tapeinfo-v13.ps1
    Author     : Stephan "Steve" Herzig
    Requires   : PowerShell 7, Veeam Backup & Replication v13
.VERSION
1.0  
#>
