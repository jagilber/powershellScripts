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
    [string]$contentType = "application/json"
)

$global:response = $null
$script:headers = $null
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
$script:nodeTypeExtensions = $null
$script:resourceGroup = $resourceGroup

function main()
{
    
    $script:headers = @{
        'authorization' = "Bearer $($token.access_token)" 
        'accept'        = "*/*"
        'ContentType'   = $contentType
    }

    if (!(get-clusterInfo))
    {
        return 1
    }

    foreach($nodeType in $script:sfnodeTypes)
    {
        if (!(get-nodeTypes -nodeTypeName ($nodeType.Name)))
        {
            return 1
        }
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
    $params = @{ 
        ContentType = $contentType
        Headers     = $script:headers
        Method      = "get"
        uri         = $geturi
    } 

    $script:clustersResponse = (invoke-rest $params)
    write-host "existing clusters:"
    $script:clusters = @($script:clustersResponse.value)

    if ($script:clusters.length -lt 1)
    {
        write-host "unable to enumerate clusters. exiting"
        return $false
    }

    $count = 0
    foreach ($script:cluster in $script:clusters)
    {
        $count++
        write-host "$($count). $($script:cluster.Name)"
    }
    
    if (($number = read-host "enter number of the cluster to query or ctrl-c to exit:") -le $script:clusters.length)
    {
        $script:cluster = $script:clusters[$number - 1]
        $script:clusterName = $script:cluster.Name
        $script:resourceGroup = [regex]::Match($script:cluster.Id,"/resourcegroups/(.+?)/").Groups[1].Value
        write-host $script:resourceGroup
    }

    write-host ($script:cluster | ConvertTo-Json)
    write-host ($script:cluster.properties)

    write-host "cluster cert:" -ForegroundColor Yellow
    $script:clusterCert = $script:cluster.properties.certificate
    write-host ($script:clusterCert)
    write-host "cluster cert primary thumbprint:" -ForegroundColor Yellow
    $script:clusterCertThumbprintPrimary = $script:clusterCert.thumbprint
    write-host $script:clusterCertThumbprintPrimary
    write-host "cluster cert secondary thumbprint:" -ForegroundColor Yellow
    $script:clusterCertThumbprintSecondary = $script:clusterCert.thumbprintSecondary
    write-host $script:clusterCertThumbprintSecondary

    write-host "client cert thumbs:" -ForegroundColor Yellow
    $script:clientCertificateThumbprints = $script:cluster.properties.clientCertificateThumbprints
    write-host ($script:clientCertificateThumbprints)
    write-host "client cert common names:" -ForegroundColor Yellow
    $script:clientCertificateCommonNames = $script:cluster.properties.clientCertificateCommonNames
    write-host ($script:clientCertificateCommonNames)

    write-host "reverse proxy cert:" -ForegroundColor Yellow
    $script:reverseProxyCertificate = $script:cluster.properties.reverseProxyCertificate
    write-host ($script:reverseProxyCertificate)

    write-host "nodetypes:" -ForegroundColor Yellow
    $script:sfnodeTypes = $script:cluster.properties.nodeTypes
    write-host ($script:sfnodeTypes)
}

function get-nodeTypes($nodeTypeName)
{

    $geturi = $baseURI + "/subscriptions/$($SubscriptionID)/resourceGroups/$($script:resourceGroup)/providers/Microsoft.Compute/virtualMachineScaleSets/$($nodeTypeName)"
    write-host $geturi 
    
    # get
    $params = @{ 
        ContentType = $contentType
        Headers     = $script:headers
        Method      = "get"
        uri         = $geturi + $nodeTypeApiVersion
    } 

    $nodeTypesResponse = (invoke-rest $params)
    write-host " nodetypes:" -ForegroundColor Green
    $script:nodeTypes = @($nodeTypesResponse)
    write-host ($script:nodeTypes)

    if ($nodeTypes.length -lt 1)
    {
        write-host "unable to enumerate nodetypes. exiting"
        return $false
    }

    foreach($nodeType in $script:nodeTypes)
    {
        get-nodeTypeExtensions $nodeType.Name
    }

}

function get-nodeTypeExtensions($nodeTypeName)
{
    $geturi = $baseURI + "/subscriptions/$($SubscriptionID)/resourceGroups/$($script:resourceGroup)/providers/Microsoft.Compute/virtualMachineScaleSets/$($nodeTypeName)/extensions"
    write-host $geturi 
    
    # get
    $params = @{ 
        ContentType = $contentType
        Headers     = $script:headers
        Method      = "get"
        uri         = $geturi + $nodeTypeApiVersion
    } 

    $nodeTypesResponse = (invoke-rest $params)
    write-host " nodetype extensions:" -ForegroundColor Green
    $script:nodeTypeExtensions = @($nodeTypesResponse)
    write-host ($script:nodeTypeExtensions)

    if ($script:nodeTypeExtensions.length -lt 1)
    {
        write-host "unable to enumerate nodetype extensions. exiting"
        return $false
    }

    foreach($nodeTypeExtension in $script:nodeTypeExtensions)
    {
        write-host ($nodeTypeExtension | convertto-json -Depth 5)
    }

}


function invoke-rest($params)
{
    write-host $params
    $error.Clear()
    $response = Invoke-RestMethod @params -Verbose -Debug
    #write-host "response: $(ConvertTo-Json -Depth 99 ($response))"
    #write-host "raw response: $($response | out-string)" 
    write-host $error
    $global:response = $response
    return $response
}

main

