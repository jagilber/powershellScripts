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
.\convert-pfx-to-pem.ps1 -pfxFile c:\temp\contoso.pfx

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/convert-pfx-to-pem.ps1" -outFile "$pwd\convert-pfx-to-pem.ps1";
    .\convert-pfx-to-pem.ps1 -pfxFile {{ pfx file }}

#>
param(
    $pfxFile = '',
    $password = $null
)

$ErrorActionPreference = "stop"

if ($pfxFile.toLower().startsWith("cert:")) {
    $cert = Get-childItem $pfxFile
}
elseif ((test-path $pfxFile)) {
    $cert = [security.cryptography.x509Certificates.x509Certificate2]::new($pfxFile, $password);
}
else {
    write-error "$pfxFile not found"
    return
}

$global:cert = $cert
if ($PSVersionTable.PSEdition -ine 'core') {
    $rsaCng = [security.cryptography.x509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    if ($rsaCng -eq $null) {
        write-warning "no private key found"
    }
    else {
        if($rsaCng.key.ExportPolicy.HasFlag([security.cryptography.cngExportPolicies]::AllowExport)){
            write-warning "private key pkcs#8 export may not work. rerun script with powershell core pwsh.exe instead of powershell.exe"
            $keyBytes = $RSACng.Key.Export([security.cryptography.cngKeyBlobFormat]::Pkcs8PrivateBlob)

            write-output '---- BEGIN RSA PRIVATE KEY ----'
            [convert]::ToBase64String($keyBytes) -split '(.{64})' | where-object { $psitem }
            write-output '---- END RSA PRIVATE KEY ----'    
        }
        else {
            Write-Warning "private key export not allowed"
        }    
    }

    write-output '---- BEGIN CERTIFICATE ----'
    [convert]::ToBase64String($cert.GetRawCertData()) -split '(.{64})' | where-object { $psitem }
    write-output '---- END CERTIFICATE ----'
}
else {
    # pscore only
    if($cert.PrivateKey){
        if ($cert.PrivateKey.key.ExportPolicy.HasFlag([security.cryptography.cngExportPolicies]::AllowExport)) {
            $cert.PrivateKey.ExportRSAPrivateKeyPem()
        }
        else {
            Write-Warning "private key export not allowed"
        }    
    }
    else {
        Write-Warning "no private key found"
    }
    $cert.ExportCertificatePem()
}

