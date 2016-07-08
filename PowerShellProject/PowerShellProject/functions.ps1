# general functions

$updateUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/PowerShellProject/PowerShellProject/rds-lic-svr-chk.ps1"

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


$HKCR = 2147483648 #HKEY_CLASSES_ROOT
$HKCU = 2147483649 #HKEY_CURRENT_USER
$HKLM = 2147483650 #HKEY_LOCAL_MACHINE
$HKUS = 2147483651 #HKEY_USERS
$HKCC = 2147483653 #HKEY_CURRENT_CONFIG

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
function runas-admin()
{
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
       log-info "please restart script as administrator. exiting..."
       return $false
    }

    return $true
}
# ----------------------------------------------------------------------------------------------------------------
