<#
.Synopsis
    provide powershell commands to copy a reference node type to an existing Azure Service Fabric cluster
    provide powershell commands to configure all existing applications to use PLB before adding new nodetype if not already done
    https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-resource-manager-cluster-description#node-properties-and-placement-constraints

.NOTE
    this script is a work in progress
    this script is not supported by Microsoft
    this script is not supported under any Microsoft standard support program or service
    the script is provided AS IS without warranty of any kind
    Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose
    the entire risk arising out of the use or performance of the sample scripts and documentation remains with you
    in no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages 

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/drafts/azure-az-sf-copy-nodetype.ps1" -outFile "$pwd/azure-az-sf-copy-nodetype.ps1";
    ./azure-az-sf-copy-nodetype.ps1 -connectionEndpoint 'sfcluster.eastus.cloudapp.azure.com:19000' -thumbprint <thumbprint> -resourceGroupName <resource group name>
.PARAMETER resourceGroupName
    the resource group name of the service fabric cluster
.PARAMETER clusterName
    the name of the service fabric cluster
.PARAMETER newNodeTypeName
    the name of the new node type to add to the service fabric cluster
.PARAMETER referenceNodeTypeName
    the name of the existing node type to use as a reference for the new node type
.PARAMETER isPrimaryNodeType
    whether the new node type is a primary node type
.PARAMETER vmImagePublisher
    the publisher of the vm image to use for the new node type
.PARAMETER vmImageOffer
    the offer of the vm image to use for the new node type
.PARAMETER vmImageSku
    the sku of the vm image to use for the new node type
.PARAMETER vmImageVersion
    the version of the vm image to use for the new node type
.PARAMETER vmInstanceCount
    the number of vm instances to use for the new node type
.PARAMETER vmSku
    the sku of the vm to use for the new node type
.PARAMETER durabilityLevel
    the durability level of the new node type
.PARAMETER adminUserName
    the admin username of the new node type
.PARAMETER adminPassword
    the admin password of the new node type
.PARAMETER newIpAddress
    the ip address of the new node type
.PARAMETER newIpAddressName
    the name of the new ip address
.PARAMETER newLoadBalancerName
    the name of the new load balancer
.PARAMETER template
    the path to the template file to use for deployment
.PARAMETER whatIf
    whether to perform a whatIf deployment
.EXAMPLE
    ./azure-az-sf-copy-nodetype.ps1.ps1 -connectionEndpoint 'sfcluster.eastus.cloudapp.azure.com:19000' -thumbprint <thumbprint> -resourceGroupName <resource group name>
.EXAMPLE
    ./azure-az-sf-copy-nodetype.ps1.ps1 -connectionEndpoint 'sfcluster.eastus.cloudapp.azure.com:19000' -thumbprint <thumbprint> -resourceGroupName <resource group name> -referenceNodeTypeName nt0 -newNodeTypeName nt1
.EXAMPLE
    ./azure-az-sf-copy-nodetype.ps1.ps1 -connectionEndpoint 'sfcluster.eastus.cloudapp.azure.com:19000' -thumbprint <thumbprint> -resourceGroupName <resource group name> -newNodeTypeName nt1 -referenceNodeTypeName nt0 -isPrimaryNodeType $false -vmImagePublisher MicrosoftWindowsServer -vmImageOffer WindowsServer -vmImageSku 2022-Datacenter -vmImageVersion latest -vmInstanceCount 5 -vmSku Standard_D2_v2 -durabilityLevel Silver -adminUserName cloudadmin -adminPassword P@ssw0rd!
todo:
private ip?
#>

