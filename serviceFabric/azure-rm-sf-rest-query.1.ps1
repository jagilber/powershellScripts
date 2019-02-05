<#
## TESTING ##
# script to test service fabric certificate settings
# https://docs.microsoft.com/en-us/rest/api/servicefabric/sfrp-api-clusters_get
#/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.ServiceFabric/clusters/{clusterName}?api-version=2016-09-01
#>

param(
    [object]$token = $global:token,
    [string]$SubscriptionID = (Get-AzureRmContext).Subscription.Id,
    [string]$baseURI = "https://management.azure.com" ,
    [string]$clusterApiVersion = "?api-version=2018-02-01" ,
    [string]$nodeTypeApiVersion = "?api-version=2018-06-01",
    [string]$keyVaultApiVersion = "?api-version=7.0",
    [string]$location = "eastus",
    [string]$clusterName,
    [bool]$verify = $true
)

$global:response = $null
$params = $null
$geturi = $null


$script:cluster = $null
$script:clusterCert = $null
$script:clusterCertThumbprintPrimary = $null
$script:clusterCertThumbprintSecondary = $null

$script:clientCertificateThumbprints = $null
$script:clientCertificateCommonNames = $null

$script:reverseProxyCert = $null
$script:reverseProxyCertThumbprintPrimary = $null
$script:reverseProxyCertThumbprintSecondary = $null

$script:sfnodeTypes = $null
$script:nodeTypes = $null
$script:resourceGroup = $resourceGroup
$script:vmExtensions = [collections.arraylist]@()
$script:vmProfiles = [collections.arraylist]@()

$contentType = "application/json"
function main()
{
    
    if (!(get-clusterInfo))
    {
        return 1
    }

    foreach ($nodeType in $script:sfnodeTypes)
    {
        if (!(get-nodeTypeInfo -nodeTypeName ($nodeType.Name)))
        {
            return 1
        }
    }

    if ($verify -and !(verify-certConfig))
    {
        return 1
    }
}

function get-clusterInfo()
{
    #https://docs.microsoft.com/en-us/rest/api/servicefabric/sfrp-model-clusterpropertiesupdateparameters
    if ($resourceGroup -and $clusterName)
    {
        $geturi = $baseURI + "/subscriptions/$($SubscriptionID)/resourceGroups/$($script:resourceGroup)/providers/Microsoft.ServiceFabric/clusters/$($clusterName)" + $clusterApiVersion
    }
    else
    {
        $geturi = $baseURI + "/subscriptions/$($SubscriptionID)/providers/Microsoft.ServiceFabric/clusters" + $clusterApiVersion
    }

    $geturi 

    # get
    $script:clustersResponse = invoke-rest $geturi
    write-host "existing clusters:"
    $script:clusters = @($script:clustersResponse.value)

    if ($script:clusters.length -lt 1)
    {
        write-host "unable to enumerate clusters. exiting"
        return $false
    }

    $count = 1
    foreach ($script:cluster in $script:clusters)
    {
        write-host "$($count). $($script:cluster.Name)"
        $count++
    }
    
    if (($number = read-host "enter number of the cluster to query or ctrl-c to exit:") -le $script:clusters.length)
    {
        $script:cluster = $script:clusters[$number - 1]
        $clusterName = $script:cluster.Name
        $script:resourceGroup = [regex]::Match($script:cluster.Id, "/resourcegroups/(.+?)/").Groups[1].Value
        write-host $script:resourceGroup
    }

    write-verbose ($script:cluster | ConvertTo-Json)
    write-host ($script:cluster.properties)

    write-host "cluster cert:" -ForegroundColor Yellow
    $script:clusterCert = $script:cluster.properties.certificate
    write-host ($script:clusterCert  | convertto-json)
    write-host "cluster cert primary thumbprint:" -ForegroundColor Yellow
    $script:clusterCertThumbprintPrimary = $script:clusterCert.thumbprint
    write-host $script:clusterCertThumbprintPrimary
    write-host "cluster cert secondary thumbprint:" -ForegroundColor Yellow
    $script:clusterCertThumbprintSecondary = $script:clusterCert.thumbprintSecondary
    write-host $script:clusterCertThumbprintSecondary

    write-host "client cert thumbs:" -ForegroundColor Yellow
    $script:clientCertificateThumbprints = $script:cluster.properties.clientCertificateThumbprints
    write-host ($script:clientCertificateThumbprints | convertto-json)
    write-host "client cert common names:" -ForegroundColor Yellow
    $script:clientCertificateCommonNames = $script:cluster.properties.clientCertificateCommonNames
    write-host ($script:clientCertificateCommonNames | convertto-json)

    write-host "reverse proxy cert:" -ForegroundColor Yellow
    $script:reverseProxyCert = $script:cluster.properties.reverseProxyCertificate
    write-host ($script:reverseProxyCert | convertto-json)
    write-host "reverse proxy cert primary thumbprint:" -ForegroundColor Yellow
    $script:reverseProxyCertThumbprintPrimary = $script:reverseProxyCert.thumbprint
    write-host $script:reverseProxyCertThumbprintPrimary
    write-host "reverse proxy cert secondary thumbprint:" -ForegroundColor Yellow
    $script:reverseProxyCertThumbprintSecondary = $script:reverseProxyCert.thumbprintSecondary
    write-host $script:reverseProxyCertThumbprintSecondary

    write-host "sf nodetypes:" -ForegroundColor Yellow
    $script:sfnodeTypes = $script:cluster.properties.nodeTypes
    write-verbose ($script:sfnodeTypes | convertto-json)
    write-host ($script:sfnodeTypes| select name, vmInstanceCount, isPrimary | convertto-json -Depth 1)
}

