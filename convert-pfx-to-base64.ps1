param(
    $pfxFile = '',
    $password = '',
    [switch]$useFile
)

$ErrorActionPreference = "continue"
[byte[]]$bytes = $null
$type = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx

if($useFile){
    $bytes = [io.file]::ReadAllBytes($pfxFile)
}
elseif ($password) {
    $cert = [security.cryptography.x509Certificates.x509Certificate2]::new($pfxFile, $password);
    $bytes = $cert.GetRawCertData()
    #$bytes = $cert.Export($type, $password)
}
else {
    $cert = [security.cryptography.x509Certificates.x509Certificate2]::new($pfxFile);
    $bytes = $cert.GetRawCertData()

    #$bytes = $cert.Export($type)

}

$base64 = [convert]::ToBase64String($bytes)

write-host $base64