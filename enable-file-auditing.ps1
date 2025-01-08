<#
# This script enables auditing of object access success/failure 
# and adds an audit rule for the 'Everyone' group on a specified folder and subfolders.
# 250108

[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/enable-file-auditing.ps1" -outFile "$pwd\enable-file-auditing.ps1";
.\enable-file-auditing.ps1 -path "C:\path\to\folder"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [switch]$disableAuditing
)

if (!(Test-Path $Path)) {
    Write-Host "Path '$Path' does not exist." -ForegroundColor Red
    return
}

write-host "Retrieve ACL from specified path" -ForegroundColor Cyan
write-host "Get-Acl -Path $Path"
$acl = Get-Acl -Path $Path

write-host "current ACL" -ForegroundColor Cyan
$acl | Format-List

write-host "Object Access policy before changes: auditpol /get /category:'Object Access'" -ForegroundColor Yellow
auditpol /get /category:'Object Access'

if (!$disableAuditing) {
    # Enable auditing of object access at the OS level
    Write-Host "Enabling Object Access auditing..." -ForegroundColor Yellow
    write-host "auditpol /set /category:'Object Access' /success:enable /failure:enable" -ForegroundColor Cyan
    auditpol /set /category:'Object Access' /success:enable /failure:enable

    write-host "auditpol /get /category:'Object Access'" -ForegroundColor Cyan
    auditpol /get /category:'Object Access'

    # Create new audit rule for 'Everyone', applying to all subfolders and files
    $auditRule = New-Object Security.AccessControl.FileSystemAuditRule(
        "Everyone",
        "FullControl",
    ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [Security.AccessControl.PropagationFlags]::None,
    ([Security.AccessControl.AuditFlags]::Success -bor [Security.AccessControl.AuditFlags]::Failure)
    )

    # Add rule to ACL and apply
    $acl.AddAuditRule($auditRule)
    write-host "Set-Acl -Path $Path -AclObject $acl" -ForegroundColor Cyan
    Set-Acl -Path $Path -AclObject $acl
    Write-Host "Auditing enabled for '$Path' with new rule for 'Everyone'." -ForegroundColor Green
}
else {
    # Disable auditing of object access at the OS level
    Write-Host "Disabling Object Access auditing..." -ForegroundColor Yellow
    write-host "auditpol /set /category:'Object Access' /success:disable /failure:disable" -ForegroundColor Cyan
    auditpol /set /category:'Object Access' /success:disable /failure:disable

    $acl = Get-Acl -Path $Path
    $references = $acl.Audit | Where-Object IdentityReference -eq "Everyone"
    foreach ($reference in $references) {
        write-host "Removing audit rule for 'Everyone'..." -ForegroundColor Yellow
        $acl.RemoveAuditRule($reference)
    }
    
    Set-Acl -Path $Path -AclObject $acl
    Write-Host "Auditing disabled for '$Path'." -ForegroundColor Green
}

write-host "Current Object Access policy:auditpol /get /category:'Object Access'" -ForegroundColor Cyan
auditpol /get /category:'Object Access'

write-host "current ACL" -ForegroundColor Cyan
$global:acl = Get-Acl -Path $Path
$global:acl | Format-List

write-host "finished" -ForegroundColor Cyan