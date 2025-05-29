<#
#Requires -Version 7.0
.SYNOPSIS
This script enumerates certificates in the specified store and matches them with key files in the MachineKeys directory.

.DESCRIPTION
 This script is designed to help manage certificates and their associated private keys in the Windows certificate store.
 It enumerates certificates in the specified store, checks for private keys, and matches them with key files in the MachineKeys directory.
 It also identifies orphaned key files that do not match any certificate.
 It outputs matched keys and orphaned keys to specified files.
 .NOTE: This script is intended for use on Windows systems with PowerShell 7.0 or later.
 .NOTES
 version: 0.1
 This script requires administrative privileges to access the certificate store and key files.
 This script makes no changes to the system or files
 .EXAMPLE
 .\certificate-machinekeys-manager.ps1
 This will run the script with default parameters, enumerating certificates in the LocalMachine\My store and checking for key files in the specified paths.
 .EXAMPLE
 .\certificate-machinekeys-manager.ps1 -store 'cert:\LocalMachine\My' -cngFilePaths 'C:\ProgramData\Microsoft\Crypto\Keys' -cspFilePaths 'C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys'
 This will run the script with specified paths for CNG and CSP key files, enumerating certificates in the LocalMachine\My store.
 .PARAMETER store
 The certificate store to enumerate. Default is 'cert:\LocalMachine\My'.
 .PARAMETER cngFilePaths
 An array of paths to search for CNG key files. Default includes 'C:\ProgramData\Microsoft\Crypto\Keys' and the user's AppData path.
 .PARAMETER cspFilePaths
 An array of paths to search for CSP key files. Default includes 'C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys' and the user's AppData path.
 .PARAMETER matchedKeysFile
 The file to output matched keys. Default is 'matched_keys.txt' in the current directory.
 .PARAMETER orphanedKeysFile
 The file to output orphaned keys. Default is 'orphaned_keys.txt' in the current directory.
 .LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    iwr https://raw.githubusercontent.com/jagilber/powershellScripts/master/certificate-machinekeys-mapper.ps1 -outfile $pwd\certificate-machinekeys-mapper.ps1;
    . $pwd\certificate-machinekeys-mapper.ps1
#>

[cmdletbinding()]
param(
    $store = 'cert:\LocalMachine\My',
    $cngFilePaths = @(
        'C:\ProgramData\Microsoft\Crypto\Keys',
        "$($env:AppData)\Microsoft\Crypto\Keys"
    ),
    $cspFilePaths = @(
        'C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys',
        "$($env:AppData)\Microsoft\Crypto\RSA\MachineKeys"
    ),
    $matchedKeysFile = "$pwd\matched_keys.txt",
    $orphanedKeysFile = "$pwd\orphaned_keys.txt"
)
$global:certificates = [hashtable]::new()
$global:keyFiles = @()

function main() {
    if (!(is-admin)) {
        return
    }
    
    $global:cngKeyFiles = enumerate-Files $cngFilePaths
    $global:cspKeyFiles = enumerate-Files $cspFilePaths
    $global:keyFiles = $global:cngKeyFiles + $global:cspKeyFiles
    
    if (!$global:keyFiles) {
        write-host "No key files found in the specified paths." -ForegroundColor Red
        return
    }
    
    write-host "Found $($global:keyFiles.Count) key files in the specified paths." -ForegroundColor Green
    write-host "Processing key files..." -ForegroundColor Cyan

    $global:certs = Get-ChildItem -Path $store -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -eq $false }

    if (-not $global:certs) {
        write-host "No certificates found in the specified store: $store" -ForegroundColor Red
        return
    }
    
    if (-not $global:keyFiles) {
        write-host "No key files found in the specified paths." -ForegroundColor Red
        return
    }

    $global:certificates = enumerate-certificates

    # match cert keys and key files
    $global:orphanedKeys = [collections.arrayList]::new()
    foreach ($keyFile in $global:keyFiles) {
        $keyFileName = $keyFile.Name
        $matchedCert = $global:certificates.GetEnumerator() | Where-Object { $_.Value.UniqueName -imatch $keyFileName }
        if (!$matchedCert) {
            write-host "Potential orphaned key file found. verify: $($keyFile.FullName)" -ForegroundColor Yellow
            [void]$global:orphanedKeys.Add($keyFile)
        }
    }
    
    # Output orphaned keys to a file
    if ((test-path -Path $orphanedKeysFile)) {
        Remove-Item -Path $orphanedKeysFile -Force
    }
    
    $global:orphanedKeys | ForEach-Object {
        "$($_.FullName)`r`n$($_ | convertto-json -depth 1 -WarningAction SilentlyContinue)" | Out-File -FilePath $orphanedKeysFile -Encoding UTF8 -Append -Force
    }

    # active certs with hasprivate key but no key file path
    $global:activeCerts = $global:certificates.GetEnumerator() | Where-Object {
        $_.Value.HasPrivateKey -and
        -not $_.Value.KeyFilePath
    }
    $global:activeCerts | ForEach-Object {
        write-host "Active certificate with private key but without key file path. verify certificate. this may be ok: $($_.Key) - $($_.Value.Subject)" -ForegroundColor Yellow
    }

    # output matched keys
    $global:matchedKeys = $global:certificates.GetEnumerator() | Where-Object {
        $_.Value.HasPrivateKey -and
        $_.Value.KeyFilePath
    }
    $global:matchedKeys | ForEach-Object {
        write-host "Matched key for certificate: $($_.Key) with key file: $($_.Value.keyFilePath)" -ForegroundColor Green
    }

    # Output matched keys to a file
    if ((test-path -Path $matchedKeysFile)) {
        Remove-Item -Path $matchedKeysFile -Force
    }
    $global:matchedKeys | ForEach-Object {
        "$($_.Key) - $($_.Value | convertto-json -depth 1 -WarningAction SilentlyContinue)" | Out-File -FilePath $matchedKeysFile -Encoding UTF8 -Append -Force
    }
}

