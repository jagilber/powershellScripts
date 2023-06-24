<#
.Synopsis
    provide powershell commands to copy a reference node type to an existing Azure Service Fabric cluster
    provide powershell commands to configure all existing applications to use PLB before adding new nodetype if not already done
    
    https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-resource-manager-cluster-description#node-properties-and-placement-constraints

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
.EXAMPLE
    ./azure-az-sf-copy-nodetype.ps1.ps1 -connectionEndpoint 'sfcluster.eastus.cloudapp.azure.com:19000' -thumbprint <thumbprint> -resourceGroupName <resource group name>
.EXAMPLE
    ./azure-az-sf-copy-nodetype.ps1.ps1 -connectionEndpoint 'sfcluster.eastus.cloudapp.azure.com:19000' -thumbprint <thumbprint> -resourceGroupName <resource group name> -referenceNodeTypeName nt0 -newNodeTypeName nt1
.EXAMPLE
    ./azure-az-sf-copy-nodetype.ps1.ps1 -connectionEndpoint 'sfcluster.eastus.cloudapp.azure.com:19000' -thumbprint <thumbprint> -resourceGroupName <resource group name> -newNodeTypeName nt1 -referenceNodeTypeName nt0 -isPrimaryNodeType $false -vmImagePublisher MicrosoftWindowsServer -vmImageOffer WindowsServer -vmImageSku 2022-Datacenter -vmImageVersion latest -vmInstanceCount 5 -vmSku Standard_D2_v2 -durabilityLevel Silver -adminUserName cloudadmin -adminPassword P@ssw0rd!
todo:
sf nodetype
protected settings
remove ip address?
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
  $vmImagePublisher = 'MicrosoftWindowsServer',
  $vmImageOffer = 'WindowsServer',
  $vmImageSku = '2022-Datacenter',
  $vmImageVersion = 'latest',
  $vmInstanceCount = 3,
  $vmSku = 'Standard_D2_v2',
  [ValidateSet('Bronze', 'Silver', 'Gold')]
  $durabilityLevel = 'Silver',
  $adminUserName = 'cloudadmin',
  $adminPassword = 'P@ssw0rd!',
  $newIpAddressName = 'pip-' + $newNodeTypeName,
  $newLoadBalancerName = 'lb-' + $newNodeTypeName,
  $template = "$psscriptroot\azure-az-sf-copy-nodetype.json",
  $protectedSettings = @{},
  $whatIf = $true
)

$PSModuleAutoLoadingPreference = 'auto'
$global:deployedServices = @{}
$regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase

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
    write-error("node type $newNodeTypeName already exists")
    return $error
  }

  if ((Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $newIpAddressName -ErrorAction SilentlyContinue)) {
    write-error("ip address $newIpAddressName already exists")
    return $error
  }

  if ((Get-AzLoadBalancer -ResourceGroupName $resourceGroupName -Name $newLoadBalancerName -ErrorAction SilentlyContinue)) {
    write-error("load balancer $newLoadBalancerName already exists")
    return $error
  }

  $referenceVmssCollection = new-vmssCollection
  $serviceFabricCluster = get-azServiceFabricCluster -ResourceGroupName $resourceGroupName -Name $clusterName
  if (!$serviceFabricCluster) {
    write-error("service fabric cluster $clusterName not found")
    return $error
  }
  write-console $serviceFabricCluster

  $referenceVmssCollection = get-vmssResources -resourceGroupName $resourceGroupName -nodeTypeName $referenceNodeTypeName
  $global:referenceVmssCollection = $referenceVmssCollection
  
  write-console $referenceVmssCollection
  $global:referenceVmssCollection = $referenceVmssCollection

  $newVmssCollection = copy-vmssCollection -vmssCollection $referenceVmssCollection
  $newServiceFabricCluster = update-serviceFabricResource -serviceFabricCluster $serviceFabricCluster
  deploy-vmssCollection -vmssCollection $newVmssCollection -serviceFabricCluster $newServiceFabricCluster

  write-console "finished"
}

