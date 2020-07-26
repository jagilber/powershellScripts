# script to add reboot resource to service fabric template using cluster upgrade
# https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-diagnostics-eventstore
# Set-AzServiceFabricSetting -ResourceGroupName 'Group1' -Name 'Contoso01SFCluster'  -Section 'upgradeDescription' -Parameter 'forceRestart' -Value true
# https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-fabric-settings
# https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-config-upgrade-azure
# forcerestart restarts fabrichost.exe
# use this to send a dynamic cluster configuration upgrade with forcerestart to true
# this allows one fabrichost restart udwalk
# setting forcerestart back to false and reverting dynamic change prevents 2nd ud walk but allows configuration to reverted

# ps command with static configuration change can be used but if change is not permanent, reverting change will cause 2nd udwalk
# Set-AzServiceFabricSetting -ResourceGroupName sfjagilber1nt3 -Name sfjagilber1nt3  -Section FabricHost -Parameter FailureReportingTimeout -Value 61

param(
  [Parameter(Mandatory = $true)]
  $resourceGroupName,
  $clusterName,
  $templateFileName = ".\template.json",
  $patchScript = "$pwd\..\azure-az-patch-resource.ps1"
)

$ErrorActionPreference = 'continue'

$upgradeDescription = @{
  "forceRestart"                  = $true #// <--- set to 'false' after upgrade
  "upgradeReplicaSetCheckTimeout" = "1.00:00:00"
  "healthCheckWaitDuration"       = "00:00:30"
  "healthCheckStableDuration"     = "00:01:00"
  "healthCheckRetryTimeout"       = "00:45:00"
  "upgradeTimeout"                = "12:00:00"
  "upgradeDomainTimeout"          = "02:00:00"
  "healthPolicy"                  = @{
    "maxPercentUnhealthyNodes"        = 0
    "maxPercentUnhealthyApplications" = 0
  }
  "deltaHealthPolicy"             = @{
    "maxPercentDeltaUnhealthyNodes"              = 0
    "maxPercentUpgradeDomainDeltaUnhealthyNodes" = 0
    "maxPercentDeltaUnhealthyApplications"       = 0
  }
}

$patchScriptName = [io.path]::GetFileName($patchScript)

if (!(test-path $patchScript) -and !(test-path "$pwd\$patchScriptName")) {
  $patchScript = "$pwd\$patchScriptName"
  invoke-webrequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/$patchScriptName" -OutFile $patchScript
}

write-host "enumerating clusters in $resourceGroupName"

if (!$clusterName) {
  $clusters = @(Get-AzServiceFabricCluster -ResourceGroupName $resourceGroupName)
  $count = 0
  if ($clusters.Count -gt 1) {
    foreach ($cluster in $clusters) {
      $count++
      write-host "$($count). $($cluster.Name)"
    }

    $response = [convert]::ToInt32((read-host "enter number of cluster to upgrade reboot:"))
    if ($response -gt 0 -and $response -le $count) {
      $clusterName = $clusters[$response -1].Name
    }
  }
  elseif ($clusters.count -eq 1) {
    $clusterName = $clusters[0].Name
  }
  else {
    write-error "unable to enumerate cluster"
    return
  }
}

. $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName

$global:resourceTemplateObj

if (!$global:resourceTemplateObj.resources.properties.upgradeDescription) {
  write-host "adding upgradeDescription" -ForegroundColor Cyan
  Add-Member -InputObject $global:resourceTemplateObj.resources.properties -NotePropertyName upgradeDescription -NotePropertyValue $upgradeDescription 
}

write-host "setting forcerestart to true" -ForegroundColor Cyan
$global:resourceTemplateObj.resources.properties.upgradeDescription.forceRestart = $true

write-host "setting tag to trigger update" -ForegroundColor Cyan
if(!(Get-Member -InputObject $global:resourceTemplateObj.resources.tags | where-object Name -icontains "patch")) {
  Add-Member -InputObject $global:resourceTemplateObj.resources.tags -NotePropertyName "patch" -NotePropertyValue (get-date).ToString("o")
}
else {
  $global:resourceTemplateObj.resources.tags.patch = (get-date).ToString("o")
}

write-host $global:resourceTemplateObj | convertto-json -depth 99

write-host "saving file $templateFileName" -ForegroundColor Cyan
$global:resourceTemplateObj | convertto-json -depth 99 | out-file $templateFileName
write-host ($global:resourceTemplateObj | convertto-json -depth 99)

write-host "executing deployment setting restart to true" -ForegroundColor Cyan
. $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName -patch

write-host "setting forcerestart back to false" -ForegroundColor Cyan
$global:resourceTemplateObj.resources.properties.upgradeDescription.forceRestart = $false
write-host $global:resourceTemplateObj | convertto-json -depth 99

write-host "saving file $templateFileName" -ForegroundColor Cyan
$global:resourceTemplateObj | convertto-json -depth 99 | out-file $templateFileName
write-host ($global:resourceTemplateObj | convertto-json -depth 99)

write-host "executing deployment setting restart to false" -ForegroundColor Cyan
. $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName -patch

write-host "verifying forcerestart set to false" -ForegroundColor Cyan
. $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName

if ($global:resourceTemplateObj.resources.properties.upgradeDescription.forceRestart -ne $false) {
  write-error "template configuration incorrect. review template."
}

write-host "finished"