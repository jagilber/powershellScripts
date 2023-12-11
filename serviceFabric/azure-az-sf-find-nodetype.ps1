<#
.SYNOPSIS
    find the vmss for a given node type. 
    the cluster endpoint and node type name are used to verify the vmss is correct.
    the vmss name should match the node type name but not always the case.
    the vmss should be in the same resource group as the cluster but not always the case.

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-find-nodetype.ps1" -outFile "$pwd/azure-az-sf-find-nodetype.ps1";
    ./azure-az-sf-find-nodetype.ps1 -resourceGroupName <resource group name> -clusterName <cluster name> -nodeTypeName <nt0>

.PARAMETER resourceGroupName
    the resource group name of the service fabric cluster
.PARAMETER clusterName
    the name of the service fabric cluster
.PARAMETER nodeTypeName
    the name of the existing node type to find the vmss for

.EXAMPLE
    ./azure-az-sf-find-nodetype.ps1.ps1 -resourceGroupName <resource group name> -clusterName <cluster name> -nodeTypeName <nt0>
#>

[CmdletBinding(DefaultParameterSetName = "Platform")]
param(
    [Parameter(ParameterSetName = 'Custom', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Platform', Mandatory = $true)]
    [string]$resourceGroupName = '', #'sfcluster',

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    [string]$clusterName = $resourceGroupName,
        
    [Parameter(ParameterSetName = 'Custom', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Platform', Mandatory = $true)]
    [string]$nodeTypeName = '' #'nt0'
)

$PSModuleAutoLoadingPreference = 'auto'

function main() {
    write-console "starting..."
    $error.Clear()

    try {
        $error.Clear()

        if (!(Get-Module az)) {
            Import-Module az
        }

        if (!(get-azresourceGroup)) {
            Connect-AzAccount
        }

        $serviceFabricResource = get-sfClusterResource -resourceGroupName $resourceGroupName -clusterName $clusterName
        if (!$serviceFabricResource) {
            write-console "service fabric cluster $clusterName not found" -err
            return $error
        }

        $nodeType = get-referenceNodeType $nodeTypeName $serviceFabricResource
        if (!$nodeType) {
            write-console "reference node type $nodeTypeName does not exist" -err
            return $error
        }

        write-console $serviceFabricResource.ResourceId

        # get vmss for reference node type by name from resource group first
        $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
            -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
            -vmssResources @(get-vmssResources -resourceGroupName $resourceGroupName -vmssName $nodeTypeName)

        # get vmss for reference node type by name from all resource groups
        if (!$currentVmss) {
            $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
                -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
                -vmssResources @(get-vmssResources -resourceGroupName $resourceGroupName)
        }

        # get vmss for reference node type by name from all resource groups
        if (!$currentVmss) {
            $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
                -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
                -vmssResources @(get-vmssResources -vmssName $nodeTypeName)
        }

        # get vmss for reference node type by name from all resource groups
        if (!$currentVmss) {
            $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
                -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
                -vmssResources @(get-vmssResources)
        }

        if (!$currentVmss) {
            write-console "vmss for reference node type: $nodeTypeName not found" -foregroundColor 'Red'
            $global:referenceNodeType = $null
            return $null
        }

        write-console $currentVmss.ResourceId -foregroundColor 'Cyan'
        $global:referenceNodeType = $currentVmss
        write-console "reference node type stored in global variable: `$global:referenceNodeType"
        return $global:referenceNodeType
    }
    catch [Exception] {
        $errorString = "exception: $($psitem.Exception.Response.StatusCode.value__)`r`nexception:`r`n$($psitem.Exception.Message)`r`n$($error | out-string)`r`n$($psitem.ScriptStackTrace)"
        write-console $errorString -foregroundColor 'Red'
    }
}

function compare-sfExtensionSettings([object]$sfExtSettings, [string]$clusterEndpoint, [string]$nodeTypeRef) {
    write-console "compare-sfExtensionSettings:`$settings, $clusterEndpoint, $nodeTypeRef"
    if (!$sfExtSettings) {
        write-console "settings not found" -foregroundColor 'Yellow'
        return $null
    }

    $clusterEndpointRef = $sfExtSettings.ClusterEndpoint
    if (!$clusterEndpointRef) {
        write-console "cluster endpoint not found" -foregroundColor 'Yellow'
        return $null
    }

    $nodeRef = $sfExtSettings.NodeTypeRef
    if (!$nodeRef) {
        write-console "node type ref not found in cluster settings" -foregroundColor 'Yellow'
        return $null
    }

    if ($clusterEndpointRef -ieq $clusterEndpoint -and $nodeTypeRef -ieq $nodeRef) {
        write-console "node type ref: $nodeTypeRef matches reference node type: $nodeRef" -foregroundColor 'Green'
        write-console "cluster endpoint ref: $clusterEndpointRef matches cluster endpoint: $clusterEndpoint" -foregroundColor 'Green'
        return $true
    }
    elseif ($nodeRef -ine $nodeTypeRef) {
        write-console "node type ref: $nodeTypeRef does not match reference node type: $nodeRef" -foregroundColor 'Yellow'
        return $false
    }
    else {
        write-console "cluster endpoint ref: $clusterEndpointRef does not match cluster endpoint: $clusterEndpoint" -foregroundColor 'Yellow'
        return $false
    }
}

function get-referenceNodeType($nodeTypeName, $clusterResource) {
    write-console "get-referenceNodeType:$nodeTypeName,$clusterResource"

    $nodetypes = @($clusterResource.Properties.NodeTypes)
    $nodeType = $nodetypes | where-object name -ieq $nodeTypeName

    write-console "returning: $($nodeType.Name)"
    return $nodeType
}

function get-referenceNodeTypeVMSS([string]$nodetypeName, [string]$clusterEndpoint, $vmssResources) {
    # nodetype name should match vmss name but not always the case
    # get-azvmss returning jobject 23-11-29 mitigation to use get-azresource
    #$referenceVmss = Get-AzVmss -ResourceGroupName $resourceGroupName -VMScaleSetName $nodeTypeName -ErrorAction SilentlyContinue
    $referenceVmss = $null

    if (!$vmssResources) {
        write-console "vmss for reference node type: $nodetypeName not found" -warn
        return $null
    }

    foreach ($vmss in $vmssResources) {
        $sfExtSettings = get-sfExtensionSettings $vmss
        $isNodeTypeRef = compare-sfExtensionSettings -sfExtSettings $sfExtSettings -clusterEndpoint $clusterEndpoint -nodeTypeRef $nodeTypeName
    
        if ($isNodeTypeRef) {
            write-console "found vmss: $($vmss.Name) for node type: $nodetypeName" -ForegroundColor Green
            $referenceVmss = $vmss
            break
        }
    }

    if (!$referenceVmss) {
        write-console "vmss for reference node type: $nodetypeName not found" -warn
        return $null
    }

    write-console "returning $($referenceVmss.ResourceId)"
    return $referenceVmss
}

function get-sfClusterResource($resourceGroupName, $clusterName) {
    write-console "get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties"
    $serviceFabricResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties
    if (!$serviceFabricResource) {
        write-console "service fabric cluster $clusterName not found" -warn
    }
    else {
        write-console "cluster endpoint: $($serviceFabricResource.Properties.ClusterEndpoint)"
    }

    return $serviceFabricResource
}

function  get-sfExtensionSettings($vmss) {
    write-console "get-sfExtensionSettings $($vmss.Name)"
    #check extension
    $sfExtension = $vmss.properties.virtualMachineProfile.extensionProfile.extensions.properties | where-object publisher -imatch 'ServiceFabric'
    $settings = $sfExtension.settings
    if (!$settings) {
        write-console "service fabric extension not found for node type: $($vmss.Name)" -warn
    }
    else {
        write-console "service fabric extension found for node type: $($vmss.Name)"
    }
    return $settings
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
        $vmssResources = @(get-azresource @paramValues -ErrorAction SilentlyContinue)
    }
    catch {
        write-console "exception:vmss $vmssName $($error | out-string)" -err
        return $null
    }

    if (!$vmssResources) {
        write-console "vmss $vmssName not found"
        return $null
    }
    elseif ($vmssResources.Count -gt 1) {
        write-console "returning: $($vmssResources.Count) vmss resource(s)"
    }
    else {
        write-console "returning: $(@($vmssResources)[0].ResourceId)"
    }
    return $vmssResources
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
