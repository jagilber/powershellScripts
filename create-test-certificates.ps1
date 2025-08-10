<#
.SYNOPSIS
    powershell script to create, list, and remove test certificates from Windows certificate stores

.DESCRIPTION
    This script provides functionality to manage test certificates in Windows certificate stores.
    It can create self-signed certificates with various algorithms and key lengths,
    export certificates to PFX format, list existing certificates, and remove certificates.
    The script supports multiple certificate stores and locations, and can work with
    both LocalMachine and CurrentUser certificate stores.

    Key features:
    - Create self-signed certificates with RSA, ECDSA algorithms
    - Export certificates to PFX format with password protection
    - List certificates by subject name, thumbprint, or expiration date
    - Remove certificates from certificate stores
    - Configurable key lengths, hash algorithms, and certificate validity periods
    - Support for multiple certificate stores (My, Root, CA, TrustedPeople, etc.)
    - Optional removal of certificates after export for temporary certificate creation

    Requirements:
    - Administrator privileges (script will attempt to restart as admin if needed)
    - PowerShell 5.0 or later for full certificate management functionality

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/create-test-certificates.ps1" -outFile "$pwd/create-test-certificates.ps1";
    ./create-test-certificates.ps1

.NOTES
    File Name  : create-test-certificates.ps1
    Author     : jagilber
    Version    : 250706 initial version
    History    : 
                250706 created script for test certificate management

.EXAMPLE
    .\create-test-certificates.ps1
    Creates a single test certificate with default settings (CN=TestCert-1) in LocalMachine\My store

.EXAMPLE
    .\create-test-certificates.ps1 -subjectName "CN=MyTestCert" -numberOfCerts 5
    Creates 5 test certificates with subject names CN=MyTestCert-1 through CN=MyTestCert-5

.EXAMPLE
    .\create-test-certificates.ps1 -action List -store "My" -location "LocalMachine"
    Lists all certificates in the LocalMachine\My certificate store

.EXAMPLE
    .\create-test-certificates.ps1 -action Remove -subjectName "TestCert" -WhatIf
    Shows what certificates would be removed (dry run) that match "TestCert" in the subject name

.EXAMPLE
    .\create-test-certificates.ps1 -subjectName "CN=ExportTest" -exportPath "C:\temp\certs" -password "MyPassword123"
    Creates a certificate and exports it to C:\temp\certs with the specified password

.EXAMPLE
    .\create-test-certificates.ps1 -subjectName "CN=TempCert" -exportPath "C:\temp" -removeExportedCerts
    Creates a certificate, exports it to C:\temp, then removes it from the certificate store

.EXAMPLE
    .\create-test-certificates.ps1 -subjectName "CN=MyKeyvaultCert" -uploadToKeyVault -keyVaultName "my-keyvault"
    Creates a certificate and uploads it to the specified Azure Key Vault

.EXAMPLE
    .\create-test-certificates.ps1 -subjectName "CN=TestApp" -uploadToKeyVault -keyVaultName "my-kv" -certificateName "test-app-cert" -azureSubscription "my-subscription-id"
    Creates a certificate and uploads it to Key Vault with a custom name and specific subscription

.EXAMPLE
    .\create-test-certificates.ps1 -subjectName "CN=ExportAndUpload" -exportPath "C:\temp" -uploadToKeyVault -keyVaultName "my-kv" -numberOfCerts 3
    Creates 3 certificates, exports them locally AND uploads them to Key Vault

.PARAMETER subjectName
    The subject name for the certificate. Default is "CN=TestCert"

.PARAMETER notBefore
    The start date for certificate validity. Default is yesterday

.PARAMETER notAfter
    The expiration date for certificate validity. Default is one year from now

.PARAMETER store
    The certificate store to use. Valid values: My, Root, CA, TrustedPeople, Disallowed, TrustedPublisher, WebHosting

.PARAMETER location
    The certificate store location. Valid values: LocalMachine, CurrentUser

.PARAMETER numberOfCerts
    Number of certificates to create. Default is 1

.PARAMETER action
    Action to perform. Valid values: Add (create), List, Remove

.PARAMETER thumbprint
    Specific certificate thumbprint to target for List or Remove actions

.PARAMETER keyLength
    RSA key length in bits. Default is 2048

