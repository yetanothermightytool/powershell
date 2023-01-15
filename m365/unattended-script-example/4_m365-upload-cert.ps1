# Get the certificate file (.CER)
$CertificateFilePath = (Resolve-Path ".\$($appName).cer").Path

# Create a new certificate object
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$cert.Import("$($CertificateFilePath)")
$bin = $cert.GetRawCertData()
$base64Value = [System.Convert]::ToBase64String($bin)
$bin = $cert.GetCertHash()
$base64Thumbprint = [System.Convert]::ToBase64String($bin)

# Upload and assign the certificate to the application
$null = New-AzureADApplicationKeyCredential -ObjectId $myApp.ObjectID `
-CustomKeyIdentifier $base64Thumbprint `
-Type AsymmetricX509Cert -Usage Verify `
-Value $base64Value `
-StartDate ($cert.NotBefore) `
-EndDate ($cert.NotAfter)
