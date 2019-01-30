<#
# https://docs.microsoft.com/en-us/rest/api/servicefabric/sfrp-api-clusters_get
#/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.ServiceFabric/clusters/{clusterName}?api-version=2016-09-01
#>

param(
    [object]$token = $global:token,
    [string]$SubscriptionID = "$(@(Get-AzureRmSubscription)[0].Id)",
    [string]$baseURI = "https://management.azure.com" ,
    [string]$clusterApiVersion = "?api-version=2018-02-01" ,
    [string]$nodeTypeApiVersion = "?api-version=2018-06-01",
    [string]$resourceGroup,
    [string]$script:clusterName,
    [string]$contentType = "application/json",
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
$script:reverseProxyCertificate = $null
$script:sfnodeTypes = $null
$script:nodeTypes = $null
#$script:nodeTypeExtensions = $null
$script:resourceGroup = $resourceGroup
#$script:sfExtensionCertInfo = $null
#$script:sfExtensionReverseProxyCertInfo = $null
$script:vmExtensions = [collections.arraylist]@()
$script:vmProfiles = [collections.arraylist]@()

function main()
{
    
    if (!(get-clusterInfo))
    {
        return 1
    }

    foreach($nodeType in $script:sfnodeTypes)
    {
        if (!(get-nodeTypInfo -nodeTypeName ($nodeType.Name)))
        {
            return 1
        }
    }

    if($verify -and !(verify-certConfig))
    {

    }
}

function get-clusterInfo()
{
    #https://docs.microsoft.com/en-us/rest/api/servicefabric/sfrp-model-clusterpropertiesupdateparameters
    if ($resourceGroup -and $script:clusterName)
    {
        $geturi = $baseURI + "/subscriptions/$($SubscriptionID)/resourceGroups/$($script:resourceGroup)/providers/Microsoft.ServiceFabric/clusters/$($script:clusterName)" + $clusterApiVersion
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
        $script:clusterName = $script:cluster.Name
        $script:resourceGroup = [regex]::Match($script:cluster.Id,"/resourcegroups/(.+?)/").Groups[1].Value
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
    $script:reverseProxyCertificate = $script:cluster.properties.reverseProxyCertificate
    write-host ($script:reverseProxyCertificate | convertto-json)

    write-host "sf nodetypes:" -ForegroundColor Yellow
    $script:sfnodeTypes = $script:cluster.properties.nodeTypes
    write-verbose ($script:sfnodeTypes | convertto-json)
    write-host ($script:sfnodeTypes| select name,vmInstanceCount,isPrimary | convertto-json -Depth 1)
}

function get-nodeTypeInfo($nodeTypeName)
{

    $geturi = $baseURI + "/subscriptions/$($SubscriptionID)/resourceGroups/$($script:resourceGroup)/providers/Microsoft.Compute/virtualMachineScaleSets/$($nodeTypeName)"
    write-host $geturi 
    
    $nodeTypesResponse = (invoke-rest ($geturi + $nodeTypeApiVersion))
    write-host "nodetypes:" -ForegroundColor Green
    $script:nodeTypes = @($nodeTypesResponse)
    write-host ($script:nodeTypes| select name,id,tags | convertto-json -Depth 1)
    write-verbose ($script:nodeTypes | convertto-json -Depth 1)

    if ($nodeTypes.length -lt 1)
    {
        write-host "unable to enumerate nodetypes. exiting"
        return $false
    }

    foreach($nodeType in $script:nodeTypes)
    {

        $vmProfile = $nodeType.properties.virtualMachineProfile
        $script:vmProfiles.Add($vmProfile)
        $osProfile = $vmProfile.osProfile
        $script:nodeTypeSecrets = $osProfile.secrets
        
        write-verbose ($script:nodeTypeSecrets | convertto-json -Depth 5)
        write-host "nodetype secrets info:" -ForegroundColor Green
        $count = 1

        foreach($secret in $script:nodeTypeSecrets)
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
    $nodeTypesResponse = (invoke-rest $geturi)
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
    $script:headers = @{
        'authorization' = "Bearer $($token.access_token)" 
        'accept'        = "*/*"
        'ContentType'   = $contentType
    }

    $params = @{ 
        ContentType = $contentType
        Headers     = $script:headers
        Method      = "get"
        uri         = $uri
    } 

    write-host $params
    $error.Clear()
    $response = Invoke-RestMethod @params -Verbose -Debug
    #write-host "response: $(ConvertTo-Json -Depth 99 ($response))"
    #write-host "raw response: $($response | out-string)" 
    write-host $error
    $global:response = $response
    return $response
}

function verify-certConfig()
{
    $retVal = $false
    write-host "checking cert configuration"
    # check local store and connect to cluster if cert exists?
    # check certs on nodes?
    # check cert expiration?
    # check cert CA?
    write-host "checking cert configuration key vault"
    write-host "checking cert configuration key vault certificates"
    write-host "checking cert configuration sf <-> vmss "

    return $retVal
}

main