function add-property($resource, $name, $value = $null, $overwrite = $false) {
  write-console "checking property '$name' = '$value' to $resource"
  if(!$resource) { return $resource }
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

function copy-vmssCollection($VmssCollection) {
  $vmss = $VmssCollection.vmssConfig
  $ip = $VmssCollection.ipConfig
  $lb = $VmssCollection.loadBalancerConfig

  # set credentials
  $vmss.properties.VirtualMachineProfile.OsProfile.AdminUsername = $adminUserName
  $vmss = add-property -resource $vmss -name 'properties.VirtualMachineProfile.OsProfile.adminPassword' -value ''
  $vmss.properties.VirtualMachineProfile.OsProfile.AdminPassword = $adminPassword
  $vmss = add-property -resource $vmss -name 'dependsOn' -value @()
  $vmss.dependsOn += $lb.Id

  $extensions = $vmss.properties.VirtualMachineProfile.ExtensionProfile.Extensions
  
  $wadExtension = $extensions | where-object { $psitem.properties.publisher -ieq 'Microsoft.Azure.Diagnostics' }
  $wadStorageAccount = $wadExtension.properties.settings.StorageAccount
  $protectedSettings = get-wadProtectedSettings -storageAccountName $wadStorageAccount
  $wadExtension = add-property -resource $wadExtension -name 'properties.protectedSettings' -value $protectedSettings
  #$vmss = add-property -resource $vmss -name  -value @{}
  
  $sfExtension = $extensions | where-object { $psitem.properties.publisher -ieq 'Microsoft.Azure.ServiceFabric' }
  $sfStorageAccount = $serviceFabricCluster.DiagnosticsStorageAccountConfig.StorageAccountName
  $protectedSettings = get-sfProtectedSettings -storageAccountName $sfStorageAccount
  $sfExtension = add-property -resource $sfExtension -name 'properties.protectedSettings' -value $protectedSettings

  # set capacity
  $vmss.Sku.Capacity = if ($vmInstanceCount) { $vmInstanceCount } else { $vmss.Sku.Capacity }

  # remove existing state
  $vmssName = "(?<initiator>/|`"|_| )$($vmss.Name)(?<terminator>/|$|`"|_| |,|\\)"
  $newVmssName = "`${initiator}$($newNodeTypeName)`${terminator}"

  #$ip.ResourceGuid = ''
  $ipName = "(?<initiator>/|`"|_| )$($ip.Name)(?<terminator>/|$|`"|,|\\)"
  $newIpName = "`${initiator}$($newIpAddressName)`${terminator}"

  #$lb.Id = ''
  $lb = add-property -resource $lb -name 'dependsOn' -value @()
  $lb.dependsOn += $ip.Id
  $lbName = "(?<initiator>/|`"|_| )$($lb.Name)(?<terminator>/|$|`"|,|\\)"
  $newLBName = "`${initiator}$($newLoadBalancerName)`${terminator}"

  # 
  $vmssJson = $vmss | convertto-json -Depth 99
  $ipJson = $ip | convertto-json -Depth 99
  $lbJson = $lb | convertto-json -Depth 99

  # remove existing state
  $ipJson = remove-nulls -json $ipJson
  $vmssJson = remove-nulls -json $vmssJson
  $lbJson = remove-nulls -json $lbJson


  $ipJson = remove-property -name "ResourceId" -json $ipJson
  $vmssJson = remove-property -name "ResourceId" -json $vmssJson
  $lbJson = remove-property -name "ResourceId" -json $lbJson

  $ipJson = remove-property -name "SubscriptionId" -json $ipJson
  $vmssJson = remove-property -name "SubscriptionId" -json $vmssJson
  $lbJson = remove-property -name "SubscriptionId" -json $lbJson

  $ipJson = remove-property -name "TagsTable" -json $ipJson
  $vmssJson = remove-property -name "TagsTable" -json $vmssJson
  $lbJson = remove-property -name "TagsTable" -json $lbJson

  $ipJson = remove-property -name "ResourceGuid" -json $ipJson
  $vmssJson = remove-property -name "ResourceGuid" -json $vmssJson
  $lbJson = remove-property -name "ResourceGuid" -json $lbJson

  $ipJson = remove-property -name "ResourceName" -json $ipJson
  $vmssJson = remove-property -name "ResourceName" -json $vmssJson
  $lbJson = remove-property -name "ResourceName" -json $lbJson

  $ipJson = remove-property -name "ResourceType" -json $ipJson
  $vmssJson = remove-property -name "ResourceType" -json $vmssJson
  $lbJson = remove-property -name "ResourceType" -json $lbJson

  $ipJson = remove-property -name "ResourceGroupName" -json $ipJson
  $vmssJson = remove-property -name "ResourceGroupName" -json $vmssJson
  $lbJson = remove-property -name "ResourceGroupName" -json $lbJson

  $ipJson = remove-property -name "ProvisioningState" -json $ipJson
  $vmssJson = remove-property -name "ProvisioningState" -json $vmssJson
  $lbJson = remove-property -name "ProvisioningState" -json $lbJson

  $ipJson = remove-property -name "CreatedTime" -json $ipJson
  $vmssJson = remove-property -name "CreatedTime" -json $vmssJson
  $lbJson = remove-property -name "CreatedTime" -json $lbJson

  $ipJson = remove-property -name "ChangedTime" -json $ipJson
  $vmssJson = remove-property -name "ChangedTime" -json $vmssJson
  $lbJson = remove-property -name "ChangedTime" -json $lbJson

  $ipJson = remove-property -name "Etag" -json $ipJson
  $vmssJson = remove-property -name "Etag" -json $vmssJson
  $lbJson = remove-property -name "Etag" -json $lbJson

  # set new names
  $ipJson = set-resourceName -referenceName $ipName -newName $newIpName -json $ipJson
  $ipJson = set-resourceName -referenceName $vmssName -newName $newVmssName -json $ipJson
  $ipJson = set-resourceName -referenceName $lbName -newName $newLBName -json $ipJson
  $ip = $ipJson | convertfrom-json -asHashtable

  $lbJson = set-resourceName -referenceName $lbName -newName $newLBName -json $lbJson
  $lbJson = set-resourceName -referenceName $vmssName -newName $newVmssName -json $lbJson
  $lbJson = set-resourceName -referenceName $ipName -newName $newIpName -json $lbJson
  $lb = $lbJson | convertfrom-json -asHashtable

  $vmssJson = set-resourceName -referenceName $vmssName -newName $newVmssName -json $vmssJson
  $vmssJson = set-resourceName -referenceName $lbName -newName $newLBName -json $vmssJson
  $vmssJson = set-resourceName -referenceName $ipName -newName $newIpName -json $vmssJson
  $vmss = $vmssJson | convertfrom-json -asHashtable

  # set names
  $vmss.Name = $newNodeTypeName
  $ip.Name = $newIpAddressName

  $ip.Properties.dnsSettings.fqdn = "$newNodeTypeName-$($ip.Properties.dnsSettings.fqdn)"
  $ip.Properties.dnsSettings.domainNameLabel = "$newNodeTypeName-$($ip.Properties.dnsSettings.domainNameLabel)"

  $lb.Name = $newLoadBalancerName
  $lb.Properties.inboundNatRules = @()
  $lb.Properties.frontendIPConfigurations.properties.inboundNatRules = @()
  
  # $existingName = $vmss.Name
  # $vmss.Id = $vmss.Id.Replace($existingName, $newNodeTypeName)
  # $vmss.Name = $newNodeTypeName
  # $vmss.VirtualMachineProfile.OsProfile.ComputerNamePrefix = $newNodeTypeName
  # $vmss.VirtualMachineProfile.OsProfile.AdminUsername = $adminUserName
  # $vmss.VirtualMachineProfile.OsProfile.AdminPassword = $adminPassword
  # $sfExtension = $vmss.VirtualMachineProfile.ExtensionProfile.Extensions | where-object Publisher -eq 'Microsoft.Azure.ServiceFabric'
  # $sfExtension.Name = $sfExtension.Name.Replace($existingName, $newNodeTypeName)
  
  $newVmssCollection = new-vmssCollection -vmss $vmss -ip $ip -loadBalancer $lb
  write-console $newVmssCollection  -foregroundColor 'Green'
  return $newVmssCollection
}

function deploy-vmssCollection($vmssCollection, $serviceFabricCluster) {
  write-console "deploying new node type $newNodeTypeName"
  #write-console $vmssCollection

  $templateJson = @{
    "`$schema"       = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json"
    "contentVersion" = "1.0.0.0"
    "parameters"     = @{}
    "variables"      = @{}
    "resources"      = @()
  }

  $templateJson.resources += $vmssCollection.ipConfig
  $templateJson.resources += $vmssCollection.loadBalancerConfig
  $templateJson.resources += $vmssCollection.vmssConfig
  $templateJson.resources += $serviceFabricCluster

  write-console $template -foregroundColor 'Cyan'
  $templateJson | convertto-json -Depth 99 | Out-File $template -Force
  write-console "template saved to $template"

  $result = test-azResourceGroupDeployment -template $template -resourceGroupName $resourceGroupName -Verbose
  if($result) {
    write-console "error: test-azResourceGroupDeployment failed" -err
    return $result
  }

  write-console "new-azResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $template -Verbose -WhatIf:$whatIf -Verbose -DeploymentDebugLogLevel All"
  $result = new-azResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $template -Verbose -WhatIf:$whatIf -Verbose -DeploymentDebugLogLevel All
  
  return $result
}

