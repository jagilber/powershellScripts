<#  
.SYNOPSIS  
    powershell script to connect to quickstart rds deployments after deploying template

.DESCRIPTION  
    https://gallery.technet.microsoft.com/Azure-Resource-Manager-4ea7e328
    
    ** REQUIRES AT LEAST WMF 5.0 AND AZURERM SDK **
    script authenticates to azure rm 
    queries all resource groups for public ip name
    gives list of resource groups
    enumerates public ip of specified resource group
    downloads certificate from RDWeb
    adds cert to local machine trusted root store
    tries to resolve subject name in dns
    if not the same as public loadbalancer ip address it is added to hosts file
    
.NOTES  
   NOTE: to remove certs from all stores Get-ChildItem -Recurse -Path cert:\ -DnsName *<%subject%>* | Remove-Item
   File Name  : azure-rm-rdp-post-deploy.ps1
   Version    : 170510 updated git links
   History    : 
                170119 removed 'vm:' entries if ip address is 'not assigned'
                161230 changed runas-admin to call powershell with -executionpolicy bypass
                
.EXAMPLE  
    .\azure-rm-rdp-post-deploy.ps1
    query azure rm for all resource groups with for all public ips.

.PARAMETER noPrompt
    to not prompt when adding cert to cert store or when modifying hosts file
 
.PARAMETER resourceManagerName
    optional parameter to specify Resource Group Name

.PARAMETER publicIpAddressName
    optional parameter to override ip resource name public ip address

.PARAMETER update
    optional parameter to check for updated script from github

#>  
 

param(
    [Parameter(Mandatory=$false)]
    [string][ValidateSet('LocalMachine', 'CurrentUser')] $certLocation="LocalMachine",
    [Parameter(Mandatory=$false)]
    [switch]$noprompt,
    [Parameter(Mandatory=$false)]
    [switch]$noretry,
    [Parameter(Mandatory=$false)]
    [string]$publicIpAddressName = ".",
    [Parameter(Mandatory=$false)]
    [string]$resourceGroupName,
    [Parameter(Mandatory=$false)]
    [switch]$update
)

$ErrorActionPreference = "SilentlyContinue"
$hostsTag = "added by azure script"
$hostsFile = "$($env:windir)\system32\drivers\etc\hosts"
$global:resourceList = @{}
$updateUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/PowerShellProject/PowerShellProject/azure-rm-rdp-post-deployment.ps1"

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    cls
    $error.Clear()
    $subList = @{}
    $rg = $null
    $subject = $null
    $certInfo = $null

    write-host "starting script $($MyInvocation.ScriptName) to enumerate public ip addresses and RDWeb sites in Azure ARM"

    if($update -and (git-update -updateUrl $updateUrl -destinationFile $MyInvocation.ScriptName))
    {
        return
    }
    

    # make sure at least wmf 5.0 installed
    if($PSVersionTable.PSVersion -lt [version]"5.0.0.0")
    {
        write-host "update version of powershell to at least wmf 5.0. exiting..." -ForegroundColor Yellow
        start-process "https://www.bing.com/search?q=download+windows+management+framework+5.0"
        # start-process "https://www.microsoft.com/en-us/download/details.aspx?id=50395"
        return
    }

    if(($ret = runas-admin) -eq $false)
    {
        return
    }


    # authenticate
    try
    {
        Get-AzureRmResourceGroup | Out-Null
    }
    catch
    {
        try
        {
            Add-AzureRmAccount
        }
        catch [System.Management.Automation.CommandNotFoundException]
        {
            write-host "installing azurerm sdk. this will take a while..."
            
            install-module azurerm
            import-module azurerm

            Add-AzureRmAccount
        }
    }

    foreach($sub in get-subscriptions)
    {
        if(![string]::IsNullOrEmpty($sub.SubscriptionId))
        {
            Set-AzureRmContext -SubscriptionId $sub.SubscriptionId
            write-host "enumerating subscription $($sub.SubscriptionName) $($sub.SubscriptionId)"

            [int]$id = enum-resourcegroup $sub.SubscriptionId

            if($id -eq -1)
            {
                # no entries found
                return
            }

            $resourceGroup = $global:resourceList[$id].Values
            $ip = $global:resourceList[$id].Keys
        
            # enumerate resource group
            write-host "provision state: $($resourceGroup.ProvisioningState)"

            if(![string]::IsNullOrEmpty($ip.IpAddress))
            {
                write-host "public loadbalancer ip address: $($ip.IpAddress)"
                $gatewayUrl = "https://$($ip.IpAddress)/RDWeb"
            }

            # get certificate from RDWeb site
            $certFile = [IO.Path]::GetFullPath("$($resourceGroup.ResourceGroupName).cer")
            $cert = get-cert -url $gatewayUrl -fileName $certFile

            if($cert -eq $false -or [string]::IsNullOrEmpty($cert))
            {
                write-host "no cert. starting mstsc."
                # add to nag list
                New-ItemProperty -Path "HKCU:\Software\Microsoft\Terminal Server Client\LocalDevices" -Name $ip.IpAddress -Value 0xc5 -PropertyType DWORD -Force 
                run-process -processName "mstsc.exe" -arguments "/v $($ip.IpAddress) /admin" -wait $false
                return
            }

            $subject = $cert.Subject.Replace("CN=","")   
        
            if(![string]::IsNullOrEmpty($subject))
            {
                import-cert -cert $cert -certFile $certFile -subject $subject    
                add-hostsEntry -ipAddress $ip -subject $subject
                # launch RDWeb site
                Start-Process "https://$($subject)/RDWeb"
            }
        }
    }

    write-host "finished"
}

