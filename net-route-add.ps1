<#
.SYNOPSIS
  This script is used to add a network route to the routing table.

.DESCRIPTION
  The script allows the user to add a new route to the routing table by specifying the destination network, subnet mask, gateway, and optionally the interface and metric.

.PARAMETER Destination
  The destination network address for the route.

.PARAMETER SubnetMask
  The subnet mask for the destination network.

.PARAMETER Gateway
  The gateway address for the route.

.PARAMETER Interface
  (Optional) The network interface to use for the route.

.PARAMETER Metric
  (Optional) The metric for the route.

.EXAMPLE
  .\net-route-add.ps1 -Destination "192.168.1.0" -SubnetMask "255.255.255.0" -Gateway "192.168.1.1"
  This example adds a route to the 192.168.1.0/24 network via the gateway 192.168.1.1.

.EXAMPLE
  .\net-route-add.ps1 -Destination "10.0.0.0" -SubnetMask "255.0.0.0" -Gateway "10.0.0.1" -Interface 2 -Metric 10
  This example adds a route to the 10.0.0.0/8 network via the gateway 10.0.0.1 using interface 2 with a metric of 10.

.NOTES
  Author: jagilber
  Date: 240924
  Version: 1.0
#>
param(
  [string]$destinationPrefix, # ip cidr Ex: 8.8.8.8/32
  [string]$interfaceAlias, # 'Ethernet', 'Wi-Fi', etc.
  [int]$interfaceIndex, # 1, 2, 3, etc.
  [ValidateSet("IPv4", "IPv6")]
  [string]$addressFamily = "IPv4",
  [int]$routeMetric = 0, # 0, 1, 2, etc.
  [string]$nextHop = $null, # gateway ip address
  [switch]$force,
  [switch]$remove,
  [string]$cidr = "/32",
  [int]$lifetimeHours = 8
)

function main() {

  if (!(is-admin)) {
    return
  }

  write-host "network interfaces:" -ForegroundColor Green
  get-netIpInterface | out-string

  write-host "network ip configurations:" -ForegroundColor Green
  $ipConfigurations = get-netIPConfiguration
  $ipConfigurations | out-string
  $global:ipConfigurations = $ipConfigurations

  $activeAdapters = @(get-netAdapter | where-object status -eq 'Up')
  $activeAdapters = $activeAdapters | sort-object -Property InterfaceIndex
  $primaryAdapter = $activeAdapters[0]
  $global:primaryAdapter = $primaryAdapter

  write-host "active adapters:" -ForegroundColor Green
  $activeAdapters | out-string

  if (!$activeAdapters) {
    Write-Warning "No active adapters found."
    return
  }

  $vpnConnections = Get-VpnConnection
  $connectedVpnConnections = $vpnConnections | where-object ConnectionStatus -eq 'Connected'
  write-host "active vpn connections:" -ForegroundColor Green
  $connectedVpnConnections | Format-List *

  if ($interfaceIndex -and $interfaceAlias) {
    Write-Warning "You must specify either an interface index or an interface alias, not both."
    return
  }

  if (!$interfaceIndex -and !$interfaceAlias) {
    $interfaceIndex = $primaryAdapter.InterfaceIndex
    write-warning "No interface specified. Using default interface index $($interfaceIndex)."

    $defaultGatewayConfiguration = ($ipConfigurations | where-object InterfaceIndex -eq $interfaceIndex).IPv4DefaultGateway
    $nextHop = $defaultGatewayConfiguration.NextHop
    write-warning "No next hop specified. Using default gateway $($nextHop)."
    $routeMetric = $defaultGatewayConfiguration.RouteMetric
  }

  if (!$nextHop -and !$force) {
    Write-Warning "You must specify a next hop address."
    return
  }

  try {
    $destinationPrefix = $destinationPrefix.Trim().Replace("'", '').Replace('"', '')
    $null = [System.Net.IPAddress]::Parse($destinationPrefix.Split('/')[0])
    $destinationPrefixes = @($destinationPrefix)
  }
  catch {
    if (!$destinationPrefix) {
      Write-Warning "No destination prefix specified."
      return
    }

    Write-Warning "Invalid destination prefix. attempting to resolve..."
    write-host "Resolve-DnsName -Name $destinationPrefix -Type A"
    $destinationPrefixes = @(Resolve-DnsName -Name $destinationPrefix -Type A).IPAddress
    if ($destinationPrefixes.Count -eq 0) {
      Write-Warning "Could not resolve destination prefix."
      return
    }
    else {
      $error.Clear()
    }
  }

  foreach ($destinationPrefix in $destinationPrefixes) {
    $prefixParams = @{
      DestinationPrefix = "$($destinationPrefix)$($cidr)"
      AddressFamily     = $addressFamily
      RouteMetric       = $routeMetric
      NextHop           = $nextHop
    }
    
    if ($interfaceAlias) {
      $prefixParams.InterfaceAlias = $interfaceAlias
    }
    else {
      $prefixParams.InterfaceIndex = $interfaceIndex
    }
  
    check-route -prefixParams $prefixParams
  }
}

function check-route($prefixParams) {
  $prefix = $prefixParams.DestinationPrefix
  write-host "checking route for $prefix"
  write-host "get-netRoute $($prefixParams | convertto-json)"
  $route = get-netRoute @prefixParams -ErrorAction SilentlyContinue

  if ($route) {
    if ($force -or $remove) {
      write-host "found and removing route..."
      write-host "remove-netRoute $($prefixParams | convertto-json)"
      remove-netRoute @prefixParams -confirm:$force
      return
    }
    Write-Warning "Route already exists."
    return
  }
  if (!$route -and $remove) {
    Write-Warning "Route does not exist."
    return
  }

  if ($lifetimeHours) {
    $prefixParams.ValidLifetime = [timeSpan]::FromHours($lifetimeHours)
    $prefixParams.PreferredLifetime = [timeSpan]::FromHours($lifetimeHours)
  }

  write-host "new-netRoute $($prefixParams | convertto-json)"
  $error.Clear()
  $result = new-netRoute @prefixParams
  if ($error.Count -gt 0) {
    Write-Warning "Error adding route."
    $result
    return
  }

  write-host "route added."
}

function is-admin() {
  
  if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole( `
        [Security.Principal.WindowsBuiltInRole] "Administrator")) {   
    Write-Warning "please restart script as administrator. exiting..."
    $command = 'pwsh'
    $commandLine = $global:myinvocation.myCommand.definition

    if ($psedition -eq 'Desktop') {
      $command = 'powershell'
    }
    write-host "Start-Process $command -Verb RunAs -ArgumentList `"-NoExit -File $commandLine`""
    Start-Process $command  -Verb RunAs -ArgumentList "-NoExit -File $commandLine"

    return $false
  }
  return $true
}


main