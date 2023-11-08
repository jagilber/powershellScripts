<#

#>
param(
  $resourceGroupName = 'sfjagilber1nt3',
  $existingPublicIPName = 'PublicIP-LB-FE-0',
  $newPublicIPName = 'LBIP-sfjagilber1nt3-nt1',
  $swap = $true,
  [switch]$execute
)

$errorActionPreference = 'Stop'
$startTime = get-date
$newPublicIps = Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName | Select-Object Name, ResourceGroupName, IpAddress, DnsSettings
$action = "To set"
if ($execute) {
  $action = "Setting and executing"
}

write-host "`nCurrent public IPs:`n" -ForegroundColor Yellow
foreach ($newPublicIp in $newPublicIps) {
  write-host "Public IP: $($newPublicIp.Name) $($newPublicIp | convertto-json)" -ForegroundColor Cyan
}

$existingPublicIP = Get-AzPublicIpAddress -Name $existingPublicIpName -ResourceGroupName $resourceGroupName
$newPublicIP = Get-AzPublicIpAddress -Name $newPublicIpName -ResourceGroupName $resourceGroupName

$dnsName = $existingPublicIP.DnsSettings.DomainNameLabel
$fqdn = $existingPublicIP.DnsSettings.Fqdn

$newDnsName = $newPublicIP.DnsSettings.DomainNameLabel
$newFqdn = $newPublicIP.DnsSettings.Fqdn

$tempDnsName = "temp-$dnsName"
$tempFqdn = "temp-$fqdn"

write-host "`n$action existing public ip: $($existingPublicIp.IpAddress) to new dns name: $newDnsName and new dns fqdn: $newfqdn`n" -ForegroundColor Yellow
$existingPublicIP.DnsSettings.DomainNameLabel = $tempDnsName
$existingPublicIP.DnsSettings.Fqdn = $tempFqdn
write-host "Set-AzPublicIpAddress -PublicIpAddress $($existingPublicIP | convertto-json)"
if ($execute) { 
  Set-AzPublicIpAddress -PublicIpAddress $existingPublicIP 
}

write-host "`n$action new public ip: $($newPublicIP.IpAddress) to existing dns name: $dnsName and existing dns fqdn: $fqdn`n" -ForegroundColor Yellow
$newPublicIP.DnsSettings.DomainNameLabel = $dnsName
$newPublicIP.DnsSettings.Fqdn = $fqdn
write-host "Set-AzPublicIpAddress -PublicIpAddress $($newPublicIP | convertto-json)"
if ($execute) { 
  Set-AzPublicIpAddress -PublicIpAddress $PublicIP
}

if ($swap) {
  write-host "`n$action existing public ip: $($existingPublicIp.IpAddress) to new dns name: $newDnsName and new dns fqdn: $newfqdn`n" -ForegroundColor Yellow
  $existingPublicIP.DnsSettings.DomainNameLabel = $newDnsName
  $existingPublicIP.DnsSettings.Fqdn = $newFqdn
  write-host "Set-AzPublicIpAddress -PublicIpAddress $($existingPublicIP | convertto-json)"
  if ($execute) {
    Set-AzPublicIpAddress -PublicIpAddress $existingPublicIP
  }
}

write-host "`nTo execute dns swap (or rerun script with -execute switch):`n
  `$resourceGroupName = '$resourceGroupName'
  `$existingPublicIPName = '$existingPublicIPName'
  `$newPublicIPName = '$newPublicIPName'
  `$swap = `$$swap
  `$existingPublicIP = Get-AzPublicIpAddress -Name `$existingPublicIpName -ResourceGroupName '$resourceGroupName'
  `$newPublicIP = Get-AzPublicIpAddress -Name '$newPublicIpName' -ResourceGroupName '$resourceGroupName'
  
  `$existingPublicIP.DnsSettings.DomainNameLabel = '$tempDnsName'
  `$existingPublicIP.DnsSettings.Fqdn = '$tempFqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$existingPublicIP

  `$newPublicIP.DnsSettings.DomainNameLabel = '$dnsName'
  `$newPublicIP.DnsSettings.Fqdn = '$fqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$newPublicIP

  if(`$swap) {
    `$existingPublicIP.DnsSettings.DomainNameLabel = '$newDnsName'
    `$existingPublicIP.DnsSettings.Fqdn = '$newFqdn'
    Set-AzPublicIpAddress -PublicIpAddress `$existingPublicIP
  }
" -ForegroundColor Green

write-host "`nTo revert dns swap:`n
  `$resourceGroupName = '$resourceGroupName'
  `$existingPublicIPName = '$existingPublicIPName'
  `$newPublicIPName = '$newPublicIPName'
  `$existingPublicIP = Get-AzPublicIpAddress -Name '$existingPublicIpName' -ResourceGroupName '$resourceGroupName'
  `$newPublicIP = Get-AzPublicIpAddress -Name '$newPublicIpName' -ResourceGroupName '$resourceGroupName'
  
  `$existingPublicIP.DnsSettings.DomainNameLabel = '$tempDnsName'
  `$existingPublicIP.DnsSettings.Fqdn = '$tempFqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$existingPublicIP

  `$newPublicIP.DnsSettings.DomainNameLabel = '$newDnsName'
  `$newPublicIP.DnsSettings.Fqdn = '$newFqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$newPublicIP

  `$existingPublicIP.DnsSettings.DomainNameLabel = '$dnsName'
  `$existingPublicIP.DnsSettings.Fqdn = '$fqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$newPublicIP
" -ForegroundColor Yellow

write-host "Done: $(get-date -format 'HH:mm:ss') - $(get-date $startTime -format 'HH:mm:ss')"
