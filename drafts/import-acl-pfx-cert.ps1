<#
.SYNOPSIS
    example script to import certificate and acl private key

.LINK
    to download and test from vmss node with managed identity enabled:
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
    invoke-webrequest https://raw.githubusercontent.com/jagilber/powershellScripts/master/import-acl-pfx-cert.ps1 -outfile $pwd/import-acl-pfx-cert.ps1;

.EXAMPLE
    .\import-acl-pfx-cert.ps1 -certificate

.EXAMPLE
    .\import-acl-pfx-cert.ps1 -certificateFile

.EXAMPLE
    .\import-acl-pfx-cert.ps1 -secretUrl

https://stackoverflow.com/questions/66543195/set-certificate-privatekey-permissions-in-net-5
NET 5 doesn't have CryptoKeySecurity, because it is Windows-specific and hasn't ported yet (if ever planned to port). Couple words on your issues:

var rsa = certificate.PrivateKey as RSACryptoServiceProvider; -- this construction can be considered obsolete and deprecated since .NET Framework 4.6. Under no condition you should use RSACryptoServiceProvider if you are on 4.6+. Instead, you should access [X509Certificate2] class extension methods only to retrieve public/private key handles. More details in my blog post: Accessing and using certificate private keys in .NET Framework/.NET Core.

