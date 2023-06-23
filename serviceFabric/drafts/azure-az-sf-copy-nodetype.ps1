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
  $vmInstanceCount = 5,
  $vmSku = 'Standard_D2_v2',
  [ValidateSet('Bronze', 'Silver', 'Gold')]
  $durabilityLevel = 'Silver',
  $adminUserName = 'cloudadmin',
  $adminPassword = 'P@ssw0rd!',
  $newIpAddressName = 'ip-' + $newNodeTypeName,
  $newLoadBalancerName = 'lb-' + $newNodeTypeName,
  $template = "$psscriptroot\azure-az-sf-copy-nodetype.json",
  $whatIf = $true
)

$PSModuleAutoLoadingPreference = 'auto'
$global:deployedServices = @{}

function main() {
  write-console "main() started"
  $error.Clear()

  if (!(Get-Module az)) {
    Import-Module az
  }

  if (!(get-azresourceGroup)) {
    Connect-AzAccount
  }

  if((get-azvmss -ResourceGroupName $resourceGroupName -Name $newNodeTypeName)) {
    write-error("node type $newNodeTypeName already exists")
    return $error
  }

  if((Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $newIpAddressName)) {
    write-error("ip address $newIpAddressName already exists")
    return $error
  }

  if((Get-AzLoadBalancer -ResourceGroupName $resourceGroupName -Name $newLoadBalancerName)) {
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

  $referenceVmssCollection = get-vmssCollection
  #$referenceVmssCollection = update-referenceVmssCollection $referenceVmssCollection
  write-console $referenceVmssCollection
  $global:referenceVmssCollection = $referenceVmssCollection

  $newVmssCollection = copy-vmssCollection -vmssCollection $referenceVmssCollection
  deploy-vmssCollection $newVmssCollection

  write-console $newVmssCollection

  write-console "finished"
}

function copy-vmssCollection($VmssCollection) {
  $vmss = $VmssCollection.vmssConfig
  $ip = $VmssCollection.ipConfig
  $lb = $VmssCollection.loadBalancerConfig

  # set credentials
  $vmss.VirtualMachineProfile.OsProfile.AdminUsername = $adminUserName
  $vmss.VirtualMachineProfile.OsProfile.AdminPassword = $adminPassword

  # remove existing state
  $vmss.ProvisioningState = ''
  $vmss.Id = ''
  $vmssName = "/$($vmss.Name)(?<terminator>/|$|`"|,|\\)"
  $newVmssName = "/$($newNodeTypeName)`${terminator}"
  #$vmss.Name = $newNodeTypeName
  $vmss.Etag = ''

  $ip.ProvisioningState = ''
  $ip.Id = ''
  $ip.ResourceGuid = ''
  $ipName = "/$($ip.Name)(?<terminator>/|$|`"|,|\\)"
  $newIpName = "/$($newIpAddressName)`${terminator}"
  #$ip.Name = $newIpAddressName
  $ip.Etag = ''

  $lb.ProvisioningState = ''
  $lb.Id = ''
  $lbName = "/$($lb.Name)(?<terminator>/|$|`"|,|\\)"
  $newLBName = "/$($newLoadBalancerName)`${terminator}"
  #$lb.Name = $newLoadBalancerName
  $lb.Etag = ''

  $vmssJson = $vmss | convertto-json -Depth 10
  $ipJson = $ip | convertto-json -Depth 10
  $lbJson = $lb | convertto-json -Depth 10

  # remove existing state
  $ipJson = set-resourceName -referenceName "`"ProvisioningState`": `".+?`"," -newName "`"ProvisioningState`": `"`"," -json $ipJson
  $vmssJson = set-resourceName -referenceName "`"ProvisioningState`": `".+?`"," -newName "`"ProvisioningState`": `"`"," -json $vmssJson
  $lbJson = set-resourceName -referenceName "`"ProvisioningState`": `".+?`"," -newName "`"ProvisioningState`": `"`"," -json $lbJson

  $ipJson = set-resourceName -referenceName "`"Etag`": `".+?`"," -newName "`"Etag`": `"`"," -json $ipJson
  $vmssJson = set-resourceName -referenceName "`"Etag`": `".+?`"," -newName "`"Etag`": `"`"," -json $vmssJson
  $lbJson = set-resourceName -referenceName "`"Etag`": `".+?`"," -newName "`"Etag`": `"`"," -json $lbJson


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
  $vmssJson = set-resourceName -referenceName $ipName -newName $newIpName -json $ipJson
  $vmss = $vmssJson | convertfrom-json -asHashtable

  # set names
  $vmss.Name = $newNodeTypeName
  $ip.Name = $newIpAddressName
  $lb.Name = $newLoadBalancerName

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

