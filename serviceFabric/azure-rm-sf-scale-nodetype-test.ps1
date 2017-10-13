<#
    example script to test scaling / keyvault
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
    $nodename,
    $resourceGroup,
    $clustername = $resourcegroup,
    $vmssName,
    [pscredential]$credential,
    [switch]$pause
)

if(!$credential)
{
    if(!$Global:credential)
    {
        $Global:credential = $credential = get-credential
    }
    else
    {
        $credential = $Global:credential
    }
}

import-module azurerm.servicefabric
$securePassword = ConvertTo-SecureString -String $credential.Password -AsPlainText -Force

if(!$nodename)
{
    # get highest id instance in vmss
    $vmssVms = Get-AzureRmVmssVM -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName
    $nodeName = $vmssVms[-1].Name
}

write-host "disabling node $($nodeName)" -ForegroundColor Cyan
$cluster = Get-AzureRmServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clustername

Connect-ServiceFabricCluster -ConnectionEndpoint ($cluster.ManagementEndpoint.Replace("19080","19000").Replace("https://","")) `
    -ServerCertThumbprint $cluster.Certificate.Thumbprint `
    -StoreLocation CurrentUser `
    -X509Credential `
    -FindType FindByThumbprint `
    -FindValue $cluster.Certificate.Thumbprint


if($pause) { pause }
$vmss = Get-AzureRmVmss -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName

if($vmss.sku.capacity -gt 1)
{
    write-host "scaling down vmss to prevent unnecessary upgrade" -ForegroundColor Cyan
    write-host "scale up vmss" -ForegroundColor Cyan

    $vmss = Get-AzureRmVmss -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName
    $vmss.sku.capacity = $vmss.sku.capacity + 1
    Update-AzureRmVmss -ResourceGroupName $resourceGroup -Name $vmssName -VirtualMachineScaleSet $vmss 
    if($pause) { pause }

    write-host "scale down vmss to original capacity" -ForegroundColor Cyan

    $vmssVms = Get-AzureRmVmssVM -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName
    $nodeName = $vmssVms[-1].Name
    Disable-ServiceFabricNode -NodeName $nodename -Intent RemoveNode -Force
    if($pause) { pause }

    $vmss.sku.capacity = $vmss.sku.capacity - 1
    Update-AzureRmVmss -ResourceGroupName $resourceGroup -Name $vmssName -VirtualMachineScaleSet $vmss 
    if($pause) { pause }

    Remove-servicefabricnodestate -nodename $nodename
}
else
{
    write-Warning "not scaling down vmss to prevent unnecessary upgrade as only one instance. exiting"
}

