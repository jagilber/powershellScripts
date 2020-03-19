# script to add app gateway to existing service fabric deployment
# script requires existing rg, vnet, sub (sf deployment)

[cmdletbinding()]
param (
    [string]$resourceGroupName = "",
    [string]$vmssName = "nt0",
    [string]$appGatewayName = "$($resourceGroupName)-ag",
    [string]$agAddressPrefix = "10.0.1.0/24",
    [string]$agSku = "Standard_Small",
    [string]$location = "",
    [string]$vnetName = "VNet",
    [string]$agSubnetName = "Subnet-AG",
    #[string[]]$backendIpAddresses = @(), 
    [string]$agGatewayIpConfigName = "$($resourceGroupName)ApplicationGatewayIPConfig",
    [string]$agBackendAddressPoolName = "$($resourceGroupName)ApplicationGatewayBEAddressPool", # LoadBalancerBEAddressPool
    [string]$agFrontendIPConfigName = "$($resourceGroupName)ApplicationGatewayFEAddressPool", # LoadBalancerFEAddressPool
    [string]$publicIpName = "$($resourceGroupName)agPublicIp1",
    [string]$listenerName = "$($resourceGroupName)agListener1",
    [ValidateSet('http', 'https')]
    [string]$protocol = "http",
    [int]$frontEndPort = 80,
    [string]$frontEndPortName = "FrontEndPort01",
    [string]$backendPoolName = "PoolSetting01",
    [string]$agRuleName = "Rule01",
    [int]$backendPort = 80,
    [ValidateSet('attach', 'create')]
    [string]$action = 'create',
    [hashtable]$additionalParameters
)

$ErrorActionPreference = 'continue'
$error.Clear()
write-host "$pscommandpath $($PSBoundParameters | out-string)"
write-host "variables: `r`n$(get-variable | select Name,Value | ft -AutoSize * | out-string)"

function main() {
    if (!$resourceGroupName -or !$appGatewayName) {
        help $MyInvocation.ScriptName -full
        Write-warning 'pass arguments'
        return
    }

    if (!(Get-AzContext)) {
        if (!(Connect-AzAccount)) { return }
    }

    if (!$location) {
        $location = (Get-AzResourceGroup $resourceGroupName).location
    }
    write-host "using location $location"

    if (!($vnet = check-vnet)) { return }
    if (!($vmss = check-vmss)) { return }
    if (!($agw = check-agw -vnet $vnet)) { return }
    
    modify-vmssIpConfig -vmss -$vmss -agw $agw
    write-host "finished"
}

function check-agw($vnet) {
    #app gateway
    $agw = Get-azApplicationGateway -ResourceGroupName $resourceGroupName -Name $appGatewayName -ErrorAction SilentlyContinue
    if ((!$agw -or !$agw.BackendAddressPools) -and $action -ieq 'attach') {
        write-warning "unable to enumerate existing ag or backend pool in resource group. returning"
        return $null
    }
    elseif ($agw -and $action -ieq 'attach') {
        write-host "app gateway config:`r`n$($agw|convertto-json -depth 5)" -ForegroundColor Magenta
    }
    elseif ($agw -and $action -ieq 'create' -and !$force) {
        write-warning "ag already exists in resource group. returning"
        return $null
    }
    elseif (!$agw -and $action -ieq 'create') {
        write-warning "ag does not exist in resource group. creating"
        return create-agw -vnet $vnet
    }
    return $agw
}