.PARAMETER keyAlgorithm
    Key algorithm to use. Valid values: RSA, ECDSA, CNG, CSP

.PARAMETER hashAlgorithm
    Hash algorithm for certificate signature. Valid values: SHA256, SHA384, SHA512

.PARAMETER provider
    Cryptographic provider to use. Default is "Microsoft Enhanced RSA and AES Cryptographic Provider"

.PARAMETER exportPath
    Directory path to export certificates as PFX files

.PARAMETER removeExportedCerts
    Switch to remove certificates from store after successful export

.PARAMETER password
    Password for PFX export. If not provided and exportPath is specified, a random password will be generated

.PARAMETER keyVaultName
    Name of the Azure Key Vault to upload certificates to. Required when uploadToKeyVault is specified.

.PARAMETER certificateName
    Name for the certificate in Key Vault. If not provided, will use SubjectName without CN= prefix and sanitize for Key Vault naming requirements.

.PARAMETER uploadToKeyVault
    Switch to enable uploading certificates to Azure Key Vault. Requires keyVaultName parameter and appropriate Azure permissions.

.PARAMETER azureSubscription
    Azure subscription ID or name. If not provided, will use the current Azure context subscription.

.PARAMETER conflictAction
    Action to take when a certificate with the same name already exists in Key Vault. Valid values:
    - Skip: Don't upload certificates that already exist
    - Overwrite: Replace existing certificates
    - Rename: Upload with a timestamped name
    - Prompt: Ask user what to do for each conflict (default)

.PARAMETER WhatIf
    Show what would be done without actually performing the action

#>

#Requires -Modules Az.KeyVault, Az.Accounts

param(
    [string]$subjectName = "CN=TestCert",
    [datetime]$notBefore = (Get-Date).AddDays(-1),
    [datetime]$notAfter = (Get-Date).AddYears(1),
    [ValidateSet("My", "Root", "CA", "TrustedPeople", "Disallowed", "TrustedPublisher", "WebHosting")]
    [string]$store = "My",
    [ValidateSet("LocalMachine", "CurrentUser")]
    [string]$location = "LocalMachine",
    [int]$numberOfCerts = 1,
    [ValidateSet("Add", "List", "Remove")]
    [string]$action = "Add",
    [string]$thumbprint,
    [int]$keyLength = 2048,
    [ValidateSet("RSA", "ECDSA", "CNG", "CSP")]
    [string]$keyAlgorithm = "RSA",
    [ValidateSet("SHA256", "SHA384", "SHA512")]
    [string]$hashAlgorithm = "SHA256",
    [string]$provider = "Microsoft Enhanced RSA and AES Cryptographic Provider",
    [string]$exportPath,
    [switch]$removeExportedCerts,
    [string]$password,
    [string]$keyVaultName,
    [string]$certificateName,
    [switch]$uploadToKeyVault,
    [string]$azureSubscription,
    [ValidateSet("Skip", "Overwrite", "Rename", "Prompt")]
    [string]$conflictAction = "Prompt",
    [switch]$WhatIf
)

$securePassword = $null

function main() {
    
    if (!(is-admin)) {
        return
    }

    # Initialize Azure context if Key Vault upload is requested
    if ($uploadToKeyVault) {
        if (-not $keyVaultName) {
            Write-Error "KeyVaultName is required when uploadToKeyVault is specified."
            return
        }
        
        Write-Host "Initializing Azure connection for Key Vault operations..." -ForegroundColor Yellow
        if (-not (Initialize-AzureContext)) {
            Write-Error "Failed to initialize Azure context. Cannot proceed with Key Vault upload."
            return
        }
    }

    if ($exportPath -or $uploadToKeyVault) {
        if ($password) {
            $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
        }
        else {
            $password = [guid]::NewGuid().ToString()
            Write-Host "No password provided. Using generated password: $password" -ForegroundColor Yellow
            $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
        }
        if ($exportPath -and !(Test-Path -Path $exportPath)) {
            Write-Host "Creating export path: $exportPath"
            New-Item -ItemType Directory -Path $exportPath | Out-Null
        }
    }

    switch ($action) {
        "Add" { Add-Certs -store $store -location $location -subjectName $subjectName -numberOfCerts $numberOfCerts -WhatIf:$WhatIf -SecurePassword $securePassword }
        "List" { List-Certs -store $store -location $location -subjectName $subjectName -thumbprint $thumbprint -notAfter $notAfter }
        "Remove" { Remove-Certs -store $store -location $location -subjectName $subjectName -thumbprint $thumbprint -notAfter $notAfter -WhatIf:$WhatIf }
    }

}

