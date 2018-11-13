<#
    script to enumerate rdp port mapping from cluster load balancer for service fabric scaleset
#>

param(
    [Parameter(Mandatory=$true)]
    $resourcegroup
)

write-host "checking resource group $resourceGroup"
$lbs = Get-AzureRmLoadBalancer -ResourceGroupName $resourcegroup
$cluster = Get-AzureRmServiceFabricCluster -ResourceGroupName $resourcegroup
$clusterfqdn = [regex]::Match($cluster.ManagementEndpoint,"http.://(.+?):").Groups[1].Value

foreach($rule in $lbs.InboundNatRules)
{
    $frontEndPort = $rule.FrontendPort
    $nicId = convertfrom-json $rule.BackendIPConfigurationText
    $matches = [regex]::Match($nicId.Id,"/virtualMachineScaleSets/(?<nodeTypeName>.+?)/virtualMachines/(?<instanceId>.+?)/networkInterfaces")
    $instanceId = $matches.Groups['instanceId'].Value
    $nodeTypeName = $matches.Groups['nodeTypeName'].Value
    $vmssvm = Get-AzureRmVmssVM -ResourceGroupName $resourcegroup -VMScaleSetName $nodeTypeName -InstanceId $instanceId
    
    "$($vmssvm.name): mstsc /v $($clusterfqdn):$($frontEndPort)"
}

write-host "finished"