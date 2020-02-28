# script to update azure service fabric settings for image store best practice

param (
    $resourceGroup = "",
    $clusterName = "",
    [bool]$useArray = $true
)

if (!(Get-AzContext)) {
    Connect-AzAccount
}

$global:currentSettings = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clusterName
write-host "current settings: `r`n $global:currentSettings" -ForegroundColor Green
write-host "current fabric settings"
$currentSettings.FabricSettings

#if (!($currentSettings.FabricSettings.Management)) {
    write-host "updating fabric settings" -foregroundcolor yellow
    if (!$useArray) {
        write-host "using fabric settings individual updates. ud walk per update. slow"
        Set-AzServiceFabricSetting -ResourceGroupName $resourceGroup `
            -Name $clusterName `
            -Section 'Management' `
            -Parameter 'CleanupApplicationPackageOnProvisionSuccess' `
            -Value $true

        Set-AzServiceFabricSetting -ResourceGroupName $resourceGroup `
            -Name $clusterName `
            -Section 'Management' `
            -Parameter 'CleanupUnusedApplicationTypes' `
            -Value $true

        Set-AzServiceFabricSetting -ResourceGroupName $resourceGroup `
            -Name $clusterName `
            -Section 'Management' `
            -Parameter 'PeriodicCleanupUnusedApplicationTypes' `
            -Value $true

        Set-AzServiceFabricSetting -ResourceGroupName $resourceGroup `
            -Name $clusterName `
            -Section 'Management' `
            -Parameter 'TriggerAppTypeCleanupOnProvisionSuccess' `
            -Value $true

        Set-AzServiceFabricSetting -ResourceGroupName $resourceGroup `
            -Name $clusterName `
            -Section 'Management' `
            -Parameter 'MaxUnusedAppTypeVersionsToKeep' `
            -Value 3
    }
    else {
        write-host "using fabric settings array. one ud walk. fast"
        $fabricSettingsArray = [collections.Generic.List[Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsSectionDescription]]::new()
        $sectionDescription = new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsSectionDescription
        $fabricParametersArray = [collections.Generic.List[Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription]]::new()

        $fabricParametersArray.Add((new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription -property @{
            name = 'CleanupApplicationPackageOnProvisionSuccess'
            value = $true
        }))

        $fabricParametersArray.Add((new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription -property @{
            name = 'CleanupUnusedApplicationTypes'
            value = $true
        }))

        $fabricParametersArray.Add((new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription -property @{
            name = 'PeriodicCleanupUnusedApplicationTypes'
            value = $true
        }))

        $fabricParametersArray.Add((new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription -property @{
            name = 'TriggerAppTypeCleanupOnProvisionSuccess'
            value = $true
        }))

        $fabricParametersArray.Add((new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription -property @{
            name = 'MaxUnusedAppTypeVersionsToKeep'
            value = 3
        }))

        $sectionDescription.name = "Management"
        $sectionDescription.parameters = $fabricParametersArray
        $fabricSettingsArray.Add($sectionDescription)

        $fabricSettingsArray | convertto-json

        write-host "Set-AzServiceFabricSetting -ResourceGroupName $resourceGroup `
            -Name $clusterName `
            -SettingsSectionDescription $fabricSettingsArray"

        Set-AzServiceFabricSetting -ResourceGroupName $resourceGroup `
            -Name $clusterName `
            -SettingsSectionDescription $fabricSettingsArray
    }
#}


$global:newSettings = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clusterName

write-host "new settings: `r`n $global:newSettings" -ForegroundColor Cyan

write-host "new fabric settings"
$currentSettings.FabricSettings
