<#
.SYNOPSIS 
Get available virtual machine skus in a region

.DESCRIPTION
Get available skus in a region for a virtual machine. 
Filter by location, sku name, max memory, max vcpu, computer architecture type, hyperVGenerations, withRestrictions, and serviceFabric
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

.PARAMETER withNoRestrictions
  Show only skus with no location or zone restrictions at all

.PARAMETER ShowRestricted
  When not using -withRestrictions, show a sample of excluded SKUs that had Location restrictions.

.PARAMETER serviceFabric
  Filter for service fabric skus

.PARAMETER showQuotas
  Display Azure subscription quota limits for the specified location and analyze quota usage for filtered SKUs

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

.EXAMPLE
  .\azure-az-available-skus.ps1 -Location "eastus2" -showQuotas
  Get available skus in eastus2 and display quota information for the location

.EXAMPLE
  .\azure-az-available-skus.ps1 -Location "eastus2" -skuName "Standard_D" -showQuotas
  Get Standard_D family skus in eastus2 and show detailed quota analysis for those SKU families

.EXAMPLE
  .\azure-az-available-skus.ps1 -Location "southeastasia" -withNoRestrictions
  Get all skus in southeastasia that have no location or zone restrictions

.EXAMPLE
  .\azure-az-available-skus.ps1 -skuName "Standard_D4ads_v5" -withNoRestrictions
  Get Standard_D4ads_v5 skus across all regions that have no restrictions

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
  [switch]$withNoRestrictions,
  [switch]$ShowRestricted,
  [switch]$serviceFabric, # hyperVGenerations needs "V1" or "V1,V2" for sf and MaxResourceVolumeMB needs temp disk (10000) 10gb and vmDeploymentTypes needs "PaaS"
  [ValidateSet("paas", "iaas", "")]
  [int]$maxResourceVolumeMB = -1, # 0 is no local disk -1 is unlimited
  [int]$minResourceVolumeMB = -1, # 0 is no local disk -1 is minimum (1)
  [string]$vmDeploymentTypes = "",
  [switch]$confidentialComputingType,
  [switch]$force,
  [switch]$showQuotas
)

$global:filteredSkus = @{}
$global:regions = @($location.Split(','))