# ----------------------------------------------------------------------------------------------------------------
function add-hostsentry($ipAddress, $subject)
{
    # see if it needs to be added to hosts file
    $dnsresolve = (Resolve-DnsName -Name $subject -ErrorAction SilentlyContinue).IPAddress

    if($ip.IpAddress -ne $dnsresolve)
    {
        write-host "$($ip.IpAddress) not same as $($dnsresolve), checking hosts file"
        if(!$noPrompt -and (read-host "Is it ok to modify hosts file and add $($ipAddress)?[y|n]") -ieq 'n')
        {
            return $false
        }

        # check hosts file
        [string]$hostFileInfo = [IO.File]::ReadAllText($hostsFile)

        if($hostFileInfo -imatch $subject)
        {
            # remove from hosts file
            [IO.StreamReader]$rStream = [IO.File]::OpenText($hostsFile)
            $newhostFileInfo = New-Object Text.StringBuilder

            while(($line = $rStream.Readline()) -ne $null)
            {
                if(![regex]::IsMatch($line, "(\S+:\S+|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\s+?$($subject)"))
                {
                    $newhostFileInfo.AppendLine($line)
                }
                else
                {
                    write-host "removing $($line) from $($hostsFile)"
                }
            }

            $rStream.Close()
            [IO.File]::WriteAllText($hostsFile, $newhostFileInfo.ToString())
        }

        # add to hosts file
        $newEntry = "$($ip.IpAddress)`t$($subject)`t# $($hostsTag) $([IO.Path]::GetFileName($MyInvocation.ScriptName)) $([DateTime]::Now.ToShortDateString())`r`n"
        write-host "adding new entry:$($newEntry)"
                
        [IO.File]::AppendAllText($hostsFile,$newEntry)
        type $hostsFile
    }
    else
    {
        write-host "dns resolution for $($subject) same as loadbalancer ip:$($ip.IpAddress)"
    }
}