function check-subnet($vnet) {
    # ag needs separate subnet that is empty or only other ags
    if (!(Get-azVirtualNetworkSubnetConfig -Name $agSubnetName -VirtualNetwork $vnet)) {
        return $false
    }

    return $true
}
function check-vmss() {
    $vmss = Get-azVmss -ResourceGroupName $resourceGroupName -VMScaleSetName $vmssScaleSetName
    if (!$vmss) {
        write-warning "unable to enumerate existing vm scaleset $vmssScaleSetName"
        return $null
    }
    write-host "vmss config:`r`n$($vmss|convertto-json -depth 5)" -ForegroundColor Magenta

    $vmssIpConfig = $vmss.VirtualMachineProfile.NetworkProfile[0].NetworkInterfaceConfigurations[0].IpConfigurations[0]
    write-host "vmss ip config:`r`n$($vmssIpConfig|convertto-json -depth 5)" -ForegroundColor Magenta

    if (!$force -and $vmssIpConfig.ApplicationGatewayBackendAddressPools.Count -gt 0) {
        write-warning "vmss nic already configured for applicationgateway. returning"
        return $null
    }

    return $vmss
}

function check-vnet () {
    $vnet = Get-azvirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroupName
    if (!$vnet) {
        write-warning "unable to enumerate existing vnet $vnet"
        return $null
    }
    write-host "vnet config:`r`n$($vnet|convertto-json -depth 5)" -ForegroundColor Magenta
    return $vnet
}

function create-agw($vnet) {
    $error.clear()
    if (!(create-subnet -vnet $vnet)) { return $null }

    $agSubnet = Get-azVirtualNetworkSubnetConfig `
        -Name $agSubnetName `
        -VirtualNetwork $vnet 
    
    $gatewayIPconfig = New-azApplicationGatewayIPConfiguration `
        -Name $agGatewayIpConfigName `
        -Subnet $agSubnet
    
    $pool = New-azApplicationGatewayBackendAddressPool `
        -Name $agBackendAddressPoolName 
    
    $poolSetting = New-azApplicationGatewayBackendHttpSettings `
        -Name $backendPoolName `
        -Port $backendPort `
        -Protocol $protocol `
        -CookieBasedAffinity "Disabled"

    $frontEndPort = New-azApplicationGatewayFrontendPort `
        -Name $frontEndPortName `
        -Port $frontEndPort

    # Create a public IP address
    $publicIp = New-azPublicIpAddress `
        -ResourceGroupName $resourceGroupName `
        -Name $publicIpName `
        -Location $location `
        -AllocationMethod "Dynamic" `
        -Force

    write-host "new ip config:`r`n$($publicIp | convertto-json)" -ForegroundColor Green

    # create application gateway
    $frontEndIpConfig = New-azApplicationGatewayFrontendIPConfig `
        -Name $agFrontendIPConfigName `
        -PublicIPAddress $publicIp `
        #-Subnet $agSubnet # for internal

    $listener = New-azApplicationGatewayHttpListener `
        -Name $listenerName  `
        -Protocol $protocol `
        -FrontendIpConfiguration $frontEndIpConfig `
        -FrontendPort $frontEndPort

    $rule = New-azApplicationGatewayRequestRoutingRule `
        -Name $agRuleName `
        -RuleType basic `
        -BackendHttpSettings $poolSetting `
        -HttpListener $listener `
        -BackendAddressPool $pool

    $agSku = New-azApplicationGatewaySku `
        -Name $agSku `
        -Tier Standard `
        -Capacity 2

   # [Microsoft.Azure.Commands.Network.Models.PSApplicationGateway]$gwModel = [Microsoft.Azure.Commands.Network.Models.PSApplicationGateway]::new()

   write-host "$gateway = New-azApplicationGateway -Name $appGatewayName `
        -ResourceGroupName $resourceGroupName `
        -Location $location `
        -BackendAddressPools $($pool |out-string)`
        -BackendHttpSettingsCollection $($poolSetting |out-string) `
        -FrontendIpConfigurations $($frontEndIpConfig |out-string) `
        -GatewayIpConfigurations $($gatewayIPconfig |out-string) `
        -FrontendPorts $($frontEndPort |out-string) `
        -HttpListeners $($listener |out-string) `
        -RequestRoutingRules $($rule |out-string) `
        -Sku $($agSku |out-string) `
        $($additionalParameters | out-string)"
        
    $gateway = New-azApplicationGateway -Name $appGatewayName `
        -ResourceGroupName $resourceGroupName `
        -Location $location `
        -BackendAddressPools $pool `
        -BackendHttpSettingsCollection $poolSetting `
        -FrontendIpConfigurations $frontEndIpConfig `
        -GatewayIpConfigurations $gatewayIPconfig `
        -FrontendPorts $frontEndPort `
        -HttpListeners $listener `
        -RequestRoutingRules $rule `
        -Sku $agSku `
        -Verbose `
        -Debug
        #@additionalParameters

    write-host "new application gateway:`r`n$($gateway|convertto-json -depth 5)" -ForegroundColor Magenta

    if (!$error -and $gateway) {
        write-host "gateway created successfully" -ForegroundColor green
        return $true
    }

    write-warning "gateway creation failed"
    return $null
}

