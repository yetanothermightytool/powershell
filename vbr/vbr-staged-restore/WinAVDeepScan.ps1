$gw = (Get-NetIPConfiguration | Foreach IPv4DefaultGateway).NextHop
$port = ":8080"
Set-ItemProperty -path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -value 1
Set-ItemProperty -path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -value 1
Set-ItemProperty -path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -value $gw$port
Set-ItemProperty -path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -value $gw$port
$defenderFolder    = (Get-ChildItem "C:\ProgramData\Microsoft\Windows Defender\Platform\" | Sort-Object -Descending | Select-Object -First 1).fullname
$defender          = "$defenderFolder\MpCmdRun.exe"
sleep 60
$output            = & $defender -scan -scantype 2

# Check if the output contains the string indicating a virus is found
if ($output -like "*Threats Detected*") {
    # Virus found, return exit code 1
    exit 1
} else {
    # No virus found, return exit code 0
    exit 0
}