function get-nodeTypeInfo($nodeTypeName)
{

    $geturi = $baseURI + "/subscriptions/$($SubscriptionID)/resourceGroups/$($script:resourceGroup)/providers/Microsoft.Compute/virtualMachineScaleSets/$($nodeTypeName)"
    write-host $geturi 
    
    $nodeTypesResponse = (invoke-rest ($geturi + $nodeTypeApiVersion))
    write-host "nodetypes:" -ForegroundColor Green
    $script:nodeTypes = @($nodeTypesResponse)
    write-host ($script:nodeTypes| select name, id, tags | convertto-json -Depth 1)
    write-verbose ($script:nodeTypes | convertto-json -Depth 1)

    if ($nodeTypes.length -lt 1)
    {
        write-host "unable to enumerate nodetypes. exiting"
        return $false
    }

    foreach ($nodeType in $script:nodeTypes)
    {

        $vmProfile = $nodeType.properties.virtualMachineProfile
        $script:vmProfiles.Add($vmProfile)
        $osProfile = $vmProfile.osProfile
        $script:nodeTypeSecrets = $osProfile.secrets
        
        write-verbose ($script:nodeTypeSecrets | convertto-json -Depth 5)
        write-host "nodetype secrets info:" -ForegroundColor Green
        $count = 1

        foreach ($secret in $script:nodeTypeSecrets)
        {
            write-host "nodetype secret $count" -ForegroundColor Green
            write-host "nodetype secret source vault $count" -ForegroundColor Green
            write-host $secret.sourceVault.id
            write-host "nodetype secret source vault certificates $count" -ForegroundColor Green
            write-host ($secret.vaultCertificates | convertto-json)
            $count++
        }

        get-nodeTypeExtensions $nodeType.Name
    }

}

function get-nodeTypeExtensions($nodeTypeName)
{
    $geturi = $baseURI + "/subscriptions/$($SubscriptionID)/resourceGroups/$($script:resourceGroup)/providers/Microsoft.Compute/virtualMachineScaleSets/$($nodeTypeName)/extensions"
    write-host $geturi 
    $nodeTypesResponse = invoke-rest ($geturi + $nodeTypeApiVersion)
    write-verbose "nodetype extensions:"
    $nodeTypeExtensions = @($nodeTypesResponse)
    write-verbose ($nodeTypeExtensions.value.properties | convertto-json)

    if ($nodeTypeExtensions.length -lt 1)
    {
        write-host "unable to enumerate nodetype extensions. exiting"
        return $false
    }

    $sfExtension = $nodeTypeExtensions.value.properties |where-object type -imatch 'ServiceFabricNode'
    $script:vmExtensions.Add($sfExtension)
    $sfExtensionSettings = $sfExtension.settings
    $sfExtensionCertInfo = $sfExtensionSettings.certificate
    $sfExtensionReverseProxyCertInfo = $sfExtensionSettings.reverseProxycertificate
    write-host "nodetype sf extension certificate info:" -ForegroundColor Green
    write-host $sfExtensionSettings.nodeTypeRef
    write-host "nodetype sf extension certificate:" -ForegroundColor Green
    write-host ($sfExtensionCertInfo | convertto-json)
    write-host "nodetype sf extension reverse proxy certificate:" -ForegroundColor Green
    write-host ($sfExtensionReverseProxyCertInfo | convertto-json)
}

