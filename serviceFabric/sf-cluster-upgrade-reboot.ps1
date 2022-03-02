<#
.SYNOPSIS
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

.LINK
To download and execute:
    [net.servicePointManager]::Expect100Continue = $true;
    [net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/temp/desktop-heap.ps1" -outFile "$pwd\desktop-heap.ps1";.\desktop-heap.ps1
#>

param(
  [Parameter(Mandatory = $true)]
  $resourceGroupName,
  $clusterName,
  $templateFileName = "$pwd\template.json",
  $patchScript = "$pwd\..\azure-az-patch-resource.ps1",
  [switch]$whatIf
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
      $clusterName = $clusters[$response - 1].Name
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

write-host ". $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName" -ForegroundColor Cyan
. $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName

$global:resourceTemplateObj

if (!($global:resourceTemplateObj.resources.properties -imatch 'upgradeDescription')) {
  write-host "adding upgradeDescription" -ForegroundColor Cyan
  Add-Member -InputObject $global:resourceTemplateObj.resources.properties -NotePropertyName upgradeDescription -NotePropertyValue $upgradeDescription 
}

write-host "setting forcerestart to true" -ForegroundColor Cyan
$global:resourceTemplateObj.resources.properties.upgradeDescription.forceRestart = $true

write-host "setting tag" -ForegroundColor Cyan
if (!(Get-Member -InputObject $global:resourceTemplateObj.resources.tags | where-object Name -icontains "patch")) {
  Add-Member -InputObject $global:resourceTemplateObj.resources.tags -NotePropertyName "patch" -NotePropertyValue (get-date).ToString("o")
}
else {
  $global:resourceTemplateObj.resources.tags.patch = (get-date).ToString("o")
}

write-host "decrementing nt 0 ephemeral start port to trigger update" -ForegroundColor Cyan
$global:currentNTEStartPort = $global:resourceTemplateObj.resources.properties.nodeTypes[0].ephemeralPorts.startPort
$global:resourceTemplateObj.resources.properties.nodeTypes[0].ephemeralPorts.startPort = $global:currentNTEStartPort - 1
write-host "current ephem start port:$($global:currentNTEStartPort)" -ForegroundColor Yellow
write-host "new ephem start port:$($global:resourceTemplateObj.resources.properties.nodeTypes[0].ephemeralPorts.startPort)" -ForegroundColor Yellow

write-host $global:resourceTemplateObj | convertto-json -depth 99

write-host "saving file $templateFileName" -ForegroundColor Cyan
$global:resourceTemplateObj | convertto-json -depth 99 | out-file $templateFileName
write-host ($global:resourceTemplateObj | convertto-json -depth 99)

write-host "executing deployment setting restart to true" -ForegroundColor Cyan
write-host ". $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName -patch" -ForegroundColor Magenta
if(!$whatIf){
  . $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName -patch
}

write-host "setting forcerestart back to false" -ForegroundColor Cyan
$global:resourceTemplateObj.resources.properties.upgradeDescription.forceRestart = $false
write-host $global:resourceTemplateObj | convertto-json -depth 99

write-host "incrementing nt 0 ephemeral start port to trigger update" -ForegroundColor Cyan
$global:currentNTEStartPort = $global:resourceTemplateObj.resources.properties.nodeTypes[0].ephemeralPorts.startPort
$global:resourceTemplateObj.resources.properties.nodeTypes[0].ephemeralPorts.startPort = $global:currentNTEStartPort + 1
write-host "current ephem start port:$($global:currentNTEStartPort)" -ForegroundColor Yellow
write-host "new ephem start port:$($global:resourceTemplateObj.resources.properties.nodeTypes[0].ephemeralPorts.startPort)" -ForegroundColor Yellow

write-host "saving file $templateFileName" -ForegroundColor Cyan
$global:resourceTemplateObj | convertto-json -depth 99 | out-file $templateFileName
write-host ($global:resourceTemplateObj | convertto-json -depth 99)

write-host "executing deployment setting restart to false" -ForegroundColor Cyan
write-host ". $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName -patch" -ForegroundColor Magenta
if(!$whatIf){
  . $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName -patch
}

write-host "verifying forcerestart set to false" -ForegroundColor Cyan
write-host ". $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName" -ForegroundColor Magenta
if(!$whatIf) {
  . $patchScript -resourceGroupName $resourceGroupName -resourceName $clusterName -templateJsonFile $templateFileName
}

if ($global:resourceTemplateObj.resources.properties.upgradeDescription.forceRestart -ne $false) {
  write-error "template configuration incorrect. review template."
}

write-host "finished"