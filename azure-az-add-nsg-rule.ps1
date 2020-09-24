<#
    script to add NSG 100 rule for remote access to azure resources for test deployments
#>

param(
    [string]$resourceGroup = '',
    [string]$nsgRuleName = "remote-rule",
    [int]$priority = 100,
    [string[]]$ports = @('3389', '19000', '19080', '19081', '22'),
    [string[]]$existingNsgNames = @(),
    [string]$access = "Allow",
    [string]$sourceAddressPrefix = (invoke-webRequest -uri "http://ifconfig.me/ip").Content, # *
    [switch]$force,
    [switch]$remove,
    [switch]$wait
)

function main () {
    $waitCount = 0

    if ($existingNsgNames.Count -lt 1) {
        $existingNsgNames = @((get-aznetworksecuritygroup -resourcegroupname $resourceGroup).Name)
    }

    $rulesCount = $existingNsgNames.Count

    while ($rulesCount) {
        foreach ($nsgName in $existingNsgNames) {
            $nsg = get-nsg $nsgName
            if (!$nsg) {
                Write-Warning "unable to find $nsgName"
                continue
            }

            modify-nsgRule $nsg
            $rulesCount--
        }

        if ($wait -and $rulesCount -gt 0) {
            Write-Host "$waitCount waiting for $rulesCount nsg $(get-date)"
            $waitCount++
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
    $currentRule = Get-AzNetworkSecurityRuleConfig -Name $nsgRuleName -NetworkSecurityGroup $nsg

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
    Add-AzNetworkSecurityRuleConfig -Name $nsgRuleName `
        -NetworkSecurityGroup $nsg `
        -Description $nsgRuleName `
        -Access $access `
        -Protocol Tcp `
        -Direction Inbound `
        -Priority $priority `
        -SourceAddressPrefix $sourceAddressPrefix `
        -SourcePortRange * `
        -DestinationAddressPrefix * `
        -DestinationPortRange $ports
    " -ForegroundColor Green

    Add-AzNetworkSecurityRuleConfig -Name $nsgRuleName `
        -NetworkSecurityGroup $nsg `
        -Description $nsgRuleName `
        -Access $access `
        -Protocol Tcp `
        -Direction Inbound `
        -Priority $priority `
        -SourceAddressPrefix $sourceAddressPrefix `
        -SourcePortRange * `
        -DestinationAddressPrefix * `
        -DestinationPortRange $ports

    write-host "setting rule: Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg" -ForegroundColor Green
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
}

main
