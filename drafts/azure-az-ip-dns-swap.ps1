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
  $resourceGroupName = 'sfjagilber1nt3',
  $oldPublicIPName = 'PublicIP-LB-FE-0',
  $newPublicIPName = 'LBIP-sfjagilber1nt3-nt1',
  $swap = $true,
  [switch]$execute
)

$errorActionPreference = 'Stop'
$startTime = get-date
$newPublicIps = Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName | Select-Object Name, ResourceGroupName, IpAddress, DnsSettings
$action = "To set"
if ($execute) {
  $action = "Setting"
}

write-host "`nCurrent public IPs in resource group:`n" -ForegroundColor Yellow
foreach ($newPublicIp in $newPublicIps) {
  write-host "Public IP: $($newPublicIp.Name) $($newPublicIp | convertto-json)" -ForegroundColor Cyan
}

$oldPublicIP = Get-AzPublicIpAddress -Name $oldPublicIpName -ResourceGroupName $resourceGroupName
$newPublicIP = Get-AzPublicIpAddress -Name $newPublicIpName -ResourceGroupName $resourceGroupName

$dnsName = $oldPublicIP.DnsSettings.DomainNameLabel
$fqdn = $oldPublicIP.DnsSettings.Fqdn

$newDnsName = $newPublicIP.DnsSettings.DomainNameLabel
$newFqdn = $newPublicIP.DnsSettings.Fqdn

$tempDnsName = "temp-$dnsName"
$tempFqdn = "temp-$fqdn"

write-host "`n$action old public ip: $($oldPublicIp.IpAddress) to new dns name: $newDnsName and new dns fqdn: $newfqdn`n" -ForegroundColor Yellow
$oldPublicIP.DnsSettings.DomainNameLabel = $tempDnsName
$oldPublicIP.DnsSettings.Fqdn = $tempFqdn
write-host "Set-AzPublicIpAddress -PublicIpAddress $($oldPublicIP | convertto-json)"
if ($execute) { 
  Set-AzPublicIpAddress -PublicIpAddress $oldPublicIP 
}

write-host "`n$action new public ip: $($newPublicIP.IpAddress) to old dns name: $dnsName and old dns fqdn: $fqdn`n" -ForegroundColor Yellow
$newPublicIP.DnsSettings.DomainNameLabel = $dnsName
$newPublicIP.DnsSettings.Fqdn = $fqdn
write-host "Set-AzPublicIpAddress -PublicIpAddress $($newPublicIP | convertto-json)"
if ($execute) { 
  Set-AzPublicIpAddress -PublicIpAddress $newPublicIP
}

if ($swap) {
  write-host "`n$action old public ip: $($oldPublicIp.IpAddress) to new dns name: $newDnsName and new dns fqdn: $newfqdn`n" -ForegroundColor Yellow
  $oldPublicIP.DnsSettings.DomainNameLabel = $newDnsName
  $oldPublicIP.DnsSettings.Fqdn = $newFqdn
  write-host "Set-AzPublicIpAddress -PublicIpAddress $($oldPublicIP | convertto-json)"
  if ($execute) {
    Set-AzPublicIpAddress -PublicIpAddress $oldPublicIP
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
  `$newPublicIP.DnsSettings.Fqdn = '$fqdn'
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
  `$oldPublicIP.DnsSettings.Fqdn = '$fqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$newPublicIP
" -ForegroundColor Yellow

$executionTime = New-TimeSpan -Start $startTime -End (get-date)
write-host "Done: time to execute $($executionTime.ToString())"
