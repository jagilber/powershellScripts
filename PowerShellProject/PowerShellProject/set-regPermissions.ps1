<#  
.SYNOPSIS  
    powershell script to manage registry auditing and permissions
.DESCRIPTION  
    This script will set access and auditing permissions on a registry key
	
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
   File Name  : set-regPermissions.ps1
   Author     : jagilber
   Version    : 150109
   History    : 
 
.EXAMPLE  
    .\set-regPermissions.ps1
    no arguments. all variables are set inside script
	
#>  
 
# variables that can be edited
$regKey = "HKLM:\SYSTEM\CurrentControlSet\services\W32Time"
$logFile = "set-regPermissions.log"
 
$objUser = New-Object System.Security.Principal.NTAccount("everyone") 
$InheritanceFlag = [System.Security.AccessControl.InheritanceFlags]::None
$PropagationFlag = [System.Security.AccessControl.PropagationFlags]::None 
$RegistryRights = [System.Security.AccessControl.RegistryRights]::SetValue
 
$AccessControl = [System.Security.AccessControl.AccessControlType]::Allow
 
$AuditFlag = [System.Security.AccessControl.AuditFlags]::Success
# end of variables
 
# ----------------------------------------------------------------------------------------------------------------
function main()
{
    cls
    $error.Clear()
 
    log-info "starting"
 
    #enable auditing
    run-process -processName "Auditpol.exe" -arguments "/set /category:`"Object Access`" /failure:enable /success:enable" -wait $true
         
    #set-accessAcl
 
    set-auditAcl
 
    log-info "finished"
}
 
# ----------------------------------------------------------------------------------------------------------------
function set-accessAcl()
{
    $acl = Get-Acl $regKey
 
    log-info "current acl:"
    log-aclInfo $acl
 
    foreach($obj in $acl.Access)
    {
    $accessLine += "$($obj.IdentityReference) $($obj.AccessControlType) $($obj.RegistryRights)`n`t"
        if($obj.IdentityReference -eq $objUser `
            -and  $obj.AccessControlType -contains $AccessControl `
            -and $obj.RegistryRights -contains $RegistryRights)
            {
                log-info "access acl already contains correct access permission. exiting"
                return
            }
    }    
 
   
    log-info "creating new access rule"
    $accessRule = New-Object System.Security.AccessControl.RegistryAccessRule ($objUser, $RegistryRights, $AccessControl)
    $acl.SetAccessRule($accessRule)
    
    $newAcl = Get-Acl $regKey
 
    log-info "new acl:"
    log-aclInfo $newAcl
}
 
# ----------------------------------------------------------------------------------------------------------------
function set-auditAcl()
{
    $acl = Get-Acl $regKey -Audit
 
    log-info "current acl:"
    log-aclInfo $acl
    
    foreach($obj in $acl.Audit)
    {
        if($obj.IdentityReference -eq $objUser `
            -and  $obj.AuditFlags -contains $AuditFlag `
            -and $obj.RegistryRights -contains $RegistryRights)
            {
                log-info "audit acl already contains correct audit permission. exiting"
                return
            }
    }    
 
 
 
    log-info "creating new audit rule"
    $auditRule = New-Object System.Security.AccessControl.RegistryAuditRule ($objUser, $RegistryRights, $InheritanceFlag, $PropagationFlag, $AuditFlag)
    $acl.SetAuditRule($auditRule)
    log-info "setting new acl"
    Set-Acl -Path $regKey -AclObject $acl
    
    $newAcl = Get-Acl $regKey -Audit
 
    log-info "new acl:"
    log-aclInfo $newAcl
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
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
{
    log-info "Running process $processName $arguments"
    $exitVal = 0
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $true

 
    [void]$process.Start()
    if($wait -and !$process.HasExited)
    {
        $process.WaitForExit($processWaitMs)
        $exitVal = $process.ExitCode
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        log-info "Process output:$stdOut"
 
        if(![String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
        {
            log-info "Error:$stdErr `n $Error"
            $Error.Clear()
        }
    }
    elseif($wait)
    {
        log-info "Process ended before capturing output."
    }
    
    #return $exitVal
    return $stdOut
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
