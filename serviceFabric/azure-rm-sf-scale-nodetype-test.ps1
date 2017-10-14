<#
    example service fabric script to test azure sf scaling / keyvault
    171013

    Copyright 2017 Microsoft Corporation

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
#>

[cmdletbinding()]
param(
    [Parameter(Mandatory = $true)]
    $resourceGroup,
    $clustername = $resourcegroup,
    [Parameter(Mandatory = $true)]
    $vmssName,
    $nodename,
    [switch]$pause
)

$startTime = get-date
import-module azurerm.servicefabric

if (!(Get-AzureRmResourceGroup))
{
    Add-AzureRmAccount
}

if (!$nodename)
{
    # get highest id instance in vmss
    $vmssVms = Get-AzureRmVmssVM -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName
    $nodeName = $vmssVms[-1].Name
}

write-host "$(get-date) connecting to cluster" -ForegroundColor Cyan
$cluster = Get-AzureRmServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clustername
$endpoint = $cluster.ManagementEndpoint.Replace($cluster.NodeTypes.HttpGatewayEndpointPort.ToString(), $cluster.NodeTypes.ClientConnectionEndpointPort.ToString())
$endpoint = [regex]::Replace($endpoint, "http.://", "")

$ret = Connect-ServiceFabricCluster -ConnectionEndpoint $endpoint `
    -ServerCertThumbprint $cluster.Certificate.Thumbprint `
    -StoreLocation CurrentUser `
    -X509Credential `
    -FindType FindByThumbprint `
    -FindValue $cluster.Certificate.Thumbprint

if ($pause)
{
    pause 
}

$vmss = Get-AzureRmVmss -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName

if ($vmss.sku.capacity -lt 1)
{
    write-Warning "not scaling down vmss as there is only one instance. exiting"
    exit 1
}

write-host "$(get-date) scaling up vmss" -ForegroundColor Cyan
$vmss = Get-AzureRmVmss -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName

write-host "$(get-date) updating scale set to $($vmss.sku.capacity + 1)" -ForegroundColor Cyan
$vmss.sku.capacity = $vmss.sku.capacity + 1
Update-AzureRmVmss -ResourceGroupName $resourceGroup -Name $vmssName -VirtualMachineScaleSet $vmss 

if ($pause)
{
    pause 
}

write-host "$(get-date) scaling down vmss to original capacity" -ForegroundColor Cyan
$vmssVms = Get-AzureRmVmssVM -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName
$nodeName = $vmssVms[-1].Name

write-host "$(get-date) disabling node $($nodeName)" -ForegroundColor Cyan
Disable-ServiceFabricNode -NodeName "_$($nodename)" -Intent RemoveNode 
$status = ""

while ($status -ine "Disabled")
{
    $status = (Get-ServiceFabricNode -NodeName "_$($nodename)").NodeStatus
    write-host "$(get-date) node status: $($status)" -foregroundcolor Cyan
    start-sleep -seconds 10
} 

if ($pause)
{
    pause 
}

write-host "$(get-date) updating scale set to $($vmss.sku.capacity - 1)" -ForegroundColor Cyan
$vmss.sku.capacity = $vmss.sku.capacity - 1
Update-AzureRmVmss -ResourceGroupName $resourceGroup -Name $vmssName -VirtualMachineScaleSet $vmss 

if ($pause)
{
    pause 
}

write-host "$(get-date) removing node state" -ForegroundColor Cyan
Remove-servicefabricnodestate -nodename $nodename -Force
write-host "$(get-date) finished. total minutes: $(((get-date) - $startTime).TotalMinutes.ToString("D3"))" -ForegroundColor Cyan