function invoke-rest($uri)
{
    $headers = @{
        'authorization' = "Bearer $($token.access_token)" 
        'accept'        = "*/*"
        'ContentType'   = $contentType
    }

    $params = @{ 
        ContentType = $contentType
        Headers     = $headers
        Method      = "get"
        uri         = $uri
    } 

    write-host $params
    $error.Clear()
    $response = Invoke-RestMethod @params -Verbose -Debug
    write-verbose "response: $response"
    write-host $error
    $global:response = $response
    return $response
}

function invoke-web($uri, $method, $body = "")
{
    $headers = @{
        'authorization' = "Bearer $($token.access_token)" 
        'ContentType'   = $contentType
    }

    $params = @{ 
        ContentType = $contentType
        Headers     = $headers
        Method      = $method
        uri         = $uri
        timeoutsec  = 600
    }

    if($method -imatch "post")
    {
        $params.Add('body', $body)
    }

    write-host ($params | out-string)
    $error.Clear()
    $response = Invoke-WebRequest @params -Verbose -Debug
    $error.Clear()

    write-host ($response | convertto-json) -ForegroundColor Green -ErrorAction SilentlyContinue

    if($error)
    {
        write-host ($response) -ForegroundColor DarkGreen
        $error.Clear()
    }

    if($method -imatch "post")
    {
        $statusUri = ($response.Headers.'Azure-AsyncOperation')

        while(!($error))
        {
            $response = (invoke-web -uri $statusUri -method "get")
            write-host ($response | out-string)
            
            if(!($response.StatusCode -eq 200))
            {
                break
            }
            
            $result = $response.Content | convertfrom-json

            if($result.status -imatch "inprogress")
            {
                start-sleep -seconds 10
            }
            elseif($result.status -imatch "succeeded")
            {
                write-host ($result.properties.output.value.message)
                break
            }
            elseif($result.status -imatch "canceled")
            {
                write-warning "action canceled"
                break
            }
            else
            {
                write-warning "unknown status $($result.status)"
                break
            }
        }

    }

    write-verbose "response: $response"
    write-host $error
    $global:response = $response
    return $response
}

function run-vmssPsCommand ($resourceGroup, $vmssName, $instanceId, [string]$script, [collections.arraylist]$parameters)
{
    # first run can take 15 minutes! has to install run extension?
    # simple subsequent commands can take minimum 30 sec

    if(!$script)
    {
        return $false
    }

    if((test-path $script))
    {
        write-host "reading file $script"
        $scriptList = [collections.arraylist]@([io.file]::readAllLines($script))
    }
    else
    {
        $scriptList = [collections.arraylist]@($script.split("`r`n",[stringsplitoptions]::removeEmptyEntries))
    }
    
    write-host $scriptList 
    
    $posturl = "$($baseUri)/subscriptions/$($subscriptionId)/resourceGroups/$($resourceGroup)/providers/Microsoft.Compute/virtualMachineScaleSets/$($vmssName)/virtualmachines/$($instanceId)/runCommand$($nodeTypeApiVersion)"
    $body = @{
        'commandId' = 'RunPowerShellScript'
        'script' = $scriptList
    } 

    if($parameters)
    {
        $body.Add('parameters',$parameters)
    }

    write-host ($body | convertto-json)
    $response = invoke-web -uri $posturl -method "post" -body ($body | convertto-json)
    write-host ($response | out-string)
    $result = $response.content | convertfrom-json
    write-host ($result.properties.output.value.message)

    return ($result.properties.output.value.message)
}

function verify-certConfig()
{
    <#
    $script:cluster
    $script:clusterCert
    $script:clusterCertThumbprintPrimary
    $script:clusterCertThumbprintSecondary
    $script:clientCertificateThumbprints
    $script:clientCertificateCommonNames
    
    $script:sfnodeTypes
    $script:nodeTypes
    $script:resourceGroup
    $script:vmExtensions
    $script:vmProfiles
    #>

    $retVal = $false
    write-host "checking cert configuration"
    # check local store and connect to cluster if cert exists?
    # check certs on nodes?
    # check cert expiration?
    # check cert CA?
    write-host "checking cert configuration key vault"
    write-host "checking cert configuration key vault certificates"
    write-host "checking cert configuration sf <-> vmss "

    $script:vmExtensions
    
    $retval = verify-keyVault ($Script:vmProfiles.osProfile.secrets)
    $retval = $retval -and (verify-nodeCertStore)

    write-host "checking cert configuration completed"
    return $retVal
}

