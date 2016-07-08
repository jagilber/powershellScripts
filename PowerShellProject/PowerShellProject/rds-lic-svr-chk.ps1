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
   Version    : 160625 adding network service
   History    : 
                160510 added installed features to list. added eventlog search
                    added osversion check and tested against 2k8
                160504 modified reading of registry to use WMI for compatibility with 2k8r2
                160502 added new methods off of Win32_TSLicenseServer. added $rdshServer argument
   Issues     : not everything logged to output file
   
.EXAMPLE  
    .\rds-lic-svr-chk.ps1
    query for license server configuration and use wmi to test functionality

.EXAMPLE  
    .\rds-lic-svr-chk.ps1 -licServer rds-lic-1
    query for license server rds-lic-1 and use wmi to test functionality

.EXAMPLE  
    .\rds-lic-svr-chk.ps1 -getUpdate

.PARAMETER licServer
    If specified, all wmi checks will use this server, else it will use enumerated list.

.PARAMETER rdshServer
    If specified, all wmi checks will use this server for testing connectivity from particular rdsh server.

.PARAMETER getUpdate
    If specified, will download latest version of script and replace if different.
#>  

Param(
 
    [parameter(HelpMessage="Enter license server name:")]
    [string] $licServer,    
    [parameter(HelpMessage="Enter rdsh server name:")]
    [string] $rdshServer = $env:COMPUTERNAME,
    [parameter(HelpMessage="Use to check for script update:")]
    [switch] $getUpdate,
    [parameter(HelpMessage="Use to run script as network service:")]
    [switch] $runAsNetworkService,
    [parameter(HelpMessage="Enter user name to check if per user:")]
    [string] $checkUser
 
    
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
$licenseModeSource = $null
$licenseMode = 0
$hasX509 = $false

# ----------------------------------------------------------------------------------------------------------------
function main()
{ 
    log-info $MyInvocation.ScriptName
    # run as administrator
    if(!(runas-admin))
    {
        return
    }
    
    if($getUpdate)
    {
        get-update -updateUrl $updateUrl
    }

    if($runAsNetworkService)
    {
        $psexec = get-sysInternalsUtility -utilityName "psexec.exe"
        if(![string]::IsNullOrEmpty($psexec))
        {
            run-process -processName $($psexec) -arguments "-accepteula -i -u `"nt authority\network service`" cmd.exe /k powershell.exe -noexit -executionpolicy Bypass -file $($MyInvocation.ScriptName) -checkUser $($env:USERNAME) " -wait $false            
            return
        }
        else
        {
            log-info "unable to download utility. exiting"
            return
        }
    }

    if(![string]::IsNullOrEmpty($checkUser))
    {
        check-user -user $checkUser
    }

    if(![string]::IsNullOrEmpty($licServer))
    {
        $licServers = @($licServer)
    }

    log-info "-----------------------------------------"
    log-info "OS $($rdshServer)"
    log-info "-----------------------------------------"
    $osVersion = read-reg -machine $licServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value CurrentVersion
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value ProductName

    log-info "-----------------------------------------"
    log-info "INSTALLED FEATURES $($rdshServer)"
    log-info "-----------------------------------------"
    
    Get-WindowsFeature -ComputerName $rdshServer | ? Installed -eq $true

    log-info "-----------------------------------------"
    log-info "EVENTS $($rdshServer)"
    log-info "-----------------------------------------"

    Get-EventLog -LogName System -Source TermService -Newest 10 -ComputerName $rdshServer -After ([DateTime]::Now).AddDays(-7) -EntryType @("Error","Warning")

    log-info "-----------------------------------------"
    log-info "REGISTRY $($rdshServer)"
    log-info "-----------------------------------------"

    if($rdshServer -ilike $env:COMPUTERNAME -and $osVersion -gt 6.1) # does not like 2k8
    {
        get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Audit | fl *
        get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM" -Audit | fl *
        get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\GracePeriod" -Audit | fl *
    }
    
    read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server' -subKeySearch $false
    $hasX509 = (read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server\RCM' -value "X509 Certificate").Length -gt 0
    read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server\RCM' 
    
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\TermServLicensing'
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList' -subKeySearch $false
    read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Services\TermService\Parameters\LicenseServers\SpecifiedLicenseServers'
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    
    log-info "-----------------------------------------"
    log-info "Win32_TerminalServiceSetting $($rdshServer)"
    log-info "-----------------------------------------"
 
    $rWmi = Get-WmiObject -Namespace root/cimv2/TerminalServices -Class Win32_TerminalServiceSetting -ComputerName $rdshServer
    log-info $rWmi
    
    # lsdiag uses licensingmode from rcm when not overriden in policy
    # todo: need to verify if same is true when in collection and when 'centrallicensing' presumably when configuring in gui in 2012
    
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
        log-info "HowDiscovered:$(if($ls.HowDiscovered) { "Manual" } else { "Auto" })"
        log-info "IsAdminOnLS:$($ls.IsAdminOnLS)"
        log-info "IsLSAvailable:$($ls.IsLSAvailable)"
        log-info "IssuingCals:$($ls.IssuingCals)"
        log-info "-----------------------------------------"
    }

    log-info "-----------------------------------------"
    log-info "Win32_TSDeploymentLicensing $($rdshServer)"
    log-info "-----------------------------------------"
    
    $rWmiL = Get-WmiObject -Namespace root/cimv2/TerminalServices -Class Win32_TSDeploymentLicensing -ComputerName $rdshServer
    log-info $rWmiL
    
    log-info "-----------------------------------------"
    log-info "checking wmi for lic server"
    $tempServers = @($rWmi.GetSpecifiedLicenseServerList().SpecifiedLSList)
    $licMode = $rWmi.LicensingType
    log-info "wmi lic servers: $($tempServers) license mode: $($licMode)"
    
    $licenseModeSource = 'wmi'
    $licenseMode = $licMode    
    
    if($licServers.Length -lt 1)
    {
        $licServers = $tempServers;
    }
 
    log-info "-----------------------------------------"
    log-info "checking gpo for lic server"
    $tempServers = @(([string](read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -value 'LicenseServers')).Split(",",[StringSplitOptions]::RemoveEmptyEntries))
    $licMode = (read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -value 'LicensingMode')
    log-info "gpo lic servers: $($tempServers) license mode: $($licMode)"

    if($rWmi.PolicySourceLicensingType)
    {
        $licenseModeSource = 'policy'
        $licenseMode = $licMode    
    }
    
    if([string]::IsNullOrEmpty($licServer) -and ($rWmi.PolicySourceConfiguredLicenseServers -or $rWmi.PolicySourceDirectConnectLicenseServers))
    {
        $licServers = $tempServers;        
    }
    
    if($rdshServer -ilike $env:COMPUTERNAME)
    {
        log-info "-----------------------------------------"
        log-info "checking local ps for lic server"
        $tempServers = @(([string]((Get-RDLicenseConfiguration).LicenseServer)).Split(",", [StringSplitOptions]::RemoveEmptyEntries))
        $licMode = (Get-RDLicenseConfiguration).Mode
        log-info "ps lic servers: $($tempServers) license mode: $($licMode)"
    }
    
    if($licServers.Length -lt 1)
    {
        $licServers = $tempServers;
    }
    
    if($licenseMode -eq 0)
    {
        $licenseModeSource = 'powershell'
        $licenseMode = $licMode -band $licMode
    }
 
    if($licServers.Length -lt 1)
    {
        log-info "license server has not been configured!"
    
    }
    else
    {
        $licCheck = $true
        foreach($server in $licServers)
        {
            # issue where server name has space in front but not sure why so adding .Trim() for now
            if($server -ne $server.Trim())
            {
               log-info "warning:whitespace characters on server name"    
            }
        
            $licCheck = $licCheck -band (check-licenseServer -licServer $server.Trim())
        }
    }
    
    try
    {
        $ret = $rWmi.GetGracePeriodDays()
        $daysLeft = $ret.DaysLeft
    }
    catch
    {
        $daysLeft = "NOT_SET"
    }
    
    log-info "-----------------------------------------" 
    # from lsdiag if findlicenseservers returns server and tsappallowlist\licensetype -ne 5 an daysleft > 0
    if($lsDiscovered -and $licCheck -and ($daysLeft -notlike "NOT_SET" -and $daysLeft -gt 0) -and $appServer -and ($licenseMode -ne 0 -and $licenseMode -ne 5) -and $hasX509)
    {
        log-info "Success:$($rdshServer) is connected to a license server. Server is in Grace Period, but this is ok. Days Left: $($daysLeft)"
    }
    elseif($lsDiscovered -and $licCheck -and ($daysLeft -eq 0 -or $daysLeft -eq "NOT_SET") -and $appServer -and ($licenseMode -ne 0 -and $licenseMode -ne 5) -and $hasX509)
    {
        log-info "Success:$($rdshServer) is connected to a license server and is not in grace. ($($daysLeft))"        
    }
    elseif($lsDiscovered -and !$licCheck -and ($daysLeft -notlike "NOT_SET" -and $daysLeft -gt 0) -and $appServer -and ($licenseMode -ne 0 -and $licenseMode -ne 5) -and $hasX509)
    {
        log-info "Warning:$($rdshServer) has connected to a license server. Server is in Grace Period, but server cannot currently connect to a license server. Days Left: $($daysLeft)"
    }
    elseif($lsDiscovered -and !$licCheck -and ($daysLeft -eq 0 -or $daysLeft -eq "NOT_SET") -and $appServer -and ($licenseMode -ne 0 -and $licenseMode -ne 5) -and $hasX509)
    {
        log-info "Warning:$($rdshServer) has connected to a license server and is not in grace but server cannot currently connect to a license server. ($($daysLeft))"        
    }
    elseif(!$lsDiscovered -and $daysLeft -eq 0 -and $appServer -and $hasX509)
    {
        log-info "ERROR:$($rdshServer) has connected to a license server at some point but is NOT in grace and is NOT currently connected to license server. ($($daysLeft))"        
    }
    elseif(!$lsDiscovered -and $daysLeft -eq 0 -and $appServer -and !$hasX509)
    {
        log-info "ERROR:$($rdshServer) is NOT connected to a license server and is NOT in grace. ($($daysLeft))"        
    }
    elseif(!$appServer)
    {
        log-info "ERROR:$($rdshServer) is configured for Remote Administration (2 session limit). ($($daysLeft))"
    }
    else
    {
        log-info "ERROR:Unknown state. ($($daysLeft))"        
    }
 
    switch($licenseMode)
    {
        0 { $modeString = "0 (should not be set to this!)"}
        1 { $modeString = "Personal Desktop (admin mode 2 session limit. should not be set to this if rdsh server!)"}
        2 { $modeString = "Per Device"}
        4 { $modeString = "Per User"}
        5 { $modeString = "Not configured (should not be set to this!)"}
        default { $modeString = "error: $($licenseMode)" }
    }
    
    log-info "current license mode: $($modeString)"
    log-info "current license mode source: $($licenseModeSource)"

    log-info "-----------------------------------------"
    log-info "finished" 
 
}
# ----------------------------------------------------------------------------------------------------------------

function check-licenseServer([string] $licServer)
{
    [bool] $retVal = $true
    
    log-info "-----------------------------------------"
    log-info "-----------------------------------------"
    log-info "checking license server: '$($licServer)'"
    log-info "-----------------------------------------" 

    log-info "-----------------------------------------"
    log-info "OS $($licServer)"
    log-info "-----------------------------------------"
     
    read-reg -machine $licServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value ProductName
    
    log-info "-----------------------------------------"
    log-info "SERVICE $($licServer)"
    log-info "-----------------------------------------"
    
    log-info "License Server Service status: $((Get-Service -Name TermServLicensing -ComputerName $licServer -ErrorAction SilentlyContinue).Status)"

    log-info "-----------------------------------------"
    log-info "EVENTS $($licServer)"
    log-info "-----------------------------------------"

    Get-EventLog -LogName "System" -Source "TermServLicensing" -Newest 10 -ComputerName $licServer -After ([DateTime]::Now).AddDays(-7) -EntryType @("Error","Warning")

    if(($rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseServer -ComputerName $licServer))
    {
        log-info "-----------------------------------------"
        log-info "Win32_TSLicenseServer $($licServer)"
        log-info "-----------------------------------------"
        log-info $rWmiLS

        $wmiClass = ([wmiclass]"\\$($licServer)\root\cimv2:Win32_TSLicenseServer")
        log-info "activation status: $($wmiClass.GetActivationStatus().ActivationStatus)"
        log-info "license server id: $($wmiClass.GetLicenseServerID().sLicenseServerId)"
        log-info "is ls in ts ls group in AD: $($wmiClass.IsLSinTSLSGroup([System.Environment]::UserDomainName).IsMember)"
        log-info "is ls on dc: $($wmiClass.IsLSonDC().OnDC)"
        log-info "is ls published in AD: $($wmiClass.IsLSPublished().Published)"
        log-info "is ls registered to SCP: $($wmiClass.IsLSRegisteredToSCP().Registered)"
        log-info "is ls security group enabled: $($wmiClass.IsLSSecGrpGPEnabled().Enabled)"
        log-info "is ls secure access allowed: $($wmiClass.IsSecureAccessAllowed($rdshServer).Allowed)"
        log-info "is rds in tsc group on ls: $($wmiClass.IsTSinTSCGroup($rdsshServer).IsMember)"
    }
    
    try
    {
        $ret = $rWmi.PingLicenseServer($licServer)
        $ret = $true
    }
    catch
    {
        $ret = $false
    }
    $retVal = $retVal -band $ret
    log-info "Can ping license server? $([bool]$ret)"
 
    $ret = $rWmi.CanAccessLicenseServer($licServer)
    $retVal = $retVal -band $ret
    log-info "Can access license server? $([bool]$ret.AccessAllowed)"
 
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
        9 { $retName = "LS_CONNECTABLE_VALID_WS08R2_VDI, R2 with VDI support (SP1 release)" }
        10 { $retName = "LS_CONNECTABLE_FEATURE_NOT_SUPPORTED" }
        11 { $retName = "LS_CONNECTABLE_VALID_LS" }
        default { $retName = "Unknown $($ret.TsToLsConnectivityStatus)" }
    }
    
    $retVal = $retVal -band ($ret.TsToLsConnectivityStatus -eq 9 -or $ret.TsToLsConnectivityStatus -eq 11)
    log-info "license connectivity status: $($retName)"
    
    return $retVal
}

# ----------------------------------------------------------------------------------------------------------------
function check-user ([string] $user)
{
    try
    {
        $strFilter = "(&(objectCategory=User)(samAccountName=$($user)))"

        $objDomain = New-Object System.DirectoryServices.DirectoryEntry

        $objSearcher = New-Object System.DirectoryServices.DirectorySearcher
        $objSearcher.SearchRoot = $objDomain
        $objSearcher.PageSize = 1000
        $objSearcher.Filter = $strFilter
        $objSearcher.SearchScope = "Subtree"

        # lic server user attributes for per user
        $colProplist = "msTSManagingLS","msTSExpireDate" #"name"
        foreach ($i in $colPropList)
        {
            $objSearcher.PropertiesToLoad.Add($i)
        }

        $colResults = $objSearcher.FindAll()

        foreach ($objResult in $colResults)
        {
            log-info "-------------------------------------"
            log-info "AD user:$($objresult.Properties["adspath"])"
            log-info "RDS CAL expire date:$($objresult.Properties["mstsexpiredate"])"
            log-ingo "RDS License Server Identity:$($objresult.Properties["mstsmanagingls"])"
        }
        
        return $true
    }
    catch
    {
        return $false
    }
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
function read-reg($machine, $hive, $key, $value, $subKeySearch = $true)
{
    $retVal = new-object Text.StringBuilder
    
    if([string]::IsNullOrEmpty($value))
    {
        [void]$retVal.AppendLine("-----------------------------------------")
        [void]$retVal.AppendLine("enumerating $($key)")
        $enumValue = $false
    }
    else
    {
        log-info "-----------------------------------------"
        log-info "enumerating $($key) for value $($value)"
        $enumValue = $true
    }
    
    try
    {
        $reg = [wmiclass]"\\$($machine)\root\default:StdRegprov"
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
                1{ 
                    $keyValue = $reg.GetStringValue($hive, $key, $sNames[$i]).sValue
                    if($enumValue)
                    {
                        return $keyValue
                    }
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)")
                    }
                }
                
                # REG_EXPAND_SZ 
                2{
                    $keyValue = $reg.GetExpandStringValue($hive, $key, $sNames[$i]).sValue
                    if($enumValue)
                    {
                        return $keyValue
                    }                    
                    else 
                    {
                         [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)") 
                    }
                }            
                
                # REG_BINARY 
                3{ 
                    $keyValue = (($reg.GetBinaryValue($hive, $key, $sNames[$i]).uValue) -join ',')
                    if($enumValue -and $displayBinaryBlob)
                    {
                        return $keyValue
                    }
                    elseif($displayBinaryBlob)
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)")
                    }
                    else
                    {
                        $blob = $reg.GetBinaryValue($hive, $key, $sNames[$i]).uValue
                        [void]$retval.AppendLine("$($sNames[$i]):(Binary Blob (length:$($blob.Length)))")
                    }
                }
                
                # REG_DWORD 
                4{ 
                    $keyValue = $reg.GetDWORDValue($hive, $key, $sNames[$i]).uValue
                    if($enumValue)
                    {
                        return $keyValue
                    }
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)")
                    } 
                }
                
                # REG_MULTI_SZ 
                7{
                    $keyValue = (($reg.GetMultiStringValue($hive, $key, $sNames[$i]).sValue) -join ',')
                    if($enumValue)
                    {
                        return $keyValue
                    }
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)") 
                    }
                }

                # REG_QWORD
                11{ 
                    $keyValue = $reg.GetQWORDValue($hive, $key, $sNames[$i]).uValue
                    if($enumValue)
                    {
                        return $keyValue
                    }
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)")
                    } 
                }
                
                # ERROR
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
                
                [void]$retval.AppendLine((read-reg -machine $machine -hive $hive -key "$($key)\$($subkey)"))
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
        # will always update once when copying from web page, then running -getUpdate due to CRLF diff between UNIX and WINDOWS
        # github can bet set to use WINDOWS style which may prevent this
        $webClient = new-object System.Net.WebClient
        $webClient.DownloadFile($updateUrl, "$($MyInvocation.ScriptName).new")
        if([string]::Compare([IO.File]::ReadAllBytes($MyInvocation.ScriptName), [IO.File]::ReadAllBytes("$($MyInvocation.ScriptName).new")))
        {
            log-info "downloaded new script"
            [IO.File]::Copy("$($MyInvocation.ScriptName).new",$MyInvocation.ScriptName, $true)
            [IO.File]::Delete("$($MyInvocation.ScriptName).new")
            log-info "restart to use new script. exiting."
            exit
        }
        else
        {
            log-info "script is up to date"
        }
        
        return $true
        
    }
    catch [System.Exception] 
    {
        log-info "get-update:exception: $($error)"
        $error.Clear()
        return $false    
    }
}

# ----------------------------------------------------------------------------------------------------------------
function get-sysInternalsUtility ([string] $utilityName)
{
    try
    {
        $destFile = "$(get-location)\$utilityName"
        
        if(![IO.File]::Exists($destFile))
        {
            $sysUrl = "http://live.sysinternals.com/$($utilityName)"

            write-host "Sysinternals process psexec.exe is needed for this option!" -ForegroundColor Yellow
            if((read-host "Is it ok to download $($sysUrl) ?[y:n]").ToLower().Contains('y'))
            {
                $webClient = new-object System.Net.WebClient
                $webClient.DownloadFile($sysUrl, $destFile)
                log-info "sysinternals utility $($utilityName) downloaded to $($destFile)"
            }
            else
            {
                return [string]::Empty
            }
        }

        return $destFile
    }
    catch
    {
        log-info "Exception downloading $($utilityName): $($error)"
        $error.Clear()
        return [string]::Empty
    }
}

# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    if(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).Identities.Name -eq "NT AUTHORITY\NETWORK SERVICE")
    {
        return $true
    }
    elseif (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
       log-info "please restart script as administrator. exiting..."
       return $false
    }

    return $true
}

# ----------------------------------------------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
{
    $Error.Clear()
    log-info "Running process $processName $arguments"
    $exitVal = 0
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = !$wait
    $process.StartInfo.RedirectStandardOutput = $wait
    $process.StartInfo.RedirectStandardError = $wait
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $wait
    $process.StartInfo.WorkingDirectory = get-location
    $process.StartInfo.ErrorDialog = $true
    $process.StartInfo.ErrorDialogParentHandle = ([Diagnostics.Process]::GetCurrentProcess()).Handle
    $process.StartInfo.LoadUserProfile = $false
    $process.StartInfo.WindowStyle = [Diagnostics.ProcessWindowstyle]::Normal


 
    [void]$process.Start()
 
    if($wait -and !$process.HasExited)
    {
 
        if($process.StandardOutput.Peek() -gt -1)
        {
            $stdOut = $process.StandardOutput.ReadToEnd()
            log-info $stdOut
        }
 
 
        if($process.StandardError.Peek() -gt -1)
        {
            $stdErr = $process.StandardError.ReadToEnd()
            log-info $stdErr
            $Error.Clear()
        }
            
    }
    elseif($wait)
    {
        log-info "Error:Process ended before capturing output."
    }
    
 
    
    $exitVal = $process.ExitCode
 
    log-info "Running process exit $($processName) : $($exitVal)"
    $Error.Clear()
 
    return $stdOut
}

# ----------------------------------------------------------------------------------------------------------------
main
