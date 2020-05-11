<#
    Script to import certificate from keyvault using azure managed identity from a configured vm scaleset node

    to download and execute:
    (new-object net.webclient).downloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-metadata-import-cert.ps1","$pwd/azure-metadata-import-cert.ps1");
    .\azure-metadata-import-cert.ps1 -keyvaultName -certificateName

    if needed, enable system / user managed identity on scaleset:
    PS C:\Users\jagilber> Update-AzVmss -ResourceGroupName sfcluster -Name nt0 -IdentityType "SystemAssigned"
#>
param(
    $keyvaultName,
    $certificateName,
    $certificateVersion
)

$error.Clear()
$ErrorActionPreference = "continue"

# acquire system managed identity oauth token from within node
$global:vaultOauthResult = (Invoke-WebRequest -Method GET `
        -UseBasicParsing `
        -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net' `
        -Headers @{'Metadata' = 'true' }).content | convertfrom-json #| convertto-json


write-host $global:vaultOauthResult

if (!$global:vaultOauthResult.access_token) {
    write-error 'no vault token'
    return
}

if ($keyvaultName -and $certificateName) {
    # get cert with private key from keyvault
    $headers = @{
        Authorization = "Bearer $($global:vaultOauthResult.access_token)"
    }

    write-host "invoke-WebRequest "https://$keyvaultName.vault.azure.net/secrets/$certificateName/$($certificateVersion)?api-version=7.0" -UseBasicParsing -Headers $headers"
    $global:certificateSecrets = invoke-WebRequest "https://$keyvaultName.vault.azure.net/secrets/$certificateName/$($certificateVersion)?api-version=7.0" -UseBasicParsing -Headers $headers

    # save secrets cert with private key to pfx
    $global:pfx = ($global:certificateSecrets.content | convertfrom-json).value
    if ($global:pfx) {
        write-host "out-file -InputObject `$global:pfx -FilePath .\$certificateName.pfx"
        out-file -InputObject $global:pfx -FilePath .\$certificateName.pfx

        write-host "Import-PfxCertificate -Exportable -CertStoreLocation Cert:\LocalMachine\My -FilePath .\$certificateName.pfx"
        Import-PfxCertificate -Exportable -CertStoreLocation Cert:\LocalMachine\My -FilePath .\$certificateName.pfx
    }

    write-host $global:certificateSecrets.content | convertfrom-json | convertto-json
}
else {
    write-error 'no keyvault or certificate name'
}

write-host "objects stored in `$global:pfx `$global:certificateSecrets"
write-host "finished."