[cmdletbinding()]
param(
  [Parameter(Mandatory = $true)]
  $resourceGroupName = '', #'sfcluster',
  $clusterName = $resourceGroupName,
  [Parameter(Mandatory = $true)]
  $newNodeTypeName = 'nt1', #'nt1'
  [Parameter(Mandatory = $true)]
  $referenceNodeTypeName = 'nt0', #'nt0',
  $isPrimaryNodeType = $false,
  $vmImageSku = '2022-Datacenter',
  $vmInstanceCount = 3,
  $vmSku = 'Standard_D2_v2',
  [ValidateSet('Bronze', 'Silver', 'Gold')]
  $durabilityLevel = 'Silver',
  $adminUserName = 'cloudadmin',
  $adminPassword = 'P@ssw0rd!',
  $newIpAddress = $null,
  $newIpAddressName = 'pip-' + $newNodeTypeName,
  $newLoadBalancerName = 'lb-' + $newNodeTypeName,
  $template = "$psscriptroot\azure-az-sf-copy-nodetype.json",
  [switch]$whatIf
)

$PSModuleAutoLoadingPreference = 'auto'
$deployedServices = @{}
$regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
$vmImagePublisher = 'MicrosoftWindowsServer'
$vmImageOffer = 'WindowsServer'
$vmImageVersion = 'latest'
$nameFindPattern = '(?<initiator>/|"|_|,|\\){0}(?<terminator>/|$|"|_|,|\\)'
$nameReplacePattern = '${{initiator}}{0}${{terminator}}'
#$nameReplacePattern = "`${initiator}{0}`${terminator}"


$error.clear()
$templateJson = @{
  "`$schema"       = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
  "contentVersion" = "1.0.0.0"
  "parameters"     = @{}
  "variables"      = @{}
  "resources"      = @()
  "outputs"        = @{}
}


function main() {
  write-console "main() started"
  $error.Clear()

  if (!(Get-Module az)) {
    Import-Module az
  }

  if (!(get-azresourceGroup)) {
    Connect-AzAccount
  }

  if ((get-azvmss -ResourceGroupName $resourceGroupName -Name $newNodeTypeName -errorAction SilentlyContinue)) {
    write-console "node type $newNodeTypeName already exists" -err
    return $error
  }

  if ((Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $newIpAddressName -ErrorAction SilentlyContinue)) {
    write-console "ip address $newIpAddressName already exists" -err
    return $error
  }

  if ((Get-AzLoadBalancer -ResourceGroupName $resourceGroupName -Name $newLoadBalancerName -ErrorAction SilentlyContinue)) {
    write-console "load balancer $newLoadBalancerName already exists" -err
    return $error
  }

  try {
    $error.Clear()
    $referenceVmssCollection = new-vmssCollection
    $serviceFabricResource = get-sfResource -resourceGroupName $resourceGroupName -clusterName $clusterName

    if (!$serviceFabricResource) {
      write-console "service fabric cluster $clusterName not found" -err
      return $error
    }
    write-console $serviceFabricResource

    $referenceVmssCollection = get-vmssResources -resourceGroupName $resourceGroupName -nodeTypeName $referenceNodeTypeName
    write-console $referenceVmssCollection

    $templateJson = copy-vmssCollection -vmssCollection $referenceVmssCollection -templateJson $templateJson
    $templateJson = update-serviceFabricResource -serviceFabricResource $serviceFabricResource -templateJson $templateJson
    $result = deploy-vmssCollection -templateJson $templateJson

    write-console "deploy result: $result"
  }
  catch [Exception] {
    $errorString = "exception: $($psitem.Exception.Response.StatusCode.value__)`r`nexception:`r`n$($psitem.Exception.Message)`r`n$($error | out-string)`r`n$($psitem.ScriptStackTrace)"
    Write-Host $errorString -foregroundColor 'Red'
  }
  finally {
    write-console "finished"
  }
}

function add-property($resource, $name, $value = $null, $overwrite = $false) {
  write-console "checking property '$name' = '$value' to $resource"
  if (!$resource) { return $resource }
  if ($name -match '\.') {
    foreach ($object in $name.split('.')) {
      $childName = $name.replace("$object.", '')
      $resource.$object = add-property -resource $resource.$object -name $childName -value $value
      return $resource
    }
  }
  else {
    foreach ($property in $resource.PSObject.Properties) {
      if ($property.Name -ieq $name) {
        write-console "property '$name' already exists" -foregroundColor 'Yellow'
        if (!$overwrite) { return $resource }
      }
    }

  }

  write-console "add-member -MemberType NoteProperty -Name $name -Value $value"
  $resource | add-member -MemberType NoteProperty -Name $name -Value $value
  write-console "added property '$name' = '$value' to resource" -foregroundColor 'Green'
  return $resource
}

