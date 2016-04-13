
# script to enumerate ts perdevice cals
 
$activeLicenses = @()
$licenses = get-wmiobject Win32_TSIssuedLicense
 
#licenseStatus = 4 = revoked, 1 = temp, 2 = permanent
$activelicenses = @($licenses | where {$_.licenseStatus -ne 4})

if($activeLicenses.Count -ge 1)
{
    #$activeLicenses | out-gridview
    $activeLicenses | select sIssuedToComputer | fl
   
    foreach ($lic in $activeLicenses)
    {
        write-host "----------------------------------"
        write-host "enumerating license:$($lic)"
        write-host $lic | fl *
        #write-host "removing clientName:$($clientName)"
        #$lic.Revoke() | select ReturnValue, RevokableCals, NextRevokeAllowedOn | fl
    }
}
else
{
    write-host "no licenses to enumerate"
}
 
write-host "finished"