# ----------------------------------------------------------------------------------------------------------------
function enum-resourcegroup([string] $subid)
{
    write-verbose "enum-resourcegroup"
    $resourceGroup = $null
    $id = 0

    try
    {
        # find resource group
        if([string]::IsNullOrEmpty($resourceGroupName))
        {
            write-host "Azure RM resource groups with public IP addresses. Green indicates RDWeb site:"
            $Null = Set-AzureRmContext -SubscriptionId $subid
            $resourceGroups = Get-AzureRmResourceGroup -WarningAction SilentlyContinue
            $count = 1
        }
        else
        {
            $resourceGroups = @(Get-AzureRmResourceGroup -Name $resourceGroupName -WarningAction SilentlyContinue)
        }

        foreach($resourceGroup in $resourceGroups)
        {
            write-verbose "enumerating resourcegroup: $($resourcegroup.ResourceGroupName)"

            # check all vm's
            foreach($vm in (Get-AzureRmVM -ResourceGroupName $resourceGroup.ResourceGroupName -WarningAction SilentlyContinue))
            {
                write-verbose "checking vm: $($vm.Name)"
                       
                foreach($interface in ($vm.NetworkProfile.NetworkInterfaces.Id))
                {
                    $interfaceName = [IO.Path]::GetFileName($interface)
                    $publicIp = Get-AzureRmPublicIpAddress -Name $interfaceName -ResourceGroupName $resourceGroup.ResourceGroupName -ErrorAction SilentlyContinue
                    
                    if([string]::IsNullOrEmpty($publicIp) -or $publicIp.IpAddress -ieq "Not Assigned")
                    {
                        continue
                    }
                        
                    write-verbose "`t $($pubIp.Id)"

                    if($global:resourceList.Count -gt 0 -and $global:resourceList.Values.Keys.IpAddress.Contains($publicIp.IpAddress))
                    {
                        write-verbose "duplicate entry $($publicIp.IpAddress)"
                        continue
                    }
                        
                    [void]$global:resourceList.Add($count,@{$publicIp = $resourceGroup})
                    $message = "`r`n`tResource Group: $($resourceGroup.ResourceGroupName)`r`n`tIP name: $($publicIp.Name)`r`n`tIP address: $($publicIp.IpAddress)"
                    $message = "$($count). VM: mstsc.exe /v $($publicIp.IpAddress) /admin$($message)"
                    write-host $message                        

                    $count++
                }
            }

            # look for public ips
            foreach($pubIp in (query-publicIp -resourceName $resourceGroup.ResourceGroupName -ipName $publicIpAddressName))
            {
                if($pubIp.IpAddress.Length -le 1)
                {
                    continue
                }

                write-verbose "`t public ip: $($pubIp.Id)"
                if($global:resourceList.Count -gt 0 -and $global:resourceList.Values.Keys.IpAddress.Contains($pubIp.IpAddress))
                {
                    write-verbose "public ip duplicate entry"
                    continue
                }
                
                [void]$global:resourceList.Add($count,@{$pubIp = $resourceGroup})
                $rdwebUrl = "https://$($pubIp.IpAddress)/RDWeb"
                $message = "`r`n`tResource Group: $($resourceGroup.ResourceGroupName)`r`n`tIP name: $($pubIp.Name)`r`n`tIP address: $($pubIp.IpAddress)"
                
                if((get-cert -url $rdwebUrl) -eq $true)
                {
                    $message = "$($count). RDWEB: $($rdwebUrl)$($message)"
                    write-host $message -ForegroundColor Green
                }
                else
                {
                    $message = "$($count). PUBIP: mstsc.exe /v $($pubIp.IpAddress) /admin$($message)"
                    write-host $message
                }
                
                $count++
            }
        }

        if($global:resourceList.Count -gt 1)
        {
            [int]$id = Read-Host ("Enter number for site / ip address to connect to")
            if($id -isnot [int] -or $id -gt $global:resourceList.Count -or $id -lt 1)
            {
                write-host "invalid entry $($id). exiting script"
                return -1
            }
        }
        elseif($global:resourceList.Count -eq 1)
        {
            $id = 1
        }
        else
        {
            write-host "no ip addresses found. returning..."

            return -1
        }

        $resourceGroup = Get-AzureRmResourceGroup -Name $global:resourceList[$id].Values.ResourceGroupName -WarningAction SilentlyContinue
        write-host $resourceGroup.ResourceGroupName
        write-verbose "enum-resourcegroup returning:$($resourceGroup | fl | out-string)"

        return $id
    }
    catch
    {
        write-host "enum-resourcegroup:exception: $($error)"
        $error.Clear()
        return -1
    }
}

