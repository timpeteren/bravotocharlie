$tenantName = "tenant.onmicrosoft.com"
$certStore = "Cert:\CurrentUser\My" # "Cert:\LocalMachine\My"
$certName = "B2CClientCert.pfx"
$pwdText = "B2CClientCertPassword"

$pfxCertFile = if ($PSCommandPath -eq "") {$certName} else {($PSCommandPath | Split-Path -Parent) + "\" + $certName}
$pwd = ConvertTo-SecureString -String $pwdText -Force -AsPlainText
$selfSignedCert = New-SelfSignedCertificate -CertStoreLocation $certStore -DnsName $tenantName -Subject "B2C Client Cert" -HashAlgorithm SHA256 -KeySpec Signature -KeyLength 2048 -FriendlyName "B2C Client Cert" -NotAfter (get-date).AddYears(10)
# Export-PfxCertificate -Cert $selfSignedCert -FilePath $pfxCertFile -Password $pwd
Remove-Item -Path $certStore\$($selfSignedCert.thumbprint)