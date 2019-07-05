<#
    creates new azurermadapplication for use with logging in to azurerm using password or cert
    to enable script execution, you may need to Set-ExecutionPolicy Bypass -Force

    # can be used with scripts for example
    # connect-azurermaccount -ServicePrincipal -CertificateThumbprint $cert.Thumbprint -ApplicationId $app.ApplicationId -TenantId $tenantId
    # requires free AAD base subscription
    # https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-authenticate-service-principal#provide-credentials-through-automated-powershell-script
    
    example command:
    iwr https://tinyurl.com/create-azure-client-id -UseBasicParsing| iex

    example command to save and/or pass arguments:
    (new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-rm-create-aad-application-spn.ps1","$(get-location)\azure-rm-create-aad-application-spn.ps1");
    then:
    .\azure-rm-create-aad-application-spn.ps1 -aadDisplayName azure-rm-rest-logon -logontype certthumb
    or
    .\azure-rm-create-aad-application-spn.ps1 
    
    # 190209
#>
param(
    [pscredential]$credentials,
    [string]$aadDisplayName = "azure-rm-rest-logon/$($env:Computername)",
    [string]$certStore = "cert:\CurrentUser\My",
    [string]$uri,
    [switch]$list,
    [string]$pfxPath = "$($env:temp)\$($aadDisplayName).pfx",
    [string]$logonType = 'certthumb'
)

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $retryCount = 10
    $cert = $null
    $keyCredential = $null
    $thumbprint = $null
    $ClientSecret = $null
    $keyvalue = $Null
    $error.Clear()
    $app = $null

    # authenticate
    try
    {
        get-command connect-azurermaccount | Out-Null
    }
    catch [management.automation.commandNotFoundException]
    {
        if ((read-host "azurerm not installed but is required for this script. is it ok to install?[y|n]") -imatch "y")
        {
            write-host "installing minimum required azurerm modules..."
            install-module azurerm.profile
            install-module azurerm.resources
            import-module azurerm.profile
            import-module azurerm.resources
        }
        else
        {
            return 1
        }
    }
    
    if (!(Get-AzureRmResourceGroup))
    {
        connect-azurermaccount
    
        if (!(Get-AzureRmResourceGroup))
        {
            Write-Warning "unable to authenticate to azurerm. returning..."
            return 1
        }
    }

    if (!$uri)
    {
        $uri = "https://$($aadDisplayName)"
    }

    $tenantId = (Get-AzureRmContext).Tenant.Id

    if ((Get-AzureRmADApplication -DisplayNameStartWith $aadDisplayName -ErrorAction SilentlyContinue))
    {
        $app = Get-AzureRmADApplication -DisplayNameStartWith $aadDisplayName

        if ((read-host "AAD application exists: $($aadDisplayName). Do you want to delete?[y|n]") -imatch "y")
        {
            remove-AzureRmADApplication -objectId $app.objectId -Force
            $app = $null
            $id = Get-AzureRmADServicePrincipal -SearchString $aadDisplayName
        
            if (@($id).Count -eq 1)
            {
                Remove-AzureRmADServicePrincipal -ObjectId $id
            }
        }
    }

    $certs = @(Get-ChildItem $certStore | Where-Object {$_.Subject -imatch "$($aadDisplayName)" -and $_.NotAfter -gt (get-date)})

    if($certs.Count -ge 1)
    {
        $count = 1

        foreach($certItem in $certs)
        {
            "$($count). $($certItem.Subject) $($certItem.NotAfter) $($certItem.Thumbprint)"
            $count++
        }

        if(($result = read-host "enter line number of existing cert to use or 0 to create new. normally an existing cert from list should be used.") -gt 0)
        {
            $cert = $certs[$result]
        }

    }
    
    if (!$list)
    {
        if ($logontype -ieq 'cert')
        {
            Write-Warning "this does not work for rest authentication, but does work for ps auth"
            
            if(!$cert)
            {
                $cert = New-SelfSignedCertificate -CertStoreLocation $certStore `
                    -Subject "CN=$($aadDisplayName)" `
                    -KeyExportPolicy Exportable `
                    -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
            }
            
            if (!$credentials)
            {
                $credentials = (get-credential)
            }

            $securePassword = ConvertTo-SecureString -String $credentials.Password -Force -AsPlainText

            if([io.file]::Exists($pfxPath))
            {
                [io.file]::Delete($pfxPath)
            }

            Export-PfxCertificate -cert "cert:\currentuser\my\$($cert.thumbprint)" -FilePath $pfxPath -Password $securePassword
            $cert509 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate($pfxPath, $securePassword)
            $thumbprint = $cert509.thumbprint
            $keyValue = [System.Convert]::ToBase64String($cert509.GetCertHash())
            write-host "New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -CertValue $keyValue -EndDate $cert.NotAfter -StartDate $cert.NotBefore"

            if($oldAdApp = Get-AzureRmADApplication -DisplayNameStartWith $aadDisplayName)
            {
                remove-AzureRmADApplication -ObjectId $oldAdApp.objectId
            }
            
            $DebugPreference = "Continue"    
            
            if(!$app)
            {
                write-host "New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -CertValue $keyValue -EndDate $($cert.NotAfter) -StartDate $($cert.NotBefore) -verbose"
                $app = New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -CertValue ($cert.GetRawCertData()) -EndDate ($cert.NotAfter) -StartDate ($cert.NotBefore) -verbose #-Debug 
            }

            $app            
            #$DebugPreference = "SilentlyContinue"
            $app = New-AzureRmADAppCredential -applicationId ($app.ApplicationId) -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -KeyCredentials $KeyCredential -Verbose

        }
        elseif ($logontype -ieq 'certthumb')
        {
            if(!$cert)
            {
                $cert = New-SelfSignedCertificate -CertStoreLocation $certStore `
                    -Subject "$($aadDisplayName)" `
                    -KeyExportPolicy Exportable `
                    -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
            }

            $keyValue = [System.Convert]::ToBase64String($cert.GetCertHash())
            $thumbprint = $cert.Thumbprint
            $ClientSecret = [System.Convert]::ToBase64String($cert.GetCertHash())
            $securePassword = ConvertTo-SecureString -String $ClientSecret -Force -AsPlainText
            write-host "New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -Password $securePassword -EndDate $($cert.NotAfter)"

            if(!$app)
            {
                $app = New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -Password $securePassword -EndDate ($cert.NotAfter)
            }
        }
        elseif ($logontype -ieq 'key')
        {
            $bytes = New-Object Byte[] 32
            $rand = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $rand.GetBytes($bytes)

            $ClientSecret = [System.Convert]::ToBase64String($bytes)
            $securePassword = ConvertTo-SecureString -String $ClientSecret -Force -AsPlainText
            $endDate = [System.DateTime]::Now.AddYears(2)

            if(!$app)
            {
                $app = New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $URI -IdentifierUris $URI -Password $securePassword -EndDate $endDate
            }

            write-host "client secret: $($ClientSecret)" -ForegroundColor Yellow

        }
        else
        {
            write-warning "credentials need to be psadcredentials to work"
            if (!$credentials)
            {
                write-warning "no credentials, exiting"
                exit 1
            }
            # to use password
            if(!$app)
            {
                $app = New-AzureRmADApplication -DisplayName $aadDisplayName -HomePage $uri -IdentifierUris $uri -PasswordCredentials $credentials
            }
        }

        $app
        $count = 0

        while ($count -lt $retryCount)
        {
            #todo check if principal exists
            $error.clear()
            start-sleep -Seconds 10
            write-host "attempt $count New-AzureRmADServicePrincipal -ApplicationId $($app.ApplicationId)" # -DisplayName $aadDisplayName"
            New-AzureRmADServicePrincipal -ApplicationId ($app.ApplicationId) #-DisplayName $aadDisplayName
            if(!$error)
            {
                break
            }
            $count++
        }
        
        if($error)
        {
            write-error "unable to add new principal, exiting"
            return 1
        }

        $count = 0

        while ($count -lt $retryCount)
        {
            try 
            {
                write-host "$($count) -- sleeping 10 seconds while new service principal is created."
                start-sleep -Seconds 10
                write-host "attempt $($count) to add role assignments read and contribute"
                New-AzureRmRoleAssignment -RoleDefinitionName Reader -ServicePrincipalName ($app.ApplicationId)
                
                if (!$error)
                {
                    write-host "role assignments read added" -ForegroundColor green
                    write-host "to remove 'read' permissions, run: Remove-AzureRmRoleAssignment -RoleDefinitionName Reader -ServicePrincipalName $($app.ApplicationId)"
                }

                if (!$error)
                {
                    New-AzureRmRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName ($app.ApplicationId)
                    write-host "role assignments contribute added" -ForegroundColor green
                    write-host "to remove 'contributor' permissions, run: Remove-AzureRmRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $($app.ApplicationId)"
                    break
                }
            }
            catch 
            {
                if($error -imatch "401")
                {
                    write-error ($error | out-string)
                    write-warning "unable to add role assignments read and or contribute due to permissions."
                    break
                }
            }
    
            write-verbose ($error | out-string)
            $error.Clear()
            $count++
        }

        if ($logontype -ieq 'cert' -or $logontype -ieq 'certthumb')
        {
            write-host "for use in script: connect-azurermaccount -ServicePrincipal -CertificateThumbprint $($cert.Thumbprint) -ApplicationId $($app.ApplicationId) -TenantId $($tenantId)"
            write-host "certificate thumbprint: $($cert.Thumbprint)"
            
        }
    } 

    $app
    write-host "application id: $($app.ApplicationId)" -ForegroundColor Cyan
    write-host "tenant id: $($tenantId)" -ForegroundColor Cyan
    write-host "application identifier Uri: $($uri)" -ForegroundColor Cyan
    write-host "keyValue: $($keyValue)" -ForegroundColor Cyan
    write-host "clientsecret: $($clientsecret)" -ForegroundColor Cyan
    write-host "clientsecret BASE64:$([convert]::ToBase64String([text.encoding]::Unicode.GetBytes($clientsecret)))"
    write-host "thumbprint: $($thumbprint)" -ForegroundColor Cyan
    write-host "pfx path: $($pfxPath)" -ForegroundColor Cyan
    $global:thumbprint = $thumbprint
    $global:applicationId = $app.Applicationid
    $global:tenantId = $tenantId
    $global:clientSecret = $ClientSecret
    $global:keyValue = $keyValue
    write-host "clientid / applicationid saved in `$global:applicationId" -ForegroundColor Yellow
    write-host "clientsecret / base64 thumb saved in `$global:clientSecret" -ForegroundColor Yellow

}
# ----------------------------------------------------------------------------------------------------------------

main