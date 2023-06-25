Param([string]$TestVmIP,
      [string]$lnxUsername,
      [string]$VirtualLab)
# Script to set HTTP Proxy on Linux VMs - Version 1.1

# Get the configured HTTP port from the virtual lab
$vlabHTTPPortCfg    = (Get-VBRViVirtualLabConfiguration -Name $VirtualLab).Proxyappliance.HTTPPort

# Read the encrypted password
$encryptedPassword  = Get-Content "D:\scripts\securestring.txt" | ConvertTo-SecureString
$password           = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($encryptedPassword))

# Location of OpenSSH key file
$KeyFile            = "D:\Scripts\openssh.openssh"

# Define the content of the shell script
$scriptContent      = @'
#!/bin/bash
# Read the default gateway from the ip route command
gateway=$(ip route | awk '/default/ {print $3; exit}')
# Set the proxy port
proxy_port="<httpcfgport>"
# Set the proxy environment variables
http_proxy="http://${gateway}:$proxy_port"
https_proxy="https://${gateway}:$proxy_port"
# Set the proxy for wget
echo "export http_proxy=${http_proxy}" >> "/home/<usernamehere>/.bashrc"
echo "export https_proxy=${http_proxy}" >> "/home/<usernamehere>/.bashrc"
source /home/<usernamehere>/.bashrc
# Update the apt-get configuration
sudo tee /etc/apt/apt.conf.d/99proxy <<EOF
Acquire::http::Proxy "${http_proxy}";
Acquire::https::Proxy "${https_proxy}";
EOF
'@

# Convert the script content to LF linefeeds
$lfScriptContent    = $scriptContent -replace "`r`n", "`n"

# Save the script content to a temporary file with LF linefeeds
$tempScriptPath     = "D:\Scripts\vbr\surebackup-scripts\set-http-proxy-temp.sh"
$lfScriptContent | Out-File -FilePath $tempScriptPath -Encoding UTF8 -NoNewline

# Read the temporary script file content
$tempScriptContent  = Get-Content -Path $tempScriptPath -Raw

# Replace the placeholder with the actual Linux username
$finalScriptContent = $tempScriptContent -replace "<usernamehere>", $lnxUsername -replace "<httpcfgport>", $vlabHTTPPortCfg

# Save the final script content to the desired file with LF linefeeds
$finalScriptPath    = "D:\Scripts\vbr\surebackup-scripts\set-http-proxy.sh"
$finalScriptContent | Set-Content -Path $finalScriptPath -Encoding UTF8 -NoNewline

# Remove the temporary script file
Remove-Item -Path $tempScriptPath

# Upload the .sh script stored on the VBR Server drive
Write-Host "Upload shell script"
scp -i $Keyfile $finalScriptPath $lnxUsername@${TestVmIp}:/tmp/set-http-proxy.sh

# Set execute permission on the uploaded file
Write-Host "Set execute permisson on script file"
ssh $lnxUsername@$TestVmIp -i $KeyFile "chmod +x /tmp/set-http-proxy.sh"

# Run the .sh Script
Write-Host "Set HTTP proxy settings"
ssh $lnxUsername@$TestVmIp -i $Keyfile "echo $password | sudo -S /tmp/set-http-proxy.sh"