function main() {
  try {
    if (!(connect-az)) { return }

    if ($serviceFabric) {
      # $script:computerArchitectureType = "x64"
      # $script:hyperVGenerations = "V1"
      $script:minResourceVolumeMB = 10000
      # $script:vmDeploymentTypes = "PaaS"
      $script:confidentialComputingType = $null
    }

    if (!$global:locations -or $force) {
      write-host "Get-AzLocation | Where-Object Providers -imatch 'Microsoft.Compute'" -ForegroundColor Cyan
      $global:locations = get-azlocation | where-object Providers -imatch 'Microsoft.Compute'
      if (!$global:locations) {
        write-error "no locations found"
        return
      }
    }

    if ($location -and ($global:locations.Location -inotcontains $location)) {
      write-host ($locations | out-string) -ForegroundColor Cyan
      write-error "location $location is not valid"
      return
    }

    if (!$global:skus -or $force) {
      $global:skus = @{}
      write-host "retrieving skus" -ForegroundColor Green
      write-host "Get-AzComputeResourceSku | Where-Object { `$psitem.resourceType -ieq 'virtualMachines' }" -ForegroundColor Cyan
      $global:skus = Get-AzComputeResourceSku | Where-Object { $psitem.resourceType -ieq 'virtualMachines' }
      write-host "global:skus:$($global:skus.Count)" -ForegroundColor Cyan
    }
    
    $global:filteredSkus = $global:skus
    write-host "`$global:filteredSkus = `$global:skus" -ForegroundColor Cyan

    check-withRestrictions
    check-withNoRestrictions
    check-skuName
    check-computerArchitectureType
    check-hyperVGenerations
    check-resourceVolumeMB # check local storage
    check-maxvCpu
    check-minvCpu
    check-maxMemoryGB
    check-minMemoryGB
    check-vmDeploymentTypes # checking for no gpu on sf
    check-confidentialComputingType
  
    if (!$global:filteredSkus) {
      write-warning "no skus found"
      return $false
    }

    $skus = check-location $global:regions $global:filteredSkus
    if (!$skus) {
      $regions = check-geoRegion $global:regions
      $skus = check-location $regions $global:filteredSkus
      if (!$skus) {
        write-warning "no skus found in georegion $location"
      }
    }

    if ($skus) {
      $global:filteredSkus = $skus
    }

    write-verbose "filtered skus:`n$($global:filteredSkus | convertto-json -depth 10)"
    
    # Sort SKUs by name and format with sorted zones
    $sortedOutput = $global:filteredSkus | Sort-Object Name | Select-Object Name, 
      @{Name='Location';Expression={$_.LocationInfo.Location}},
      @{Name='Zones';Expression={($_.LocationInfo.Zones | Sort-Object) -join ', '}},
      @{Name='RestrictionInfo';Expression={
        if ($_.Restrictions) {
          $r = $_.Restrictions
          "type: $($r.Type), locations: $($r.RestrictionInfo.Locations -join ','), zones: $(($r.RestrictionInfo.Zones | Sort-Object) -join ',')"
        }
      }} | Format-Table -AutoSize | Out-String
    
    write-host "filtered skus ($($global:filteredSkus.Count)):`n$sortedOutput" -ForegroundColor Magenta

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
      withNoRestrictions: $withNoRestrictions
      " -ForegroundColor DarkGray

    # Show quota information if requested
    if ($showQuotas -and $global:regions) {
      Get-AzureQuotaLimits -Location $global:regions[0] -ShowSkuFamilyQuotas -FilteredSkus $global:filteredSkus
    }

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

function check-computerArchitectureType() {
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

    $tempSkus = [collections.arrayList]::new(@($global:filteredSkus))
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

function check-geoRegion([string[]]$regions) {
  if (!$regions) { return $null }

  $geoGroups = $global:locations.GeographyGroup | select-object -Unique
  $geoGroups = ($global:locations | where-object Location -in $regions | select-object GeographyGroup).GeographyGroup
  
  write-host "searching for regions in geoGroup: $geoGroups" -ForegroundColor Cyan
  $geoRegions = @($global:locations | where-object GeographyGroup -in $geoGroups).location | sort-object
  
  write-host "regions in geoGroup:`n$($geoRegions | out-string)" -ForegroundColor Cyan
  write-host "returning regions for: $($geoGroups | out-string)"
  return $geoRegions
}

function check-hyperVGenerations() {
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

function check-location([string[]]$locations, [object[]]$skus) {
  if ($locations.Length -gt 0) {
    write-host "filtering skus by locations $locations" -ForegroundColor Green
    write-host "
    `$skus = `$skus | Where-Object { 
      `$psitem.Locations -in $locations
    }" -ForegroundColor Cyan
    $skus = $skus | Where-Object { 
      $psitem.Locations -in $locations
    }
    write-verbose "available skus:`n$($skus | convertto-json -depth 10)"
  }
  else {
    # $global:filteredSkus = $global:skus
    write-host "no location specified. returning all skus" -ForegroundColor Yellow
  }
  write-host "filtered skus ($($skus.Count))" -ForegroundColor Green
  return $skus
}

function check-locations([string[]]$locations) {
  $geoRegions = check-geoRegion $locations
  if ($geoRegions) {
    $global:filteredSkus = @($global:skus | where-object Locations -in $geoRegions)
    write-host "skus found in geo regions $(convertto-json $geoRegions)" -ForegroundColor Green
  }
  else {
    write-error "no skus found in geo region $location"
    return $false
  }

  if (!$global:filteredSkus) {
    write-error "no skus found in region $location"
    return $false
  }
  return $true
}

function check-maxMemoryGB() {
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

function check-maxvCpu() {
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

function check-minMemoryGB() {
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

function check-minvCpu() {
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

function check-resourceVolumeMB() {
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

function check-skuName() {
  if ($skuName) {
    write-host "`$global:filteredSkus = `$global:filteredSkus | Where-Object { `$psitem.Name -imatch $skuName }" -ForegroundColor Cyan
    $global:filteredSkus = $global:filteredSkus | Where-Object { $psitem.Name -imatch $skuName }
    write-verbose "skus in region:`n$($global:filteredSkus | convertto-json -depth 10)"
    write-host "skus in region ($($global:filteredSkus.Count))" -ForegroundColor Green
  }
}

function check-vmDeploymentTypes() {
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

function check-withRestrictions() {
  if (!$withRestrictions) {
    # Drop any SKU that has a Location restriction that includes the requested location(s)
    # A Location restriction means the SKU is NOT AVAILABLE in those locations for this subscription
    $requested = @($global:regions | Where-Object { $_ })
    $requestedSet = $requested | ForEach-Object { $_.ToLower() } | Select-Object -Unique
    $before = $global:filteredSkus.Count
    $excluded = New-Object System.Collections.Generic.List[object]

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($sku in $global:filteredSkus) {
      $restrictions = @($sku.Restrictions)
      if ($restrictions.Count -eq 0) { 
        $null = $result.Add($sku); continue 
      }

      $locationRestrictions = @($restrictions | Where-Object { $_.Type -ieq 'Location' })
      if ($locationRestrictions.Count -eq 0) { 
        $null = $result.Add($sku); continue 
      }

      if ($requestedSet.Count -eq 0) {
        # No specific location requested -> exclude all SKUs with Location restriction
        $null = $excluded.Add($sku)
        continue
      }

      # Collect restricted locations for this SKU
      # These are locations where the SKU is NOT AVAILABLE
      $restrictedLocations = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
      foreach ($r in $locationRestrictions) {
        # Only consider restrictions that make the SKU unavailable
        if ($r.ReasonCode -ieq 'NotAvailableForSubscription') {
          foreach ($c in @($r.RestrictionInfo.Locations) + @($r.Locations) + @($r.Values)) {
            if ($c) { 
              [void]$restrictedLocations.Add($c.ToString().Trim()) 
            }
          }
        }
      }

      # If any requested location is in the restricted locations, exclude this SKU
      $isRestricted = $false
      foreach ($loc in $requestedSet) { 
        if ($restrictedLocations.Contains($loc)) { 
          $isRestricted = $true
          break 
        } 
      }
      
      if ($isRestricted) { 
        $null = $excluded.Add($sku)
        continue 
      }
      $null = $result.Add($sku)
    }

    $global:filteredSkus = $result
    $removed = $before - $global:filteredSkus.Count
    write-host "removed $removed skus due to location restrictions (remaining: $($global:filteredSkus.Count))" -ForegroundColor Green
    if ($ShowRestricted -and $removed -gt 0) {
      $sample = $excluded | Select-Object -Property Name, Locations, @{n='RestrictedLocations';e={
          ($_.Restrictions | Where-Object { $_.Type -ieq 'Location' } | ForEach-Object { @($_.RestrictionInfo.Locations)+@($_.Locations)+@($_.Values) } | Where-Object { $_ } | Select-Object -Unique) -join ',' }}
      write-host "excluded:`n$($sample | Format-Table -AutoSize | Out-String)" -ForegroundColor DarkYellow
    }
  }
}

function check-withNoRestrictions() {
  if ($withNoRestrictions) {
    write-host "filtering skus to show only those with NO restrictions (no location or zone restrictions)" -ForegroundColor Green
    $before = $global:filteredSkus.Count
    
    # Keep only SKUs with no restrictions at all
    $global:filteredSkus = $global:filteredSkus | Where-Object { 
      $null -eq $_.Restrictions -or @($_.Restrictions).Count -eq 0 
    }
    
    $removed = $before - $global:filteredSkus.Count
    write-host "removed $removed skus with restrictions (remaining: $($global:filteredSkus.Count))" -ForegroundColor Green
    write-verbose "filtered skus with no restrictions:`n$($global:filteredSkus | convertto-json -depth 10)"
  }
}

function Get-AzureQuotaLimits {
  <#
  .SYNOPSIS
  Get Azure subscription quota limits for compute, network, and storage resources
  
  .DESCRIPTION
  Retrieves quota limits and current usage for Azure resources in specified locations.
  Can show quota information for specific SKU families and provide detailed breakdown.
  
  .PARAMETER Location
  The Azure location to get quota information for. If not specified, uses the global location from script.
  
  .PARAMETER ShowSkuFamilyQuotas
  Show detailed quota information for specific VM SKU families
  
  .PARAMETER FilteredSkus
  Array of SKU objects to analyze for quota usage
  
  .EXAMPLE
  Get-AzureQuotaLimits -Location "eastus2"
  
  .EXAMPLE
  Get-AzureQuotaLimits -Location "eastus2" -ShowSkuFamilyQuotas -FilteredSkus $global:filteredSkus
  #>
  param(
    [Parameter(Mandatory = $false)]
    [string]$Location = $global:regions[0],
    [switch]$ShowSkuFamilyQuotas,
    [object[]]$FilteredSkus = @()
  )
  
  if (!$Location) {
    Write-Warning "No location specified for quota check"
    return
  }
  
  Write-Host "`n=== Azure Quota Limits for Location: $Location ===" -ForegroundColor Cyan
  
  try {
    # Get VM/Compute quotas
    Write-Host "`nCompute Quotas:" -ForegroundColor Yellow
    $vmQuotas = Get-AzVMUsage -Location $Location -ErrorAction SilentlyContinue
    if ($vmQuotas) {
      $vmQuotas | Where-Object { $_.Limit -gt 0 } | 
        Sort-Object Name | 
        Format-Table @{
          Name = 'Quota Name'; Expression = { $_.Name.LocalizedValue }; Width = 40
        }, @{
          Name = 'Current'; Expression = { $_.CurrentValue }; Width = 10
        }, @{
          Name = 'Limit'; Expression = { $_.Limit }; Width = 10
        }, @{
          Name = 'Available'; Expression = { 
            try {
              [int]$_.Limit - [int]$_.CurrentValue 
            } catch { 
              'N/A' 
            }
          }; Width = 12
        }, @{
          Name = 'Usage %'; Expression = { 
            if ($_.Limit -gt 0) { 
              [math]::Round(($_.CurrentValue / $_.Limit) * 100, 1) 
            } else { 0 }
          }; Width = 10
        } -AutoSize
      
      # Highlight high usage quotas
      $highUsage = $vmQuotas | Where-Object { 
        $_.Limit -gt 0 -and ($_.CurrentValue / $_.Limit) -gt 0.8 
      }
      if ($highUsage) {
        Write-Host "`nHigh Usage Quotas (>80%):" -ForegroundColor Red
        $highUsage | Format-Table @{
          Name = 'Quota Name'; Expression = { $_.Name.LocalizedValue }
        }, CurrentValue, Limit, @{
          Name = 'Usage %'; Expression = { 
            [math]::Round(($_.CurrentValue / $_.Limit) * 100, 1) 
          }
        } -AutoSize
      }
    } else {
      Write-Warning "Unable to retrieve VM quotas for location $Location"
    }
    
    # Get Network quotas
    Write-Host "`nNetwork Quotas:" -ForegroundColor Yellow
    $networkQuotas = Get-AzNetworkUsage -Location $Location -ErrorAction SilentlyContinue
    if ($networkQuotas) {
      $networkQuotas | Where-Object { $_.Limit -gt 0 } | 
        Sort-Object Name |
        Format-Table @{
          Name = 'Resource Type'; Expression = { $_.Name.LocalizedValue }; Width = 40
        }, @{
          Name = 'Current'; Expression = { $_.CurrentValue }; Width = 10
        }, @{
          Name = 'Limit'; Expression = { $_.Limit }; Width = 10
        }, @{
          Name = 'Available'; Expression = { 
            if ($_.Limit -is [int] -and $_.CurrentValue -is [int]) {
              $_.Limit - $_.CurrentValue 
            } else { 'N/A' }
          }; Width = 12
        } -AutoSize
    }
    
    # Get Storage quotas
    Write-Host "`nStorage Quotas:" -ForegroundColor Yellow
    $storageQuotas = Get-AzStorageUsage -Location $Location -ErrorAction SilentlyContinue
    if ($storageQuotas) {
      $storageQuotas | Format-Table @{
        Name = 'Resource Type'; Expression = { $_.Name.LocalizedValue }; Width = 40
      }, @{
        Name = 'Current'; Expression = { $_.CurrentValue }; Width = 10
      }, @{
        Name = 'Limit'; Expression = { $_.Limit }; Width = 10
      }, @{
        Name = 'Available'; Expression = { 
          if ($_.Limit -is [int] -and $_.CurrentValue -is [int]) {
            $_.Limit - $_.CurrentValue 
          } else { 'N/A' }
        }; Width = 12
      } -AutoSize
    }
    
    # Analyze SKU family quotas if FilteredSkus provided
    if ($ShowSkuFamilyQuotas -and $FilteredSkus.Count -gt 0) {
      Write-Host "`nSKU Family Quota Analysis:" -ForegroundColor Yellow
      
      # Group SKUs by family
      $skuFamilies = @{}
      foreach ($sku in $FilteredSkus) {
        # Extract family from SKU name (e.g., Standard_D2s_v3 -> Standard_D)
        if ($sku.Name -match '^(Standard_[A-Z]+)') {
          $familyName = $matches[1]
        } else {
          $familyName = $sku.Name -replace '_.*$', ''
        }
        
        if (!$skuFamilies.ContainsKey($familyName)) {
          $skuFamilies[$familyName] = @()
        }
        $skuFamilies[$familyName] += $sku
      }
      
      # Find matching quota entries for each family
      $familyQuotas = @()
      foreach ($family in $skuFamilies.Keys) {
        # Look for exact family match first
        $matchingQuota = $vmQuotas | Where-Object { 
          $_.Name.LocalizedValue -like "*$family*" -and $_.Name.LocalizedValue -like "*Family*"
        } | Select-Object -First 1
        
        if ($matchingQuota) {
          try {
            $available = [int]$matchingQuota.Limit - [int]$matchingQuota.CurrentValue
          } catch {
            $available = 'N/A'
          }
          
          $familyQuotas += [PSCustomObject]@{
            Family = $family
            SKUCount = $skuFamilies[$family].Count
            QuotaName = $matchingQuota.Name.LocalizedValue
            Current = $matchingQuota.CurrentValue
            Limit = $matchingQuota.Limit
            Available = $available
            SampleSKUs = ($skuFamilies[$family].Name | Sort-Object | Select-Object -First 3) -join ', '
          }
        }
      }
      
      # Add general quota info if no specific families found
      if ($familyQuotas.Count -eq 0) {
        $generalQuota = $vmQuotas | Where-Object { 
          $_.Name.LocalizedValue -like "*total*vcpu*" -or
          $_.Name.LocalizedValue -like "*regional*vcpu*"
        } | Select-Object -First 1
        
        if ($generalQuota) {
          try {
            $available = [int]$generalQuota.Limit - [int]$generalQuota.CurrentValue
          } catch {
            $available = 'N/A'
          }
          
          $familyQuotas += [PSCustomObject]@{
            Family = "All Families"
            SKUCount = $FilteredSkus.Count
            QuotaName = $generalQuota.Name.LocalizedValue
            Current = $generalQuota.CurrentValue
            Limit = $generalQuota.Limit
            Available = $available
            SampleSKUs = ($FilteredSkus.Name | Sort-Object | Select-Object -First 5) -join ', '
          }
        }
      }
      
      if ($familyQuotas) {
        $familyQuotas | Format-Table -AutoSize
      } else {
        Write-Host "No specific quota information found for the filtered SKU families." -ForegroundColor Yellow
      }
    }
    
  } catch {
    Write-Error "Error getting quota information: $($_.Exception.Message)"
    Write-Verbose $_.Exception.StackTrace
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