function copy-vmssCollection($vmssCollection, $templateJson) {
  $vmss = $vmssCollection.vmssConfig
  $ip = $null
  $lb = $vmssCollection.loadBalancerConfig

  # set credentials
  $vmss.properties.VirtualMachineProfile.OsProfile.AdminUsername = $adminUserName
  $vmss = add-property -resource $vmss -name 'properties.VirtualMachineProfile.OsProfile.adminPassword' -value ''
  $vmss.properties.VirtualMachineProfile.OsProfile.AdminPassword = $adminPassword
  $vmss = add-property -resource $vmss -name 'dependsOn' -value @()
  $vmss.dependsOn += $lb.Id

  $extensions = $vmss.properties.VirtualMachineProfile.ExtensionProfile.Extensions

  $wadExtension = $extensions | where-object { $psitem.properties.publisher -ieq 'Microsoft.Azure.Diagnostics' }
  $wadStorageAccount = $wadExtension.properties.settings.StorageAccount
  $protectedSettings = get-wadProtectedSettings -storageAccountName $wadStorageAccount -templaetJson $templateJson
  $wadExtension = add-property -resource $wadExtension -name 'properties.protectedSettings' -value $protectedSettings

  $sfExtension = $extensions | where-object { $psitem.properties.publisher -ieq 'Microsoft.Azure.ServiceFabric' }
  $sfStorageAccount = $serviceFabricResource.Properties.DiagnosticsStorageAccountConfig.StorageAccountName
  $protectedSettings = get-sfProtectedSettings -storageAccountName $sfStorageAccount -templaetJson $templateJson
  $sfExtension = add-property -resource $sfExtension -name 'properties.protectedSettings' -value $protectedSettings

  # set durabilty level
  $sfExtension.properties.settings.durabilityLevel = $durabilityLevel

  # todo parameterize cluster id ?
  #$clusterEndpoint = $serviceFabricResource.Properties.ClusterEndpoint

  # set capacity
  $vmss.Sku.Capacity = if ($vmInstanceCount) { $vmInstanceCount } else { $vmss.Sku.Capacity }

  $vmssName = $nameFindPattern -f $vmss.Name
  $newVmssName = $nameReplacePattern -f $newNodeTypeName
  $lbName = $nameFindPattern -f $lb.Name
  $newLBName = $nameReplacePattern -f $newLoadBalancerName

  # convert to json
  $vmssJson = $vmss | convertto-json -Depth 99
  #$ipJson = $ip | convertto-json -Depth 99
  $lbJson = $lb | convertto-json -Depth 99
  
  if ($vmssCollection.isPublicIp) {
    write-console "setting public ip address to $newIpAddress"
    $ip = $vmssCollection.ipConfig
    $ipName = $nameFindPattern -f $ip.Name
    $newIpName = $nameReplacePattern -f $newIpAddressName
  
    $lb = add-property -resource $lb -name 'dependsOn' -value @()
    $lb.dependsOn += $ip.Id
    $lbJson = $lb | convertto-json -Depth 99

    $ipJson = $ip | convertto-json -Depth 99
    $ipJson = remove-nulls -json $ipJson
    $ipJson = remove-commonProperties -json $ipJson

    # set new resource names
    $ipJson = set-resourceName -referenceName $ipName -newName $newIpName -json $ipJson
    $ipJson = set-resourceName -referenceName $vmssName -newName $newVmssName -json $ipJson
    $ipJson = set-resourceName -referenceName $lbName -newName $newLBName -json $ipJson
    $ip = $ipJson | convertfrom-json -asHashTable
  
    $lbJson = set-resourceName -referenceName $ipName -newName $newIpName -json $lbJson
    $vmssJson = set-resourceName -referenceName $ipName -newName $newIpName -json $vmssJson
  
    # set names
    $ip.Name = $newIpAddressName
    $ip.Properties.dnsSettings.fqdn = "$newNodeTypeName-$($ip.Properties.dnsSettings.fqdn)"
    $ip.Properties.dnsSettings.domainNameLabel = "$newNodeTypeName-$($ip.Properties.dnsSettings.domainNameLabel)"
  

    if ($vmssCollection.ipType -ieq 'Static') {
      $ip.Properties.ipAddress = $newIpAddress
    }
  }
  else {
    # remove ip address from new loadbalancer to avoid conflict
    write-console "setting private ip address to $newIpAddress"
    if ($vmssCollection.ipType -ieq 'Static' -and $newIpAddress) {
      $loadBalancer.FrontendIpConfigurations.properties.privateIpAddress = $newIpAddress
    }
  }

  # remove existing state
  $vmssJson = remove-nulls -json $vmssJson
  $lbJson = remove-nulls -json $lbJson

  #$ipJson = remove-commonProperties -json $ipJson
  $vmssJson = remove-commonProperties -json $vmssJson
  $lbJson = remove-commonProperties -json $lbJson

  # set new names
  $lbJson = set-resourceName -referenceName $lbName -newName $newLBName -json $lbJson
  $lbJson = set-resourceName -referenceName $vmssName -newName $newVmssName -json $lbJson
  $lb = $lbJson | convertfrom-json -asHashTable

  $vmssJson = set-resourceName -referenceName $vmssName -newName $newVmssName -json $vmssJson
  $vmssJson = set-resourceName -referenceName $lbName -newName $newLBName -json $vmssJson
  $vmss = $vmssJson | convertfrom-json -asHashTable

  # set names
  $vmss.Name = $newNodeTypeName

  $lb.Name = $newLoadBalancerName
  $lb.Properties.inboundNatRules = @()
  $lb.Properties.frontendIPConfigurations.properties.inboundNatRules = @()

  if ($ip) {
    $templateJson.resources += $ip
  }
  
  $templateJson.resources += $lb
  $templateJson.resources += $vmss
  write-console $newVmssCollection  -foregroundColor 'Green'
  return $templateJson
}

