<#
different ways to enable remoting
winrm enable (source side):
    winrm set winrm/config/client '@{TrustedHosts="*"}'
winrm disable (source side):
    winrm set winrm/config/client '@{TrustedHosts=""}'

cmd:
    winrm quickconfig

powershell:
    enable-psremoting

firewall:
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False


run azure ps command on remote vm with no access:
if(!(get-module azurerm) -and !(get-module azurerm.compute))
{
    install-module azurerm.compute -force
}

Invoke-AzureRmVMRunCommand
      [-ResourceGroupName] <String>
      [-VMName] <String>
      -CommandId <String>
      [-ScriptPath <String>]
      [-Parameter <Hashtable>]
      [-AsJob]
      [-DefaultProfile <IAzureContextContainer>]
      [-WhatIf]
      [-Confirm]
      [<CommonParameters>]

CommandIds:

EnableRemotePS - Configure the machine to enable remote PowerShell. (Windows)
Ipconfig - List IP configuration (Windows)
ifconfig - List network configuration (Linux)
RunPowerShellScript - Executes a PowerShell script (Windows)
RunShellScript - Executes a Linux shell script
EnableAdminAccount - Enable administrator account (Windows)
ResetAccountPassword - Reset built-in Administrator account password (Windows)
RDPSettings - Verify RDP Listener Settings (Windows)
SetRDPPort - Set Remote Desktop port (Windows)
ResetRDPCert - Restore RDP Authentication mode to defaults (Windows)

example:
"Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False" | out-file c:\temp\disable-firewall.ps1
"get-netFirewallProfile | out-file c:\temp\fw.txt" | out-file c:\temp\disable-firewall.ps1 -Append
Invoke-AzureRmVMRunCommand -ResourceGroupName sfjagilbersa1 -VMName sfjagilbersa11 -CommandId RunPowerShellScript -ScriptPath c:\temp\disable-firewall.ps1

# type of dump configured for os
HKLM\SYSTEM\CurrentControlSet\Control\CrashControl
CrashDumpEnabled
REG_DWORD
0x0 No info recorded xxx <---- not useful
0x1 Complete dump <---- best option if space available
(pagefile = RAM + 1mB) Also used for Active Memory Dump (w/FilterPages key set = 1)
http://blogs.msdn.com/b/clustering/archive/2015/05/18/10615526.aspx
0x2 Kernel dump
0x3 Small (Mini) dump xxx <---- not useful
0x7 Automatic memory dump

#>

param(
    $remotemachine = ".", #"10.1.0.4",
    $workingDir = "c:\temp", #$env:TEMP,
    [switch]$downloadFilesOnly,
    [switch]$setupOnly,
    [string][ValidateSet('complete', 'kernel', 'automatic','none')] $setDumpType,
    [swith]$noRdp
)

$ErrorActionPreference = "Continue" #"SilentlyContinue"
$rdp = $false
$winrm = $false
$smb = $false
$startingDir = get-location
$fwEnabled = $false
$trustedHosts = $Null
$localhost = $false
$readOnly = $false
$crashControlRegKey = "SYSTEM\\CurrentControlSet\\Control\\CrashControl"
$crashDumpEnabled = "CrashDumpEnabled"