function get-latestApiVersion($resourceType) {
  $provider = get-azresourceProvider -ProviderNamespace $resourceType.Split('/')[0]
  $resource = $provider.ResourceTypes | where-object ResourceTypeName -eq $resourceType.Split('/')[1]
  $apiVersion = $resource.ApiVersions[0]
  write-console "latest api version for $resourceType is $apiVersion"
  return $apiVersion
}

function get-sfProtectedSettings($storageAccountName) {
  $storageAccountKey1 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('supportLogStorageAccountName')),'2015-05-01-preview').key1]"
  $storageAccountKey2 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('supportLogStorageAccountName')),'2015-05-01-preview').key2]"
  write-console "get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName"
  $storageAccountKeys = get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName

  if (!$storageAccountKeys) {
    write-error("storage account key not found")
    $error.Clear()
    #return $error
  }
  else {
    $storageAccountKey1 = $storageAccountKeys[0].Value
    $storageAccountKey2 = $storageAccountKeys[1].Value
  }

  $storageAccountProtectedSettings = @{
      "storageAccountKey1"  = $storageAccountKey1
      "storageAccountKey2"  = $storageAccountKey2
  }

  write-console $storageAccountProtectedSettings
  return $storageAccountProtectedSettings
}

function get-vmssCollection($nodeTypeName) {
  write-console "using node type $nodeTypeName"

  $Vmss = Get-AzVmss -ResourceGroupName $resourceGroupName -Name $nodeTypeName
  if (!$Vmss) {
    write-error("node type $nodeTypeName not found")
    return $error
  }

  $loadBalancerName = $Vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerInboundNatPools[0].Id.Split('/')[8]
  if (!$loadBalancerName) {
    write-error("load balancer not found")
    return $error
  }

  $LoadBalancer = Get-AzLoadBalancer -ResourceGroupName $resourceGroupName -Name $loadBalancerName
  if (!$LoadBalancer) {
    write-error("load balancer not found")
    return $error
  }
  
  $IpName = $LoadBalancer.FrontendIpConfigurations[0].PublicIpAddress.Id.Split('/')[8]
  if (!$IpName) {
    write-error("ip not found")
    return $error
  }

  $Ip = Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $IpName
  if (!$Ip) {
    write-error("ip not found")
    return $error
  }

  $VmssCollection = new-vmssCollection -vmss $Vmss -ip $Ip -loadBalancer $LoadBalancer
  write-console $VmssCollection
  return $VmssCollection
}