function deploy-vmssCollection($vmssCollection, $serviceFabricResource) {
  write-console "deploying new node type $newNodeTypeName"
  write-console $template -foregroundColor 'Cyan'

  $templateJson | convertto-json -Depth 99 | Out-File $template -Force
  write-console "template saved to $template"
  write-console "test-azResourceGroupDeployment -templateFile $template -resourceGroupName $resourceGroupName -Verbose"
  $result = test-azResourceGroupDeployment -templateFile $template -resourceGroupName $resourceGroupName -Verbose

  if ($result) {
    write-console "error: test-azResourceGroupDeployment failed:$($result | out-string)" -err
    return $result
  }
  
  $deploymentName = $($MyInvocation.MyCommand.Name)-$(get-date -Format 'yyMMddHHmmss')
  write-console "new-azResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroupName -TemplateFile $template -Verbose -Verbose -DeploymentDebugLogLevel All"
  
  if (!$whatIf) {
    $result = new-azResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroupName -TemplateFile $template -Verbose -DeploymentDebugLogLevel All
  }

  return $result
}

function get-latestApiVersion($resourceType) {
  $provider = get-azresourceProvider -ProviderNamespace $resourceType.Split('/')[0]
  $resource = $provider.ResourceTypes | where-object ResourceTypeName -eq $resourceType.Split('/')[1]
  $apiVersion = $resource.ApiVersions[0]

  write-console "latest api version for $resourceType is $apiVersion"

  return $apiVersion
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

  $Vmss = Get-AzVmss -ResourceGroupName $resourceGroupName -Name $nodeTypeName
  if (!$Vmss) {
    write-console "node type $nodeTypeName not found" -err
    return $error
  }

  $loadBalancerName = $Vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerInboundNatPools[0].Id.Split('/')[8]
  if (!$loadBalancerName) {
    write-console "load balancer not found" -err
    return $error
  }

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

function get-vmssResources($resourceGroupName, $nodeTypeName) {
  $vmssResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.Compute/virtualMachineScaleSets -Name $nodeTypeName -ExpandProperties
  
  if (!$vmssResource) {
    write-console "node type $nodeTypeName not found" -err
    return $error
  }
  $vmssResource = add-property -resource $vmssResource -name 'apiVersion' -value (get-latestApiVersion -resourceType $vmssResource.Type)

  $ipProperties = $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.ipConfigurations.properties
  # todo modify subnet?
  #$subnetName = $ipProperties.subnet.id.Split('/')[10]

  $lbName = $ipProperties.loadBalancerBackendAddressPools.id.Split('/')[8]
  $lbResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.Network/loadBalancers -Name $lbName -ExpandProperties
  $lbResource = add-property -resource $lbResource -name 'apiVersion' -value (get-latestApiVersion -resourceType $lbResource.Type)

  $vmssCollection = new-vmssCollection -vmss $vmssResource -loadBalancer $lbResource
  $vmssCollection.isPublicIp = if ($lbResource.Properties.frontendIPConfigurations.properties.publicIPAddress) { $true } else { $false }

  if ($vmssCollection.isPublicIp) {
    $ipName = $lbResource.Properties.frontendIPConfigurations.properties.publicIPAddress.id.Split('/')[8]
    $ipResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.Network/publicIPAddresses -Name $ipName -ExpandProperties
    $ipResource = add-property -resource $ipResource -name 'apiVersion' -value (get-latestApiVersion -resourceType $ipResource.Type)
    $vmssCollection.ipConfig = $ipResource
  }

  write-console $vmssCollection
  return $vmssCollection
}

function get-wadProtectedSettings($storageAccountName, $templateJson) {
  $storageAccountTemplate = "[variables('applicationDiagnosticsStorageAccountName')]"
  $storageAccountKey = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('applicationDiagnosticsStorageAccountName')),'2015-05-01-preview').key1]"
  $storageAccountEndPoint = "https://core.windows.net/"

  write-console "get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName"
  $storageAccountKeys = get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName

  if (!$storageAccountKeys) {
    write-console "storage account key not found"
    $storageAccountName = $storageAccountTemplate
    $templateJson = add-property -resource $templateJson -name 'variables.applicationDiagnosticsStorageAccountName' -value $storageAccountName
  }
  else {
    $storageAccountName = $storageAccountName
    $storageAccountKey = $storageAccountKeys[0].Value
  }

  $storageAccountProtectedSettings = @{
    "storageAccountName"     = $storageAccountName
    "storageAccountKey"      = $storageAccountKey
    "storageAccountEndPoint" = $storageAccountEndPoint
  }
  write-console $storageAccountProtectedSettings
  return $storageAccountProtectedSettings
}

