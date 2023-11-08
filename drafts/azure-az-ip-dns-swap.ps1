<#
.SYNOPSIS
  Swap DNS names between two public IPs in Azure
.DESCRIPTION
  Swap DNS names between two public IPs in Azure
.NOTES
  File Name: azure-az-ip-dns-swap.ps1
  version: 231108
  Requires : Azure Az PowerShell modules
.EXAMPLE
  .\azure-az-ip-dns-swap.ps1 -resourceGroupName 'sfjagilber1nt3' -oldPublicIPName 'PublicIP-LB-FE-0' -newPublicIPName 'LBIP-sfjagilber1nt3-nt1' -swap $true -execute
.EXAMPLE
  .\azure-az-ip-dns-swap.ps1 -resourceGroupName 'sfjagilber1nt3' -oldPublicIPName 'PublicIP-LB-FE-0' -newPublicIPName 'LBIP-sfjagilber1nt3-nt1' -swap $true
.EXAMPLE
  .\azure-az-ip-dns-swap.ps1 -resourceGroupName 'sfjagilber1nt3' -oldPublicIPName 'PublicIP-LB-FE-0' -newPublicIPName 'LBIP-sfjagilber1nt3-nt1'
.EXAMPLE
  .\azure-az-ip-dns-swap.ps1 -resourceGroupName 'sfjagilber1nt3' -oldPublicIPName 'PublicIP-LB-FE-0' -newPublicIPName 'LBIP-sfjagilber1nt3-nt1' -swap $false
.EXAMPLE
  .\azure-az-ip-dns-swap.ps1 -resourceGroupName 'sfjagilber1nt3' -oldPublicIPName 'PublicIP-LB-FE-0' -newPublicIPName 'LBIP-sfjagilber1nt3-nt1' -execute
.PARAMETER resourceGroupName
  resource group name
.PARAMETER newPublicIPName
  new public ip name
.PARAMETER oldPublicIPName
  old public ip name
.PARAMETER swap
  Swap DNS names between two public IPs in Azure
.PARAMETER execute
  Execute commands instead of just displaying them