When using [X509Certificate2].GetRSAPrivateKey() extension method on Windows, it will return an instance of RSACng class that contains Key property which is of type CngKey. Then use GetProperty and SetProperty methods to read and write Security Descr property. You can check for Security Descr Support property if key supports ACL (1 if supports, any other value means the key doesn't support ACL).
https://stackoverflow.com/questions/51018834/cngkey-assign-permission-to-machine-key

23-08-13 07:13:47 acles not working
#>
using namespace System
using namespace System.Security.AccessControl
using namespace System.Security.Principal
using namespace System.Security.Cryptography
using namespace System.Security.Cryptography.X509Certificates
using namespace System.Text.RegularExpressions
[cmdletBinding()]
param(
    #[Parameter(Mandatory = $true, ParameterSetName = 'certificate')]
    [X509Certificate2]$certificate,
    #[Parameter(Mandatory = $true, ParameterSetName = 'certificateFile')]
    [string]$certificateFile = '',
    #[Parameter(Mandatory = $true, ParameterSetName = 'secretUrl')]
    [string]$secretUrl = '',
    [string]$storeName = 'My',
    [string]$storeLocation = 'LocalMachine', #'CurrentUser', #'cert:\LocalMachine\My', #'cert:\LocalMachine\Root', #'cert:\LocalMachine\CA',
    [string]$acl = 'NetworkService', #'NS', #'NetworkServiceSid', 'NetworkService',
    [string]$password = $null,
    [securestring]$securePassword = $null
)

$error.Clear()  
$ErrorActionPreference = "continue"

function main () {

    if ($certificate) {
        $certificate = new-certificate -certificate $certificate -certificatePassword ($securePassword, $password | select-object -first 1)
    }
    elseif ($certificateFile) {
        $certificate = get-certificate2 -certificateFile $certificateFile -certificatePassword ($securePassword, $password | select-object -first 1)
    }
    elseif ($secretUrl) {
        $certificate = get-keyVaultCertificate -secretUrl $secretUrl
        if (!$certificate) {
            write-host 'error:secret not found' -ForegroundColor Red
            return
        }
    }
    else {
        write-host 'no input'
        write-host 'error:missing required parameter. must specify -certificate [X509Certificate2], -certificateFile c:\temp\cert.pfx, or -secretUrl https://keyvault.vault.azure.net/secrets/cert/1234567890abcdef1234567890abcdef' -ForegroundColor Red
        return
    }

    import-certificate2 -certificate $certificate -storeName $storeName -storeLocation $storeLocation -acl $acl

    write-host 'finished'
}

function new-certificate([X509Certificate2]$certificate, $certificatePassword = $null) {
    write-host 'certificate'
    $certificate = [X509Certificate2]::new($certificateFile , $certificatePassword, [X509keystorageflags]::Exportable)
    return $certificate
}

function get-certificate2([string]$certificateFile, $certificatePassword = $null) {
    write-host 'certificateFile'
    if (!(test-path $certificateFile)) {
        write-host 'error:certificateFile not found' -ForegroundColor Red
        return
    }
    $certificate = [X509Certificate2]::new($certificateFile , $certificatePassword, [X509keystorageflags]::Exportable)
    return $certificate
}

function get-keyVaultCertificate($secretUrl) {
    write-host 'secretUrl'
    if (!(get-module -ListAvailable az)) {
        write-host 'az module is required for secretUrl but not installed. to install az module run the following command:' -ForegroundColor Yellow
        write-host 'install-module az -force'
        return $null
    }
    if (!(get-azresourcegroup | out-null)) {
        connect-azAccount | out-null
    }

    $secretPattern = 'https://(?<keyvaultName>.+?).vault.azure.net/secrets/(?<secretName>.+?)/(?<secretVersion>.+)'
    $results = [regex]::Match($secretUrl, $secretPattern, [RegexOptions]::IgnoreCase)
    $keyvaultName = $results.groups['keyvaultName'].Value
    $secretName = $results.groups['secretName'].Value
    $secretVersion = $results.groups['secretVersion'].Value
    #$secret = Get-AzKeyVaultSecret -VaultName $keyvaultName -Name $secretName -Version $secretVersion
    write-host "Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $secretName -Version $secretVersion" -ForegroundColor Green
    $certificate = Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $secretName -Version $secretVersion
    return $certificate
    
}

function add-certificateAcl([X509Certificate2]$certificate, [string]$acl) {
    write-host 'acl'
    $cngKeyParameter = [CngKeyCreationParameters]::new()
    $security = [FileSecurity]::new()
    $security.AddAccessRule([FileSystemAccessRule]::new(
            [SecurityIdentifier]::new([WellKnownSidType]::BuiltinAdministratorsSid, $null), 
            [FileSystemRights]::FullControl, 
            [AccessControlType]::Allow))
    $security.AddAccessRule([FileSystemAccessRule]::new(
            [SecurityIdentifier]::new([WellKnownSidType]::LocalSystemSid, $null), 
            [FileSystemRights]::FullControl, 
            [AccessControlType]::Allow))

    $security.AddAccessRule([FileSystemAccessRule]::new(
            [SecurityIdentifier]::new([WellKnownSidType]::NetworkServiceSid, $null), 
            [FileSystemRights]::FullControl, 
            [AccessControlType]::Allow))

    $NCRYPT_SECURITY_DESCR_PROPERTY = "Security Descr";
    $DACL_SECURITY_INFORMATION = [CngPropertyOptions]4;

    $permissions = [CngProperty]::new(
        $NCRYPT_SECURITY_DESCR_PROPERTY,
        $security.GetSecurityDescriptorBinaryForm(),
        [CngPropertyOptions]::Persist -bor $DACL_SECURITY_INFORMATION);

    $cngKeyParameter.Parameters.Add($permissions);


    $cngKeyParameter.KeyUsage = [CngKeyUsages]::AllUsages
    $cngKeyParameter.ExportPolicy = [CngExportPolicies]::AllowPlaintextExport

    $cngKeyParameter.Provider = [CngProvider]::MicrosoftSoftwareKeyStorageProvider
    $cngKeyParameter.UIPolicy = [CngUIPolicy]::new([CngUIProtectionLevels]::None)
    $cngKeyParameter.KeyCreationOptions = [CngKeyCreationOptions]::MachineKey

    #Create Cng Property for Length, set its value and add it to Cng Key Parameter
    [CngProperty] $cngProperty = [CngProperty]::new($cngPropertyName, [BitConverter]::GetBytes(2048), [CngPropertyOptions]::None)
    $cngKeyParameter.Parameters.Add($cngProperty)

    #Create Cng Key for given $keyName using Rsa Algorithm
    $key = [CngKey]::Create([CngAlgorithm]::Rsa, "MyKey", $cngKeyParameter)
    $certificate.PrivateKey = $key
    return $certificate
}

function add-certificateToStore([X509Certificate2]$certificate, [string]$storeName, [string]$storeLocation) {
    if (!(is-certValid $certificate)) {
        write-host 'error:certificate date not valid' -ForegroundColor Red
        return
    }
    $certStore = [X509store]::new($storeName, $storeLocation)
    [void]$certStore.open([OpenFlags]::MaxAllowed)
    $certificateCollection = [X509Certificate2Collection]$certStore.Certificates.Find([X509FindType]::FindByThumbprint, $certificate.Thumbprint, $false)
    if ($certificateCollection.Count -gt 0) {
        write-host 'certificate already exists. removing...' -ForegroundColor Yellow
        [void]$certStore.remove($certificate)
        #    return
    }

    $certStore.add($certificate)
    $certStore.close()
    write-host 'imported certificate'

    $certificateCollection = [X509Certificate2Collection]$certStore.Certificates.Find([X509FindType]::FindByThumbprint, $certificate.Thumbprint, $false)
    $certificate = $certificateCollection[0]
    return $certificate
}

function import-certificate2([X509Certificate2]$certificate, [string]$storeName, [string]$storeLocation, [string]$acl = 'NetworkService') {
    write-host 'import-certificate2'

    # $certificate = add-certificateAcl -certificate $certificate -acl $acl
    # $certificate = add-certificateToStore -certificate $certificate -storeName $storeName -storeLocation $storeLocation
    
    #$csp = [CspParameters]::new($certificate.PrivateKey.CspKeyContainerInfo.ProviderType, $certificate.PrivateKey.CspKeyContainerInfo.ProviderName, $certificate.PrivateKey.CspKeyContainerInfo.KeyContainerName)

    #$certificate

    # set key acl
    $NCRYPT_SECURITY_DESCR_PROPERTY = "Security Descr"   
    $NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY = "Security Descr Support"   
    $DACL_SECURITY_INFORMATION = [CngPropertyOptions]4
    
    # $cngKeyParameter = [CngKeyCreationParameters]::new()
    # $cngKeyParameter.KeyUsage = [CngKeyUsages]::AllUsages
    # $cngKeyParameter.ExportPolicy = [CngExportPolicies]::AllowPlaintextExport

    $rsaCert = [RsaCertificateExtensions]::GetRSAPrivateKey($certificate)
    $rsaProvider = $rsaCert.Key

    $privateKey = $certificate.PrivateKey.Key
    Clear-Host
    $cngPropertycheck = [CngProperty]$privateKey.GetProperty($NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY, [CngPropertyOptions]::None -bor $DACL_SECURITY_INFORMATION)
    $cngPropertycheck
    $cngPropertycheck = [CngProperty]$privateKey.GetProperty($NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY, [CngPropertyOptions]::None)
    $cngPropertycheck

    $cngPropertycheck = [CngProperty]$privateKey.GetProperty($NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY, [CngPropertyOptions]::CustomProperty -bor $DACL_SECURITY_INFORMATION)
    $cngPropertycheck
    $cngPropertycheck = [CngProperty]$privateKey.GetProperty($NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY, [CngPropertyOptions]::CustomProperty)
    $cngPropertycheck

    $cngPropertycheck = [CngProperty]$privateKey.GetProperty($NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY, [CngPropertyOptions]::Persist -bor $DACL_SECURITY_INFORMATION)
    $cngPropertycheck
    $cngPropertycheck = [CngProperty]$privateKey.GetProperty($NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY, [CngPropertyOptions]::Persist)
    $cngPropertycheck
    $cngPropertycheck = [CngProperty]$privateKey.GetProperty($NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY, $DACL_SECURITY_INFORMATION)
    $cngPropertycheck

    $rsaPropertycheck = $rsaProvider.GetProperty($NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY, [CngPropertyOptions]::Persist -bor $DACL_SECURITY_INFORMATION)
    $rsaPropertycheck
    $rsaPropertycheck = $rsaProvider.GetProperty($NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY, [CngPropertyOptions]::Persist)
    $rsaPropertycheck
    $rsaPropertycheck = $rsaProvider.GetProperty($NCRYPT_SECURITY_DESCR_SUPPORT_PROPERTY, $DACL_SECURITY_INFORMATION)
    $rsaPropertycheck

    return
    $cngProperty = [CngProperty]$privateKey.GetProperty($NCRYPT_SECURITY_DESCR_PROPERTY, [CngPropertyOptions]::Persist -bor $DACL_SECURITY_INFORMATION)
    $cngProperty | convertto-json
    $rsaProperty = $rsaProvider.GetProperty($NCRYPT_SECURITY_DESCR_PROPERTY, [CngPropertyOptions]::Persist -bor $DACL_SECURITY_INFORMATION)
    $rsaProperty | convertto-json
    
 
    ####### core doesnt have CryptoKeySecurity
    #    $keySecurity = [security.accesscontrol.CryptoKeySecurity]::new()
    # $keySecurity.SetSecurityDescriptorBinaryForm($cngProperty.PrivateKey.SecurityDescriptorBinaryForm)

    # $keySecurity.AddAccessRule([CryptoKeyAccessRule]::new($acl, 
    #          [CryptoKeyRights]::FullControl,
    #          [AccessControlType]::Allow)
    #  )
    ####################

    $keySecurity = [FileSecurity]::new()
    $keySecurity.SetSecurityDescriptorBinaryForm($cngProperty.PrivateKey.SecurityDescriptorBinaryForm)

    $keySecurity.AddAccessRule([FileSystemAccessRule]::new($acl, 
            [FileSystemRights]::FullControl,
            [AccessControlType]::Allow)
    )


    # $newCngProperty = [CngProperty]::new($NCRYPT_SECURITY_DESCR_PROPERTY, $keySecurity.GetSecurityDescriptorBinaryForm(), $DACL_SECURITY_INFORMATION)
    #     $rsaCert.Set

    $rsaCert = [RsaCertificateExtensions]::GetRSAPrivateKey($certificate)
    # $rsaProvider = [Rsacryptoserviceprovider]$certificate.PrivateKey
    # #$rsaProvider.CspKeyContainerInfo.ProviderType
    #$csp = [CspParameters]::new($rsaCert.PrivateKey.CspKeyContainerInfo.ProviderType, $rsacert.PrivateKey.CspKeyContainerInfo.ProviderName, $rsaCert.PrivateKey.CspKeyContainerInfo.KeyContainerName)

    # Set flags and key security based on existing cert
    $cspParameters = [CspParameters]::new($rsaProvider.CspKeyContainerInfo.ProviderType, 
        $rsaProvider.CspKeyContainerInfo.ProviderName, 
        $rsaProvider.CspKeyContainerInfo.KeyContainerName
    )
    # $cspParameters.Flags = [CspProviderFlags]::UseExistingKey -bor [CspProviderFlags]::UseMachineKeyStore
    # $cspParameters.CryptoKeySecurity = $rsaProvider.CspKeyContainerInfo.CryptoKeySecurity
        
    # $cspParameters.AddAccessRule([CryptoKeyAccessRule]::new($acl, 
    #         [CryptoKeyRights]::FullControl,
    #         [AccessControlType]::Allow)
    # )

    $fileName = $rsaCert.key.UniqueName
    $path = "$env:ALLUSERSPROFILE\Microsoft\Crypto\RSA\MachineKeys\$fileName"

    $permissions = get-acl -path $path
    $access_rule = [FileSystemAccessRule]::new($acl, 
        [FileSystemRights]::FullControl,
        [InheritanceFlags]::None,
        [PropagationFlags]::None,
        [AccessControlType]::Allow)
    $permissions.AddAccessRule($access_rule)

    write-host "set-acl -path $path -aclObject $permissions"
    set-acl -path $path -aclObject $permissions

            


    return $certificate
}

function is-certValid([X509Certificate2]$certificate) {
    write-host 'is-certValid'
    if (!($certificate.NotBefore -lt (get-date) -and $certificate.NotAfter -gt (get-date))) {
        write-host 'error:certificate date not valid' -ForegroundColor Red
        return $false
    }
    return $true
}

main