# ----------------------------------------------------------------------------------------------------------------
function get-cert([string] $url,[string] $fileName)
{
    write-verbose "get-cert:$($url) $($fileName)"

    $webRequest = [Net.WebRequest]::Create($url)
    $webRequest.Timeout = 1000 #ms

    try
    { 
        $webRequest.GetResponse() 
        return $true
    }
    catch { }

    try
    {
        $webRequest = [Net.WebRequest]::Create($url)
        $cert = $webRequest.ServicePoint.Certificate
        $bytes = $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)

        if($bytes.Length -gt 0)
        {
            if([string]::IsNullOrEmpty($filename))
            {
                return $true
            }

            $fileName = [IO.Path]::GetFullPath($fileName)

            if([IO.File]::Exists($fileName))
            {
                [IO.File]::Delete($fileName)
            }

            set-content -value $bytes -encoding byte -path $fileName
            $crt = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $crt.Import($fileName)

            return $crt
        }
        else
        {
            return $false
        }
    }
    catch
    {
        write-verbose "get-cert:error: $($error)"
        $error.Clear()
        return $false
    }
}

# ----------------------------------------------------------------------------------------------------------------
function get-gatewayUrl($resourceGroup)
{
    write-verbose "get-gatewayUrl $($resourceGroup)"

    $gatewayUrl = [string]::Empty
    write-host "provision state: $($resourceGroup.ProvisioningState)"
    
    # find public ip from loadbalancer
    $ip = query-publicIp -resourceName $resourceGroup.ResourceGroupName -ipName $publicIpAddressName

    if(![string]::IsNullOrEmpty($ip.IpAddress))
    {
        write-host "public loadbalancer ip address: $($ip.IpAddress)"
        $gatewayUrl = "https://$($ip.IpAddress)/RDWeb"
    }
    
    write-verbose "get-gatewayUrl returning:$($gatewayUrl)"
    return $gatewayUrl
}

# ----------------------------------------------------------------------------------------------------------------
function get-subscriptions()
{
    write-host "enumerating subscriptions"
    $subs = Get-AzureRmSubscription -WarningAction SilentlyContinue

    if($subs.Count -gt 1)
    {
        [int]$count = 1
        foreach($sub in $subs)
        {
            $message = "$($count). $($sub.SubscriptionName) $($sub.SubscriptionId)"
            Write-Host $message
            $subList.Add($count,$sub.SubscriptionId)
            $count++
        }
        
        [int]$id = Read-Host ("Enter number for subscription to enumerate or 0 to query all:")
        Set-AzureRmContext -SubscriptionId $subList[$id].ToString()

        if($id -ne 0)
        {
            $subs = Get-AzureRmSubscription -SubscriptionId $subList[$id].ToString() -WarningAction SilentlyContinue
        }
    }

    write-verbose "enum-resourcegroup returning:$($subs | fl | out-string)"
    return $subs
}

# ----------------------------------------------------------------------------------------------------------------
function git-update($updateUrl, $destinationFile)
{
    write-verbose "get-update:checking for updated script: $($updateUrl)"

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
            $fileClean = [regex]::Replace(([IO.File]::ReadAllBytes($destinationFile)), '\W+', "")
        }

        if(([string]::Compare($gitClean, $fileClean) -ne 0))
        {
            write-host "copying script $($destinationFile)"
            [IO.File]::WriteAllText($destinationFile, $git)
            write-host "script updated. restart script" -ForegroundColor Yellow
            return $true
        }
        else
        {
            write-host "script is up to date"
        }
        
        return $false
        
    }
    catch [System.Exception] 
    {
        write-host "get-update:exception: $($error)"
        $error.Clear()
        return $false    
    }
}

