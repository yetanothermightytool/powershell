Param([string]$TestVmIP,
      [string]$lnxUsername)

# Helper Script to set HTTP Proxy on Linux VMs
# Read the password encrypted using ConvertTo-SecureString
$encryptedPassword = Get-Content "D:\scripts\securestring.txt" | ConvertTo-SecureString
$password          = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($encryptedPassword))

# Location of Key File
$KeyFile           = "D:\Scripts\openssh.openssh"

# Upload the .sh script stored on the VBR Server drive
Write-Host "Upload shell script"
scp -i $Keyfile  D:\Scripts\vbr\surebackup-scripts\set-http-proxy.sh $lnxUsername@${TestVmIp}:/tmp/set-http-proxy.sh

# Set execute permission on the uploaded file
Write-Host "Set execute permisson on script file"
ssh $lnxUsername@$TestVmIp -i $KeyFile "chmod +x /tmp/set-http-proxy.sh"

# Run the .sh Script
Write-Host "Set HTTP proxy settings"
ssh $lnxUsername@$TestVmIp -i $Keyfile "echo $password | sudo -S /tmp/set-http-proxy.sh"
