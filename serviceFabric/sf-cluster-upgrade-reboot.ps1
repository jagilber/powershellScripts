# script to add reboot resource to service fabric template using cluster upgrade
param(
  [Parameter(Mandatory = $true)]
  $resourceGroupName,
  $clusterName,
  $templateFileName = ".\template.json",
  $patchScript = "$pwd\..\azure-az-patch-resource.ps1"
)

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
      write-host "$(++$count). $($cluster.Name)"
    }

    $response = [convert]::ToInt32((read-host "enter number of cluster to upgrade reboot:"))
    if ($response -gt 0 -and $response -le $count) {
      $clusterName = $clusters[$response].Name
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
write-host $global:resourceTemplateObj | convertto-json -depth 99

write-host "saving file $templateFileName" -ForegroundColor Cyan
$global:resourceTemplateObj | convertto-json -depth 99 | out-file $templateFileName

write-host "executing deployment setting restart to true" -ForegroundColor Cyan
. $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName -patch

write-host "setting forcerestart back to false" -ForegroundColor Cyan
$global:resourceTemplateObj.resources.properties.upgradeDescription.forceRestart = $false
write-host $global:resourceTemplateObj | convertto-json -depth 99

write-host "saving file $templateFileName" -ForegroundColor Cyan
$global:resourceTemplateObj | convertto-json -depth 99 | out-file $templateFileName
write-host $global:resourceTemplateObj | convertto-json -depth 99

write-host "executing deployment setting restart to false" -ForegroundColor Cyan
. $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName -patch

write-host "verifying forcerestart set to false" -ForegroundColor Cyan
. $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName

if ($global:resourceTemplateObj.resources.properties.upgradeDescription.forceRestart -ne $false) {
  write-error "template configuration incorrect. review template."
}

write-host "finished"