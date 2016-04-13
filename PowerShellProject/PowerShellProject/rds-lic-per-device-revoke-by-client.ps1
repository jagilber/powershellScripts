# script to revoke ts perdevice cal
# will prompt for client name to revoke
 
$activeLicenses = @()
$licenses = get-wmiobject Win32_TSIssuedLicense
 
#licenseStatus = 4 = revoked, 1 = temp, 2 = 2 permanent
$activelicenses = @($licenses | where {$_.licenseStatus -ne 4})
# status 1 = 1 temp 2 = 2 perm
 
if($activeLicenses.Count -ge 1)
{
    #$activeLicenses | out-gridview
    $activeLicenses | select sIssuedToComputer | fl
    
    #sIssuedToComputer for client name
    $clientName = Read-Host 'What client machine do you want to revoke (sIssuedToComputer)?'
    if(![string]::IsNullOrEmpty($clientName))
    {
        foreach ($lic in ($activeLicenses| where {$_.sIssuedToComputer -ieq $clientName}))
        {
            write-host "removing clientName:$($clientName)"
            $lic.Revoke() | select ReturnValue, RevokableCals, NextRevokeAllowedOn | fl
            break
        }
    }
}
else
{
    write-host "no licenses to revoke"
}
 
write-host "finished"