function Add-Certs {
    param($store, $location, $subjectName, $numberOfCerts, $WhatIf, $SecurePassword)
    for ($i = 1; $i -le $numberOfCerts; $i++) {
        $subject = "$subjectName-$i"
        Write-Host "Creating certificate: $subject"
        if (-not $WhatIf) {
            #cng
            # $cert = New-SelfSignedCertificate -Subject $subject -CertStoreLocation "Cert:\$Location\$Store"
            #csp
            write-host "New-SelfSignedCertificate -Subject $subject ``
                -CertStoreLocation 'Cert:\$location\$store' ``
                -NotBefore $notBefore ``
                -NotAfter $notAfter ``
                -HashAlgorithm $hashAlgorithm ``
                -KeyAlgorithm $keyAlgorithm ``
                -KeyLength $keyLength ``
                -Provider $provider
            "

            $cert = New-SelfSignedCertificate -Subject $subject `
                -CertStoreLocation "Cert:\$location\$store" `
                -NotBefore $notBefore `
                -NotAfter $notAfter `
                -HashAlgorithm $hashAlgorithm `
                -KeyAlgorithm $keyAlgorithm `
                -KeyLength $keyLength `
                -Provider $provider
            Write-Host "Created: $($cert.Thumbprint)"
            
            # Export to PFX file if exportPath is specified
            if ($exportPath) {
                $certPath = Join-Path -Path $exportPath -ChildPath "$($cert.Thumbprint).pfx"
                Write-Host "Exporting certificate to: $certPath"
                write-host "Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $SecurePassword -Force"
                Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $SecurePassword -Force
                Write-Host "Certificate exported successfully."
            }
            
            # Upload to Key Vault if specified
            if ($uploadToKeyVault) {
                $kvCertName = $certificateName
                if (-not $kvCertName) {
                    # Generate certificate name from subject, removing CN= and invalid characters
                    $kvCertName = $subject -replace '^CN=', '' -replace '[^a-zA-Z0-9-]', '-'
                }
                
                try {
                    Write-Host "Uploading certificate to Key Vault: $keyVaultName as $kvCertName" -ForegroundColor Green
                    Upload-CertificateToKeyVault -Certificate $cert -KeyVaultName $keyVaultName -CertificateName $kvCertName -SecurePassword $SecurePassword
                    Write-Host "Certificate uploaded to Key Vault successfully." -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to upload certificate to Key Vault: $($_.Exception.Message)"
                    Write-Host "Certificate creation will continue..." -ForegroundColor Yellow
                }
            }

            # Remove from local store if specified
            if ($removeExportedCerts) {
                Write-Host "Removing certificate from store: $($cert.Thumbprint)"
                Write-Host "Remove-Item -Path $cert.PSPath -Force"
                Remove-Item -Path $cert.PSPath -Force
                Write-Host "Certificate removed from store." -ForegroundColor Green
            }
        }
    }
}

function is-admin() {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Warning "restarting script as administrator..."
        $command = 'pwsh'
        $commandLine = $global:myinvocation.myCommand.definition

        if ($psedition -eq 'Desktop') {
            $command = 'powershell'
        }
        write-host "Start-Process $command -Verb RunAs -ArgumentList `"-NoExit -File $commandLine`""
        Start-Process $command  -Verb RunAs -ArgumentList "-NoExit -File $commandLine"

        return $false
    }
    return $true
}

function List-Certs {
    param($store, $location, $subjectName, $thumbprint, $notAfter)
    $path = "Cert:\$location\$store"
    $certs = Get-ChildItem -Path $path
    if ($subjectName) { $certs = $certs | Where-Object { $_.Subject -like "*$subjectName*" } }
    if ($thumbprint) { $certs = $certs | Where-Object { $_.Thumbprint -eq $thumbprint } }
    if ($notAfter) { $certs = $certs | Where-Object { $_.NotAfter -le $notAfter } }
    $certs | Select-Object Subject, Thumbprint, NotAfter
}

function Remove-Certs {
    param($store, $location, $subjectName, $thumbprint, $notAfter, $WhatIf)
    $path = "Cert:\$location\$store"
    $certs = Get-ChildItem -Path $path
    if ($subjectName) { $certs = $certs | Where-Object { $_.Subject -like "*$subjectName*" } }
    if ($thumbprint) { $certs = $certs | Where-Object { $_.Thumbprint -eq $thumbprint } }
    if ($notAfter) { $certs = $certs | Where-Object { $_.NotAfter -le $notAfter } }
    foreach ($cert in $certs) {
        Write-Host "Removing certificate: $($cert.Subject) $($cert.Thumbprint)"
        if (-not $WhatIf) {
            Remove-Item -Path $cert.PSPath -Force
        }
    }
}

function Initialize-AzureContext {
    <#
    .SYNOPSIS
    Initialize Azure PowerShell context with proper error handling and retry logic
    #>
    try {
        # Check if Azure modules are available
        $azAccountsModule = Get-Module -ListAvailable -Name Az.Accounts
        $azKeyVaultModule = Get-Module -ListAvailable -Name Az.KeyVault
        
        if (-not $azAccountsModule -or -not $azKeyVaultModule) {
            Write-Warning "Required Azure PowerShell modules are not installed."
            Write-Host "Please install using: Install-Module -Name Az.KeyVault, Az.Accounts -Force" -ForegroundColor Yellow
            return $false
        }

        # Import modules
        Import-Module Az.Accounts -Force
        Import-Module Az.KeyVault -Force

        # Check current context
        $currentContext = Get-AzContext -ErrorAction SilentlyContinue
        
        if (-not $currentContext) {
            Write-Host "No Azure context found. Initiating interactive login..." -ForegroundColor Yellow
            try {
                $context = Connect-AzAccount -ErrorAction Stop
                Write-Host "Successfully connected to Azure as: $($context.Context.Account.Id)" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to connect to Azure: $($_.Exception.Message)"
                return $false
            }
        }
        else {
            Write-Host "Using existing Azure context: $($currentContext.Account.Id)" -ForegroundColor Green
        }

        # Set subscription if provided
        if ($azureSubscription) {
            try {
                Set-AzContext -Subscription $azureSubscription -ErrorAction Stop
                Write-Host "Switched to subscription: $azureSubscription" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to set subscription '$azureSubscription': $($_.Exception.Message)"
                return $false
            }
        }

        # Verify Key Vault access
        try {
            $keyVault = Get-AzKeyVault -VaultName $keyVaultName -ErrorAction Stop
            Write-Host "Successfully validated access to Key Vault: $($keyVault.VaultName)" -ForegroundColor Green
            $keyVaultCertificates = Get-AzKeyVaultCertificate -VaultName $keyVaultName
            if($error) {
                Write-Error "Failed to retrieve certificates from Key Vault: $($_.Exception.Message)"
                return $false
            }
            if ($keyVaultCertificates) {
                Write-Host "Found existing certificates in Key Vault '$keyVaultName':" -ForegroundColor Cyan
                $keyVaultCertificates | ForEach-Object {
                    Write-Host "  - Name: $($_.Name), Thumbprint: $($_.Thumbprint), Expires: $($_.Expires)" -ForegroundColor Cyan
                }
            }
            else {
                Write-Host "No certificates found in Key Vault '$keyVaultName'." -ForegroundColor Yellow
            }
            return $true
        }
        catch {
            Write-Error "Failed to access Key Vault '$keyVaultName': $($_.Exception.Message)"
            Write-Host "Please ensure you have appropriate permissions (Certificate Officer or Contributor role)" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Error "Failed to initialize Azure context: $($_.Exception.Message)"
        return $false
    }
}

function Upload-CertificateToKeyVault {
    <#
    .SYNOPSIS
    Upload certificate to Azure Key Vault with comprehensive error handling and conflict resolution
    #>
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$KeyVaultName,
        [string]$CertificateName,
        [System.Security.SecureString]$SecurePassword
    )
    
    try {
        # Check if certificate already exists in Key Vault
        Write-Host "Checking for existing certificate '$CertificateName' in Key Vault..." -ForegroundColor Yellow
        $existingKvCert = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertificateName -ErrorAction SilentlyContinue
        
        if ($existingKvCert) {
            Write-Host "Certificate '$CertificateName' already exists in Key Vault '$KeyVaultName'" -ForegroundColor Yellow
            Write-Host "Existing certificate details:" -ForegroundColor Cyan
            Write-Host "  Thumbprint: $($existingKvCert.Thumbprint)" -ForegroundColor Cyan
            Write-Host "  Created: $($existingKvCert.Created)" -ForegroundColor Cyan
            Write-Host "  Expires: $($existingKvCert.Expires)" -ForegroundColor Cyan
            
            $action = $script:conflictAction
            
            if ($script:conflictAction -eq "Prompt") {
                Write-Host "`nWhat would you like to do?" -ForegroundColor Yellow
                Write-Host "1. Skip - Don't upload this certificate" -ForegroundColor Green
                Write-Host "2. Overwrite - Replace the existing certificate" -ForegroundColor Red
                Write-Host "3. Rename - Upload with a new name" -ForegroundColor Blue
                
                do {
                    $choice = Read-Host "Enter your choice (1-3)"
                    switch ($choice) {
                        "1" { $action = "Skip" }
                        "2" { $action = "Overwrite" }
                        "3" { $action = "Rename" }
                        default { Write-Host "Invalid choice. Please enter 1, 2, or 3." -ForegroundColor Red }
                    }
                } while ($choice -notin @("1", "2", "3"))
            }
            
            switch ($action) {
                "Skip" {
                    Write-Host "Skipping upload for certificate '$CertificateName'." -ForegroundColor Green
                    return $null
                }
                "Overwrite" {
                    Write-Host "Proceeding to overwrite existing certificate..." -ForegroundColor Yellow
                }
                "Rename" {
                    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                    $CertificateName = "$CertificateName-$timestamp"
                    Write-Host "Renaming certificate to: $CertificateName" -ForegroundColor Green
                }
            }
        }
        else {
            Write-Host "No existing certificate found. Proceeding with upload..." -ForegroundColor Green
        }
        
        # Create a temporary PFX file for Key Vault upload
        $tempPath = [System.IO.Path]::GetTempPath()
        $tempPfxFile = Join-Path -Path $tempPath -ChildPath "$([guid]::NewGuid().ToString()).pfx"
        
        try {
            # Export certificate to temporary PFX file
            Export-PfxCertificate -Cert $Certificate -FilePath $tempPfxFile -Password $SecurePassword -Force | Out-Null
            
            # Import certificate to Key Vault
            Write-Host "Importing certificate '$CertificateName' to Key Vault..." -ForegroundColor Yellow
            $result = Import-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertificateName -FilePath $tempPfxFile -Password $SecurePassword -ErrorAction Stop
            
            Write-Host "Certificate imported successfully:" -ForegroundColor Green
            Write-Host "  Key Vault: $KeyVaultName" -ForegroundColor Cyan
            Write-Host "  Certificate Name: $CertificateName" -ForegroundColor Cyan
            Write-Host "  Certificate ID: $($result.Id)" -ForegroundColor Cyan
            Write-Host "  Thumbprint: $($result.Thumbprint)" -ForegroundColor Cyan
            Write-Host "  Expires: $($result.Expires)" -ForegroundColor Cyan
            
            return $result
        }
        finally {
            # Clean up temporary file
            if (Test-Path -Path $tempPfxFile) {
                Remove-Item -Path $tempPfxFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Error "Failed to upload certificate to Key Vault: $($_.Exception.Message)"
        
        # Provide specific guidance based on common errors
        if ($_.Exception.Message -like "*403*" -or $_.Exception.Message -like "*Forbidden*") {
            Write-Host "Access denied. Please ensure you have the following permissions on Key Vault '$KeyVaultName':" -ForegroundColor Yellow
            Write-Host "  - Certificate permissions: Import, Get, List" -ForegroundColor Yellow
            Write-Host "  - Key permissions: Get, Create, Import" -ForegroundColor Yellow
            Write-Host "  - Secret permissions: Get, Set" -ForegroundColor Yellow
        }
        elseif ($_.Exception.Message -like "*404*" -or $_.Exception.Message -like "*NotFound*") {
            Write-Host "Key Vault '$KeyVaultName' not found. Please verify the name and ensure it exists." -ForegroundColor Yellow
        }
        
        throw
    }
}

main