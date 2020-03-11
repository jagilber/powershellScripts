<#
# script to update azure vmss nic with existing application gateway in same resource group
download:
(new-object net.webclient).DownloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-vmss-set-appgw.ps1","$pwd\azure-az-vmss-set-appgw.ps1")
.\azure-az-vmss-set-appgw.ps1 -resourceGroupName {{ resource group name }} -appGatewayName {{ existing app gateway name }} [-force]

.EXAMPLE
#>
param (
    [string]$resourceGroupName = 'sfjagilber1nt3',
    [string]$existingAppGatewayName = 'sfjagilber1nt3ag',
    [string]$vmssScaleSetName = 'nt0',
    [switch]$force
)

function main () {
    
    if (!$resourceGroupName -or !$existingAppGatewayName) {
        write-error 'pass arguments'
        return
    }

    if (!(Get-AzContext)) {
        Connect-AzAccount
    }

    $agw = Get-azApplicationGateway -ResourceGroupName $resourceGroupName -Name $existingAppGatewayName
    if (!$agw -or !$agw.BackendAddressPools) {
        write-warning "unable to enumerate existing ag or backend pool in resource group. returning"
        return
    }

    $vmss = Get-azVmss -ResourceGroupName $resourceGroupName -VMScaleSetName $vmssScaleSetName
    if (!$vmss) {
        write-warning "unable to enumerate existing vm scaleset $vmssScaleSetName"
        return
    }


    if (!$force -and $vmssIpConfig.ApplicationGatewayBackendAddressPools.Count -gt 0) {
        write-warning "vmss nic already configured for applicationgateway. returning"
        return
    }

    $vmssIpConfig = $vmss.VirtualMachineProfile.NetworkProfile[0].NetworkInterfaceConfigurations[0].IpConfigurations[0]
    write-host "old config:`r`n$($vmssIpConfig|convertto-json -depth 5)" -ForegroundColor Magenta


    $error.Clear()
}

main