function create-agSku($skuName, $tier = 'Standard', $capacity = 2) {
    return New-azApplicationGatewaySku -Name $skuName `
        -Tier $tier `
        -Capacity $capacity
}

function create-subnet($vnet, $sleepSeconds = 30, $maxSleepCount = 5) {
    # ag needs separate subnet that is empty or only other ags
    if (!(check-subnet -vnet $vnet)) {
        Add-azVirtualNetworkSubnetConfig -Name $agSubnetName -VirtualNetwork $vnet -AddressPrefix $agAddressPrefix
        Set-azVirtualNetwork -VirtualNetwork $vnet 
    }
    
    # timing issue?
    while (!(Get-azVirtualNetworkSubnetConfig -Name $agSubnetName -VirtualNetwork $vnet) -and ($count -lt $maxSleepCount)) {
        start-sleep -seconds $sleepSeconds
        $count++
    }

    if ($count -eq $maxSleepCount) {
        write-warning "timed out waiting for subnet change maxsleepcount $maxsleepcount sleepseconds $sleepseconds"
        return $false
    }

    return $true
}

function modify-vmssIpConfig ($vmss, $agw) {
    # change ip configuration on vmss
    $error.clear()
    $vmss = Get-azVmss -ResourceGroupName $resourceGroupName -VMScaleSetName $vmssName
    $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations 
 
    $agw = Get-azApplicationGateway -ResourceGroupName $resourceGroupName
    $agw.BackendAddressPools 
 
    $vmssipconf_LB_BEAddPools = $vmss.VirtualMachineProfile.NetworkProfile[0].NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools[0].Id
    $vmssipconf_LB_InNATPools = $vmss.VirtualMachineProfile.NetworkProfile[0].NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerInboundNatPools[0].Id
    $vmssipconf_Name = $vmss.VirtualMachineProfile.NetworkProfile[0].NetworkInterfaceConfigurations[0].IpConfigurations[0].Name
    $vmssipconf_Subnet = $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].Subnet.Id
    $vmssipconf_AppGW_BEAddPools = $agw.BackendAddressPools[0].Id
 
    $vmssipConfig = New-azVmssIPConfig -Name $vmssipconf_Name `
        -LoadBalancerInboundNatPoolsId $vmssipconf_LB_InNATPools `
        -LoadBalancerBackendAddressPoolsId $vmssipconf_LB_BEAddPools `
        -SubnetId $vmssipconf_Subnet `
        -ApplicationGatewayBackendAddressPoolsId $vmssipconf_AppGW_BEAddPools
 
    $nicconfigname = $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].Name
    Remove-azVmssNetworkInterfaceConfiguration -VirtualMachineScaleSet $vmss -Name $nicconfigname 
    Add-azVmssNetworkInterfaceConfiguration -VirtualMachineScaleSet $vmss -Name $nicconfigname -Primary $true -IPConfiguration $vmssipConfig
    Update-azVmss -ResourceGroupName $resourceGroupName -VirtualMachineScaleSet $vmss -Name $vmssName 
    if (!$error) {
        write-host "vmss updated successfully" -ForegroundColor green
        return $true
    }

    write-warning "vmss update failed"
    return $null

}

main
