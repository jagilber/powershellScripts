<#
https://learn.microsoft.com/en-us/rest/api/servicefabric/sfclient-api-startclusterconfigurationupgrade
$clusterConfig = get-azresource -ResourceGroupName sfjagilber1nt5vm -ResourceType Microsoft.ServiceFabric/clusters -Name sfjagilber1nt5vm
$clusterConfig.Properties.nodeTypes[0].placementProperties

#>
#requires -psedition core

param(
  [string]$resourceGroupName = "sfcluster",
  [string]$clusterName = $resourceGroupName,
  [string]$apiVersion = "2023-11-01-preview",
  [string]$subscriptionId = (get-azcontext).Subscription.Id,
  [string]$nodeType = "nodetype0",
  [string]$jsonFile = "$pwd\current-config.json",
  [ValidateSet('add', 'remove')]
  [string]$addOrRemove = "add",
  [hashtable]$placementProperties = @{
    "nodeFunction" = "apps"
  },
  [switch]$whatIf
)

function main() {
  if ($resourceGroupName -eq "" -or $clusterName -eq "") {
    write-error "Please provide resourceGroupName and clusterName"
    return
  }

  $cluster = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroupName -Name $clusterName
  if ($cluster -eq $null) {
    write-error "Cluster not found"
    return
  }

  write-host "Cluster found: $($cluster.Name)"
  if (!(get-azresourcegroup)) {
    Connect-AzAccount
  }

  #$jsonht = $jsonConfig | ConvertFrom-Json -AsHashtable
  #  $jsonConfig = export-resource $subscriptionId $resourceGroupName $clusterName
  $resource = Get-AzResource -Name $clusterName `
    -ResourceGroupName $resourceGroupName `
    -ResourceType 'microsoft.servicefabric/clusters'

  Export-AzResourceGroup -ResourceGroupName $resourceGroupName `
    -Resource $resource.Id `
    -Path $jsonFile `
    -SkipAllParameterization `
    -Force

  $jsonConfig = ConvertFrom-Json -AsHashTable (Get-Content -Raw $jsonFile)

  # write-host "Configuration: $($jsonConfig | convertto-json)"
  if ($jsonConfig -eq $null) {
    write-error "Failed to get configuration"
    return
  }

  # $jsonConfig = $config | ConvertTo-Json -Depth 100
  write-host "Current configuration: $($jsonConfig | convertto-json)"
  $jsonConfig | out-file "\temp\current-config.json" -Force
  # code "\temp\current-config.json"


  # $config = update-placementConstraints $nodeType $placementProperties $config
  $config = update-jsonPlacementConstraints $nodeType $placementProperties $jsonConfig
  write-host "Result: $($config | ConvertTo-Json -d 5)"

  $jsonConfig = $config | ConvertTo-Json -Depth 100
  write-host "New configuration: $jsonConfig"
  #$jsonConfig | out-file "\temp\new-config.json"
  #code "\temp\new-config.json"

  if ($whatIf) {
    write-host "WhatIf: $whatIf"
    return
  }

  write-host "
    New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName ``
      -TemplateObject $config ``
      -Mode Incremental ``
      -Force ``
      -Verbose ``
      -DeploymentDebugLogLevel All
  "
  $result = New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
    -TemplateObject $config `
    -Mode Incremental `
    -Force `
    -Verbose `
    -DeploymentDebugLogLevel All

  write-host "Result: $result"
  write-host "finished"
}

function export-resource($subscriptionId, $resourceGroupName, $clusterName) {
  $resourceId = "/subscriptions/$($subscriptionId)/resourcegroups/$($resourceGroupName)/providers/Microsoft.ServiceFabric/clusters/$($clusterName)"
  $resource = export-azresourcegroup -ResourceGroupName $resourceGroupName `
    -resource $resourceId `
    -Path "C:\temp\exported-resource.json" `
    -SkipAllParameterization `
    -IncludeComments `
    -Force

  return (get-content "C:\temp\exported-resource.json" -raw) | ConvertFrom-Json -AsHashtable
}

function update-jsonPlacementConstraints($nodeType, $placementProperties, $config) {
  # $cluster = ConvertFrom-Json -AsHashTable $config
  # $clusterResource = $config.resources | Where-Object type -ieq 'microsoft.servicefabric/clusters'
  $nodeTypesList = $config.resources.properties.nodeTypes
  # $nodeTypeIndex = $nodeTypes | where-object { $_.name -eq $nodeType }
  $placementJson = $placementProperties | ConvertTo-Json -d 5
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
  write-host "updated placementProperties: $($nodeTypesList.placementProperties | ConvertTo-Json -d 5)"
  write-host "updated nodeTypes: $($nodeTypesList | ConvertTo-Json -d 5)"
  return $config
}

# function update-placementConstraints($nodeType, $placementProperties, $config) {
#   $nodeTypes = $config.Properties.nodeTypes
#   $nodeTypeIndex = $nodeTypes | where-object { $_.name -eq $nodeType }
#   if ($nodeTypeIndex -eq $null) {
#     Write-Host "Node type not found"
#     return $null
#   }

#   $placementJson = $placementProperties | ConvertTo-Json -d 5

#   if ($nodeTypeIndex.placementProperties -eq $null) {
#     # $nodeTypeIndex.placementProperties = @{}
#     write-host "placementProperties not found"
#     write-host "Add-Member -InputObject $nodeTypeIndex -MemberType NoteProperty -Name placementProperties -Value $placementProperties"
#     # Add-Member -InputObject $config.Properties.nodeTypes -MemberType NoteProperty -Name placementProperties -Value @{}
#     Add-Member -InputObject $nodeTypeIndex -MemberType NoteProperty -Name placementProperties -Value $placementProperties
#   }
#   else {
#     write-host "current placementProperties: $($nodeTypeIndex.placementProperties | ConvertTo-Json)"
#     $nodeTypeIndex.placementProperties = $placementProperties
#   }

#   write-host "updated placementProperties: $($nodeTypeIndex.placementProperties | ConvertTo-Json -d 5)"
#   write-host "updated nodeTypes: $($nodeTypes | ConvertTo-Json -d 5)"
#   return $config
# }

main