function verify-keyVault($secrets)
{
    # cant test rest
    write-host $secrets.sourceVault
    write-host $secrets.vaultCertificates
    # The GET operation is applicable to any secret stored in Azure Key Vault. This operation requires the secrets/get permission.
    # https://docs.microsoft.com/en-us/rest/api/keyvault/getsecret/getsecret
    # https://docs.microsoft.com/en-us/azure/key-vault/key-vault-group-permissions-for-apps
    # /subscriptions/$($subscriptionId)/resourceGroups/certsjagilber/providers/Microsoft.KeyVault/vaults/sfjagilber
    # https://sfjagilber.vault.azure.net/secrets/sfjagilber/87fcb8695bcb4ac6ba103b7bbfd04911

    $pattern = "//(?<vaultName>.+?)\.vault\.azure\.net/secrets/(?<secretName>.+?)/"
    $error.Clear()

    
    foreach ($secret in $secrets)
    {
        write-verbose ($secret | convertto-json)
        $match = [regex]::Match($secret.vaultCertificates.certificateUrl, $pattern)
        $secretName = $match.Groups['secretName'].value
        $vaultName = $match.Groups['vaultName'].value
        write-host "checking secret:$secretname in vault:$vaultName" -ForegroundColor Cyan

        $geturi = $secret.vaultCertificates.certificateUrl + $keyVaultApiVersion
        write-host $geturi
        $response = invoke-web $geturi
        
        if(!($error))
        {
            write-host ($response)
            $result = $response | convertfrom-json
            if(!($result.attributes.enabled) -or ($result.attributes.exp -lt (get-date)))
            {
                Write-Warning "cert not valid! check if enabled and not expired"    
                return $false
            }
        }
        elseif($error -and $error -imatch "401")
        {
            write-host "to verify secret permissions, applicationid needs vault / key / secret 'get' rights in 'access policies' "
            write-host "https://docs.microsoft.com/en-us/rest/api/keyvault/getsecret/getsecret"
        
            if(get-command -name Get-AzureKeyVaultSecret)
            {
                if(!(get-azurermresource))
                {
                    add-azurermaccount
                }
                $kvsecret = Get-AzureKeyVaultSecret -VaultName $vaultName -Name $secretName
                write-host ($kvsecret | out-string)

                if (!($kvsecret.Enabled) -or ($kvsecret.Expires -lt (get-date)))
                {
                    Write-Warning "cert not valid! check if enabled and not expired"    
                    return $false
                }

                $error.Clear()
            }
            else
            {
                return $false;
            }
        }
    }

    if ($error)
    {
        $error.Clear()
        Write-Warning "error in azure rm keyvault validation. returning false."
        return $false            
    }

    Write-host "keyvault(s) and cert(s) validated. returning true." -ForegroundColor Cyan
    return $true
}

function verify-nodeCertStore
{
    $retval = $false
    $parameters = [collections.arraylist]@() # @{}

    foreach($nodetype in $script:sfnodeTypes)
    {
        for($i = 0;$i -lt $nodetype.vmInstanceCount; $i++)
        {
            # send match for every populated value and return True if all matched
            $thumbArray = @($script:clusterCertThumbprintPrimary,$script:clusterCertThumbprintSecondary,$script:reverseProxyCertThumbprintPrimary,$script:reverseProxyCertThumbprintSecondary)
            $joinstring = $thumbArray -join ","
            $thumbArray = $joinstring.Split(",",[StringSplitOptions]::RemoveEmptyEntries)
            $parameters.Add(@{"name" = "patterns";"value" = "$($thumbArray -join ",")"})

            $result = run-vmssPsCommand -resourceGroup $script:resourceGroup -vmssName $nodeType.Name -instanceId $i -script (node-psCertScript) -parameters $parameters
            write-host "node ps command result:$($result)" -ForegroundColor Magenta

            $retval = $retval -and ($result -imatch "True")
        }

        return $retval
    }
}

function node-psCertScript()
{
    return @'
        param($patterns)
        $certInfo = Get-ChildItem -path cert: -recurse | Out-String
        $patterns = @($patterns.split(",",[stringsplitoptions]::RemoveEmptyEntries))
        $patternMatch = $patterns.length
        $patterns | ForEach-Object {if($certInfo -imatch $_) { $patternMatch--}}
        $patternMatch -eq 0
'@
}

main

