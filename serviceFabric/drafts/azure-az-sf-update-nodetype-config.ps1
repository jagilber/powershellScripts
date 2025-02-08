<#
https://learn.microsoft.com/en-us/rest/api/servicefabric/sfclient-api-startclusterconfigurationupgrade
$clusterConfig = get-azresource -ResourceGroupName sfjagilber1nt5vm -ResourceType Microsoft.ServiceFabric/clusters -Name sfjagilber1nt5vm
$clusterConfig.Properties.nodeTypes[0].placementProperties

#>
#requires -psedition core

param(
  [Parameter(Mandatory = $true)]
  [string]$resourceGroupName = "sfcluster",
  [string]$clusterName = $resourceGroupName,
  [string]$apiVersion = "2023-11-01-preview",
  [string]$subscriptionId = (get-azcontext).Subscription.Id,
  [string]$nodeType = "nodetype0",
  [string]$jsonFile = "$pwd\current-config.json",
  [string]$deploymentName = "$resourceGroupName-$((get-date).ToString("yyyyMMdd-HHmms"))",
  [ValidateSet('add', 'remove')]
  [string]$addOrRemove = "add",
  [hashtable]$placementProperties = @{
    "nodeFunction" = "management"
  },
  [switch]$whatIf
)

function main() {
  if ($resourceGroupName -eq "" -or $clusterName -eq "") {
    write-error "Please provide resourceGroupName and clusterName"
    return
  }

  if (!(get-azresourcegroup)) {
    Connect-AzAccount
  }

  $cluster = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroupName -Name $clusterName
  if ($cluster -eq $null) {
    write-error "Cluster not found"
    return
  }

  write-host "Cluster found: $($cluster.Name)"
  
  $resource = Get-AzResource -Name $clusterName `
    -ResourceGroupName $resourceGroupName `
    -ResourceType 'microsoft.servicefabric/clusters'

  Export-AzResourceGroup -ResourceGroupName $resourceGroupName `
    -Resource $resource.Id `
    -Path $jsonFile `
    -SkipAllParameterization `
    -Force

  $jsonConfig = convert-fromJson (Get-Content -Raw $jsonFile)

  if ($jsonConfig -eq $null) {
    write-error "Failed to get configuration"
    return
  }

  write-host "Current configuration: $(convert-toJson $jsonConfig)"
  $jsonConfig | out-file $jsonFile -Force

  $config = update-jsonPlacementConstraints $nodeType $placementProperties $jsonConfig
  write-host "Result: $(convert-toJson $config)"

  # if ($config.resources.properties.upgradeMode -ieq 'Automatic') {
  #   write-host "removing cluster code version since upgrade mode is Automatic" -foregroundColor 'Yellow'
  #   $config.resources.properties.clusterCodeVersion = $null
  # }

  $jsonConfig = convert-toJson $config
  write-host "New configuration: $jsonConfig"

  $newJsonFile = $jsonFile.Replace(".json", ".new.json")
  $jsonConfig | out-file $newJsonFile -Force
  write-host "New configuration saved to $newJsonFile"

  write-host "
  Test-AzResourceGroupDeployment -resourceGroupName $resourceGroupName ``
    -TemplateFile $newJsonFile ``
    -Verbose
  " -foregroundColor 'Cyan'

  $result = test-azResourceGroupDeployment -templateFile $newJsonFile -resourceGroupName $resourceGroupName -Verbose

  if ($result) {
    write-console "error: test-azResourceGroupDeployment failed:$($result | out-string)" -err
    return $result
  }

  write-host "
    New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName ``
      -DeploymentName $deploymentName ``
      -TemplateFile $newJsonFile ``
      -Mode Incremental ``
      -Force ``
      -Verbose ``
      -DeploymentDebugLogLevel All
  "
  if (!$whatIf) {
    $result = New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
      -DeploymentName $deploymentName `
      -TemplateFile $newJsonFile `
      -Mode Incremental `
      -Force `
      -Verbose `
      -DeploymentDebugLogLevel All
  }

  write-host "Result: $result"
  write-host "finished"
}

function convert-fromJson($json) {
  return convertFrom-json $json -AsHashtable
}

function convert-toJson($object) {
  return convertTo-json -d 10 $object
}

function update-jsonPlacementConstraints($nodeType, $placementProperties, $config) {
  $nodeTypesList = $config.resources.properties.nodeTypes
  $placementJson = convert-toJson $placementProperties

  write-host "current placementJson: $placementJson"
  $key = $placementProperties.Keys[0]
  $value = $placementProperties[$key]

  $found = $false
  foreach ($nodeTypeIndex in $nodeTypesList) {
    if (!($nodeTypeIndex.name -ieq $nodeType)) {
      continue
    }
    $found = $true

    if ($addOrRemove -ieq "add") {
      if ($nodeTypeIndex.placementProperties -eq $null) {
        Write-Host "Setting placement properties for node type $nodeType"
        $nodeTypeIndex.placementProperties = $placementProperties
      }
      elseif ($nodeTypeIndex.placementProperties.ContainsKey($key)) {
        Write-Host "Updating placement properties for node type $nodeType"
        $nodeTypeIndex.placementProperties.$key = $value
      }
      else {
        Write-Host "Adding placement properties for node type $nodeType"
        $nodeTypeIndex.placementProperties.Add($key, $value)
      }
    }
    elseif ($addOrRemove -ieq "remove") {
      if ($nodeTypeIndex.placementProperties -ne $null -and $nodeTypeIndex.placementProperties.ContainsKey($key)) {
        Write-Host "Removing placement properties for node type $nodeType"
        $nodeTypeIndex.placementProperties.Remove($key)
      }
      else {
        Write-Host "Key not found for $nodeType"
      }
    }
  }

  if (!$found) {
    Write-Host "Node type not found"
    return $null
  }

  #$clusterResource.properties.nodeTypes = $nodeTypes
  write-host "updated placementProperties: $(convert-toJson $nodeTypesList.placementProperties)"
  write-host "updated nodeTypes: $(convert-toJson $nodeTypesList)"
  return $config
}

main

