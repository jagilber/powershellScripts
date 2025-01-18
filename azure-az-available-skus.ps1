<#
.SYNOPSIS 
Get available virtual machine skus in a region

.DESCRIPTION
Get available skus in a region for a virtual machine. 
Filter by location, sku name, max memory, max vcpu, computer architecture type, hyperVGenerations, withRestrictions, and serviceFabric. 
If no skus are found, script returns $false to indicate no skus found else returns $true
Use the $filteredSkus variable to get details on available skus. example $filteredSkus | out-gridview
Can also be executed from https://shell.azure.com

.NOTES
  File Name      : azure-az-available-skus.ps1
  Author         : jagilber
  Prerequisite   : PowerShell core 6.1.0 or higher
  version        : 1.1

.PARAMETER force
  Force refresh of skus

.PARAMETER hyperVGenerations
    The hyperVGenerations to filter by

.PARAMETER maxMemoryGB
  The maximum memory in GB to filter by

.PARAMETER maxVCPU
  The maximum vcpu to filter by

.PARAMETER minMemoryGB
  The minimum memory in GB to filter by

.PARAMETER minVCPU
  The minimum vcpu to filter by

.PARAMETER location
  The location to get available skus

.PARAMETER skuName
  The sku name to filter by. regex based

.PARAMETER subscriptionId
  The subscription id to use

.PARAMETER computerArchitectureType
  The architecture type to filter by

.PARAMETER withRestrictions
  Include skus with restrictions

.PARAMETER serviceFabric
  Filter for service fabric skus

.EXAMPLE
  .\azure-az-available-skus.ps1 -location "eastus" -serviceFabric
  Get available skus in eastus for service fabric clusters

.EXAMPLE
  .\azure-az-available-skus.ps1 -skuName 'Standard_D2'
  Get available skus in all regions with sku name regex matching Standard_D2

.EXAMPLE
  .\azure-az-available-skus.ps1 -maxMemoryGB 64 -maxVCPU 12
  Get available skus in all regions with memory <= 64GB and vcpu <= 12

.EXAMPLE
  .\azure-az-available-skus.ps1 -maxMemoryGB 64 -maxVCPU 12 -location "eastus"
  Get available skus in all regions with memory <= 64GB and vcpu <= 12 in eastus

.EXAMPLE
  .\azure-az-available-skus.ps1 -maxMemoryGB 64 -maxVCPU 12 -hyperVGenerations "V1,V2"
  Get available skus in all regions with memory <= 64GB and vcpu <= 12 for hyperVGenerations V1 or V2 (V1 is default and required for sf)

.EXAMPLE
  .\azure-az-available-skus.ps1 -Location "eastus" -computerArchitectureType "x64"
  Get available skus in eastus for x64 architecture

.EXAMPLE
  .\azure-az-available-skus.ps1 -Location "eastus" -computerArchitectureType "x64" -verbose
  Get available skus in eastus for x64 architecture with verbose output

.EXAMPLE
  .\azure-az-available-skus.ps1 -Location "eastus" -computerArchitectureType "x64" -withRestrictions
  Get available skus in eastus for x64 architecture including skus with restrictions

.EXAMPLE
  .\azure-az-available-skus.ps1 -Location "eastus" -computerArchitectureType "ARM64" -withRestrictions
  Get available skus in eastus for ARM64 architecture including skus with restrictions

.OUTPUTS
  [bool] $true if skus are found, $false if no skus are found

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-available-skus.ps1" -outFile "$pwd\azure-az-available-skus.ps1";
    .\azure-az-available-skus.ps1

#>

[cmdletbinding()]
param (
  [string]$location = $null,
  [string]$subscriptionId = $null,
  [string]$computerArchitectureType = "x64",
  [ValidateSet("V1", "V2", "V1,V2", "", ".")]
  [string]$hyperVGenerations = "",
  [string]$skuName = $null,
  [int]$maxMemoryGB = 0, # 64, # 0 = unlimited
  [int]$maxVCPU = 0, # 4, # 0 = unlimited
  [int]$minMemoryGB = 0, # 0 = unlimited
  [int]$minVCPU = 0, # 0 = unlimited
  [switch]$withRestrictions,
  [switch]$serviceFabric, # hyperVGenerations needs "V1" or "V1,V2" for sf and MaxResourceVolumeMB needs temp disk (10000) 10gb and vmDeploymentTypes needs "PaaS"
  [ValidateSet("paas", "iaas", "")]
  [int]$maxResourceVolumeMB = -1, # 0 is no local disk -1 is unlimited
  [int]$minResourceVolumeMB = -1, # 0 is no local disk -1 is minimum (1)
  [string]$vmDeploymentTypes = "",
  [switch]$confidentialComputingType,
  [switch]$force
)

