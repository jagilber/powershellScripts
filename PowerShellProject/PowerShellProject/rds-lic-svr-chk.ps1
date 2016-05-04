<#  
.SYNOPSIS  
    powershell script to enumerate license server connectivity.
    can be used on rdsh server or license server
    
.DESCRIPTION  
    This script will enumerate license server configuration off of an RDS server. it will check the known registry locations
    as well as run WMI tests against the configuration. a log file named rds-lic-svr-chk.txt will be generated that should
    be uploaded to support.
    Tested on windows 2008 r2 and windows 2012 r2
 
.NOTES  
   File Name  : rds-lic-svr-chk.ps1  
   Author     : jagilber
   Version    : 160504 modified reading of registry to use WMI for compatibility with 2k8r2
                
   History    : 
                160502 added new methods off of Win32_TSLicenseServer. added $rdshServer argument
                160425 cleaned output. set $retval to $Null in reg read
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
$HKCR = 2147483648 #HKEY_CLASSES_ROOT
$HKCU = 2147483649 #HKEY_CURRENT_USER
$HKLM = 2147483650 #HKEY_LOCAL_MACHINE
$HKUS = 2147483651 #HKEY_USERS
$HKCC = 2147483653 #HKEY_CURRENT_CONFIG
$displayBinaryBlob = $false
$lsDiscovered = $false
$appServer = $false

# ----------------------------------------------------------------------------------------------------------------
function main()
{ 
    log-info $MyInvocation.ScriptName
    # run as administrator
    runas-admin 
    # get-update -updateUrl $updateUrl
    log-info "-----------------------------------------"
    log-info "REGISTRY"
    log-info "-----------------------------------------"

    read-reg -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server\RCM' 
    read-reg -hive $HKLM -key 'SOFTWARE\Microsoft\TermServLicensing'
    read-reg -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList' -subKeySearch $false
    read-reg -hive $HKLM -key 'SYSTEM\CurrentControlSet\Services\TermService\Parameters\LicenseServers\SpecifiedLicenseServers'
    read-reg -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    
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
    
    # lsdiag calls this
    log-info "-----------------------------------------"
    log-info "Win32_TerminalServiceSetting::FindLicenseServers()"
    log-info "-----------------------------------------"
 
    $lsList = $rWmi.FindLicenseServers().LicenseServersList

    
    foreach($ls in $lsList)
    {
        #lsdiag uses this
        if(![string]::IsNullOrEmpty($ls.LicenseServer))
        {
            $lsDiscovered = $true
        }

        #lsdiag uses this to determine if app server or admin server
        if($rWmi.TerminalServerMode -eq 1)
        {
            $appServer = $true
        }
    
        log-info "LicenseServer:$($ls.LicenseServer)"
        log-info "HowDiscovered:$($ls.HowDiscovered)"
        log-info "IsAdminOnLS:$($ls.IsAdminOnLS)"
        log-info "IsLSAvailable:$($ls.IsLSAvailable)"
        log-info "IssuingCals:$($ls.IssuingCals)"
        log-info "-----------------------------------------"
    }

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
    $tempServers = @(([string](read-reg -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -value 'LicenseServers')).Split(",",[StringSplitOptions]::RemoveEmptyEntries))
    $licMode = (read-reg -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -value 'LicensingMode')
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
        $daysLeft = $ret.DaysLeft
    }
    catch
    {
        $daysLeft = "ERROR"
    }
 
    # from lsdiag if findlicenseservers returns server and tsappallowlist\licensetype -ne 5 an daysleft > 0
    if($lsDiscovered -and $daysLeft -gt 0 -and $appServer)
    {
        log-info "Server is connected to license server and is NOT in grace"
    }
    elseif(!$appServer)
    {
        log-info "Server is configured for Remote Administration (2 session limit)"
    }
    else
    {
        log-info "WARNING:Grace Period Days Left: $($daysLeft)"
    }
 
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
            if($member.MemberType.ToString().ToLower().Contains("property") -and !$member.Name.StartsWith('_'))
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
function read-reg($hive, $key, $value, $subKeySearch = $true)
{
    $retVal = new-object Text.StringBuilder
    if([string]::IsNullOrEmpty($value))
    {
        [void]$retVal.AppendLine("-----------------------------------------")
        [void]$retVal.AppendLine("enumerating $($key)")
    }
    else
    {
        log-info "-----------------------------------------"
        log-info "enumerating $($key) for value $($value)"
    }
    
    try
    {
            
        $reg = [wmiclass]'\\.\root\default:StdRegprov'
         
#        if($reg.EnumValues($hive, $key).ReturnValue -ne 0)
#        {
#            return   
#        }
        
        $sNames = $reg.EnumValues($hive, $key).sNames
        $sTypes = $reg.EnumValues($hive, $key).Types
        
        for($i = 0; $i -lt $sNames.count; $i++)
        {
            if(![string]::IsNullOrEmpty($value) -and $sNames[$i] -inotlike $value)
            {
                continue
            }

            switch ($sTypes[$i])
            {
                # REG_SZ
                1 
                { 
                    [void]$retval.AppendLine("$($sNames[$i]):$($reg.GetStringValue($hive, $key, $sNames[$i]).sValue)")
                    break
                }
                # REG_EXPAND_SZ
                2 
                { 
                    [void]$retval.AppendLine("$($sNames[$i]):$($reg.GetExpandStringValue($hive, $key, $sNames[$i]).sValue)")
                    break
                }
                # REG_BINARY
                3 
                { 
                    if($displayBinaryBlob)
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$((($reg.GetBinaryValue($hive, $key, $sNames[$i]).uValue) -join ','))")
                    }
                    else
                    {
                        $blob = $reg.GetBinaryValue($hive, $key, $sNames[$i]).uValue
                        [void]$retval.AppendLine("$($sNames[$i]):(Binary Blob (length:$($blob.Length)))")
                    }
                    break
                }
                # REG_DWORD
                4 
                { 
                    [void]$retval.AppendLine("$($sNames[$i]):$($reg.GetDWORDValue($hive, $key, $sNames[$i]).uValue)")
                    break
                }
                # REG_MULTI_SZ
                7 
                { 
                    [void]$retval.AppendLine("$($sNames[$i]):$((($reg.GetMultiStringValue($hive, $key, $sNames[$i]).sValue) -join ','))")
                    break;
                }
                # REG_QWORD
                11 
                { 
                    [void]$retval.AppendLine("$($sNames[$i]):$($reg.GetQWORDValue($hive, $key, $sNames[$i]).uValue)")
                    break
                }
                default { [void]$retval.AppendLine("unknown type") }
            }
        }
        
        if([string]::IsNullOrEmpty($value) -and $subKeySearch)
        {
            
            foreach($subKey in $reg.EnumKey($hive, $key).sNames)
            {
                if([string]::IsNullOrEmpty($subKey))
                {
                    continue
                }
                
                [void]$retval.AppendLine((read-reg -hive $hive -key "$($key)\$($subkey)"))
            }
        }

    }
    catch
    {
        #log-info "read-reg:exception $($error)"
        $error.Clear()
        return 
    }

    return $retVal.toString()
}

# ----------------------------------------------------------------------------------------------------------------
function get-update($updateUrl)
{
    try 
    {
        $webClient = new-object System.Net.WebClient
        $webClient.DownloadFile($updateUrl, "c:\temp\test.ps1")
        if([IO.File]::ReadAllBytes($MyInvocation.ScriptName) -ne [IO.File]::ReadAllBytes($MyInvocation.ScriptName))
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