function new-vmssCollection($vmss = $null, $ip = $null, $loadBalancer = $null) {
  $vmssCollection = @{
    #[Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSetList]
    vmssConfig         = $vmss
    #[Microsoft.Azure.Commands.Network.Automation.Models.PSPublicIPAddress]
    ipConfig           = $ip
    #[Microsoft.Azure.Commands.Network.Automation.Models.PSLoadBalancer]
    loadBalancerConfig = $loadBalancer
    isPublicIp         = $false
    ipAddress          = ''
    ipType             = ''
  }
  return $vmssCollection
}

function remove-commonProperties($json) {
  $commonProperties = @(
    'ResourceId',
    'SubscriptionId',
    'TagsTable',
    'ResourceGuid',
    'ResourceName',
    'ResourceType',
    'ResourceGroupName',
    'ProvisioningState',
    'CreatedTime',
    'ChangedTime',
    'Etag',
    'requireGuestProvisionSignal'
  )

  foreach ($property in $commonProperties) {
    $json = remove-property -name $property -json $json
  }
  return $json
}

function remove-nulls($json, $name = $null) {
  $findName = "`"(?<propertyName>.+?)`": null,"
  $replaceName = "//`"`${propertyName}`": null,"

  if (!$json) {
    write-console "error: json is null" -err
  }

  if ($name) {
    $findName = "`"$name`": null,"
    $replaceName = "//`"$name`": null,"
  }

  if ([regex]::isMatch($json, $findName, $regexOptions)) {
    write-console "replacing $findName with $replaceName in `$json" -foregroundColor 'Green'
    $json = [regex]::Replace($json, $findName, $replaceName, $regexOptions)
  }
  else {
    write-console "$findName not found" #-err
  }
  return $json
}

