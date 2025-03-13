<#
    script to add NSG 100 rule for remote access to azure resources for test deployments
    https://docs.microsoft.com/en-us/azure/virtual-network/service-tags-overview
    iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-add-nsg-rule.ps1" -out "$pwd\azure-az-add-nsg-rule.ps1";.\azure-az-add-nsg-rule.ps1
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup = '',
    [string]$nsgRuleName = "remote-rule",
    [int]$priority = 100,
    [string[]]$destPorts = @('*'), #@('3389', '19000', '19080', '19081', '22'),
    [string[]]$existingNsgNames = @(),
    [ValidateSet('allow','deny')]
    [string]$access = "Allow",
    [ValidateSet('inbound','outbound')]
    [string]$direction = "inbound",
    [string[]]$sourceAddressPrefix = @(((Invoke-RestMethod https://ipinfo.io/json).ip)), #,'*','AzureDevOps','AzureTrafficManager','ServiceFabric'), # *
    [string[]]$destAddressPrefix = @('*'), #,'*','AzureDevOps','AzureTrafficManager','ServiceFabric'), # *
    [switch]$force,
    [switch]$remove,
    [switch]$wait
)

function main () {
    $waitCount = 0

    while ($wait -or $waitCount -eq 0) {
        if (!$existingNsgNames) {
            $existingNsgNames = @((get-aznetworksecuritygroup -resourcegroupname $resourceGroup).Name)
        }
    
        foreach ($nsgName in $existingNsgNames) {
            if ([string]::IsNullOrEmpty($nsgName)) { continue }
            $nsg = get-nsg $nsgName
            if (!$nsg) {
                Write-Warning "unable to find $nsgName"
                continue
            }

            modify-nsgRule $nsg
            $waitCount++
        }

        if ($wait -and $waitCount -eq 0) {
            Write-Host "$waitCount waiting for nsg $(get-date)"
            Start-Sleep -Seconds 60
        }
        else {
            break
        }
    }
    write-host "finished"
}

function get-nsg($name) {
    $nsg = Get-AzNetworkSecurityGroup -Name $name -ResourceGroupName $resourceGroup
    if (!$nsg) {
        Write-Warning "no nsg $nsgname`r`nreturning"
        return $false
    }
    return $nsg
}

function modify-nsgRule($nsg) {
    $currentRule = Get-AzNetworkSecurityRuleConfig -Name $nsgRuleName -NetworkSecurityGroup $nsg -ErrorAction SilentlyContinue

    if ($currentRule -and ($force -or $remove)) {
        Write-Warning "deleting existing rule`r`n$($currentRule | convertto-json -depth 5)"
        Remove-AzNetworkSecurityRuleConfig -Name $nsgRuleName -NetworkSecurityGroup $nsg
    }
    elseif ($currentRule) {
        Write-Warning "$nsgRuleName exists`r`nreturning"
        return
    }
    elseif (!$currentRule -and $remove) {
        Write-Warning "$nsgRuleName does not exist`r`nreturning"
        return
    }

    write-host "adding rule:
    Add-AzNetworkSecurityRuleConfig -Name $nsgRuleName ``
        -NetworkSecurityGroup $nsg ``
        -Description $nsgRuleName ``
        -Access $access ``
        -Protocol Tcp ``
        -Direction $direction ``
        -Priority $priority ``
        -SourceAddressPrefix $sourceAddressPrefix ``
        -SourcePortRange * ``
        -DestinationAddressPrefix $destAddressPrefix ``
        -DestinationPortRange $destPorts
    " -ForegroundColor Green

    Add-AzNetworkSecurityRuleConfig -Name $nsgRuleName `
        -NetworkSecurityGroup $nsg `
        -Description $nsgRuleName `
        -Access $access `
        -Protocol Tcp `
        -Direction $direction `
        -Priority $priority `
        -SourceAddressPrefix $sourceAddressPrefix `
        -SourcePortRange * `
        -DestinationAddressPrefix $destAddressPrefix `
        -DestinationPortRange $destPorts

    write-host "setting rule: Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg" -ForegroundColor Green
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
}

main
