 Param(
    [Parameter(Mandatory=$true)]
    [string]$hostname,
    [string]$destinationserver,
    [string]$destinationpath
    
    )
Clear-Host

Connect-VBRServer -Server localhost

$restorePoint = Get-VBRRestorePoint | Sort-Object -Property CreationTime -Descending | Where-Object {$_.VmName -eq $hostname} | Select-Object -First 1 

$destServer = Get-VBRServer -Name $destinationserver

$destPath = $destinationpath

$vmdkfiles = Get-VBRFilesInRestorePoint -RestorePoint $restorePoint | Where-Object {$_.Name -like "*.vmdk"}
 
Start-VBRRestoreVMFiles -RestorePoint $restorePoint -Server $destServer -Path $destinationpath -Files $vmdkfiles -Reason "VMDK Restore by PowerShell" -RunAsync

Disconnect-VBRServer
 