$global:filteredSkus = @{}

function main() {
  try {
    if (!(connect-az)) { return }
    if ($serviceFabric) {
      $computerArchitectureType = "x64"
      $hyperVGenerations = "V1"
      $minResourceVolumeMB = 10000
      $vmDeploymentTypes = "PaaS"
      $confidentialComputingType = $false
    }

    if (!$global:locations -or $force) {
      write-host "Get-AzLocation | Where-Object Providers -imatch 'Microsoft.Compute'" -ForegroundColor Cyan
      $global:locations = get-azlocation | where-object Providers -imatch 'Microsoft.Compute'
      if (!$global:locations) {
        write-error "no locations found"
        return
      }
    }

    if ($location -and ($global:locations.location -inotcontains $location)) {
      write-host ($locations | out-string) -ForegroundColor Cyan
      write-error "location $location is not valid"
      return
    }

    if (!$global:skus -or $force) {
      $global:skus = @{}
      write-host "retrieving skus" -ForegroundColor Green
      write-host "Get-AzComputeResourceSku | Where-Object { `$psitem.resourceType -ieq 'virtualMachines' }" -ForegroundColor Cyan
      $global:skus = Get-AzComputeResourceSku | Where-Object { 
        $psitem.resourceType -ieq 'virtualMachines' `
          -and $global:locations.Location -icontains $psitem.LocationInfo.Location
      }
      write-host "global:skus:$($global:skus.Count)" -ForegroundColor Cyan
    }

    if ($location) {
      write-host "filtering skus by location $location" -ForegroundColor Green
      write-host "
      `$global:filteredSkus = `$global:skus | Where-Object { 
        `$psitem.Locations -ieq $location
      }" -ForegroundColor Cyan
      $global:filteredSkus = $global:skus | Where-Object { 
        $psitem.Locations -ieq $location
      }
      write-verbose "available skus:`n$($global:skus | convertto-json -depth 10)"
      write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
    }
    else {
      $global:filteredSkus = $global:skus
    }

    if (!$global:skus) {
      write-error "no skus found in region $location"
      return
    }

    write-host "`$global:filteredSkus = `$global:skus" -ForegroundColor Cyan
    
    check-withRestrictions
    check-skuName
    check-computerArchitectureType
    check-hyperVGenerations
    check-resourceVolumeMB # check local storage
    check-maxMemoryGB
    check-maxvCpu
    check-vmDeploymentTypes
    check-minMemoryGB
    check-minvCpu
    check-confidentialComputingType

    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count)):`n$($global:filteredSkus | sort-object | out-string)" -ForegroundColor Magenta

    $locationGroup = $filteredSkus.LocationInfo.Location | group-object
    if ($locationGroup.Count -gt 1) {
      write-host "sku types grouped by location:`n$($locationGroup | select-object Count,Name | sort-object Name | out-string)" -ForegroundColor DarkMagenta
    }

    write-host "filtered skus with:
      location: $location
      computerArchitectureType: $computerArchitectureType
      hyperVGenerations: $hyperVGenerations
      maxMemoryGB: $maxMemoryGB
      maxVCPU: $maxVCPU
      skuName: $skuName
      MaxResourceVolumeMB: $maxResourceVolumeMB
      vmDeploymentTypes: $vmDeploymentTypes
      withRestrictions: $withRestrictions
      " -ForegroundColor DarkGray

    write-host "use variable `$filteredSkus to get details on available skus. example `$filteredSkus | out-gridview" -ForegroundColor Green
    return ($filteredSkus.Count -gt 0)
  }
  catch {
    write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
    write-verbose "variables:$((get-variable -scope local).value | convertto-json -WarningAction SilentlyContinue -depth 2)"
    return $false
  }
  finally {
  }
}

