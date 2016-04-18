<#  
.SYNOPSIS  
    script to enumerate Windows RDS perdevice cals

.DESCRIPTION  
    script to enumerate Windows RDS perdevice cals
    tested on Windows 2008 r2 and 2012 RDS License server
  
.NOTES  
   File Name  : rds-lic-per-device-cal-enumerate.ps1  
   Author     : jagilber
   Version    : 160418
                
   History    : 160414 original

.EXAMPLE  
    Example: .\rds-lic-per-device-cal-enumerate.ps1 
#>  


$ErrorActionPreference = "Stop"
$activeLicenses = @()
$error.Clear()
cls

write-host "----------------------------------"
write-host "key packs:"
$keyPacks = Get-WmiObject Win32_TSLicenseKeyPack
foreach($keyPack in $keyPacks)
{
    write-host "----------------------------------"
    $keyPack
}
write-host "----------------------------------"
write-host "----------------------------------"

$licenses = get-wmiobject Win32_TSIssuedLicense

if($licenses -eq $null)
{
    write-host "no issued licenses. returning"
    return
}

#licenseStatus = 4 = revoked, 1 = temp, 2 = permanent
$activelicenses = @($licenses)

if($activeLicenses.Count -ge 1)
{

    foreach ($lic in $activeLicenses)
    {
        if(($keypacks | Where { $_.KeyPackId -eq $lic.KeyPackId -and $_.ProductType -eq 0 }))
        {
            write-host "----------------------------------"
            $lic
            write-host "----------------------------------"
        }
        else
        {
            write-host "license is not per device"
        }

    }
}
else
{
    write-host "no licenses to enumerate"
}

write-host "----------------------------------" 
write-host "finished"
