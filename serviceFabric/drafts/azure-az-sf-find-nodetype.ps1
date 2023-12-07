<#
.Synopsis

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/drafts/azure-az-sf-find-nodetype.ps1.ps1" -outFile "$pwd/azure-az-sf-find-nodetype.ps1.ps1";
    ./azure-az-sf-find-nodetype.ps1.ps1 -resourceGroupName <resource group name> -clusterName <cluster name> -referenceNodeTypeName <nt1> -newNodeTypeName <nt2>
.PARAMETER resourceGroupName
    the resource group name of the service fabric cluster
.PARAMETER clusterName
    the name of the service fabric cluster
.PARAMETER referenceNodeTypeName
    the name of the existing node type to use as a reference for the new node type

.EXAMPLE
    ./azure-az-sf-find-nodetype.ps1.ps1 -resourceGroupName <resource group name>
#>

[CmdletBinding(DefaultParameterSetName = "Platform")]
param(
    [Parameter(ParameterSetName = 'Custom', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Platform', Mandatory = $true)]
    $resourceGroupName = '', #'sfcluster',

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $clusterName = $resourceGroupName,
        
    [Parameter(ParameterSetName = 'Custom', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Platform', Mandatory = $true)]
    $referenceNodeTypeName = 'nt0', #'nt0',

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    [switch]$loadFunctions
)

$PSModuleAutoLoadingPreference = 'auto'
$vmssName = $referenceNodeTypeName

function main() {
    write-console "starting..."
    $error.Clear()

    # convert-fromjson -ashashtable requires ps version 6+
    if ($psversiontable.psversion.major -lt 6) {
        write-console "powershell version 6+ required. use pwsh.exe" -foregroundColor 'Red'
        return
    }

    if (!(Get-Module az)) {
        Import-Module az
    }

    if (!(get-azresourceGroup)) {
        Connect-AzAccount
    }

    $clusterEndpoint = get-sfClusterEndpoint $resourceGroupName $clusterName
    if (!$clusterEndpoint) {
        write-console "service fabric cluster $clusterName not found" -err
        return $error
    }

    $vmss = get-referenceNodeTypeVMSS $referenceNodeTypeName $clusterEndpoint
    if (!$vmss) {
        write-console "reference node type $referenceNodeTypeName does not exist" -err
        return $error
    }

    if ($vmssName -ine $vmss.Name) {
        write-console "reference node type $referenceNodeTypeName does not match vmss name $($vmss.Name)" -warn
        $vmssName = $vmss.Name
    }

    try {
        $error.Clear()

        $serviceFabricResource = get-sfResource -resourceGroupName $resourceGroupName -clusterName $clusterName

        if (!$serviceFabricResource) {
            write-console "service fabric cluster $clusterName not found" -err
            return $error
        }
        write-console $serviceFabricResource.ResourceId

        $referenceVmssCollection = get-vmssResources -resourceGroupName $resourceGroupName -vmssName $vmssName
        write-console $referenceVmssCollection.ResourceId

    }
    catch [Exception] {
        $errorString = "exception: $($psitem.Exception.Response.StatusCode.value__)`r`nexception:`r`n$($psitem.Exception.Message)`r`n$($error | out-string)`r`n$($psitem.ScriptStackTrace)"
        write-console $errorString -foregroundColor 'Red'
    }
    finally {
        write-console "finished"
    }
}

function compare-sfExtensionSettings($settings, $clusterEndpoint, $nodeTypeRef) {
    write-console "compare-sfExtensionSettings:`$settings,$clusterEndpoint,$nodeTypeRef"
    if (!$settings) {
        write-console "settings not found" -foregroundColor 'Yellow'
        return $error
    }

    $clusterEndpointRef = $settings.ClusterEndpoint
    if (!$clusterEndpointRef) {
        write-console "cluster endpoint not found" -err
        return $error
    }

    $nodeRef = $settings.NodeTypeRef
    if (!$nodeRef) {
        write-console "node type ref not found" -err
        return $error
    }

    if ($clusterEndpointRef -ieq $clusterEndpoint -and $nodeTypeRef -ieq $nodeRef) {
        write-console "node type ref: $nodeTypeRef matches reference node type: $nodeRef" -foregroundColor 'Green'
        return $true
    }
    else {
        write-console "node type ref: $nodeTypeRef does not match reference node type: $nodeRef" -foregroundColor 'Yellow'
        write-console "cluster endpoint ref: $clusterEndpointRef does not match cluster endpoint: $clusterEndpoint" -foregroundColor 'Yellow'
        return $false
    }
}

function convert-fromJson($json, $display = $false) {
    write-console "convert-fromJson:$json" -verbose:$display
    $object = $json | convertfrom-json -asHashTable
  
    return $object
}

function convert-toJson($object, $display = $false) {
    $json = $object | convertto-json -Depth 99
    write-console $json -verbose:$display  
  
    return $json
}

function get-referenceNodeTypeVMSS($referenceNodeTypeName, $clusterEndpoint) {
    # nodetype name should match vmss name but not always the case
    # get-azvmss returning jobject 23-11-29 mitigation to use get-azresource
    #$referenceVmss = Get-AzVmss -ResourceGroupName $resourceGroupName -VMScaleSetName $referenceNodeTypeName -ErrorAction SilentlyContinue
    $found = $false
    $referenceVmss = @(get-vmssResources $resourceGroupName $referenceNodeTypeName)

    if ($referenceVmss) {
        $found = $true
    }
    if (!$referenceVmss) {
        $referenceVmss = @(get-vmssResources $resourceGroupName)
    }

    if (!$referenceVmss) {
        $referenceVmss = @(get-vmssResources -vmssName $referenceNodeTypeName)
    }

    if (!$referenceVmss) {
        $referenceVmss = @(get-vmssResources)
    }

    if (!$referenceVmss) {
        write-console "vmss for reference node type: $referenceNodeTypeName not found" -warn
        return $null
    }

    if (!$found) {
        foreach ($vmss in $referenceVmss) {
            $sfSettings = get-sfExtensionSettings $referenceVmss
            $isNodeTypeRef = compare-sfExtensionSettings -settings $sfSettings -clusterEndpoint $clusterEndpoint -nodeTypeRef $referenceNodeTypeName
    
            if ($isNodeTypeRef) {
                write-console "found vmss: $($availableNodeType.Name) for node type: $referenceNodeTypeName" -ForegroundColor Green
                #$referenceVmss = Get-AzVmss -ResourceGroupName $resourceGroupName -Name $availableNodeType.Name -ErrorAction SilentlyContinue
                $found = $true
                $referenceVmss = $vmss
                break
            }
            else {
                write-console "node type ref: $nodeTypeRef does not match reference node type: $referenceNodeTypeName" -ForegroundColor Yellow
                write-console "cluster endpoint ref: $clusterEndpointRef does not match cluster endpoint: $clusterEndpoint" -ForegroundColor Yellow
            }
        }
    }

    if (!$found) { $referenceVmss = $null }
    write-console "returning $($referenceVmss.ResourceId)"
    return $referenceVmss
}

function get-sfClusterEndpoint($resourceGroupName, $clusterName) {
    write-console "get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties"
    $serviceFabricResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties
    if (!$serviceFabricResource) {
        write-console "service fabric cluster $clusterName not found" -err
        return $error
    }

    $clusterEndpoint = $serviceFabricResource.Properties.ClusterEndpoint
    if (!$clusterEndpoint) {
        write-console "cluster endpoint not found" -err
        return $error
    }

    write-console "cluster endpoint: $clusterEndpoint"
    return $clusterEndpoint
}

function  get-sfExtensionSettings($vmss) {
    write-console "get-sfExtensionSettings $($vmss.Name)"
    #check extension
    $sfExtension = $vmss.properties.virtualMachineProfile.extensionProfile.extensions.properties | where-object publisher -imatch 'ServiceFabric'
    $settings = $sfExtension.settings
    if (!$settings) {
        write-console "service fabric extension not found for node type: $($availableNodeType.Name)" -warn
    }
    return $settings
}

function get-sfProtectedSettings($storageAccountName, $templateJson) {
    $storageAccountKey1 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('supportLogStorageAccountName')),'2015-05-01-preview').key1]"
    $storageAccountKey2 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('supportLogStorageAccountName')),'2015-05-01-preview').key2]"
    write-console "get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName"
    $storageAccountKeys = get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName

    if (!$storageAccountKeys) {
        write-console "storage account key not found" -err
        $error.Clear()
        $templateJson = add-property -resource $templateJson -name 'variables.supportLogStorageAccountName' -value $storageAccountName
    }
    else {
        $storageAccountKey1 = $storageAccountKeys[0].Value
        $storageAccountKey2 = $storageAccountKeys[1].Value
    }

    $storageAccountProtectedSettings = @{
        "storageAccountKey1" = $storageAccountKey1
        "storageAccountKey2" = $storageAccountKey2
    }

    write-console $storageAccountProtectedSettings
    return $storageAccountProtectedSettings
}