.LINK
  [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
  invoke-webRequest "  https://raw.githubusercontent.com/jagilber/powershellScripts/master/drafts/azure-az-ip-dns-swap.ps1" -outFile "$pwd/azure-az-ip-dns-swap.ps1";
#>
param(
  #[Parameter(Mandatory=$true)]
  [string]$resourceGroupName = 'sfjagilber1nt3',
  #[Parameter(Mandatory=$true)]
  [string]$oldPublicIPName = 'PublicIP-LB-FE-0',
  #[Parameter(Mandatory=$true)]
  [string]$newPublicIPName = 'LBIP-sfjagilber1nt3-nt1',
  [bool]$swap = $true,
  [switch]$execute,
  [int]$openTcpPort = 19000
)

$errorActionPreference = 'Stop'
$startTime = get-date

function main() {
  $currentPublicIps = Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName | Select-Object Name, ResourceGroupName, IpAddress, DnsSettings
  $action = "To set"
  if ($execute) {
    $action = "Setting"
  }

  write-host "`nCurrent public IPs in resource group:`n" -ForegroundColor Yellow
  foreach ($currentPublicIp in $currentPublicIps) {
    write-host "Public IP: $($currentPublicIp.Name) $($currentPublicIp | convertto-json)" -ForegroundColor Cyan
  }

  $oldPublicIP = Get-AzPublicIpAddress -Name $oldPublicIpName -ResourceGroupName $resourceGroupName
  validate-connection $oldPublicIP.IpAddress $oldPublicIP.DnsSettings.Fqdn

  $newPublicIP = Get-AzPublicIpAddress -Name $newPublicIpName -ResourceGroupName $resourceGroupName
  validate-connection $newPublicIP.IpAddress $newPublicIP.DnsSettings.Fqdn

  $dnsName = $oldPublicIP.DnsSettings.DomainNameLabel
  $oldFqdn = $oldPublicIP.DnsSettings.Fqdn

  $newDnsName = $newPublicIP.DnsSettings.DomainNameLabel
  $newFqdn = $newPublicIP.DnsSettings.Fqdn

  $tempDnsName = "temp-$dnsName"
  $tempFqdn = "temp-$oldFqdn"

  write-host "`n$action old public ip: $($oldPublicIp.IpAddress) to new dns name: $newDnsName and new dns fqdn: $newfqdn`n" -ForegroundColor Yellow
  $oldPublicIP.DnsSettings.DomainNameLabel = $tempDnsName
  $oldPublicIP.DnsSettings.Fqdn = $tempFqdn
  write-host "Set-AzPublicIpAddress -PublicIpAddress $($oldPublicIP | convertto-json)"
  if ($execute) { 
    Set-AzPublicIpAddress -PublicIpAddress $oldPublicIP 
    validate-connection $oldPublicIP.IpAddress $newfqdn
  }

  write-host "`n$action new public ip: $($newPublicIP.IpAddress) to old dns name: $dnsName and old dns fqdn: $oldFqdn`n" -ForegroundColor Yellow
  $newPublicIP.DnsSettings.DomainNameLabel = $dnsName
  $newPublicIP.DnsSettings.Fqdn = $oldFqdn
  write-host "Set-AzPublicIpAddress -PublicIpAddress $($newPublicIP | convertto-json)"
  if ($execute) { 
    Set-AzPublicIpAddress -PublicIpAddress $newPublicIP
    validate-connection $newPublicIP.IpAddress $oldFqdn
  }

  if ($swap) {
    write-host "`n$action old public ip: $($oldPublicIp.IpAddress) to new dns name: $newDnsName and new dns fqdn: $newFqdn`n" -ForegroundColor Yellow
    $oldPublicIP.DnsSettings.DomainNameLabel = $newDnsName
    $oldPublicIP.DnsSettings.Fqdn = $newFqdn
    write-host "Set-AzPublicIpAddress -PublicIpAddress $($oldPublicIP | convertto-json)"
    if ($execute) {
      Set-AzPublicIpAddress -PublicIpAddress $oldPublicIP
      validate-connection $oldPublicIP.IpAddress $newFqdn
    }
  }

  write-host "`nTo execute dns swap (or rerun script with -execute switch):`n
  `$resourceGroupName = '$resourceGroupName'
  `$oldPublicIPName = '$oldPublicIPName'
  `$newPublicIPName = '$newPublicIPName'
  `$swap = `$$swap
  `$oldPublicIP = Get-AzPublicIpAddress -Name `$oldPublicIpName -ResourceGroupName '$resourceGroupName'
  `$newPublicIP = Get-AzPublicIpAddress -Name '$newPublicIpName' -ResourceGroupName '$resourceGroupName'
  
  `$oldPublicIP.DnsSettings.DomainNameLabel = '$tempDnsName'
  `$oldPublicIP.DnsSettings.Fqdn = '$tempFqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$oldPublicIP

  `$newPublicIP.DnsSettings.DomainNameLabel = '$dnsName'
  `$newPublicIP.DnsSettings.Fqdn = '$oldFqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$newPublicIP

  if(`$swap) {
    `$oldPublicIP.DnsSettings.DomainNameLabel = '$newDnsName'
    `$oldPublicIP.DnsSettings.Fqdn = '$newFqdn'
    Set-AzPublicIpAddress -PublicIpAddress `$oldPublicIP
  }
" -ForegroundColor Green

  write-host "`nTo revert dns swap:`n
  `$resourceGroupName = '$resourceGroupName'
  `$oldPublicIPName = '$oldPublicIPName'
  `$newPublicIPName = '$newPublicIPName'
  `$oldPublicIP = Get-AzPublicIpAddress -Name '$oldPublicIpName' -ResourceGroupName '$resourceGroupName'
  `$newPublicIP = Get-AzPublicIpAddress -Name '$newPublicIpName' -ResourceGroupName '$resourceGroupName'
  
  `$oldPublicIP.DnsSettings.DomainNameLabel = '$tempDnsName'
  `$oldPublicIP.DnsSettings.Fqdn = '$tempFqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$oldPublicIP

  `$newPublicIP.DnsSettings.DomainNameLabel = '$newDnsName'
  `$newPublicIP.DnsSettings.Fqdn = '$newFqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$newPublicIP

  `$oldPublicIP.DnsSettings.DomainNameLabel = '$dnsName'
  `$oldPublicIP.DnsSettings.Fqdn = '$oldFqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$newPublicIP
" -ForegroundColor Yellow

  $executionTime = New-TimeSpan -Start $startTime -End (get-date)
  write-host "Finished execution. Time to execute in seconds: $($executionTime.TotalSeconds)"
}

function validate-connection($ipAddress, $computerName) {
  write-host "clearing dns cache"
  Clear-DnsClientCache
  $retval = $true

  write-host "Testing DNS resolution for $computerName resolving to $ipAddress" -ForegroundColor Magenta
  $resolvedComputerName = Resolve-DnsName -Name $computerName -ErrorAction SilentlyContinue -QuickTimeout

  if ($resolvedComputerName) {
    if ($resolvedComputerName.IPAddress.count -gt 1) {
      write-host "Resolved error $computerName resolves to more than one IP address $($resolvedComputerName.IPAddress)" -ForegroundColor Red
      $retval = $false
    }

    foreach ($ip in $resolvedComputerName.IPAddress) {
      if ($ip -eq $ipAddress) {
        write-host "Resolved successfully $computerName to $ipAddress" -ForegroundColor Green
        $retval = $retval -and $true
      }
      else {
        write-host "Resolved error $computerName does not resolve to $ipAddress. $computername currently resolves to $($resolvedComputerName.IPAddress)" -ForegroundColor Red
        $retval = $false
      }
    }
  }
  else {
    write-host "Resolved error $computerName does not resolve to $ipAddress" -ForegroundColor Red
    $retval = $false
  }

  write-host "Testing tcp connection to $computerName" -ForegroundColor Magenta
  $testConnection = Test-NetConnection -ComputerName $computerName -Port $openTcpPort
  
  if ($testConnection.TcpTestSucceeded) {
    write-host "Tcp connection to $computerName successful" -ForegroundColor Green
    $retval = $retval -and $true
  }
  else {
    write-host "Tcp connection to $computerName failed" -ForegroundColor Red
    $retval = $false
  }

  return $retval
}

main