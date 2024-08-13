<#
.SYNOPSIS 
Get available skus in a region for a given architecture type

.DESCRIPTION
Get available skus in a region for a given architecture type

.NOTES
  File Name      : azure-az-available-skus.ps1
  Author         : jagilber
  Prerequisite   : PowerShell core 6.1.0 or higher

.PARAMETER Location
  The location to get available skus

.PARAMETER SubscriptionId
  The subscription id to use

.PARAMETER computerArchitectureType
  The architecture type to filter by

.PARAMETER withRestrictions
  Include skus with restrictions

.EXAMPLE
  azure-az-available-skus.ps1 -Location "eastus" -computerArchitectureType "x64"
  Get available skus in eastus for x64 architecture

.EXAMPLE
  azure-az-available-skus.ps1 -Location "eastus" -computerArchitectureType "x64" -verbose
  Get available skus in eastus for x64 architecture with verbose output

.EXAMPLE
  azure-az-available-skus.ps1 -Location "eastus" -computerArchitectureType "x64" -withRestrictions
  Get available skus in eastus for x64 architecture including skus with restrictions

.EXAMPLE
  azure-az-available-skus.ps1 -Location "eastus" -computerArchitectureType "ARM64" -withRestrictions
  Get available skus in eastus for ARM64 architecture including skus with restrictions

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-available-skus.ps1" -outFile "$pwd\azure-az-available-skus.ps1";
    .\azure-az-available-skus.ps1

#>

[cmdletbinding()]
param (
  [string]$Location = $null,
  [string]$SubscriptionId = $null,
  [string]$computerArchitectureType = "x64",
  [switch]$withRestrictions
)

function main() {
  try {
    if (!(connect-az)) { return }

    if (!$location) {
      write-host "get-azlocation | Select-Object -Property DisplayName, Location"
      $locations = get-azlocation | Select-Object -Property DisplayName, Location
      write-host ($locations | out-string)
      write-error "location is required"
      return
    }

    write-host "Get-AzComputeResourceSku | Where-Object { `$psitem.Locations -ieq $location -and `$psitem.resourceType -ieq 'virtualMachines' }"
    $skus = Get-AzComputeResourceSku | Where-Object { 
      $psitem.Locations -ieq $location -and $psitem.resourceType -ieq 'virtualMachines'
    }
    write-verbose "available skus in region:`n$($skus | convertto-json -depth 10)"
    if(!$skus) {
      $locations = get-azlocation | Select-Object -Property DisplayName, Location
      if ($locations -inotcontains $location) {
        write-host ($locations | out-string)
        write-error "location $location is not valid"
        return
      }
      write-error "no skus found in region $location"
      return
    }
    if (!$withRestrictions) {
      write-host "`$skus | Where-Object { `$psitem.Locations -ieq $location -and `$psitem.Restrictions.Count -eq 0 }"
      $unrestrictedSkus = $skus | Where-Object { $psitem.Locations -ieq $location -and $psitem.Restrictions.Count -eq 0 }
      write-verbose "unrestricted skus in region:`n$($unrestrictedSkus | convertto-json -depth 10)"
    }
    else {
      $unrestrictedSkus = $skus
    }

    write-host "filtering skus by Capabilities.CpuArchitectureType = '$computerArchitectureType'"
    $filteredSkus = [hashtable]@{}
    foreach ($unrestrictedsku in $unrestrictedSkus) { 
      foreach ($capability in $unrestrictedsku.capabilities) {
        if ($capability.name -ieq 'CpuArchitectureType' -and $capability.value -ieq $computerArchitectureType) {
          write-verbose ($capability | convertto-json)
          $filteredSkus.Add($unrestrictedsku.Name, $unrestrictedsku)
          continue
        }
        else{
          write-verbose ($capability | convertto-json)
        }
      }
    }

    write-verbose "filtered skus in region:`n$($filteredSkus | convertto-json -depth 10)"
    write-host "filtered skus in region:`n$($filteredSkus.Keys | sort-object | out-string)"
  }
  catch {
    write-verbose "variables:$((get-variable -scope local).value | convertto-json -WarningAction SilentlyContinue -depth 2)"
    write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
    return 1
  }
  finally {
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