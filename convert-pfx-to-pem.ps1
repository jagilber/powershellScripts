<#
.SYNOPSIS
Converts a PFX file to base64 format for use in a Kubernetes secret

.DESCRIPTION
Converts a PFX file to base64 format for use in a Kubernetes secret

.PARAMETER pfxFile
The path to the PFX file or the certificate store path 'cert:\CurrentUser\My\1234567890abcdef1234567890abcdef12345678'

.PARAMETER password
The password for the PFX file

.EXAMPLE 
.\convert-pfx-to-pem.ps1 -pfxFile cert:\CurrentUser\My\1234567890abcdef1234567890abcdef12345678 -password 'password'

.EXAMPLE
.\convert-pfx-to-pem.ps1 -pfxFile c:\temp\contoso.pfx -useFile

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/convert-pfx-to-pem.ps1" -outFile "$pwd\convert-pfx-to-pem.ps1";
    .\convert-pfx-to-pem.ps1 -pfxFile {{ pfx file }}

#>
param(
    $pfxFile = '',
    $password = $null,
    [switch]$useFile
)

$ErrorActionPreference = "continue"
[byte[]]$bytes = $null

if ($pfxFile.toLower().startsWith("cert:")) {
    $cert = Get-Item $pfxFile
    $bytes = $cert.GetRawCertData()
}
elseif ((test-path $pfxFile)) {
    $cert = [security.cryptography.x509Certificates.x509Certificate2]::new($pfxFile, $password);
    $bytes = $cert.GetRawCertData()
}
else {
    write-error "$pfxFile not found"
    return
}

$global:cert = $cert
if ($PSVersionTable.PSEdition -ine 'core') {
    $rsaCng = [security.cryptography.x509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    $keyBytes = $RSACng.Key.Export([security.cryptography.cngKeyBlobFormat]::Pkcs8PrivateBlob)
    $keyBase64 = [convert]::ToBase64String($KeyBytes, [base64FormattingOptions]::InsertLineBreaks)

    write-host '---- BEGIN RSA PRIVATE KEY ----'
    [convert]::ToBase64String($keyBytes) -split '(.{64})' | where-object { $psitem }
    write-host '---- END RSA PRIVATE KEY ----'
    write-host '---- BEGIN CERTIFICATE ----'
    [convert]::ToBase64String($cert.GetRawCertData()) -split '(.{64})' | where-object { $psitem }
    write-host '---- END CERTIFICATE ----'
}
else {
    # pscore only
    if ($cert.PrivateKey.key.ExportPolicy.HasFlag([security.cryptography.cngExportPolicies]::AllowExport)) {
        $cert.PrivateKey.ExportRSAPrivateKeyPem()
    }
    else {
        Write-Warning "private key export not allowed"
    }
    $cert.ExportCertificatePem()
}

