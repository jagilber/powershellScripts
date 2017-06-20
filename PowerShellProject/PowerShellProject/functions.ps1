# general functions


# ----------------------------------------------------------------------------------------------------------------
function authenticate-azureRm()
{
    # make sure at least wmf 5.0 installed

    if ($PSVersionTable.PSVersion -lt [version]"5.0.0.0")
    {
        write-host "update version of powershell to at least wmf 5.0. exiting..." -ForegroundColor Yellow
        start-process "https://www.bing.com/search?q=download+windows+management+framework+5.0"
        # start-process "https://www.microsoft.com/en-us/download/details.aspx?id=50395"
        exit
    }

    #  verify NuGet package
	$nuget = get-packageprovider nuget -Force

	if (-not $nuget -or ($nuget.Version -lt [version]::New("2.8.5.22")))
	{
		write-host "installing nuget package..."
		install-packageprovider -name NuGet -minimumversion ([version]::New("2.8.5.201")) -force
	}

    $allModules = (get-module azure* -ListAvailable).Name
	#  install AzureRM module
	if ($allModules -inotcontains "AzureRM")
	{
        # each has different azurerm module requirements
        # installing azurerm slowest but complete method
        # if wanting to do minimum install, run the following script against script being deployed
        # https://raw.githubusercontent.com/jagilber/powershellScripts/master/PowerShellProject/PowerShellProject/script-azurerm-module-enumerator.ps1
        # this will parse scripts in given directory and output which azure modules are needed to populate the below

        # at least need profile, resources, insights, logicapp for this script
        if ($allModules -inotcontains "AzureRM.profile")
        {
            write-host "installing AzureRm.profile powershell module..."
            install-module AzureRM.profile -force
        }
        if ($allModules -inotcontains "AzureRM.resources")
        {
            write-host "installing AzureRm.resources powershell module..."
            install-module AzureRM.resources -force
        }
        if ($allModules -inotcontains "AzureRM.compute")
        {
            write-host "installing AzureRm.compute powershell module..."
            install-module AzureRM.compute -force
        }
        if ($allModules -inotcontains "AzureRM.network")
        {
            write-host "installing AzureRm.network powershell module..."
            install-module AzureRM.network -force

        }
            
        Import-Module azurerm.profile        
        Import-Module azurerm.resources        
        Import-Module azurerm.compute
        Import-Module azurerm.network
		#write-host "installing AzureRm powershell module..."
		#install-module AzureRM -force
        
	}
    else
    {
        Import-Module azurerm
    }

    # authenticate
    try
    {
        $rg = @(Get-AzureRmTenant)
                
        if($rg)
        {
            write-host "job:auth passed $($rg.Count)"
        }
        else
        {
            write-host "job:auth error $($error)" -ForegroundColor Yellow
            throw [Exception]
        }
    }
    catch
    {
        try
        {
            Add-AzureRmAccount
        }
        catch
        {
            write-host "exception authenticating. exiting $($error)" -ForegroundColor Yellow
            exit 1
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function get-workingDirectory()
{
    $retVal = [string]::Empty
 
    if (Test-Path variable:\hostinvocation)
    {
        $retVal = $hostinvocation.MyCommand.Path
    }
    else
    {
        $retVal = (get-variable myinvocation -scope script).Value.Mycommand.Definition
    }
  
    if (Test-Path $retVal)
    {
        $retVal = (Split-Path $retVal)
    }
    else
    {
        $retVal = (Get-Location).path
        log-info "get-workingDirectory: Powershell Host $($Host.name) may not be compatible with this function, the current directory $retVal will be used."
        
    } 
 
    
    Set-Location $retVal | out-null
 
    return $retVal
}

# ----------------------------------------------------------------------------------------------------------------
function get-subscriptions()
{
    write-host "enumerating subscriptions"
    $subList = @{}
    $subs = Get-AzureRmSubscription -WarningAction SilentlyContinue
    $newSubFormat = (get-module AzureRM.Resources).Version.ToString() -ge "4.0.0"
            
    if($subs.Count -gt 1)
    {
        [int]$count = 1
        foreach($sub in $subs)
        {
           if($newSubFormat)
           { 
                $message = "$($count). $($sub.name) $($sub.id)"
                $id = $sub.id
           }
           else
           {
                $message = "$($count). $($sub.SubscriptionName) $($sub.SubscriptionId)"
                $id = $sub.SubscriptionId
           }

            Write-Host $message
            [void]$subList.Add($count,$id)
            $count++
        }
        
        [int]$id = Read-Host ("Enter number for subscription to enumerate or {enter} to query all:")
        $null = Set-AzureRmContext -SubscriptionId $subList[$id].ToString()
        
        if($id -ne 0 -and $id -le $subs.count)
        {
            return $subList[$id]
        }
    }
    elseif($subs.Count -eq 1)
    {
        if($newSubFormat)
        {
            [void]$subList.Add("1",$subs.Id)
        }
        else
        {
            [void]$subList.Add("1",$subs.SubscriptionId)
        }
    }

    write-verbose "get-subscriptions returning:$($subs | fl | out-string)"
    return $subList.Values
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

            write-host "Sysinternals process $($utilityName) is needed for this option!" -ForegroundColor Yellow
            if((read-host "Is it ok to download $($sysUrl) ?[y:n]").ToLower().Contains('y'))
            {
                $webClient = new-object System.Net.WebClient
                $webclient.UseDefaultCredentials = $true
                #$webclient.Credentials = [Net.NetworkCredential](get-credential -UserName "$($env:USERDOMAIN)\$($env:USERNAME)" -Message "AZRDAV Sharepoint")
                [void]$webClient.DownloadFile($sysUrl, $destFile)
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


$updateUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/PowerShellProject/PowerShellProject/rds-lic-svr-chk.ps1"


#----------------------------------------------------------------------------
function get-update($updateUrl, $destinationFile)
{
    log-info "get-update:checking for updated script: $($updateUrl)"

    try 
    {
        $git = Invoke-RestMethod -Method Get -Uri $updateUrl 
        $gitClean = [regex]::Replace($git, '\W+', "")

        if(![IO.File]::Exists($destinationFile))
        {
            $fileClean = ""    
        }
        else
        {
            $fileClean = [regex]::Replace(([IO.File]::ReadAllText($destinationFile)), '\W+', "")
        }

        if(([string]::Compare($gitClean, $fileClean) -ne 0))
        {
            log-info "copying script $($destinationFile)"
            [IO.File]::WriteAllText($destinationFile, $git)
            return $true
        }
        else
        {
            log-info "script is up to date"
        }
        
        return $false
        
    }
    catch [System.Exception] 
    {
        log-info "get-update:exception: $($error)"
        $error.Clear()
        return $false    
    }
}

# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    $dataWritten = $false
    $data = "$([System.DateTime]::Now):$($data)`n"
    if([regex]::IsMatch($data.ToLower(),"error|exception|fail|warning"))
    {
        write-host $data -foregroundcolor Yellow
    }
    elseif([regex]::IsMatch($data.ToLower(),"running"))
    {
       write-host $data -foregroundcolor Green
    }
    elseif([regex]::IsMatch($data.ToLower(),"job completed"))
    {
       write-host $data -foregroundcolor Cyan
    }
    elseif([regex]::IsMatch($data.ToLower(),"starting"))
    {
       write-host $data -foregroundcolor Magenta
    }
    else
    {
        Write-Host $data
    }

    $counter = 0
    while(!$dataWritten -and $counter -lt 1000)
    {
        try
        {
            $ret = out-file -Append -InputObject $data -FilePath $logFile
            $dataWritten = $true
        }
        catch
        {
            Start-Sleep -Milliseconds 50
            $error.Clear()
            $counter++
        }
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
        [void]$retVal.AppendLine("-----------------------------------------")
        [void]$retVal.AppendLine("enumerating $($key) for value $($value)")
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
                    if($enumValue -or $displayBinaryBlob)
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
                
                read-reg -machine $machine -hive $hive -key "$($key)\$($subkey)"
            }
        }
        
        if($enumValue)
        {
            # no value
            return $null
        }
        else
        {
            return $retVal.ToString()
        }
    }
    catch
    {
        #"read-reg:exception $($error)"
        $error.Clear()
        return 
    }
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

$noretry
# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    write-verbose "checking for admin"
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        if(!$noretry)
        { 
            write-host "restarting script as administrator."
            Write-Host "run-process -processName powershell.exe -arguments -ExecutionPolicy Bypass -File $($SCRIPT:MyInvocation.MyCommand.Path) -noretry"
            run-process -processName "powershell.exe" -arguments "-ExecutionPolicy Bypass -File $($SCRIPT:MyInvocation.MyCommand.Path) -noretry" -wait $true
        }
       
        return $false
   }
   else
   {
        write-verbose "running as admin"

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

