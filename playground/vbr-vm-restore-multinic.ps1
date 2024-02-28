Param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    [Parameter(Mandatory=$true)]
    [string]$DestESXiServer,
    [Parameter(Mandatory=$true)]
    [string]$SourceNetworkName,
    [Parameter(Mandatory=$true)]
    [string]$DestinationNetworkName
    )

Connect-VBRServer -Server localhost

$restorePoint    = Get-VBRRestorePoint -Name $VMName | Sort-Object -Descending CreationTime | select -First 1
$destEsxiSrv     = Get-VBRServer -Name $DestESXiServer
$sourceNetwork   = $restorepoint.Auxdata.Nics.Network | Where-Object NetworkName -eq $SourceNetworkName


if ($restorePoint.AuxData.Nics.Length -gt 1){
    $targetnetwork = @()
    for ($i = 0; $i -lt $restorepoint.AuxData.Nics.Length; $i++)
    {
        $targetnetwork += Get-VBRViServerNetworkInfo -Server $destEsxiSrv | Where-Object NetworkName -eq $DestinationNetworkName
    }
} else {
    $targetnetwork = Get-VBRViServerNetworkInfo -Server $destEsxiSrv | Where-Object NetworkName -eq $DestinationNetworkName
}


$instantVMRecovery = Start-VBRInstantRecovery -RestorePoint $restorepoint -VMName $vmName"_restoretest" -Server $destEsxiSrv -SourceNetwork $sourceNetwork -TargetNetwork $targetNetwork
#$VMRestore         = Start-VBRRestoreVM -RestorePoint $restorepoint -Server $destEsxiSrv -SourceNetwork $sourceNetwork -TargetNetwork $targetNetwork -VMName $VMName"_restoretest" 

Disconnect-VBRServer 