# -------------------------------------------------------------------------------------------------
function main()
{
    $ret = $false

    if (!(test-path $workingDir))
    {
        [io.directory]::CreateDirectory($workingDir)
    }

    Set-Location $workingDir
    $error.Clear()

    # set remotemachine if local to name that can be used for all commands
    if ($remotemachine -ieq "." -or $remotemachine -ieq "localhost")
    {
        $remotemachine = "127.0.0.1"
        $localhost = $true
    }

    if ($downloadFilesOnly)
    {
        download-files
        clean-up
        return
    }

    # setup local (source) machine for best chance of success
    $t = [regex]::matches((winrm get winrm/config/client) , "TrustedHosts = (.*)")
    $trustedHosts = $t.groups[1].value

    winrm set winrm/config/client '@{TrustedHosts="*"}'
    Enable-PSRemoting

    if ((Get-NetFirewallProfile).Enabled -eq "True")
    {
        $fwEnabled = $true
        Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False
    }

    $rdp = check-port -port 3389 -name "rdp" -remotemachine $remotemachine
    $winrm = check-port -port 5985 -name "winrm/wmi/psremote" -remotemachine $remotemachine
    $smb = check-port -port 445 -name "smb/psexec" -remotemachine $remotemachine
    
    if (!($rdp + $winrm + $smb))
    {
        Write-Error "no remote connectivity exists to $($remotemachine)."# exiting script!"
        #return
    }

    if ($rdp -and !$setupOnly -and !$noRdp)
    {
        if ((read-host "rdp port is open and should be used if possible. do you want to connect to remote machine using rdp? [y|n]") -icontains "y")
        {
            Start-Process -FilePath "mstsc.exe" -ArgumentList "/v $($ip.IpAddress) /admin" -wait $false
            return
        }
    }

    if ($winrm)
    {
        $ret = check-regWinRM
    }
    
    if (!$ret -and $smb)
    {
        $ret = check-regSmb        
    }
    
    if(!$ret -and $localhost)
    {
        $ret = check-regLocal
    }

    clean-up

    if(!$ret)
    {
        write-warning "unable to check / set dump type on $($remotemachine)"
    }

    write-host "finished"
}

# -------------------------------------------------------------------------------------------------
function check-port($port, $name, $remotemachine)
{
    if ((Test-NetConnection -Port $port -computername $remotemachine))
    {
        write-host "able to ping $($name) $($port) port $($remotemachine)" -ForegroundColor Green
        return $true
    }
    else
    {
        Write-Warning "unable to ping $($name) $($port) port $($remotemachine)"
        return $false
    }

}

# -------------------------------------------------------------------------------------------------
function clean-up()
{
    if ($trustedHosts)
    {
        # set local machine back
        winrm set winrm/config/client "@{TrustedHosts="$($trustedHosts)"}"
    }

    if ($fwEnabled)
    {
        Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True
    }

    Set-Location $startingDir
}

# -------------------------------------------------------------------------------------------------
function download-files()
{
    $error.Clear()
    [System.Net.ServicePointManager]::Expect100Continue = $true;
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
    $psexecSource = "https://live.sysinternals.com/psexec.exe"
    $psexecDest = "$(get-location)\psexec.exe"

    if (!(test-path $psexecDest))
    {
        write-host "downloading $($psexecSource) to $($psexecDest)" -ForegroundColor Yellow
        (new-object net.webclient).DownloadFile($psexecSource, $psexecDest)
    }
    else
    {
        write-host "$($psexecDest) exists" -ForegroundColor Green
    }

    $notMyFaultSource = "https://download.sysinternals.com/files/NotMyFault.zip"
    $notMyFaultDest = "$(get-location)\notmyfault.zip"

    if (!(test-path $notMyFaultSource))
    {
        write-host "downloading $($notMyFaultSource) to $($notMyFaultDest)" -ForegroundColor Yello
        (new-object net.webclient).DownloadFile($notMyFaultSource, $notMyFaultDest)
    }
    else
    {
        write-host "$($notMyFaultSource) exists" -ForegroundColor Green
    }

    Expand-Archive $notMyFaultDest ([io.path]::GetFileNameWithoutExtension($notMyFaultDest))
    write-host "execute $(get-location)\notmyfault\notmyfault64.exe when ready to capture dump and force restart of machine" -ForegroundColor Yellow

    if ($error)
    {
        Write-Error "error downloading files. $($error | out-string)"
        $error.Clear()
    }

    return $false
}
# -------------------------------------------------------------------------------------------------

