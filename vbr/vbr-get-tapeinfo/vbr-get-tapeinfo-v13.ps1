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
 param(
    [Parameter(Mandatory = $false)]
    [string[]]$Barcode
)

Connect-VBRServer -Server localhost

$TapeList = [System.Collections.Generic.List[psobject]]::new()

try {
    $catalogItems = Find-VBRTapeCatalog -WarningAction Ignore | Where-Object { $_.Type -eq 'File' }

    foreach ($cat in $catalogItems) {
        $version = $cat.LatestVersion
        if ($version -and $version.FirstPart) {
            $medium = $version.FirstPart.GetTapeMedium()
            if ($null -eq $medium) { continue }

            $TapeList.Add([pscustomobject]@{
                JobName      = $cat.Parent.Name
                VMName       = $cat.Name
                Content      = if ($cat.Path) { $cat.Path.Link } else { $null }
                TapeMedium   = $medium.Barcode
                CreationTime = $version.CreationTime
            })
        }
    }

    if ($Barcode) {
        foreach ($b in $Barcode) {
            $TapeList |
                Where-Object { $_.TapeMedium -like $b } |
                Group-Object TapeMedium |
                ForEach-Object {
                    $_.Group | Select-Object TapeMedium, Content, CreationTime |
                        Format-Table -AutoSize
                }
        }
    } else {
        $TapeList | Select-Object TapeMedium, Content, CreationTime
    }
}
finally {
    Disconnect-VBRServer
}
 