function check-computerArchitectureType(){
  if ($computerArchitectureType) {
    write-host "filtering skus by Capabilities.CpuArchitectureType = '$computerArchitectureType'" -ForegroundColor Green
    write-host "
    `$global:filteredSkus = `$global:filteredSkus | Where-Object { 
      `$psitem.Capabilities | where-object {
      `$psitem.Name -ieq 'CpuArchitectureType' -and `$psitem.Value -ieq $computerArchitectureType
    }" -ForegroundColor Cyan
    
    $global:filteredSkus = $global:filteredSkus | Where-Object {
      $psitem.Capabilities | where-object { 
        $psitem.Name -ieq 'CpuArchitectureType' -and $psitem.Value -ieq $computerArchitectureType
      }
    }
    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function check-confidentialComputingType() {
  if ($confidentialComputingType) {
    write-host "filtering skus by Capabilities.ConfidentialComputingType = '$confidentialComputingType'" -ForegroundColor Green
    write-host "
    `$global:filteredSkus = `$global:filteredSkus | Where-Object { 
      `$psitem.Capabilities | where-object {
      `$psitem.Name -ieq 'ConfidentialComputingType' -and `$psitem.Value -imatch $confidentialComputingType
    }" -ForegroundColor Cyan
    
    $global:filteredSkus = $global:filteredSkus | Where-Object {
      $psitem.Capabilities | where-object { 
        $psitem.Name -ieq 'ConfidentialComputingType' -and $psitem.Value -imatch $confidentialComputingType
      }
    }
    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
  else {
    write-host "removing skus by Capabilities.ConfidentialComputingType != `$null" -ForegroundColor Green
    write-host "
    `$tempSkus = [collections.arrayList]::new(`$global:filteredSkus)
      `$global:filteredSkus | Where-Object { 
      `$sku = $psitem
      foreach (`$capability in `$sku.Capabilities) {
        if (`$capability.Name -ieq 'ConfidentialComputingType') { 
          [void]`$tempSkus.Remove(`$sku)
          return
        }
      }
    }" -ForegroundColor Cyan
    $tempSkus = [collections.arrayList]::new($global:filteredSkus)
    $global:filteredSkus | Where-Object {
      $sku = $psitem
      foreach ($capability in $sku.Capabilities) {
        if ($capability.Name -ieq 'ConfidentialComputingType') { 
          #write-host "removing sku $($capability.Name) with value $($capability.Value)" -ForegroundColor Yellow
          [void]$tempSkus.Remove($sku)
          #write-host "temp skus count: ($($tempSkus.Count))" -ForegroundColor Magenta
          return
        }
      }
    }

    $global:filteredSkus = $tempSkus.ToArray()
    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function check-hyperVGenerations(){
  if ($hyperVGenerations) {
    write-host "filtering skus by Capabilities.HyperVGenerations = '$hyperVGenerations'" -ForegroundColor Green
    write-host "
    `$global:filteredSkus = `$global:filteredSkus | Where-Object { 
      `$psitem.Capabilities | where-object {
      `$psitem.Name -ieq 'HyperVGenerations' -and `$psitem.Value -imatch $hyperVGenerations
    }" -ForegroundColor Cyan
    
    $global:filteredSkus = $global:filteredSkus | Where-Object {
      $psitem.Capabilities | where-object { 
        $psitem.Name -ieq 'HyperVGenerations' -and $psitem.Value -imatch $hyperVGenerations
      }
    }
    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function check-maxMemoryGB(){
  if ($maxMemoryGB) {
    write-host "filtering skus by Capabilities.MemoryGB <= $maxMemoryGB" -ForegroundColor Green
    write-host "
    `$global:filteredSkus = `$global:filteredSkus | Where-Object { 
      `$psitem.Capabilities | where-object {
        `$psitem.Name -ieq 'MemoryGB' -and [int]`$psitem.Value -le $maxMemoryGB
      }
    }" -ForegroundColor Cyan

    $global:filteredSkus = $global:filteredSkus | where-object { 
      $psitem.Capabilities | where-object {
        $psitem.Name -ieq 'MemoryGB' -and [int]$psitem.Value -le $maxMemoryGB
      }
    }
    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function check-maxvCpu(){
  if ($maxVCPU) {
    write-host "filtering skus by Capabilities.VCPUs <= $maxVCPU" -ForegroundColor Green
    write-host "
    `$global:filteredSkus = `$global:filteredSkus | Where-Object { 
      `$psitem.Capabilities | where-object {
        `$psitem.Name -ieq 'VCPUs' -and [int]`$psitem.Value -le $maxVCPU
      }
    }" -foregroundColor Cyan

    $global:filteredSkus = $global:filteredSkus | where-object {
      $psitem.Capabilities | where-object {
        $psitem.Name -ieq 'VCPUs' -and [int]$psitem.Value -le $maxVCPU
      }
    }
    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function check-minMemoryGB(){
  if ($minMemoryGB) {
    write-host "filtering skus by Capabilities.MemoryGB >= $minMemoryGB" -ForegroundColor Green
    write-host "
    `$global:filteredSkus = `$global:filteredSkus | Where-Object { 
      `$psitem.Capabilities | where-object {
        `$psitem.Name -ieq 'MemoryGB' -and [int]`$psitem.Value -ge $minMemoryGB
      }
    }" -ForegroundColor Cyan

    $global:filteredSkus = $global:filteredSkus | where-object { 
      $psitem.Capabilities | where-object {
        $psitem.Name -ieq 'MemoryGB' -and [int]$psitem.Value -ge $minMemoryGB
      }
    }
    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function check-minvCpu(){
  if ($minVCPU) {
    write-host "filtering skus by Capabilities.VCPUs >= $minVCPU" -ForegroundColor Green
    write-host "
    `$global:filteredSkus = `$global:filteredSkus | Where-Object { 
      `$psitem.Capabilities | where-object {
        `$psitem.Name -ieq 'VCPUs' -and [int]`$psitem.Value -ge $minVCPU
      }
    }" -foregroundColor Cyan

    $global:filteredSkus = $global:filteredSkus | where-object {
      $psitem.Capabilities | where-object {
        $psitem.Name -ieq 'VCPUs' -and [int]$psitem.Value -ge $minVCPU
      }
    }
    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function check-resourceVolumeMB(){
  if ($maxResourceVolumeMB -ne -1 -or $minResourceVolumeMB -ne -1) {
    if ($maxResourceVolumeMB -eq -1) { $maxResourceVolumeMB = [int]::MaxValue }
    if ($minResourceVolumeMB -eq -1) { $minResourceVolumeMB = 1 }
    write-host "checking for local storage" -ForegroundColor Green
    write-host "filtering skus by Capabilities.MaxResourceVolumeMB <= '$maxResourceVolumeMB' and Capabilities.MaxResourceVolumeMB >= $minResourceVolumeMB" -ForegroundColor Green
    write-host "
    `$global:filteredSkus = `$global:filteredSkus | Where-Object { 
      `$psitem.Capabilities | where-object {
      `$psitem.Name -ieq 'MaxResourceVolumeMB' -and (`$psitem.Value -le $maxResourceVolumeMB -and `$psitem.Value -ge $minResourceVolumeMB)
    }" -ForegroundColor Cyan
    
    $global:filteredSkus = $global:filteredSkus | Where-Object {
      $psitem.Capabilities | where-object { 
        $psitem.Name -ieq 'MaxResourceVolumeMB' -and ($psitem.Value -le $maxResourceVolumeMB -and $psitem.Value -ge $minResourceVolumeMB)
      }
    }
    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function check-skuName(){
  if ($skuName) {
    write-host "`$global:filteredSkus = `$global:filteredSkus | Where-Object { `$psitem.Name -imatch $skuName }" -ForegroundColor Cyan
    $global:filteredSkus = $global:filteredSkus | Where-Object { $psitem.Name -imatch $skuName }
    write-verbose "skus in region:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "skus in region ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function check-vmDeploymentTypes(){
  if ($vmDeploymentTypes) {
    write-host "filtering skus by Capabilities.VMDeploymentTypes = '$vmDeploymentTypes'" -ForegroundColor Green
    write-host "
    `$global:filteredSkus = `$global:filteredSkus | Where-Object { 
      `$psitem.Capabilities | where-object {
      `$psitem.Name -ieq 'VMDeploymentTypes' -and `$psitem.Value -imatch $vmDeploymentTypes
    }" -ForegroundColor Cyan
    
    $global:filteredSkus = $global:filteredSkus | Where-Object {
      $psitem.Capabilities | where-object { 
        $psitem.Name -ieq 'VMDeploymentTypes' -and $psitem.Value -imatch $vmDeploymentTypes
      }
    }
    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function check-withRestrictions(){
  if (!$withRestrictions) {
    write-host "`$global:filteredSkus = `$global:filteredSkus | Where-Object { `$psitem.Restrictions.Count -eq 0 }" -ForegroundColor Cyan
    $global:filteredSkus = $global:filteredSkus | Where-Object { $psitem.Restrictions.Count -eq 0 }
    write-verbose "unrestricted skus in region:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "unrestricted skus in region ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function connect-az($subscriptionId) {
  $moduleList = @('az.accounts', 'az.resources', 'az.compute')

  foreach ($module in $moduleList) {
    write-verbose "checking module $module"
    if (!(get-module -name $module)) {
      if (!(get-module -name $module -listavailable)) {
        write-host "installing module $module" -ForegroundColor Yellow
        install-module $module -force
        import-module $module
        if (!(get-module -name $module -listavailable)) {
          return $false
        }
      }
    }
  }

  if ($subscriptionId -and (Get-AzContext).Subscription.Id -ne $subscriptionId) {
    write-host "setting subscription $subscriptionId" -ForegroundColor Yellow
    set-azcontext -SubscriptionId $subscriptionId
  }

  if (!(@(Get-AzResourceGroup).Count)) {
    $error.clear()
    Connect-AzAccount

    if ($error -and ($error | out-string) -match '0x8007007E') {
      $error.Clear()
      Connect-AzAccount -UseDeviceAuthentication
    }
  }

  return $null = get-azcontext
}

main