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
    .\create-test-certificates.ps1 -SubjectName "CN=MyTestCert" -NumberOfCerts 5
    Creates 5 test certificates with subject names CN=MyTestCert-1 through CN=MyTestCert-5

.EXAMPLE
    .\create-test-certificates.ps1 -Action List -Store "My" -Location "LocalMachine"
    Lists all certificates in the LocalMachine\My certificate store

.EXAMPLE
    .\create-test-certificates.ps1 -Action Remove -SubjectName "TestCert" -WhatIf
    Shows what certificates would be removed (dry run) that match "TestCert" in the subject name

.EXAMPLE
    .\create-test-certificates.ps1 -SubjectName "CN=ExportTest" -exportPath "C:\temp\certs" -password "MyPassword123"
    Creates a certificate and exports it to C:\temp\certs with the specified password

.EXAMPLE
    .\create-test-certificates.ps1 -SubjectName "CN=TempCert" -exportPath "C:\temp" -removeExportedCerts
    Creates a certificate, exports it to C:\temp, then removes it from the certificate store

.PARAMETER SubjectName
    The subject name for the certificate. Default is "CN=TestCert"

.PARAMETER NotBefore
    The start date for certificate validity. Default is yesterday

.PARAMETER NotAfter
    The expiration date for certificate validity. Default is one year from now

.PARAMETER Store
    The certificate store to use. Valid values: My, Root, CA, TrustedPeople, Disallowed, TrustedPublisher, WebHosting

.PARAMETER Location
    The certificate store location. Valid values: LocalMachine, CurrentUser

.PARAMETER NumberOfCerts
    Number of certificates to create. Default is 1

.PARAMETER Action
    Action to perform. Valid values: Add (create), List, Remove

.PARAMETER Thumbprint
    Specific certificate thumbprint to target for List or Remove actions

.PARAMETER KeyLength
    RSA key length in bits. Default is 2048

.PARAMETER KeyAlgorithm
    Key algorithm to use. Valid values: RSA, ECDSA, CNG, CSP

.PARAMETER HashAlgorithm
    Hash algorithm for certificate signature. Valid values: SHA256, SHA384, SHA512

.PARAMETER Provider
    Cryptographic provider to use. Default is "Microsoft Enhanced RSA and AES Cryptographic Provider"

.PARAMETER exportPath
    Directory path to export certificates as PFX files

.PARAMETER removeExportedCerts
    Switch to remove certificates from store after successful export

.PARAMETER password
    Password for PFX export. If not provided and exportPath is specified, a random password will be generated

.PARAMETER WhatIf
    Show what would be done without actually performing the action

#>
param(
    [string]$SubjectName = "CN=TestCert",
    [datetime]$NotBefore = (Get-Date).AddDays(-1),
    [datetime]$NotAfter = (Get-Date).AddYears(1),
    [ValidateSet("My", "Root", "CA", "TrustedPeople", "Disallowed", "TrustedPublisher", "WebHosting")]
    [string]$Store = "My",
    [ValidateSet("LocalMachine", "CurrentUser")]
    [string]$Location = "LocalMachine",
    [int]$NumberOfCerts = 1,
    [ValidateSet("Add", "List", "Remove")]
    [string]$Action = "Add",
    [string]$Thumbprint,
    [int]$KeyLength = 2048,
    [ValidateSet("RSA", "ECDSA", "CNG", "CSP")]
    [string]$KeyAlgorithm = "RSA",
    [ValidateSet("SHA256", "SHA384", "SHA512")]
    [string]$HashAlgorithm = "SHA256",
    [string]$Provider = "Microsoft Enhanced RSA and AES Cryptographic Provider",
    [string]$exportPath,
    [switch]$removeExportedCerts,
    [string]$password,
    [switch]$WhatIf
)

$securePassword = $null