function get-vmssResources($resourceGroupName, $nodeTypeName) {
  $vmssResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.Compute/virtualMachineScaleSets -Name $nodeTypeName -ExpandProperties
  $vmssResource = add-property -resource $vmssResource -name 'apiVersion' -value (get-latestApiVersion -resourceType $vmssResource.Type)

  $ipProperties = $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.ipConfigurations.properties
  # todo modify subnet?
  #$subnetName = $ipProperties.subnet.id.Split('/')[10]
  
  $lbName = $ipProperties.loadBalancerBackendAddressPools.id.Split('/')[8]
  $lbResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.Network/loadBalancers -Name $lbName -ExpandProperties
  $lbResource = add-property -resource $lbResource -name 'apiVersion' -value (get-latestApiVersion -resourceType $lbResource.Type)
  
  $ipName = $lbResource.Properties.frontendIPConfigurations.properties.publicIPAddress.id.Split('/')[8]
  $ipResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.Network/publicIPAddresses -Name $ipName -ExpandProperties
  $ipResource = add-property -resource $ipResource -name 'apiVersion' -value (get-latestApiVersion -resourceType $ipResource.Type)

  $vmssCollection = new-vmssCollection -vmss $vmssResource -ip $ipResource -loadBalancer $lbResource
  
  write-console $vmssCollection
  return $vmssCollection
}

