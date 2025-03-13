<#
.SYNOPSIS
    This script enables or disables file auditing on a specified path.

.DESCRIPTION
    When run without the -disableAuditing switch, the script enables 
    Object Access auditing at the OS level and adds an audit rule for 
    "Everyone" with FullControl permissions on all subfolders and files 
    in the specified path. If the -disableAuditing switch is used, 
    Object Access auditing is disabled, and the audit rules for 
    "Everyone" are cleared from the specified path.

.PARAMETER Path
    Specifies the directory path on which to enable or disable file auditing.

.PARAMETER disableAuditing
    Switch to disable Object Access auditing and remove any "Everyone" 
    audit rules from the specified path.

.EXAMPLE
    .\enable-file-auditing.ps1 -Path "C:\MyFolder"
    Enables OS-level object access auditing and assigns FullControl 
    auditing for "Everyone" on C:\MyFolder and its subitems.

.EXAMPLE
    .\enable-file-auditing.ps1 -Path "C:\MyFolder" -disableAuditing
    Disables OS-level object access auditing and removes all "Everyone" 
    audit entries on C:\MyFolder.

.NOTES
    Requires Administrator privileges to modify audit settings.
    **use in development / test environment only**
    v250109

.LINK
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/enable-file-auditing.ps1" -outFile "$pwd\enable-file-auditing.ps1";
.\enable-file-auditing.ps1 -path "C:\path\to\folder"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [switch]$disableAuditing
)

$warningTime = 5
$error.Clear()

if (!(Test-Path $Path)) {
    Write-Host "Path '$Path' does not exist." -ForegroundColor Red
    return
}

write-host "**use in non-production environment only. starting in $warningTime seconds... ctrl-c to exit**" -ForegroundColor Yellow
start-sleep -seconds $warningTime

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

    if($error){
        Write-Host "Error enabling Object Access auditing." -ForegroundColor Red
        # return
    }
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
    if($error){
        Write-Host "Error enabling Object Access auditing." -ForegroundColor Red
        # return
    }

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
# audit: in output is always empty regardless of the audit rule. not sure why so removing it from output 
# to avoid confusion
$global:acl = Get-Acl -Path $Path
if (!($global:acl.Audit)) {
    write-verbose "removing audit from output"
    $global:acl.psobject.properties.Remove('Audit')
}
$global:acl | Format-List *

write-host "finished" -ForegroundColor Cyan
 