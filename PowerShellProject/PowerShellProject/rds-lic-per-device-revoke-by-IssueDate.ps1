# script to revoke Windows RDS perdevice cal by issue date
# requires issuedate as parameter
# any cal with a date greater than provided issuedate will attempt revocation

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
    if(!(Read-Host "WARNING:This will revoke up to $($activeLicenses.Count), are you sure you want to continue?") -icontains "y")
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