function main() {
    
    if (!(is-admin)) {
        return
    }

    if ($exportPath) {
        if ($password) {
            $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
        }
        else {
            $password = [guid]::NewGuid().ToString()
            Write-Host "No password provided. Using generated password: $password" -ForegroundColor Yellow
            $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
        }
        if (!(Test-Path -Path $exportPath)) {
            Write-Host "Creating export path: $exportPath"
            New-Item -ItemType Directory -Path $exportPath | Out-Null
        }
    }

    switch ($Action) {
        "Add" { Add-Certs -Store $Store -Location $Location -SubjectName $SubjectName -NumberOfCerts $NumberOfCerts -WhatIf:$WhatIf }
        "List" { List-Certs -Store $Store -Location $Location -SubjectName $SubjectName -Thumbprint $Thumbprint -NotAfter $NotAfter }
        "Remove" { Remove-Certs -Store $Store -Location $Location -SubjectName $SubjectName -Thumbprint $Thumbprint -NotAfter $NotAfter -WhatIf:$WhatIf }
    }

}

function Add-Certs {
    param($Store, $Location, $SubjectName, $NumberOfCerts, $WhatIf)
    for ($i = 1; $i -le $NumberOfCerts; $i++) {
        $subject = "$SubjectName-$i"
        Write-Host "Creating certificate: $subject"
        if (-not $WhatIf) {
            #cng
            # $cert = New-SelfSignedCertificate -Subject $subject -CertStoreLocation "Cert:\$Location\$Store"
            #csp
            write-host "New-SelfSignedCertificate -Subject $subject ``
                -CertStoreLocation 'Cert:\$Location\$Store' ``
                -NotBefore $NotBefore ``
                -NotAfter $NotAfter ``
                -HashAlgorithm $HashAlgorithm ``
                -KeyAlgorithm $KeyAlgorithm ``
                -KeyLength $KeyLength ``
                -Provider $Provider
            "

            $cert = New-SelfSignedCertificate -Subject $subject `
                -CertStoreLocation "Cert:\$Location\$Store" `
                -NotBefore $NotBefore `
                -NotAfter $NotAfter `
                -HashAlgorithm $HashAlgorithm `
                -KeyAlgorithm $KeyAlgorithm `
                -KeyLength $KeyLength `
                -Provider $Provider
            Write-Host "Created: $($cert.Thumbprint)"
            if ($exportPath) {
                $certPath = Join-Path -Path $exportPath -ChildPath "$($cert.Thumbprint).pfx"
                Write-Host "Exporting certificate to: $certPath"
                write-host "Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $securePassword -Force"
                Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $securePassword -Force
                Write-Host "Certificate exported successfully."

                if ($removeExportedCerts) {
                    Write-Host "Removing certificate from store: $($cert.Thumbprint)"
                    Write-Host "Remove-Item -Path $cert.PSPath -Force"
                    Remove-Item -Path $cert.PSPath -Force
                    Write-Host "Certificate removed from store." -ForegroundColor Green
                }
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
    param($Store, $Location, $SubjectName, $Thumbprint, $NotAfter)
    $path = "Cert:\$Location\$Store"
    $certs = Get-ChildItem -Path $path
    if ($SubjectName) { $certs = $certs | Where-Object { $_.Subject -like "*$SubjectName*" } }
    if ($Thumbprint) { $certs = $certs | Where-Object { $_.Thumbprint -eq $Thumbprint } }
    if ($NotAfter) { $certs = $certs | Where-Object { $_.NotAfter -le $NotAfter } }
    $certs | Select-Object Subject, Thumbprint, NotAfter
}

function Remove-Certs {
    param($Store, $Location, $SubjectName, $Thumbprint, $NotAfter, $WhatIf)
    $path = "Cert:\$Location\$Store"
    $certs = Get-ChildItem -Path $path
    if ($SubjectName) { $certs = $certs | Where-Object { $_.Subject -like "*$SubjectName*" } }
    if ($Thumbprint) { $certs = $certs | Where-Object { $_.Thumbprint -eq $Thumbprint } }
    if ($NotAfter) { $certs = $certs | Where-Object { $_.NotAfter -le $NotAfter } }
    foreach ($cert in $certs) {
        Write-Host "Removing certificate: $($cert.Subject) $($cert.Thumbprint)"
        if (-not $WhatIf) {
            Remove-Item -Path $cert.PSPath -Force
        }
    }
}

main