function deploy-vmssCollection($vmssCollection){
  write-console "deploying new node type $newNodeTypeName"
  write-console $vmssCollection
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

function new-psVmssCollection($VmssCollection) {
  write-console "deploying new node type $newNodeTypeName"
  $vmss = $VmssCollection.vmssConfig
  $ip = $VmssCollection.ipConfig
  $loadBalancer = $VmssCollection.loadBalancerConfig

  # deploy ip
  write-console "New-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $newIpAddressName -AllocationMethod Static -DomainNameLabel $newNodeTypeName -Location $vmss.Location -Sku Standard -Zone 1"
  $result = New-AzPublicIpAddress -ResourceGroupName $resourceGroupName `
    -Name $newIpAddressName `
    -AllocationMethod Static `
    -DomainNameLabel $newNodeTypeName `
    -Location $vmss.Location `
    -Sku Standard `
    -Zone 1 `
    -WhatIf:$whatIf
  write-console $result

  # deploy load balancer
  write-console "New-AzLoadBalancer -ResourceGroupName $resourceGroupName -Name $newLoadBalancerName -LoadBalancingRule $loadBalancer.LoadBalancingRules[0] -FrontendIpConfiguration $loadBalancer.FrontendIpConfigurations[0] -BackendAddressPool $loadBalancer.BackendAddressPools[0] -Probe $loadBalancer.Probes[0] -InboundNatPool $loadBalancer.InboundNatPools[0]"
  $result = New-AzLoadBalancer -ResourceGroupName $resourceGroupName `
    -Name $newLoadBalancerName `
    -LoadBalancingRule $loadBalancer.LoadBalancingRules `
    -FrontendIpConfiguration $loadBalancer.FrontendIpConfigurations `
    -BackendAddressPool $loadBalancer.BackendAddressPools `
    -Probe $loadBalancer.Probes `
    -InboundNatPool $loadBalancer.InboundNatPools
  write-console $result

  # deploy vmss
  write-console "New-AzVmss -ResourceGroupName $resourceGroupName -Name $newNodeTypeName -VirtualMachineScaleSet $vmss"
  $result = New-AzVmss -ResourceGroupName $resourceGroupName -Name $newNodeTypeName -VirtualMachineScaleSet $vmss
  write-console $result
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

function set-resourceName($referenceName, $newName, $json) {
  $regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase

  if(!$json) {
    write-console "error: json is null" #-err
  }
  elseif(!$referenceName) {
    write-console "error: referenceName is null" #-err
  }
  elseif(!$newName) {
    write-console "newName is null"
  }

  # if([regex]::isMatch($json, $newName, $regexOptions)) {
  #   write-console "$newName already in `$json" #-err
  # }
  # elseif([regex]::isMatch($json, $referenceName, $regexOptions)) {
  #   write-console "replacing $referenceName with $newName in `$json" -foregroundColor 'Green'
  #   $json = [regex]::Replace($json, $referenceName, $newName)
  # }
  # else {
  #   write-console "$referenceName not found" #-err
  # }
  if([regex]::isMatch($json, $referenceName, $regexOptions)) {
    write-console "replacing $referenceName with $newName in `$json" -foregroundColor 'Green'
    $json = [regex]::Replace($json, $referenceName, $newName)
  }
  else {
    write-console "$referenceName not found" #-err
  }  
  return $json
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

  if($err) {
    write-error($message)
    throw
  }
}

main
