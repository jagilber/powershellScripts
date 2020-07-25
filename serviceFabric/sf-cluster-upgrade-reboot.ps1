# script to add reboot resource to service fabric template using cluster upgrade
param(
    $resourceGroup,
    $cluster,
    $patchScript = "$pwd\..\azure-az-patch-resource.ps1"
)

if (!(Get-AzContext)) {
    if (!(Connect-AzAccount)) { return }
}

$patchScriptName = [io.path]::GetFileName($patchScript)

if (!(test-path $patchScript) -and !(test-path "$pwd\$patchScriptName")) {
    $patchScript = "$pwd\$patchScriptName"
    invoke-webrequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/$patchScriptName" -OutFile $patchScript
    #.\azure-az-patch-resource.ps1 -resourceGroupName {{ resource group name }} -resourceName {{ resource name }} [-patch]
}

<#
# add to properties section
"upgradeDescription": {
    "forceRestart": true, // <--- set to 'false' after upgrade
    "upgradeReplicaSetCheckTimeout": "1.00:00:00",
    "healthCheckWaitDuration": "00:00:30",
    "healthCheckStableDuration": "00:01:00",
    "healthCheckRetryTimeout": "00:45:00",
    "upgradeTimeout": "12:00:00",
    "upgradeDomainTimeout": "02:00:00",
    "healthPolicy": {
      "maxPercentUnhealthyNodes": 0,
      "maxPercentUnhealthyApplications": 0
    },
    "deltaHealthPolicy": {
      "maxPercentDeltaUnhealthyNodes": 0,
      "maxPercentUpgradeDomainDeltaUnhealthyNodes": 0,
      "maxPercentDeltaUnhealthyApplications": 0
    }
  },
  #>