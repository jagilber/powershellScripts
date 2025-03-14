<#
.SYNOPSIS
    example script to import certificate from keyvault using azure managed identity from a configured vm scaleset node

    enable system / user managed identity on scaleset:
        Update-AzVmss -ResourceGroupName sfcluster -Name nt0 -IdentityType "SystemAssigned"

    add vmss managed identity to keyvault with read secrets permission
    
    convert certificate to base64 string and add as new secret value
        $base64String = [convert]::ToBase64String([io.file]::ReadAllBytes($certFile))

    use custom script extension (cse) or similar to deploy a script to vmss with ARM template

.LINK
    to download and test from vmss node with managed identity enabled:
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webrequest https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-metadata-import-cert.ps1 -outfile $pwd/azure-metadata-import-cert.ps1;

.EXAMPLE
    .\azure-metadata-import-cert.ps1 -secretUrl 'https://<keyvaultName>.vault.azure.net/secrets/<secretName>/<secretVersion>' -base64

MIT License
Copyright (c) Microsoft Corporation. All rights reserved.
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE

#>

param(
    [Parameter(Mandatory = $true)]
    [string]$secretUrl = '',
    [string]$certStoreLocation = 'cert:\LocalMachine\My', #'cert:\LocalMachine\Root', #'cert:\LocalMachine\CA',
    [switch]$base64,
    [bool]$pfx = $true
)

$error.Clear()  
$ErrorActionPreference = "continue"

# acquire system managed identity oauth token from within node
$global:vaultOauthResult = (Invoke-WebRequest -Method GET `
        -UseBasicParsing `
        -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" `
        -Headers @{'Metadata' = 'true' }).content | convertfrom-json


write-host $global:vaultOauthResult

$secretPattern = 'https://(?<keyvaultName>.+?).vault.azure.net/secrets/(?<secretName>.+?)/(?<secretVersion>.+)'
$results = [regex]::Match($secretUrl, $secretPattern, [text.RegularExpressions.RegexOptions]::IgnoreCase)
$keyvaultName = $results.groups['keyvaultName'].Value
$secretName = $results.groups['secretName'].Value
$secretVersion = $results.groups['secretVersion'].Value

if (!$global:vaultOauthResult.access_token) {
    write-error 'no vault token'
    return
}

if ($keyvaultName -and $secretName -and $secretVersion) {
    # get cert with private key from keyvault
    $headers = @{
        Authorization = "Bearer $($global:vaultOauthResult.access_token)"
    }

    write-host "invoke-WebRequest "$secretUrl?api-version=7.0" -UseBasicParsing -Headers $headers"
    $global:certificateSecrets = invoke-WebRequest "$($secretUrl)?api-version=7.0" -UseBasicParsing -Headers $headers

    write-host "$certStoreLocation before"
    Get-ChildItem $certStoreLocation

    # save secrets cert with private key to pfx
    $global:secret = ($global:certificateSecrets.content | convertfrom-json).value

    if ($global:secret) {
        $certFile = [io.path]::GetTempFileName()


        if ($base64) {
            $global:secret = [text.encoding]::UNICODE.GetString([convert]::FromBase64String($global:secret))
        }
    
        write-host "out-file -InputObject `$global:secret -FilePath $certFile"
        out-file -InputObject $global:secret -FilePath $certFile

        if ($pfx) {
        
            write-host "Import-PfxCertificate -Exportable -CertStoreLocation $certStoreLocation -FilePath $certFile"
            Import-PfxCertificate -Exportable -CertStoreLocation $certStoreLocation -FilePath $certFile        
        }
        else {
        
            write-host "Import-Certificate -Exportable -CertStoreLocation $certStoreLocation -FilePath $certFile"
            Import-Certificate -CertStoreLocation $certStoreLocation -FilePath $certFile
        }

        write-host "$certStoreLocation after"
        Get-ChildItem $certStoreLocation
    }

    write-host $global:certificateSecrets.content | convertfrom-json | convertto-json
}
else {
    write-error 'no keyvault or certificate name'
}

write-host "objects stored in `$global:secret `$global:certificateSecrets"
write-host "finished."