function remove-property($name, $json) {
  # todo implement same as add-property?
  $findName = "`"$name`":"
  $replaceName = "//`"$name`":"

  if (!$json) {
    write-console "error: json is null" -err
  }
  elseif (!$name) {
    write-console "error: name is null" -err
  }

  if ([regex]::isMatch($json, $findName, $regexOptions)) {
    write-console "replacing $findName with $replaceName in `$json" -foregroundColor 'Green'
    $json = [regex]::Replace($json, $findName, $replaceName, $regexOptions)
  }
  else {
    write-console "$findName not found" #-err
  }
  return $json
}

function set-resourceName($referenceName, $newName, $json) {
  if (!$json) {
    write-console "error: json is null" -err
  }
  elseif (!$referenceName) {
    write-console "error: referenceName is null" -err
  }
  elseif (!$newName) {
    write-console "newName is null" -err
  }

  if ([regex]::isMatch($json, $referenceName, $regexOptions)) {
    write-console "replacing $referenceName with $newName in `$json" -foregroundColor 'Green'
    write-console "[regex]::Replace($json, $referenceName, $newName, $regexOptions)"
    $json = [regex]::Replace($json, $referenceName, $newName, $regexOptions)
  }
  else {
    write-console "$referenceName not found" #-err
  }
  return $json
}

function update-serviceFabricResource($serviceFabricResource, $templateJson) {

  if (!$serviceFabricResource) {
    write-console "service fabric cluster $clusterName not found" -err
    return $error
  }

  $sfJson = $serviceFabricResource | convertto-json -Depth 99

  # remove properties not supported for deployment
  $sfJson = remove-nulls -json $sfJson
  $sfJson = remove-commonProperties -json $sfJson

  $serviceFabricResource = $sfJson | convertfrom-json -asHashTable
  $nodeTypes = $serviceFabricResource.Properties.nodeTypes

  if (!$nodeTypes) {
    write-console "node types not found" -err
    return $serviceFabricResource
  }

  $serviceFabricResource = add-property -resource $serviceFabricResource -name 'apiVersion' -value (get-latestApiVersion -resourceType $serviceFabricResource.Type)
  $referenceNodeTypeJson = $nodeTypes | where-object name -ieq $referenceNodeTypeName | convertto-json -Depth 99

  if (!$referenceNodeTypeJson) {
    write-console "node type $referenceNodeTypeName not found" -err
    return $serviceFabricResource
  }

  $nodeType = $nodeTypes | where-object Name -ieq $newNodeTypeName
  if ($nodeType) {
    write-console "node type $referenceNodeTypeName already exists" -err
    return $serviceFabricResource
  }

  $newList = [collections.arrayList]::new()
  [void]$newList.AddRange($nodeTypes)
  $nodeTypeTemplate = $referenceNodeTypeJson | convertfrom-json -asHashTable

  $nodeTypeTemplate.isPrimary = $isPrimaryNodeType
  $nodeTypeTemplate.name = $newNodeTypeName
  $nodeTypeTemplate.vmInstanceCount = $vmInstanceCount
  $nodeTypeTemplate.durabilityLevel = $durabilityLevel

  [void]$newList.Add($nodeTypeTemplate)
  $serviceFabricResource.Properties.nodeTypes = $newList

  write-console $serviceFabricResource
  $templateJson.resources += $serviceFabricResource
  return $templateJson
}

function write-console($message, $foregroundColor = 'White', [switch]$verbose, [switch]$err) {
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

  if ($err) {
    write-error($message)
    throw
  }
}

main
