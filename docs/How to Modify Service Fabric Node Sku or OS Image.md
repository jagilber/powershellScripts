# How to Modify Service Fabric Node Sku or Operating System Image High-Level Steps

This guide gives a high-level overview of the steps involved to modify a Service Fabric nodetype / virtual machine scale set (vmss) hardware sku or operating system image.

Review [Scale up a Service Fabric cluster primary nodetype](https://docs.microsoft.com/azure/service-fabric/service-fabric-scale-up-primary-node-type) for detailed information about this process.

:exclamation:NOTE: As above document states, it is best to perform this process with a test cluster before production to fully understand process and time to complete.

## High-Level Steps

### - Create test cluster with same / similar setup as production

### - Add a new nodetype with modified sku and / or image with 'isPrimary' set to true

- ARM or powershell can be used
	- Powershell provides an easy method to add a new nodetype. However, not all properties of node configuration are configurable using this method.
		- [Add-AzServiceFabricNodeType](https://docs.microsoft.com/powershell/module/az.servicefabric/add-azservicefabricnodetype)
			```powershell
			$pwd = ConvertTo-SecureString -String 'Password$123456' -AsPlainText -Force

			Add-AzServiceFabricNodeType -ResourceGroupName 'sfclustergroup' `
				-Name 'sfcluster' `
				-NodeType 'nt1' `
				-Capacity 5 `
				-VmUserName 'cloudadmin' `
				-VmPassword $pwd `
				-DurabilityLevel Silver `
				-Verbose `
				-VMImageSku '2022-Datacenter' `
				-IsPrimaryNodeType $true
			```
	- ARM template provides access to all configuration options for new nodetype.
		- Copy / create these resources for new scale set:
			- Set keyvault certificate references
			- [Microsoft.Network/loadBalancers](https://docs.microsoft.com/azure/templates/microsoft.network/loadbalancers?tabs=json)
			- [Microsoft.Network/publicIPAddresses](https://docs.microsoft.com/azure/templates/microsoft.network/publicipaddresses?tabs=json)
			- [Microsoft.Compute/virtualMachineScaleSets](https://docs.microsoft.com/azure/templates/microsoft.compute/virtualmachinescalesets?tabs=json)
			- [Microsoft.Compute/virtualMachineScaleSets/extensions](https://docs.microsoft.com/azure/templates/microsoft.compute/virtualmachinescalesets/extensions?tabs=json)
			- [Microsoft.ServiceFabric/clusters nodetypes[]](https://docs.microsoft.com/azure/templates/microsoft.servicefabric/clusters?tabs=json)
				- Set new / copied nodetype property 'isPrimary' to true

### - Execute Change

### - Verify Cluster Health

See [Verifying Cluster Health](#verifying-cluster-health)

### - Set original primary nodetype 'isPrimary' to false

- Navigate to <https://resources.azure.com>, select the cluster resource, and select 'Edit'.

	```
		subscriptions
		└───%subscription name%
			└───resourceGroups
				└───%resource group name%
					└───providers
						└───Microsoft.ServiceFabric
							└───clusters
								└───%cluster name%
	```

- In the 'nodetypes[]' array, find old nodetype by name, set 'isPrimary' to false, and select 'PUT'.

	![](media/resources-azure-com-isprimary-false.png)

### - Execute Change

- This will perform 2 upgrade domain (UD) walks per seed node and will take Hours to perform

### - After all seed nodes have moved to new nodetype, disable original nodetype nodes

- [Disable-ServiceFabricNode](https://docs.microsoft.com/powershell/module/servicefabric/disable-servicefabricnode)
	```powershell
	Disable-ServiceFabricNode -NodeName "_nt0_0" -Intent RemoveNode
	Disable-ServiceFabricNode -NodeName "_nt0_1" -Intent RemoveNode
	...
	```

### - Migrate Traffic to new Loadbalancer

- There are multiple ways to achieve this and best way may depend on environment.
	- Move DNS name from old load balancer ip address to new load balancer ip.
	This method is fast as there are no dependent Azure resources bound to this object.
		```powershell
		$resourceGroupName = 'sfclustergroup'

		$oldPublicIP = Get-AzPublicIpAddress -Name 'PublicIP-LB-FE-nt0' -ResourceGroupName $resourceGroupName
		$publicIP = Get-AzPublicIpAddress -Name 'PublicIP-LB-FE-nt1' -ResourceGroupName $resourceGroupName
		
		$publicIP.DnsSettings.DomainNameLabel = $oldPublicIP.DnsSettings.DomainNameLabel
		$publicIP.DnsSettings.Fqdn = $oldPublicIP.DnsSettings.Fqdn
		Set-AzPublicIpAddress -PublicIpAddress $PublicIP
		```
	- Move IP address from old load balancer to new load balancer.
	This process takes longer to process from Azure perspective than using DNS method above due to network resources being modified.
	- Use new IP address of new loadbalancer.
	This method requires no change in Azure but requires resources connecting to cluster to be updated with new IP or DNS.
	- CNAME

### - After all data has been moved from original nodetype, remove original nodetype.

- [Remove-AzResource](https://docs.microsoft.com/powershell/module/az.resources/remove-azresource)
	```powershell
	Remove-AzResource -ResourceType 'Microsoft.Compute/virtualMachineScaleSets' -ResourceName 'nt0' -Force
	```

### - After all data has been moved from original loadbalancer, remove loadbalancer and IP resources.

- [Remove-AzResource](https://docs.microsoft.com/powershell/module/az.resources/remove-azresource)
	```powershell
	Remove-AzResource -ResourceType 'Microsoft.Network/loadBalancers' -ResourceName 'PublicIP-LB-FE-nt0' -Force

	Remove-AzResource -ResourceType 'Microsoft.Network/publicIPAddresses' -ResourceName 'PublicIP-VM' -Force
	```

### - After all original nodetype resources have been removed, remove node state from service fabric 
- [Remove-ServiceFabricNodeState](https://docs.microsoft.com/powershell/module/servicefabric/remove-servicefabricnodestate)
	```powershell
	Remove-ServiceFabricNodeState -NodeName "_nt0_0" -Intent RemoveNode
	Remove-ServiceFabricNodeState -NodeName "_nt0_1" -Intent RemoveNode
	...
	```

### - Verify Cluster Health

See [Verifying Cluster Health](#verifying-cluster-health)

### - ARM Template Cleanup

If using an ARM template for deployments, remove resources that are no longer being used.
- Verify and remove the following resourcetypes associated with the removed nodetype.
	- [Microsoft.Network/loadBalancers](https://docs.microsoft.com/azure/templates/microsoft.network/loadbalancers?tabs=json)
	- [Microsoft.Network/publicIPAddresses](https://docs.microsoft.com/azure/templates/microsoft.network/publicipaddresses?tabs=json)
	- [Microsoft.Compute/virtualMachineScaleSets](https://docs.microsoft.com/azure/templates/microsoft.compute/virtualmachinescalesets?tabs=json)
	- [Microsoft.Compute/virtualMachineScaleSets/extensions](https://docs.microsoft.com/azure/templates/microsoft.compute/virtualmachinescalesets/extensions?tabs=json)
	- [Microsoft.ServiceFabric/clusters nodetypes[]](https://docs.microsoft.com/azure/templates/microsoft.servicefabric/clusters?tabs=json)

## Verifying Cluster Health

- Ensure cluster has no Warnings or Errors after adding new nodetype and before continuing using Service Fabric Explorer (SFX) or Powershell
- SFX select 'Cluster' node to verify 0 Errors and 0 Warnings.
	- https://localhost:19080/Explorer
		![](../media/sfx-essentials.png)
- Using Powershell command [Get-ServiceFabricClusterHealth](https://docs.microsoft.com/powershell/module/servicefabric/get-servicefabricclusterhealth), check for AggregatedHealthState of 'Ok'.
	```powershell
	Get-ServiceFabricClusterHealth
	AggregatedHealthState   : Ok
	NodeHealthStates        : 
							NodeName              : _nt0_4
							AggregatedHealthState : Ok
							
							NodeName              : _nt0_3
							AggregatedHealthState : Ok
							
							NodeName              : _nt0_2
							AggregatedHealthState : Ok
							
							NodeName              : _nt0_1
							AggregatedHealthState : Ok
							
							NodeName              : _nt0_0
							AggregatedHealthState : Ok
							
	ApplicationHealthStates : 
							ApplicationName       : fabric:/System
							AggregatedHealthState : Ok
							
	HealthEvents            : None
	HealthStatistics        : 
	Node                  : 5 Ok, 0 Warning, 0 Error
	```