function enumerate-certificates() {
    foreach ($cert in $global:certs) {
        if (!$cert -or !$cert.Subject -or !$cert.Thumbprint) {
            write-verbose "empty certificate found, skipping. $($cert|convertto-json -depth 1 -WarningAction SilentlyContinue)"
            continue
        }
        
        $storePath = $cert.PSParentPath.replace('Microsoft.PowerShell.Security\Certificate::', '')
        
        write-host "Processing certificate: $($cert.Subject) - $($cert.Thumbprint) in store: $($storePath)" -ForegroundColor Magenta
        $global:certificates[$cert.Thumbprint] = @{
            KeyFilePath   = $null
            Subject       = $cert.Subject
            Certificate   = $cert
            NotAfter      = $cert.NotAfter
            NotBefore     = $cert.NotBefore
            IsValid       = $cert.NotAfter -gt (Get-Date) -and $cert.NotBefore -lt (Get-Date)
            HasPrivateKey = $cert.HasPrivateKey
            UniqueName    = $null
            StorePath     = $storePath
        }

        if (!$cert.HasPrivateKey) {
            write-host "Certificate does not have a private key: $($cert.Subject)" -ForegroundColor Cyan
            continue
        }
        if (!$cert.PrivateKey) {
            write-host "Certificate has private key but privatekey is null: $($cert.Subject)" -ForegroundColor Red
            continue
        }
        if ($PSVersionTable.PSEdition -eq 'Core') {
            $uniqueName = $cert.PrivateKey.Key.UniqueName
        }
        else {
            # # framework
            # does not query cng private key so using core is better
            $uniqueName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
        }
            
        if (!$uniqueName) {
            write-verbose "No unique name found for private key of certificate: $($cert.Subject)"
            continue
        }

        # determine if csp or cng
        # this only works on core
        if ($cert.PrivateKey -is [System.Security.Cryptography.RSACryptoServiceProvider]) {
            write-host "Certificate uses CSP (RSACryptoServiceProvider)" -ForegroundColor Yellow
            $keyFilePath = $global:KeyFiles | Where-Object { $_.Name -imatch $uniqueName }
            if (!$keyFilePath) {
                write-host "No key file found for CSP certificate: $($cert.Subject)" -ForegroundColor Red
                continue
            }
            # $keyFilePath = "$keyFilePath\" + $uniqueName
        }
        elseif ($cert.PrivateKey -is [System.Security.Cryptography.RSACng]) {
            write-host "Certificate uses CNG (RSACng)" -ForegroundColor Yellow
            # $keyFilePath = "$keyFilePath\" + $uniqueName
        }
        else {
            write-host "Unknown private key type for certificate: $($cert.Subject)" -ForegroundColor Red
            # continue
        }
        $keyFilePath = $global:KeyFiles | Where-Object { $_.Name -imatch $uniqueName }
        if (!$keyFilePath) {
            write-host "No key file found for CNG certificate: $($cert.Subject)" -ForegroundColor Red
            continue
        }
        else {
            $keyFilePath = $keyFilePath.FullName
            write-host "Found matching key file path: $keyFilePath for certificate: $($cert.Subject)" -ForegroundColor Green
        }
        write-host "Adding private key unique name: $uniqueName"
        $global:certificates[$cert.Thumbprint].KeyFilePath = $keyFilePath
        $global:certificates[$cert.Thumbprint].UniqueName = $uniqueName

    }

    return $global:certificates
}

function enumerate-Files($paths) {
    write-host "Enumerating files in paths: $($paths -join ', ')" -ForegroundColor Cyan
    $files = @()
    foreach ($path in $paths) {
        if (Test-Path $path) {
            $files += Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue
        }
        else {
            write-host "Path does not exist: $path" -ForegroundColor Yellow
        }
    }
    return $files
}

function is-admin() {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Warning "restart script as administrator..."
        return $false
    }
    return $true
}

main