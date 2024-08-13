<#
#>

[cmdletbinding()]
param (
  [string]$Location = "eastus",
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
      write-host $locations | Format-Table -AutoSize
      write-error "location is required"
      return
    }

    write-host "Get-AzComputeResourceSku | Where-Object { `$psitem.Locations -ieq $location -and `$psitem.resourceType -ieq 'virtualMachines' }"
    $skus = Get-AzComputeResourceSku | Where-Object { 
      $psitem.Locations -ieq $location -and $psitem.resourceType -ieq 'virtualMachines'
    }
    write-verbose "available skus in region:$($skus | convertto-json -depth 5)"

    if (!$withRestrictions) {
      write-host "`$skus | Where-Object { `$psitem.Locations -contains $location -and `$psitem.Restrictions.Count -eq 0 }"
      $unrestrictedSkus = $skus | Where-Object { $psitem.Locations -contains $location -and $psitem.Restrictions.Count -eq 0 }
      write-verbose "unrestricted skus in region:$($unrestrictedSkus | convertto-json -depth 5)"
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

    write-verbose "filtered skus in region:$($filteredSkus | convertto-json -depth 5)"
    write-host "filtered skus in region:$($filteredSkus.Keys | sort-object | out-string)"
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