# ----------------------------------------------------------------------------------------------------------------
function import-cert($cert, $certFile, $subject)
{
    write-verbose "import-cert $($certFile) $($subject)"

    $certList = Get-ChildItem -Recurse -Path cert:\ -DnsName "$($subject)"

    # see if trusted or non-trusted
    if($cert.Subject -ieq $cert.Issuer)
    {
        # self signed
        $certStore = "Cert:\$($certLocation)\Root"
        write-host "cert is self-signed."
    }
    else
    {
        # trusted
        $certStore = "Cert:\$($certLocation)\My"
        write-host "cert is trusted. not importing..."
        # shouldnt need to be added
        return $false    
    }


    # see if cert needs to be imported
    if($certList.Count -gt 0)
    {
        write-host "$($certList.Count) certificates already installed $($subject) checking thumbprint"
        $count = 0
        foreach($c in $certList)
        {
            if($cert.Thumbprint -eq $c.Thumbprint)
            {
                write-host "cert has same thumbprint $($c.Subject) $($c.PSParentPath)"
                $count++
            }
            else
            {
                if((read-host "cert has different thumbprint, do you want to delete?[y|n]") -ilike 'y')
                {
                    remove-item $c.pspath -Force
                    $count--
                }
            }
        }

        if($count -gt 2)
        {
            # when importing to LocalMachine it shows up as CurrentUser and LocalMachine
            write "warning:cert with same thumbprint is in $($count) locations"
        }
    }
    
    $certList = Get-ChildItem -Recurse -Path cert:\ -DnsName "$($subject)"
    
    if($certList.Count -lt 1)
    {
        if(!$noprompt -and (read-host "Is it ok to import certificate from RDWeb site into local certificate store?[y|n]") -ieq 'n')
        {
            return $false
        }
        else
        {
            write-host "importing certificate:$($subject) into $($certStore)"
            $certFile = [IO.Path]::GetFullPath("$($resourceGroup.ResourceGroupName).cer")
            $certInfo = Import-Certificate -FilePath $certFile -CertStoreLocation $certStore
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function query-publicIp([string] $resourceName, [string] $ipName)
{
    write-verbose "query-publicIp $($resourceName) $($ipName)"

    $count = 0
    $returnList = New-Object Collections.ArrayList
    $ips = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceName
    $ipList = new-object Collections.ArrayList

    foreach($ip in $ips)
    {
        if([string]::IsNullOrEmpty($ip.IpAddress) -or $ip.IpAddress -eq "Not Assigned")
        {
            continue
        }

        if($ip.Name -imatch $ipName -and !$ipList.Contains($ip))
        {
            $ipList.Add($ip)
        }
    }

    write-verbose "get-publicIp returning: $($ipList | fl | out-string)"
    return $ipList
}

# ----------------------------------------------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
{
    write-host "Running process $processName $arguments"
    $exitVal = 0
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = $true
    $process.StartInfo.RedirectStandardOutput = $false
    $process.StartInfo.RedirectStandardError = $false
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $false
    $process.StartInfo.WorkingDirectory = get-location
    $process.StartInfo.Verb = "runas"
 
    $retval = $process.Start()
    if($wait -and !$process.HasExited)
    {
        $process.WaitForExit($processWaitMs)
        $exitVal = $process.ExitCode
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        write-host "Process output:$stdOut"
 
        if(![String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
        {
            #write-host "Error:$stdErr `n $Error"
            $Error.Clear()
        }
    }
    elseif($wait)
    {
        write-host "Process ended before capturing output."
    }
    
    return $retval
}

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
            if(($retval = run-process -processName "powershell.exe" -arguments "-ExecutionPolicy Bypass -File $($SCRIPT:MyInvocation.MyCommand.Path) -noretry") -eq $true)
            {
                return $false
            }
            else
            {
                write-host "error $($retval)"
                write-host "exiting script..."
                pause
            }
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
main

