<#  
.SYNOPSIS  
    powershell script to enumerate license server connectivity.
    can be used on rdsh server or license server
    
.DESCRIPTION  
    This script will enumerate license server configuration off of an RDS server. it will check the known registry locations
    as well as run WMI tests against the configuration. a log file named rds-lic-svr-chk.txt will be generated that should
    be uploaded to support.
    Written for Windows 2012. Will partially work on Windows 2008 r2 except for registry enumeration.
 
.NOTES  
   File Name  : rds-lic-svr-chk.ps1  
   Author     : jagilber
   Version    : 160502 added new methods off of Win32_TSLicenseServer. added $rdshServer argument
                
   History    : 160425 cleaned output. set $retval to $Null in reg read
                160412 added Win32_TSDeploymentLicensing
                160329 original

.EXAMPLE  
    .\rds-lic-svr-chk.ps1
    query for license server configuration and use wmi to test functionality

.EXAMPLE  
    .\rds-lic-svr-chk.ps1 -licServer rds-lic-1
    query for license server rds-lic-1 and use wmi to test functionality

.PARAMETER licServer
    If specified, all wmi checks will use this server, else it will use enumerated list.
#>  

Param(
 
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter license server name:")]
    [string] $licServer,    
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter rdsh server name:")]
    [string] $rdshServer
    )
$error.Clear()
cls 
$ErrorActionPreference = "SilentlyContinue"
$logFile = "rds-lic-svr-chk.txt"
$licServers = @()
$updateUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/PowerShellProject/PowerShellProject/rds-lic-svr-chk.ps1"

