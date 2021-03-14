<#
.SYNOPSIS
# script to update azure service fabric settings
# https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-fabric-settings

.LINK
(new-object net.webclient).DownloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-set-fabric-settings.ps1","$pwd\azure-az-sf-set-fabric-settings.ps1")
.\azure-az-sf-set-fabric-settings.ps1 -resourceGroup {{cluster resource group}} -clusterName {{cluster name}} -fabricSettingsJson {{fabric settings arm template json string}}

.EXAMPLE
.\azure-az-sf-set-fabric-settings.ps1 -resourceGroup someResourceGroup `
    -clusterName someCluster `
    -fabricSettingsJson '[
        {
            "name": "Security",
            "parameters": [{
                "name": "ClusterProtectionLevel",
                "value": "EncryptAndSign"
            }]
        }
    ]'
#>

param (
    [string]$resourceGroup = '',
    [string]$clusterName = '',
    [string]$fabricSettingsJson = '', # '{"name":"Management","parameters":[{"name":"CleanupApplicationPackageOnProvisionSuccess","value":"True"}]}'
    [hashtable]$fabricSettings = @{''=@{}} # @{'Management' = @{%parameter name%=%parameter value%}
)

$PSModuleAutoLoadingPreference = 1

function main () {
    $fabricSettingsArray = [collections.Generic.List[Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsSectionDescription]]::new()

    if(!$resourceGroup -or !$clusterName -or !($fabricSettingsJson -or $fabricSettings)) {
        write-error 'pass arguments'
        return
    }

    if (!(Get-AzResourceGroup | out-null)) {
        Connect-AzAccount
    }

    $error.Clear()
    $global:currentSettings = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clusterName
    write-host "current settings: `r`n $global:currentSettings" -ForegroundColor Green
    write-host "current fabric settings"
    $currentSettings.FabricSettings
    if($error) {
        Write-Warning "error enumerating cluster"
        return
    }

    write-host "updating fabric settings" -foregroundcolor yellow
    write-host "using fabric settings array for one ud walk"

    if($fabricSettingsJson) {
        $error.Clear()
        write-host ($fabricSettingsJson | convertfrom-json | convertto-json) -ForegroundColor Green
        $fabricSettings = $fabricSettingsJson | convertfrom-json

        if($error) {
            Write-Warning "error converting json"
            return
        }

        foreach($fabricSetting in $fabricSettings) {
            $fabricParametersArray = [collections.Generic.List[Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription]]::new()
            $sectionDescription = new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsSectionDescription
            $sectionDescription.name = $fabricSetting.name

            foreach($setting in $fabricSetting.parameters) {
                $fabricParametersArray.Add((add-parameter -name $setting.name -value $setting.value))
            }

            $sectionDescription.parameters = $fabricParametersArray
            $fabricSettingsArray.Add($sectionDescription)
        }

    }
    else {
        foreach($fabricSetting in $fabricSettings.GetEnumerator()) {
            $fabricParametersArray = [collections.Generic.List[Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription]]::new()
            $sectionDescription = new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsSectionDescription
            $sectionDescription.name = $fabricSetting.Key

            foreach($setting in $fabricSetting.Value.GetEnumerator()) {
                $fabricParametersArray.Add((add-parameter -name $setting.name -value $setting.value))
            }

            $sectionDescription.parameters = $fabricParametersArray
            $fabricSettingsArray.Add($sectionDescription)
        }
    }
    $fabricSettingsArray

    write-host "Set-AzServiceFabricSetting -ResourceGroupName $resourceGroup `
            -Name $clusterName `
            -SettingsSectionDescription $fabricSettingsArray"

    Set-AzServiceFabricSetting -ResourceGroupName $resourceGroup `
        -Name $clusterName `
        -SettingsSectionDescription $fabricSettingsArray

    $global:newSettings = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clusterName
    write-host "new settings: `r`n $global:newSettings" -ForegroundColor Cyan
    write-host "new fabric settings"

    $currentSettings.FabricSettings
    write-host 'finished'
}

function add-parameter([string]$name, $value) {
    return (new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription -property @{
        name  = $name
        value = $value
    })
}
    
main