function get-wadProtectedSettings($storageAccountName) {
  $storageAccountTemplate = "[variables('applicationDiagnosticsStorageAccountName')]"
  $storageAccountKey = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('applicationDiagnosticsStorageAccountName')),'2015-05-01-preview').key1]"
  $storageAccountEndPoint = "https://core.windows.net/"

  write-console "get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName"
  $storageAccountKeys = get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName

  if (!$storageAccountKeys) {
    write-console "storage account key not found"
    $storageAccountName = $storageAccountTemplate
  }
  else {
    $storageAccountName = $storageAccountName
    $storageAccountKey = $storageAccountKeys[0].Value
  }

  $storageAccountProtectedSettings = @{
      "storageAccountName" = $storageAccountName
      "storageAccountKey"  = $storageAccountKey
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
  }
  return $vmssCollection
}

function remove-nulls($json, $name = $null) {
  $findName = "`"(?<propertyName>.+?)`": null,"
  $replaceName = "//`"${propertyName}`":"

  if (!$json) {
    write-console "error: json is null" #-err
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
    write-console "error: json is null" #-err
  }
  elseif (!$name) {
    write-console "error: name is null" #-err
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
    write-console "error: json is null" #-err
  }
  elseif (!$referenceName) {
    write-console "error: referenceName is null" #-err
  }
  elseif (!$newName) {
    write-console "newName is null"
  }

  if ([regex]::isMatch($json, $referenceName, $regexOptions)) {
    write-console "replacing $referenceName with $newName in `$json" -foregroundColor 'Green'
    $json = [regex]::Replace($json, $referenceName, $newName, $regexOptions)
  }
  else {
    write-console "$referenceName not found" #-err
  }  
  return $json
}

function update-serviceFabricResource($serviceFabricResource){
  $nodeTypes = $serviceFabricResource.Properties.NodeTypes
  if(!$nodeTypes) { 
    write-error("node types not found")
    return $serviceFabricResource 
  }

  $nodeType = $nodeTypes | where-object Name -ieq $referenceNodeTypeName
  if($nodeType) { 
    write-console "node type $referenceNodeTypeName already exists" -err
    return $serviceFabricResource 
  }

  $nodeTypeTemplate = $nodeTypes[0]
  $nodeTypeTemplate.isPrimaryNodeType = $isPrimaryNodeType
  $nodeTypeTemplate.name = $newNodeTypeName
  $nodeTypes += $nodeTypeTemplate
  
  write-console $serviceFabricResource
  return $serviceFabricResource
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