# ----------------------------------------------------------------------------------------------------------------
function main()
{ 
    log-info $MyInvocation.ScriptName
    # run as administrator
    runas-admin 
    get-update -updateUrl $updateUrl
    log-info "-----------------------------------------"
    log-info "REGISTRY"
    log-info "-----------------------------------------"

    read-reg 'SYSTEM\CurrentControlSet\Control\Terminal Server\RCM'
 
    read-reg 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList\LicenseServers'
    read-reg 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList\LicensingMode'
 
    read-reg 'SYSTEM\CurrentControlSet\Services\TermService\Parameters\LicenseServers\SpecifiedLicenseServers'
        
    
    if(($rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseServer))
    {
        log-info "-----------------------------------------"
        log-info "Win32_TSLicenseServer"
        log-info "-----------------------------------------"
        log-info $rWmiLS

        $wmiClass = ([wmiclass]"Win32_TSLicenseServer")
        log-info "activation status: $($wmiClass.GetActivationStatus().ActivationStatus)"
        log-info "license server id: $($wmiClass.GetLicenseServerID().sLicenseServerId)"
        log-info "is in ts ls group in AD: $($wmiClass.IsLSinTSLSGroup([System.Environment]::UserDomainName).IsMember)"
        log-info "is ls on dc: $($wmiClass.IsLSonDC().OnDC)"
        log-info "is ls published in AD: $($wmiClass.IsLSPublished().Published)"
        log-info "is ls registered to SCP: $($wmiClass.IsLSRegisteredToSCP().Registered)"
        log-info "is ls security group enabled: $($wmiClass.IsLSSecGrpGPEnabled().Enabled)"
        log-info "is ls secure access allowed: $($wmiClass.IsSecureAccessAllowed($rdshServer).Allowed)"
        log-info "is rds in tsc group on ls: $($wmiClass.IsTSinTSCGroup($rdsshServer).IsMember)"
    }
        
    
    log-info "-----------------------------------------"
    log-info "Win32_TerminalServiceSetting"
    log-info "-----------------------------------------"
 
    $rWmi = Get-WmiObject -Namespace root/cimv2/TerminalServices -Class Win32_TerminalServiceSetting
    log-info $rWmi
    
    
    log-info "-----------------------------------------"
    log-info "Win32_TSDeploymentLicensing"
    log-info "-----------------------------------------"
    
    $rWmiL = Get-WmiObject -Namespace root/cimv2/TerminalServices -Class Win32_TSDeploymentLicensing
    log-info $rWmiL
    
    if(![string]::IsNullOrEmpty($licServer))
    {
        $licServers = @($licServer)
    }

    log-info "checking gpo for lic server"
    $tempServers = @(([string](read-reg 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\LicenseServers')).Split(",",[StringSplitOptions]::RemoveEmptyEntries))
    $licMode = (read-reg 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\LicensingMode')
    log-info "gpo lic servers: $($tempServers) license mode: $($licMode)"

    if($licServers.Length -lt 1)
    {
        $licServers = $tempServers;
    }

    log-info "checking wmi for lic server"
    $tempServers = @($rWmi.GetSpecifiedLicenseServerList().SpecifiedLSList)
    $licMode = "$($rWmi.LicensingName) ($($rWmi.LicensingType))"
    log-info "wmi lic servers: $($tempServers) license mode: $($licMode)"
    
    if($licServers.Length -lt 1)
    {
        $licServers = $tempServers;
    }
 
    
    log-info "checking ps for lic server"
    $tempServers = @(([string]((Get-RDLicenseConfiguration).LicenseServer)).Split(",", [StringSplitOptions]::RemoveEmptyEntries))
    $licMode = (Get-RDLicenseConfiguration).Mode
    log-info "ps lic servers: $($tempServers) license mode: $($licMode)"
    
    if($licServers.Length -lt 1)
    {
        $licServers = $tempServers;
    }
 
    if($licServers.Length -lt 1)
    {
        log-info "license server has not been configured! exiting"
        exit
    }
 
    foreach($server in $licServers)
    {
        # issue where server name has space in front but not sure why so adding .Trim() for now
        if($server -ne $server.Trim())
        {
           log-info "warning:whitespace characters on server name"    
        }
        
        check-licenseServer -licServer $server.Trim()
    }


    log-info "-----------------------------------------"
    log-info "finished" 
 
}
# ----------------------------------------------------------------------------------------------------------------

function check-licenseServer([string] $licServer)
{
    log-info "-----------------------------------------"
    log-info "-----------------------------------------"
    log-info "checking license server: '$($licServer)'"
    log-info "-----------------------------------------" 

    try
    {
        $ret = $rWmi.PingLicenseServer($licServer)
        $ret = $true
    }
    catch
    {
        $ret = $false
    }
 
    log-info "Can ping license server? $([bool]$ret)"
 
    $ret = $rWmi.CanAccessLicenseServer($licServer)
    log-info "Can access license server? $([bool]$ret.AccessAllowed)"
 
    try
    {
        $ret = $rWmi.GetGracePeriodDays()
        $ret = $ret.DaysLeft
    }
    catch
    {
        $ret = "ERROR"
    }
 
    log-info "Grace Period Days: $($ret)"
 
    $ret = $rWmi.GetTStoLSConnectivityStatus($licServer)
 
 
    switch($ret.TsToLsConnectivityStatus)
    {
        0 { $retName = "LS_CONNECTABLE_UNKNOWN" }
        1 { $retName = "LS_CONNECTABLE_VALID_WS08R2=1" }
        2 { $retName = "LS_CONNECTABLE_VALID_WS08" }
        3 { $retName = "LS_CONNECTABLE_BETA_RTM_MISMATCH" }
        4 { $retName = "LS_CONNECTABLE_LOWER_VERSION" }
        5 { $retName = "LS_CONNECTABLE_NOT_IN_TSCGROUP" }
        6 { $retName = "LS_NOT_CONNECTABLE" }
        7 { $retName = "LS_CONNECTABLE_UNKNOWN_VALIDITY" }
        8 { $retName = "LS_CONNECTABLE_BUT_ACCESS_DENIED" }
        9 { $retName = "LS_CONNECTABLE_VALID_WS08R2_VDI, //R2 with VDI support (SP1 release)" }
        10 { $retName = "LS_CONNECTABLE_FEATURE_NOT_SUPPORTED" }
        11 { $retName = "LS_CONNECTABLE_VALID_LS" }
        default { $retName = "Unknown $($ret.TsToLsConnectivityStatus)" }
    }
 
    log-info "license connectivity status: $($retName)"
 
}

# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    if(($data.GetType()).Name -eq "ManagementObject")
    {
        foreach($member in $data| Get-Member)
        {
            if($member.MemberType.ToString().ToLower().Contains("property"))
            {
                $tempData = "$($member.Name): $($data.Item($member.Name))"
                write-host $tempData
                out-file -Append -InputObject $tempData -FilePath $logFile
            }
        }
    }
    elseif($data.GetType().BaseType.Name -eq "Array")
    {
        foreach($dataitem in $data)
        {
            Write-Host "$dataitem"
            out-file -Append -InputObject $dataitem -FilePath $logFile
        }
    }
    else
    {

        Write-Host $data
        out-file -Append -InputObject $data -FilePath $logFile
	}
}

# ----------------------------------------------------------------------------------------------------------------
function read-reg($key)
{
    $retVal = $null

    log-info "-----------------------------------------" 
    log-info "enumerating $($key)"
    #log-info "-----------------------------------------" 

    try
    {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey( `
                        [Microsoft.Win32.RegistryHive]::LocalMachine, `
                        [Microsoft.Win32.RegistryView]::Default).OpenSubKey($key);
    }
    catch
    {
        #log-info "read-reg:exception $($error)"
        $error.Clear()
        return 
    }

     if($baseKey -eq $null)
     {
            try
            {
                # try as value
                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey( `
                                [Microsoft.Win32.RegistryHive]::LocalMachine, `
                                [Microsoft.Win32.RegistryView]::Default).OpenSubKey([IO.Path]::GetDirectoryName($key));
                $retVal = ($baseKey.GetValue([IO.Path]::GetFileName($key)) -join ",")
                log-info ([string]::Format("{0,-20}:'{1}'", [IO.Path]::GetFileName($key) , $retVal))
                return $retVal
            }
            catch
            {
                #log-info "read-reg:exception reading value $($error)"
                $error.Clear()
                return
            }
    }

    foreach($valueName in $baseKey.GetValueNames())
    {
        $value = $baseKey.GetValue($valueName)
        $tempVal = ([string]::Format("{0,-20}:'{1}'", $valueName, ($value -join ",")))
        log-info $tempVal
        log-info ""

        #$retVal += $tempVal
    }

    foreach($subkey in $baseKey.GetSubKeyNames())
    {
        read-reg "$($key)\$($subkey)"
    }

    $baseKey.Close();
    return $retVal
}

# ----------------------------------------------------------------------------------------------------------------
function get-update($updateUrl)
{
    try 
    {
        $webClient = new-object System.Net.WebClient
        if($webClient.DownloadData($updateUrl) -ne [IO.File]::ReadAllBytes($MyInvocation.ScriptName))
        {
            log-info "downloading updated script"
            $webClient.DownloadFile($updateUrl, $MyInvocation.ScriptName)
            log-info "restart script for update"
            exit
        }
        
        return $true
        
    }
    catch [System.Exception] 
    {
        return $false    
    }
}

# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole( `
        [Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
       log-info "please restart script as administrator. exiting..."
       exit
    }
}
# ----------------------------------------------------------------------------------------------------------------

main
