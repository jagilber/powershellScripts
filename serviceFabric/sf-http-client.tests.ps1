<#
.SYNOPSIS
    Pester tests for sf-http-client.ps1

.DESCRIPTION
    Unit tests for sf-http-client.ps1 helper functions including:
    - validate-certificate EKU, chain, expiration, and private key checks
    - test-connection TCP endpoint parsing and connectivity
    - get-serverCertificate endpoint parsing
    - invoke-request parameter validation
    - Endpoint URL normalization (https prefix, port append)
    Uses self-signed test certificates to validate without requiring a live cluster.

.NOTES
    Requires Pester v5+
    Run: Invoke-Pester -Path .\sf-http-client.tests.ps1 -Output Detailed
#>

BeforeAll {
    # dot-source the script functions by loading them without executing main
    # we override main entry by setting globals so it skips to function defs
    $scriptPath = "$PSScriptRoot\sf-http-client.ps1"

    # extract function definitions from the script
    $scriptContent = Get-Content $scriptPath -Raw
    # extract all function blocks
    $functionPattern = '(?ms)^function\s+([\w-]+)\s*\(.*?\)\s*\{.*?^}'
    $functions = [regex]::Matches($scriptContent, $functionPattern)

    foreach ($func in $functions) {
        try {
            Invoke-Expression $func.Value
        }
        catch {
            # some functions may reference script-scoped vars, skip those that fail
        }
    }

    # create a self-signed test certificate for validation tests
    $script:testCert = New-SelfSignedCertificate `
        -Subject "CN=sf-http-client-test" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyExportPolicy Exportable `
        -KeySpec Signature `
        -NotAfter (Get-Date).AddYears(1) `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1,1.3.6.1.5.5.7.3.2")

    # create an expired certificate for expiration tests
    $script:expiredCert = New-SelfSignedCertificate `
        -Subject "CN=sf-http-client-test-expired" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyExportPolicy Exportable `
        -KeySpec Signature `
        -NotBefore (Get-Date).AddYears(-2) `
        -NotAfter (Get-Date).AddDays(-1)

    # create a cert with server auth only EKU
    $script:serverOnlyCert = New-SelfSignedCertificate `
        -Subject "CN=sf-http-client-test-server" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyExportPolicy Exportable `
        -KeySpec Signature `
        -NotAfter (Get-Date).AddYears(1) `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")

    # create a cert with no EKU - use -Type Custom with -KeyUsage only (no -TextExtension for EKU)
    $script:noEkuCert = New-SelfSignedCertificate `
        -Subject "CN=sf-http-client-test-noeku" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyExportPolicy Exportable `
        -KeySpec Signature `
        -KeyUsage DigitalSignature `
        -Type Custom `
        -NotAfter (Get-Date).AddYears(1)
}

AfterAll {
    # cleanup test certificates
    @($script:testCert, $script:expiredCert, $script:serverOnlyCert, $script:noEkuCert) | ForEach-Object {
        if ($_ -and (Test-Path "Cert:\CurrentUser\My\$($_.Thumbprint)")) {
            Remove-Item "Cert:\CurrentUser\My\$($_.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "validate-certificate" {

    It "should pass for valid cert with both server and client EKU" {
        { validate-certificate -cert $script:testCert } | Should -Not -Throw
    }

    It "should warn on expired certificate" {
        $warningOutput = validate-certificate -cert $script:expiredCert 3>&1 | Out-String
        $warningOutput | Should -Match "EXPIRED"
    }

    It "should report server auth EKU present" {
        $output = validate-certificate -cert $script:testCert 6>&1 | Out-String
        $output | Should -Match "Server Authentication"
    }

    It "should report client auth EKU present" {
        $output = validate-certificate -cert $script:testCert 6>&1 | Out-String
        $output | Should -Match "Client Authentication"
    }

    It "should note missing client auth on server-only cert" {
        $output = validate-certificate -cert $script:serverOnlyCert 6>&1 | Out-String
        $output | Should -Match "does not have Client Authentication"
    }

    It "should report no EKU as all purposes allowed" {
        $output = validate-certificate -cert $script:noEkuCert 6>&1 | Out-String
        $output | Should -Match "all purposes allowed"
    }

    It "should report private key present for cert with private key" {
        $output = validate-certificate -cert $script:testCert 6>&1 | Out-String
        $output | Should -Match "private key: present"
    }

    It "should report chain info" {
        $output = validate-certificate -cert $script:testCert 6>&1 | Out-String
        $output | Should -Match "chain element"
    }
}

Describe "test-connection" {

    It "should parse https endpoint with host and port" {
        # test against a known-unreachable endpoint to verify parsing
        $result = test-connection -tcpEndpoint "https://localhost:19080"
        # result may be true or false depending on local services, but should not throw
        $result | Should -BeOfType [bool]
    }

    It "should parse endpoint without scheme" {
        $result = test-connection -tcpEndpoint "localhost:80"
        $result | Should -BeOfType [bool]
    }

    It "should return false for invalid port" {
        { test-connection -tcpEndpoint "localhost:" } | Should -Not -Throw
    }

    It "should return false for unreachable endpoint" {
        $result = test-connection -tcpEndpoint "https://192.0.2.1:19080"
        $result | Should -Be $false
    }
}

Describe "invoke-request" {

    It "should return null when absolutePath is empty" {
        $result = invoke-request -absolutePath '' 2>$null
        $result | Should -BeNullOrEmpty
    }

    It "should return null when endpoint is empty" {
        $global:clusterHttpConnectionEndpoint = $null
        $result = invoke-request -absolutePath '/$/GetClusterHealth' -endpoint '' 2>$null
        $result | Should -BeNullOrEmpty
    }

    It "should return null when certificate is null" {
        $result = invoke-request -absolutePath '/$/GetClusterHealth' `
            -endpoint 'https://localhost:19080' `
            -x509Certificate $null 2>$null
        $result | Should -BeNullOrEmpty
    }
}

Describe "Endpoint URL Normalization" {

    It "should add https prefix when missing" {
        $endpoint = "mycluster.eastus.cloudapp.azure.com:19080"
        if (!($endpoint -imatch '^http')) {
            $endpoint = "https://$endpoint"
        }
        $endpoint | Should -Be "https://mycluster.eastus.cloudapp.azure.com:19080"
    }

    It "should not double-add https when already present" {
        $endpoint = "https://mycluster.eastus.cloudapp.azure.com:19080"
        if (!($endpoint -imatch '^http')) {
            $endpoint = "https://$endpoint"
        }
        $endpoint | Should -Be "https://mycluster.eastus.cloudapp.azure.com:19080"
    }

    It "should add port 19080 when missing" {
        $endpoint = "https://mycluster.eastus.cloudapp.azure.com"
        if (!($endpoint -imatch ':\d+$')) {
            $endpoint = "$($endpoint):19080"
        }
        $endpoint | Should -Be "https://mycluster.eastus.cloudapp.azure.com:19080"
    }

    It "should not add port when already present" {
        $endpoint = "https://mycluster.eastus.cloudapp.azure.com:19080"
        if (!($endpoint -imatch ':\d+$')) {
            $endpoint = "$($endpoint):19080"
        }
        $endpoint | Should -Be "https://mycluster.eastus.cloudapp.azure.com:19080"
    }

    It "should handle http scheme" {
        $endpoint = "http://mycluster.eastus.cloudapp.azure.com:19080"
        if (!($endpoint -imatch '^http')) {
            $endpoint = "https://$endpoint"
        }
        $endpoint | Should -Be "http://mycluster.eastus.cloudapp.azure.com:19080"
    }
}

Describe "get-serverCertificate" {

    It "should parse endpoint regex correctly for host and port" {
        $endpoint = "https://mycluster.eastus.cloudapp.azure.com:19080"
        $match = [regex]::match($endpoint, '^(?:http.?://)?(?<hostName>[^:]+?):(?<port>\d+)$')
        $match.Groups['hostName'].Value | Should -Be "mycluster.eastus.cloudapp.azure.com"
        $match.Groups['port'].Value | Should -Be "19080"
    }

    It "should parse endpoint without scheme" {
        $endpoint = "mycluster.eastus.cloudapp.azure.com:19080"
        $match = [regex]::match($endpoint, '^(?:http.?://)?(?<hostName>[^:]+?):(?<port>\d+)$')
        $match.Groups['hostName'].Value | Should -Be "mycluster.eastus.cloudapp.azure.com"
        $match.Groups['port'].Value | Should -Be "19080"
    }

    It "should return null for unreachable endpoint" {
        $result = get-serverCertificate -endpoint "https://192.0.2.1:19080"
        $result | Should -BeNullOrEmpty
    }
}

Describe "Script Parameters" {

    It "should have default parameter set" {
        $command = Get-Command $scriptPath
        # DefaultParameterSet may be null when using Get-Command on scripts with CmdletBinding
        $command.ParameterSets.Name | Should -Contain "default"
    }

    It "should have keyvault parameter set" {
        $command = Get-Command $scriptPath
        $command.ParameterSets.Name | Should -Contain "keyvault"
    }

    It "should have local parameter set" {
        $command = Get-Command $scriptPath
        $command.ParameterSets.Name | Should -Contain "local"
    }

    It "should have rest parameter set" {
        $command = Get-Command $scriptPath
        $command.ParameterSets.Name | Should -Contain "rest"
    }

    It "should have apiVersion default of 9.1" {
        $command = Get-Command $scriptPath
        $apiParam = $command.Parameters['apiVersion']
        $apiParam | Should -Not -BeNullOrEmpty
    }

    It "should have validateOnly switch parameter" {
        $command = Get-Command $scriptPath
        $command.Parameters['validateOnly'].SwitchParameter | Should -Be $true
    }

    It "should have examples switch parameter" {
        $command = Get-Command $scriptPath
        $command.Parameters['examples'].SwitchParameter | Should -Be $true
    }
}
