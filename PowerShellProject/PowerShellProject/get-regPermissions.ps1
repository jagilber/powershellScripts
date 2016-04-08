<#  
.SYNOPSIS  
    powershell script to query registry auditing and permissions
.DESCRIPTION  
    This script will get access and auditing permissions on a registry key
	
	*** ALWAYS TEST IN LAB BEFORE USING IN PRODUCTION TO VERIFY FUNCTIONALITY ***        
	
    ** Copyright (c) Microsoft Corporation. All rights reserved - 2015.
    **
    ** This script is not supported under any Microsoft standard support program or service.
    ** The script is provided AS IS without warranty of any kind. Microsoft further disclaims all
    ** implied warranties including, without limitation, any implied warranties of merchantability
    ** or of fitness for a particular purpose. The entire risk arising out of the use or performance
    ** of the scripts and documentation remains with you. In no event shall Microsoft, its authors,
    ** or anyone else involved in the creation, production, or delivery of the script be liable for
    ** any damages whatsoever (including, without limitation, damages for loss of business profits,
    ** business interruption, loss of business information, or other pecuniary loss) arising out of
    ** the use of or inability to use the script or documentation, even if Microsoft has been advised
    ** of the possibility of such damages.
    **
 
.NOTES  
   File Name  : get-regPermissions.ps1
   Author     : jagilber
   Version    : 150109
   History    : 
 
.EXAMPLE  
    .\get-regPermissions.ps1
    no arguments. all variables are  inside script
	
#>  
 
# variables that can be edited
$regKeys = @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume","HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket","HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer","HKCU:\Software\Microsoft\Windows\CurrentVersion")

$logFile = "get-regPermissions.log"

# end of variables
 
# ----------------------------------------------------------------------------------------------------------------
function main()
{
    cls
    $error.Clear()
 
    log-info "starting"
 
    
    foreach($regKey in $regkeys)
    {
        get-accessAcl $regKey
    }
 
    log-info "finished"
}

# ----------------------------------------------------------------------------------------------------------------
function get-accessAcl($key)
{
    $acl = Get-Acl $key -Audit
    log-info "--------------------------------------------------"
    log-info "--------------------------------------------------"
    log-info "current acl:$($key)"
    log-aclInfo $acl
    
    
}
 
# ----------------------------------------------------------------------------------------------------------------
function log-aclInfo($acl)
{
    log-info "Path: $($acl.Path)"
    log-info "Owner: $($acl.Owner)"
    log-info "Group: $($acl.Group)"
 
    log-info "Access:"
    foreach($obj in $acl.Access)
    {
        $accessLine += "$($obj.IdentityReference) $($obj.AccessControlType) $($obj.RegistryRights)`n`t"
    }
 
    log-info $accessLine
 
    log-info "Audit:"
    foreach($obj in $acl.Audit)
    {
        $auditLine += "$($obj.IdentityReference) $($obj.AuditFlags) $($obj.RegistryRights)`n`t"
    }
 
    log-info $auditLine
 
    log-info "Sddl: $($acl.Sddl)"
}
 

# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    $data = "$([DateTime]::Now):$($data)"
    Write-Host $data
    out-file -Append -InputObject $data -FilePath $logFile
}
 
# ----------------------------------------------------------------------------------------------------------------
 
main 
