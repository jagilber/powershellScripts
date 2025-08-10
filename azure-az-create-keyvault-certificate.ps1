#Requires -Modules Az.KeyVault, Az.Accounts

<#
.SYNOPSIS
    Creates a self-signed certificate directly in Azure Key Vault with conflict resolution

.DESCRIPTION
    This script creates a self-signed certificate directly in Azure Key Vault using the Key Vault
    certificate generation capabilities. It includes conflict resolution when certificates with
    the same name already exist.

.PARAMETER keyVaultName
    Name of the Azure Key Vault where the certificate will be created

.PARAMETER certificateName
    Name for the certificate in Key Vault

.PARAMETER subjectName
    Subject name for the certificate (e.g., "CN=example.com")

.PARAMETER validityInMonths
    Certificate validity period in months. Default is 12 months

.PARAMETER issuerName
    Certificate issuer name. Default is "Self" for self-signed certificates

.PARAMETER conflictAction
    Action to take when a certificate with the same name already exists. Valid values:
    - Skip: Exit without creating certificate
    - Overwrite: Replace the existing certificate
    - Rename: Create with a timestamped name
    - Prompt: Ask user what to do (default)

.EXAMPLE
    .\azure-az-create-keyvault-certificate.ps1 -keyVaultName "my-keyvault" -certificateName "test-cert" -subjectName "CN=test.example.com"
    Creates a self-signed certificate in the specified Key Vault

.EXAMPLE
    .\azure-az-create-keyvault-certificate.ps1 -keyVaultName "my-kv" -certificateName "app-cert" -subjectName "CN=app.com" -conflictAction "Overwrite"
    Creates a certificate and overwrites any existing certificate with the same name
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$keyVaultName,
    
    [Parameter(Mandatory = $true)]
    [string]$certificateName,
    
    [Parameter(Mandatory = $true)]
    [string]$subjectName,
    
    [Parameter(Mandatory = $false)]
    [int]$validityInMonths = 12,
    
    [Parameter(Mandatory = $false)]
    [string]$issuerName = "Self",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Skip", "Overwrite", "Rename", "Prompt")]
    [string]$conflictAction = "Prompt"
)

try {
    # Ensure Azure context is available
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "No Azure context found. Please login..." -ForegroundColor Yellow
        Connect-AzAccount
    }

    # Verify Key Vault exists and we have access
    $keyVault = Get-AzKeyVault -VaultName $keyVaultName -ErrorAction SilentlyContinue
    if (-not $keyVault) {
        throw "Key Vault '$keyVaultName' not found or access denied."
    }

    # Check if certificate already exists
    Write-Host "Checking for existing certificate '$certificateName'..." -ForegroundColor Yellow
    $existingCert = Get-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName -ErrorAction SilentlyContinue
    
    if ($existingCert) {
        Write-Host "Certificate '$certificateName' already exists in Key Vault '$keyVaultName'" -ForegroundColor Yellow
        Write-Host "Existing certificate details:" -ForegroundColor Cyan
        Write-Host "  Thumbprint: $($existingCert.Thumbprint)" -ForegroundColor Cyan
        Write-Host "  Created: $($existingCert.Created)" -ForegroundColor Cyan
        Write-Host "  Expires: $($existingCert.Expires)" -ForegroundColor Cyan
        Write-Host "  Enabled: $($existingCert.Enabled)" -ForegroundColor Cyan
        
        $action = $conflictAction
        
        if ($conflictAction -eq "Prompt") {
            Write-Host "`nWhat would you like to do?" -ForegroundColor Yellow
            Write-Host "1. Skip - Exit without creating certificate" -ForegroundColor Green
            Write-Host "2. Overwrite - Replace the existing certificate" -ForegroundColor Red
            Write-Host "3. Rename - Create with a new name" -ForegroundColor Blue
            
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
                Write-Host "Skipping certificate creation. Existing certificate will remain unchanged." -ForegroundColor Green
                return
            }
            "Overwrite" {
                Write-Host "Proceeding to overwrite existing certificate..." -ForegroundColor Yellow
                # Remove existing certificate first
                Write-Host "Removing existing certificate..." -ForegroundColor Yellow
                Remove-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName -Force -Confirm:$false
                Write-Host "Existing certificate removed." -ForegroundColor Green
            }
            "Rename" {
                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $certificateName = "$certificateName-$timestamp"
                Write-Host "Renaming certificate to: $certificateName" -ForegroundColor Green
            }
        }
    }
    else {
        Write-Host "No existing certificate found. Proceeding with creation..." -ForegroundColor Green
    }

    Write-Host "Creating certificate policy..." -ForegroundColor Green
    
    # Create comprehensive certificate policy
    $policy = New-AzKeyVaultCertificatePolicy `
        -SubjectName $subjectName `
        -IssuerName $issuerName `
        -ValidityInMonths $validityInMonths `
        -KeyType "RSA" `
        -KeySize 2048 `
        -SecretContentType "application/x-pkcs12" `
        -ReuseKeyOnRenewal `
        -KeyUsage @("DigitalSignature", "KeyEncipherment") `
        -Ekus @("1.3.6.1.5.5.7.3.1", "1.3.6.1.5.5.7.3.2") # Server Auth, Client Auth

    Write-Host "Initiating certificate creation in Key Vault..." -ForegroundColor Green
    
    # Create certificate
    $certificate = Add-AzKeyVaultCertificate `
        -VaultName $keyVaultName `
        -Name $certificateName `
        -CertificatePolicy $policy `
        -ErrorAction Stop

    Write-Host "Certificate creation initiated successfully!" -ForegroundColor Green
    Write-Host "Certificate ID: $($certificate.Id)" -ForegroundColor Cyan
    Write-Host "Status: $($certificate.Status)" -ForegroundColor Cyan
    
    # Monitor certificate creation status
    do {
        Start-Sleep -Seconds 5
        $operation = Get-AzKeyVaultCertificateOperation -VaultName $keyVaultName -Name $certificateName
        Write-Host "Status: $($operation.Status)" -ForegroundColor Yellow
    } while ($operation.Status -eq "inProgress")

    if ($operation.Status -eq "completed") {
        Write-Host "Certificate created successfully!" -ForegroundColor Green
        
        # Retrieve the completed certificate
        $completedCert = Get-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName
        Write-Host "Certificate Thumbprint: $($completedCert.Thumbprint)" -ForegroundColor Cyan
        Write-Host "Expires: $($completedCert.Expires)" -ForegroundColor Cyan
    }
    else {
        Write-Warning "Certificate creation failed with status: $($operation.Status)"
        if ($operation.Error) {
            Write-Error "Error: $($operation.Error.Message)"
        }
    }
}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    Write-Error $_.Exception.StackTrace
}