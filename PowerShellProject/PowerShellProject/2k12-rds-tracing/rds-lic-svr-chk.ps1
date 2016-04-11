<#  
.SYNOPSIS  
    powershell script to enumerate license server connectivity
.DESCRIPTION  
    This script will enumerate license server configuration off of an RDS server. it will check the known registry locations
    as well as run WMI tests against the configuration. a log file named rds-lic-svr-chk.txt will be generated that should
    be uploaded to support.
    
    ** Copyright (c) Microsoft Corporation. All rights reserved - 2016.
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
   File Name  : rds-lic-svr-chk.ps1  
   Author     : jagilber
   Version    : 160329
                
   History    : original

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
    [string] $licServer
    )
$error.Clear()
cls 
$ErrorActionPreference = "SilentlyContinue"
$logFile = "rds-lic-svr-chk.txt"
$licServers = @()

# ----------------------------------------------------------------------------------------------------------------
function main()
{ 
    log-info "-----------------------------------------"
    log-info "Win32_TerminalServiceSetting"
    log-info "-----------------------------------------"
 
    $rWmi = Get-WmiObject -Namespace root/cimv2/TerminalServices -Class Win32_TerminalServiceSetting
    log-info $rWmi
 
    if([string]::IsNullOrEmpty($licServer))
    {
        log-info "checking gpo for lic server"
        #--> HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\LicenseServers
        #--> HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows NT\Terminal Services\LicenseServers
        $licServers = @((read-reg 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\LicenseServers').ToString().Split(","))
   
    }
    else
    {
        $licServers = @($licServer)
    }

 
    if($licServers.Length -lt 1)
    {
        log-info "checking wmi for lic server"
        $licServers = @($rWmi.GetSpecifiedLicenseServerList().SpecifiedLSList)
    }
 
    if($licServers.Length -lt 1)
    {
        log-info "checking ps for lic server"
        $licServers = @((Get-RDLicenseConfiguration).LicenseServer.ToString().Split(","))
    }
 
    log-info (read-reg 'SYSTEM\CurrentControlSet\Control\Terminal Server\RCM')
 
    log-info (read-reg 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList\LicenseServers')
    log-info (read-reg 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList\LicensingMode')
 
    log-info (read-reg 'SYSTEM\CurrentControlSet\Services\TermService\Parameters\LicenseServers\SpecifiedLicenseServers')
    log-info (read-reg 'SYSTEM\CurrentControlSet\Services\TermService\Parameters\LicenseServers\LicensingMode')
 
    log-info (read-reg 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\LicenseServers')
    log-info (read-reg 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\LicensingMode')
 
    if($licServers.Length -lt 1)
    {
        log-info "license server has not been configured! exiting"
        exit
    }
 
    foreach($server in $licServers)
    {
        check-licenseServer -licserver $server
    }


    log-info "-----------------------------------------"
    log-info "finished" 
 
}
# ----------------------------------------------------------------------------------------------------------------

function check-licenseServer([string] $licserver)
{
    log-info "-----------------------------------------"
    log-info "-----------------------------------------"
    log-info "checking license server: $($licServer)"
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
                log-info ([string]::Format("{0,-20}: {1}", [IO.Path]::GetFileName($key) , ($baseKey.GetValue([IO.Path]::GetFileName($key)) -join ",")))
                return
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
        log-info ([string]::Format("{0,-20}: {1}", $valueName, ($value -join ",")))
        log-info ""
    }

    foreach($subkey in $baseKey.GetSubKeyNames())
    {
        read-reg "$($key)\$($subkey)"
    }

    $baseKey.Close();
}

# ----------------------------------------------------------------------------------------------------------------

main
