<#  
.SYNOPSIS  
    script to revoke Windows RDS perdevice cal by issue date

.DESCRIPTION  
    script to revoke Windows RDS perdevice cal by issue date
    requires issuedate as parameter
    to be run on Windows 2012 RDS License server
    any cal with a date greater than provided issuedate will attempt revocation
  
.NOTES  
   File Name  : rds-lic-per-device-revoke-by-issuedate.ps1  
   Author     : jagilber
   Version    : 160418
                
   History    :  160414 original

.EXAMPLE  
    Example: .\rds-lic-per-device-revoke-by-IssueDate.ps1 -issueDate 2/16/2016 -test
    
.PARAMETER issueDate
    IssueDate is any valid date string, example 2/16/2016. Any cal with a date greater then provided date will be revoked!"
.PARAMETER test
    use switch test to simulate cal revoke but not perform. it will not however produce next cal revoke date.
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
#licenseStatus = 4 = revoked, 1 = temp, 2 = 2 permanent
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