function get-sfResource($resourceGroupName, $clusterName) {
    write-console "get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties"
    $serviceFabricResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties
  
    if (!$serviceFabricResource) {
        write-console "service fabric cluster $clusterName not found" -err
        return $error
    }

    write-console $serviceFabricResource
    return $serviceFabricResource
}

function get-vmssCollection($nodeTypeName) {
    write-console "using node type $nodeTypeName"
    $Vmss = get-referenceNodeTypeVMSS $nodeTypeName
    if (!$Vmss) {
        write-console "node type $nodeTypeName not found" -err
        return $error
    }

    $loadBalancerName = $Vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerInboundNatPools[0].Id.Split('/')[8]
    if (!$loadBalancerName) {
        write-console "load balancer not found" -err
        return $error
    }

    write-console "get-azloadbalancer -ResourceGroupName $resourceGroupName -Name $loadBalancerName" -foregroundColor cyan
    $loadBalancer = Get-AzLoadBalancer -ResourceGroupName $resourceGroupName -Name $loadBalancerName
    if (!$loadBalancer) {
        write-console "load balancer not found" -err
        return $error
    }

    $vmssCollection = new-vmssCollection -vmss $Vmss -loadBalancer $loadBalancer

    # private ip check
    $vmssCollection.isPublicIp = if ($loadBalancer.FrontendIpConfigurations.PublicIpAddress) { $true } else { $false }

    if ($vmssCollection.isPublicIp) {
        write-console "public ip found"
        #$ipName = $loadBalancer.FrontendIpConfigurations.PublicIpAddress.Id.Split('/')[8]
        write-console "get-azpublicipaddress -ResourceGroupName $resourceGroupName -Name $ipName" -foregroundColor cyan
        $ip = Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $ipName
        $vmssCollection.ipAddress = $ip.IpAddress
        $vmssCollection.ipType = $ip.PublicIpAllocationMethod
    }
    else {
        write-console "private ip found"
        $vmssCollection.ipAddress = $loadBalancer.FrontendIpConfigurations.PrivateIpAddress
        $vmssCollection.ipType = $loadBalancer.FrontendIpConfigurations.PrivateIpAllocationMethod
    }

    if (!$ip) {
        write-console "public ip not found" -foregroundColor 'Yellow'
    }
    else {
        $vmssCollection.ipConfig = $ip
    }

    write-console "current ip address is type:$($vmssCollection.ipType) public:$($vmssCollection.isPublicIp) address:$($vmssCollection.ipAddress)" -foregroundColor 'Cyan'
    write-console $vmssCollection

    return $vmssCollection
}

