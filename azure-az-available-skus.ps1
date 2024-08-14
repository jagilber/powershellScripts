<#
.SYNOPSIS 
Get available skus in a region for a given architecture type

.DESCRIPTION
Get available skus in a region for a given architecture type

.NOTES
  File Name      : azure-az-available-skus.ps1
  Author         : jagilber
  Prerequisite   : PowerShell core 6.1.0 or higher


.PARAMETER force
  Force refresh of skus

.PARAMETER hyperVGenerations
    The hyperVGenerations to filter by

.PARAMETER maxMemoryGB
  The maximum memory in GB to filter by

.PARAMETER maxVCPU
  The maximum vcpu to filter by

.PARAMETER location
  The location to get available skus

.PARAMETER skuName
  The sku name to filter by

.PARAMETER subscriptionId
  The subscription id to use

.PARAMETER computerArchitectureType
  The architecture type to filter by

.PARAMETER withRestrictions
  Include skus with restrictions

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
  [string]$hyperVGenerations = "V1", # "V2" will fail for sf. needs "V1" or "V1,V2" for sf
  [string]$skuName = $null,
  [int]$maxMemoryGB = 0, # 64, # 0 = unlimited
  [int]$maxVCPU = 0, # 4, # 0 = unlimited
  [switch]$withRestrictions,
  [switch]$force
)

$global:filteredSkus = @{}

function main() {
  try {
    if (!(connect-az)) { return }

    if (!$global:locations -or $force) {
      write-host "get-azlocation | Select-Object -Property DisplayName, Location" -ForegroundColor Cyan
      $global:locations = get-azlocation | Select-Object -Property DisplayName, Location
      if (!$global:locations) {
        write-error "no locations found"
        return
      }
      if ($global:locations.location -inotcontains $location) {
        write-host ($locations | out-string) -ForegroundColor Cyan
        write-warning "location $location is not valid"
        # return
      }
    }

    if (!$global:skus -or $force) {
      $global:skus = @{}
      write-host "retrieving skus" -ForegroundColor Green
      write-host "Get-AzComputeResourceSku | Where-Object { `$psitem.resourceType -ieq 'virtualMachines' }" -ForegroundColor Cyan
      $global:skus = Get-AzComputeResourceSku | Where-Object { 
        $psitem.resourceType -ieq 'virtualMachines'
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

    if (!$withRestrictions) {
      write-host "`$global:skus | Where-Object { `$psitem.Restrictions.Count -eq 0 }" -ForegroundColor Cyan
      $global:filteredSkus = $global:filteredSkus | Where-Object { $psitem.Restrictions.Count -eq 0 }
      write-verbose "unrestricted skus in region:`n$($global:filteredSkus | convertto-json -depth 10)"
      write-host "unrestricted skus in region ($($global:filteredSkus.Count))" -ForegroundColor Green
    }

    if ($skuName) {
      write-host "`$global:skus | Where-Object { `$psitem.Name -imatch $skuName }" -ForegroundColor Cyan
      $global:filteredSkus = $global:filteredSkus | Where-Object { $psitem.Name -imatch $skuName }
      write-verbose "skus in region:`n$($global:filteredSkus | convertto-json -depth 10)"
      write-host "skus in region ($($global:filteredSkus.Count))" -ForegroundColor Green
    }

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

    if ($hyperVGenerations) {
      write-host "filtering skus by Capabilities.HyperVGenerations = '$hyperVGenerations'" -ForegroundColor Green
      write-host "
      `$global:filteredSkus = `$global:filteredSkus | Where-Object { 
        `$psitem.Capabilities | where-object {
        `$psitem.Name -ieq 'HyperVGenerations' -and `$psitem.Value -icontains $hyperVGenerations
      }" -ForegroundColor Cyan
      
      $global:filteredSkus = $global:filteredSkus | Where-Object {
        $psitem.Capabilities | where-object { 
          $psitem.Name -ieq 'HyperVGenerations' -and $psitem.Value -icontains $hyperVGenerations
        }
      }
      write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
      write-host "filtered skus ($($global:filteredSkus.Count))" -ForegroundColor Green
    }

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

    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus ($($global:filteredSkus.Count)):`n$($global:filteredSkus | sort-object | out-string)" -ForegroundColor Green
  }
  catch {
    write-verbose "variables:$((get-variable -scope local).value | convertto-json -WarningAction SilentlyContinue -depth 2)"
    write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
    return 1
  }
  finally {
    write-host "filtered skus with:
      location: $location
      computerArchitectureType: $computerArchitectureType
      hyperVGenerations: $hyperVGenerations
      maxMemoryGB: $maxMemoryGB
      maxVCPU: $maxVCPU
      skuName: $skuName
      withRestrictions: $withRestrictions
      " -ForegroundColor Yellow

    write-host "use variable `$filteredSkus to get details on available skus. example `$filteredSkus | out-gridview" -ForegroundColor Green
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