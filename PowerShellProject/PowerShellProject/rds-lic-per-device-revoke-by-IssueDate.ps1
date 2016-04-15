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
   Version    : 160414
                
   History    :  160414 original

.EXAMPLE  
    Example: .\rds-lic-per-device-revoke-by-IssueDate.ps1 -issueDate 2/16/2016 -test
    
.PARAMETER issueDate
    IssueDate is any valid date string, example 2/16/2016. Any cal with a date greater then provided date will be revoked!"
.PARAMETER test
    use switch test to simulate cal revoke but not perform. it will not however produce next cal revoke date.
#>  


Param(
 
    [parameter(Position=0,Mandatory=$true,HelpMessage="Enter the IssueDate. Any cal with a date greater then provided date will be revoked!")]
    [string] $issueDate,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Use -test to test revocation but not perform.")]
    [switch] $test
 )

$ErrorActionPreference = "Stop"
$activeLicenses = @()
$error.Clear()

try
{
    $issueDate = [Convert]::ToDateTime($issueDate).ToString("yyyyMMdd")
}
catch
{
    write-host "invalid issueDate provided. use date format of mm/dd/yyyy. for example 7/30/2014. exiting"
    return
}

write-host "converted issueDate: $($issueDate)"

$licenses = get-wmiobject Win32_TSIssuedLicense
#licenseStatus = 4 = revoked, 1 = temp, 2 = 2 permanent
$activelicenses = @($licenses | where {
    $_.licenseStatus -ne 4 -and $_.IssueDate.SubString(0,8) -ge $issueDate
    })

if($activeLicenses.Count -ge 1)
{
    if(!((Read-Host "WARNING:This will revoke up to $($activeLicenses.Count) cals, are you sure you want to continue?") -icontains "y"))
    {
        return
    }

    foreach ($lic in ($activeLicenses| where {$_.IssueDate.SubString(0,8) -le $issueDate}))
    {
        write-host "----------------------------------"
        write-host "removing license:$($lic.sIssuedToComputer) $($lic.sIssuedToUser) $($lic.IssueDate)"
        if(!$test)
        {
            $lic.Revoke() | select ReturnValue, RevokableCals, NextRevokeAllowedOn | fl
        }
    }
}
else
{
    write-host "no licenses to revoke"
}
 
write-host "finished"
