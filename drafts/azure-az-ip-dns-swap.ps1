<#

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
$publicIps = Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName | Select-Object Name, ResourceGroupName, IpAddress, DnsSettings

write-host "current public IPs:"
foreach ($publicIp in $publicIps) {
  write-host "Public IP: $($publicIp.Name) $($publicIp | convertto-json)" -ForegroundColor Cyan
}

$oldPublicIP = Get-AzPublicIpAddress -Name $oldPublicIpName -ResourceGroupName $resourceGroupName
$publicIP = Get-AzPublicIpAddress -Name $newPublicIpName -ResourceGroupName $resourceGroupName

$dnsName = $oldPublicIP.DnsSettings.DomainNameLabel
$fqdn = $oldPublicIP.DnsSettings.Fqdn

$newDnsName = $publicIP.DnsSettings.DomainNameLabel
$newFqdn = $publicIP.DnsSettings.Fqdn

$tempDnsName = "temp-$dnsName"
$tempFqdn = "temp-$fqdn"

write-host "setting $($oldPublicIp.IpAddress) to $newDnsName and $newfqdn" -ForegroundColor Yellow
$oldPublicIP.DnsSettings.DomainNameLabel = $tempDnsName
$oldPublicIP.DnsSettings.Fqdn = $tempFqdn
write-host "Set-AzPublicIpAddress -PublicIpAddress $($oldPublicIP | convertto-json)"
if ($execute) { 
  Set-AzPublicIpAddress -PublicIpAddress $oldPublicIP 
}

write-host "setting $($publicIP.IpAddress) to $dnsName and $fqdn" -ForegroundColor Yellow
$publicIP.DnsSettings.DomainNameLabel = $dnsName
$publicIP.DnsSettings.Fqdn = $fqdn
write-host "Set-AzPublicIpAddress -PublicIpAddress $($publicIP | convertto-json)"
if ($execute) { 
  Set-AzPublicIpAddress -PublicIpAddress $PublicIP
}

if ($swap) {
  write-host "setting $($oldPublicIp.IpAddress) to $newDnsName and $newfqdn" -ForegroundColor Yellow
  $oldPublicIP.DnsSettings.DomainNameLabel = $newDnsName
  $oldPublicIP.DnsSettings.Fqdn = $newFqdn
  write-host "Set-AzPublicIpAddress -PublicIpAddress $($oldPublicIP | convertto-json)"
  if ($execute) {
    Set-AzPublicIpAddress -PublicIpAddress $oldPublicIP
  }
}

write-host "to execute (or rerun with -execute)):
  `$resourceGroupName = '$resourceGroupName'
  `$oldPublicIPName = '$oldPublicIPName'
  `$newPublicIPName = '$newPublicIPName'
  `$swap = `$$swap
  `$oldPublicIP = Get-AzPublicIpAddress -Name `$oldPublicIpName -ResourceGroupName '$resourceGroupName'
  `$publicIP = Get-AzPublicIpAddress -Name '$newPublicIpName' -ResourceGroupName '$resourceGroupName'
  
  `$oldPublicIP.DnsSettings.DomainNameLabel = '$tempDnsName'
  `$oldPublicIP.DnsSettings.Fqdn = '$tempFqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$oldPublicIP

  `$publicIP.DnsSettings.DomainNameLabel = '$dnsName'
  `$publicIP.DnsSettings.Fqdn = '$fqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$publicIP

  if(`$swap) {
    `$oldPublicIP.DnsSettings.DomainNameLabel = '$newDnsName'
    `$oldPublicIP.DnsSettings.Fqdn = '$newFqdn'
    Set-AzPublicIpAddress -PublicIpAddress `$oldPublicIP
  }
" -ForegroundColor Green

write-host "to revert:
  `$resourceGroupName = '$resourceGroupName'
  `$oldPublicIPName = '$oldPublicIPName'
  `$newPublicIPName = '$newPublicIPName'
  `$oldPublicIP = Get-AzPublicIpAddress -Name '$oldPublicIpName' -ResourceGroupName '$resourceGroupName'
  `$publicIP = Get-AzPublicIpAddress -Name '$newPublicIpName' -ResourceGroupName '$resourceGroupName'
  
  `$oldPublicIP.DnsSettings.DomainNameLabel = '$tempDnsName'
  `$oldPublicIP.DnsSettings.Fqdn = '$tempFqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$oldPublicIP

  `$publicIP.DnsSettings.DomainNameLabel = '$newDnsName'
  `$publicIP.DnsSettings.Fqdn = '$newFqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$publicIP

  `$oldPublicIP.DnsSettings.DomainNameLabel = '$dnsName'
  `$oldPublicIP.DnsSettings.Fqdn = '$fqdn'
  Set-AzPublicIpAddress -PublicIpAddress `$publicIP
" -ForegroundColor Yellow

write-host "Done: $(get-date -format 'HH:mm:ss') - $(get-date $startTime -format 'HH:mm:ss')"
