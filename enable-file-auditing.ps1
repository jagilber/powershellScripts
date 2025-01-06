<#
# This ai script enables auditing of object access success/failure 
# and adds an audit rule for the 'Everyone' group on a specified folder and subfolders.
# 250106

[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/enable-file-auditing.ps1" -outFile "$pwd\enable-file-auditing.ps1";
.\enable-file-auditing.ps1 -path "C:\path\to\folder"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

# Enable auditing of object access at the OS level
Write-Host "Enabling Object Access auditing..."
auditpol /set /category:"Object Access" /success:enable /failure:enable

# Retrieve ACL from specified path
$acl = Get-Acl -Path $Path

# Create new audit rule for 'Everyone', applying to all subfolders and files
$auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule(
    "Everyone",
    "FullControl",
    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
    [System.Security.AccessControl.PropagationFlags]::None,
    ([System.Security.AccessControl.AuditFlags]::Success -bor [System.Security.AccessControl.AuditFlags]::Failure)
)

# Add rule to ACL and apply
$acl.AddAuditRule($auditRule)
Set-Acl -Path $Path -AclObject $acl

Write-Host "Auditing enabled for '$Path' with new rule for 'Everyone'."