function get-vmssResources($resourceGroupName, $vmssName) {
    write-console "get-vmssResources -resourceGroupName $resourceGroupName -vmssName $vmssName"
    $paramValues = @{
        resourceType     = 'Microsoft.Compute/virtualMachineScaleSets'
        expandProperties = $true
    }

    if ($resourceGroupName) { [void]$paramValues.Add('resourceGroupName', $resourceGroupName) }
    if ($vmssName) { [void]$paramValues.Add('name', $vmssName) }

    write-console "get-azresource $($paramValues | convertto-json)" -foregroundColor cyan
    try {
        $vmssResource = get-azresource @paramValues -ErrorAction SilentlyContinue
    }
    catch {
        write-console "vmss $vmssName not found" -err
        return $null
    }

    write-console $vmssResource.ResourceId
    return $vmssResource
}

function write-console($message, $foregroundColor = 'White', [switch]$verbose, [switch]$err, [switch]$warn) {
    if (!$message) { return }
    if ($message.gettype().name -ine 'string') {
        $message = $message | convertto-json -Depth 10
    }

    if ($verbose) {
        write-verbose($message)
    }
    else {
        write-host($message) -ForegroundColor $foregroundColor
    }

    if ($warn) {
        write-warning($message)
    }
    elseif ($err) {
        write-error($message)
        throw
    }
}

main