function check-regLocal()
{
    $ret = $true

    if ($localhost)
    {
        write-host "checking local registry"
        $dumpType = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\$($crashControlRegKey)" -name $crashDumpEnabled).CrashDumpEnabled
        write-host "current CrashControl value: $($dumpType)"
        $newDumpType = set-dumpType -dumpType $dumpType

        if ($newDumpType)
        {
            $error.Clear()
            $ret = Set-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\$($crashControlRegKey)" -name $crashDumpEnabled -Value $newDumpType
            $ret
            $ret = restart-machine
        }
    }
    else
    {
        write-host "checking local registry: $($localhost) not local machine"
        $ret = $false
    }

    return $ret
}
# -------------------------------------------------------------------------------------------------
function check-regSmb()
{
    write-host "checking remote registry with smb"
    # HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\CrashControl
    # CrashDumpEnabled    REG_DWORD    0x7
    $pattern = "0x(.)"
    $dumpString = (reg query "\\$($remotemachine)\HKLM\$($crashcontrolregkey.Replace("\\","\"))" /v $crashDumpEnabled)
    $ret = $true

    if([regex]::IsMatch($dumpString, $pattern))
    {
        $dumpType = [regex]::Match($dumpString, $pattern).Groups[1].Value
        write-host "current CrashControl value: $($dumpType)"
        $newDumpType = set-dumpType -dumpType $dumpType

        if ($newDumpType)
        {
            $error.Clear()
            $ret = Set-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\$($crashControlRegKey)" -name $crashDumpEnabled -Value $newDumpType
            $ret
            $ret = restart-machine
        }
    }
    else
    {
        write-error "checking remote registry with smb failed $($dumpstring)"
        $ret = $false
    }

    return $ret
}
# -------------------------------------------------------------------------------------------------
function check-regWinRM()
{
    write-host "checking winrm crash dump settings. settings should typically be 1 = complete, 2 = kernel, or 7 = automatic kernel" -ForegroundColor Cyan
    $ret = $true
    $Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $remotemachine)
    $RegKey = $Reg.OpenSubKey($crashControlRegKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
    
    if ($error -or !$RegKey)
    {
        Write-Warning "unable to open CrashControl key for writing"
        $error.Clear()
        $readonly = $true
    }

    $RegKey = $Reg.OpenSubKey($crashControlRegKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadSubTree)
    
    if ($error -or !$RegKey)
    {
        Write-Error "unable to open CrashControl key for reading. returning"
        return $false
    }

    $dumpType = $RegKey.GetValue($crashDumpEnabled)
    write-host "current CrashControl value: $($dumpType)"

    if (!$readOnly)
    {
        $newDumpType = set-dumpType -dumpType $dumpType

        if ($newDumpType)
        {
            $error.Clear()
            $ret = $RegKey.SetValue($crashDumpEnabled, $newDumpType, [Microsoft.Win32.RegistryValueKind]::DWord)
            $ret
            $ret = restart-machine
        }
    }

    if(!$ret -or $readOnly)
    {
        return $false
    }
    else
    {
        return $true
    }
}
# -------------------------------------------------------------------------------------------------

function restart-machine()
{
    
    if (!$error)
    {
        $reboot = read-host "changes to CrashDumpEnabled *require* machine to be rebooted for setting to take effect. Do you want to do this now? [y|n]"

        if ($reboot -icontains "y")
        {
            write-host "restarting $($remotemachine). please wait..."
            Restart-Computer -ComputerName $remotemachine -Wait
            
            if ($error)
            {
                write-error "error restarting machine: $($error | out-string)"
                return $false
            }
            else
            {
                return $true
            }
        }
    }
    else
    {
        Write-Error "error setting CrashDumpEnabled value to $($newDumpType). $($error | out-string) exiting"
        return $false
    }
}

# -------------------------------------------------------------------------------------------------
function set-dumpType($dumpType)
{
    $newDumpType = $Null
    
    if($setDumpType)
    {
        
        switch($setDumpType.tolower())
        {
            'complete' { $newDumpType = 1 }
            'kernel' { $newDumpType = 2 }
            'automatic' { $newDumpType = 7 }
            'none' { $newDumpType = 0 }
            default { Write-Error "unknown option $($setDumpType)" }
        }
    }
    else
    {
        write-host "do you want to enable / change dump type on $($remotemachine)?" -ForegroundColor Yellow
        $newDumpType = read-host "if so, enter number for type (1 = complete 2 = kernel 7 = automatic kernel) or select {enter} to continue with no change:"
    }    

    if ($newDumpType -and ($newDumpType -ine $dumpType))
    {
        write-host "setting dump type to $($newDumptype)" -foreground yellow
        return $newDumpType
    }
    else
    {
        return $null
    }

}
# -------------------------------------------------------------------------------------------------

main
