<#
.SYNOPSIS
    powershell script to test service fabric nodetype scaling / keyvault

.DESCRIPTION
    powershell script to test service fabric nodetype scaling / keyvault

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

.NOTES  
   File Name  : azure-rm-sf-scale-nodetype-test.ps1
   https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-rm-sf-scale-nodetype-test.ps1
   Author     : jagilber
   Version    : 171015
   History    : 

.EXAMPLE  
    .\azure-rm-sf-scale-nodetype-test.ps1 -resourceGroupName someClusterResource -vmssName nt0
    adds and removes new test node to cluster named 'someClusterResource' in resource group named 'someClusterResource' 
    to nodetype named 'nt0'

.EXAMPLE  
    .\azure-rm-sf-scale-nodetype-test.ps1 -resourceGroupName someClusterResource -vmssName nt0 -clusterName someServiceFabricCluster
    adds and removes new test node to cluster named 'someServiceFabricCluster' in resource group named 'someClusterResource' 
    to nodetype named 'nt0'

.EXAMPLE  
    .\azure-rm-sf-scale-nodetype-test.ps1 -resourceGroupName someClusterResource -vmssName nt0 -clusterName someServiceFabricCluster -noprompt
    adds and removes new test node to cluster named 'someServiceFabricCluster' in resource group named 'someClusterResource' 
    to nodetype named 'nt0' without prompting to remove

.PARAMETER resourceGroupName
    required paramater for the resource group name for service fabric cluster

.PARAMETER clusterName
    optional parameter for the service fabric cluster name
    default is resourceGroupName

.PARAMETER vmssName
    required parameter for the vm scale set / nodetype name to add test node to

.PARAMETER pause
    optional switch to add a pause after each command
    
.PARAMETER pause
    optional switch to disable prompt when removing test node
#>

[cmdletbinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup,
    [string]$clustername = $resourcegroup,
    [Parameter(Mandatory = $true)]
    [string]$vmssName,
    [switch]$pause,
    [switch]$noprompt
)

$startTime = get-date
import-module azurerm.servicefabric

try 
{
    Get-AzureRmResourceGroup | Out-Null
}
catch 
{
    Add-AzureRmAccount
}

write-host "$(get-date) connecting to cluster $($clustername)" -ForegroundColor Cyan
$cluster = Get-AzureRmServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clustername
$endpoint = $cluster.ManagementEndpoint.Replace($cluster.NodeTypes.HttpGatewayEndpointPort.ToString(), $cluster.NodeTypes.ClientConnectionEndpointPort.ToString())
$endpoint = [regex]::Replace($endpoint, "http.://", "")

Connect-ServiceFabricCluster -ConnectionEndpoint $endpoint `
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

write-host "$(get-date) scaling up vmss $($vmssName)" -ForegroundColor Cyan
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
$nodeName = "_$($vmssVms[-1].Name)"

write-host "$(get-date) disabling node $($nodeName)" -ForegroundColor Cyan

if ($noprompt)
{
    Disable-ServiceFabricNode -NodeName $nodename -Intent RemoveNode -Force
}
else 
{
    Disable-ServiceFabricNode -NodeName $nodename -Intent RemoveNode 
}
    
$status = ""

while ($status -ine "Disabled")
{
    $status = (Get-ServiceFabricNode -NodeName $nodename).NodeStatus
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
write-host "$(get-date) finished. total minutes: $(((get-date) - $startTime).TotalMinutes)" -ForegroundColor Cyan
