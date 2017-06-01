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
    
    start with -verbose if you need to troubleshoot script

.NOTES  
   NOTE: to remove certs from all stores Get-ChildItem -Recurse -Path cert:\ -DnsName *<%subject%>* | Remove-Item
   File Name  : azure-rm-rdp-post-deployment.ps1
   Version    : 170601 fix for wildcard certs
   History    : 
                170524 another change for azurerm.resources coming back not as collection for single sub?
                170405 cleaned up and added -rdWebUrl
                161230 changed runas-admin to call powershell with -executionpolicy bypass
.EXAMPLE  
    .\azure-rm-rdp-post-deployment.ps1
    query azure rm for all resource groups with for all public ips.

.EXAMPLE
    .\azure-rm-rdp-post-deployment.ps1 -rdWebUrl https://contoso.eastus.cloudapp.azure.com/RDWeb
    used to bypass Azure enumeration and to copy cert from url to local cert store

.PARAMETER noPrompt
    to not prompt when adding cert to cert store or when modifying hosts file
 
.PARAMETER rdWebUrl
    used to pass complete RDWeb url to script to bypass Azure enumeration. will add self-signed cert to cert store.

.PARAMETER resourceManagerName
    optional parameter to specify Resource Group Name

.PARAMETER publicIpAddressName
    optional parameter to override ip resource name public ip address

.PARAMETER update
    optional parameter to check for updated script from github

#>  
 

param(
    [Parameter(Mandatory = $false)]
    [string][ValidateSet('LocalMachine', 'CurrentUser')] $certLocation = "LocalMachine",
    [Parameter(Mandatory = $false)]
    [switch]$noprompt,
    [Parameter(Mandatory = $false)]
    [switch]$noretry,
    [Parameter(Mandatory = $false)]
    [string]$publicIpAddressName = ".",
    [Parameter(Mandatory = $false)]
    [string]$rdWebUrl = "",
    [Parameter(Mandatory = $false)]
    [string]$resourceGroupName,
    [Parameter(Mandatory = $false)]
    [switch]$update
)

$ErrorActionPreference = "SilentlyContinue"
$WarningPreference = "SilentlyContinue"
$global:resourceList = @{}
$global:selfSigned = $false
$global:san = $false
$global:wildcard = $false
$hostsTag = "added by azure script"
$hostsFile = "$($env:windir)\system32\drivers\etc\hosts"
$updateUrl = "https://aka.ms/azure-rm-rdp-post-deployment.ps1"

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    cls
    $error.Clear()
    $subList = @{}
    $rg = $null
    $subject = $null
    $certInfo = $null

    write-host "starting script $($MyInvocation.ScriptName) to enumerate public ip addresses and RDWeb sites in Azure RM"

    if ($update -and (get-update -updateUrl $updateUrl -destinationFile $MyInvocation.ScriptName))
    {
        return
    }
    
    # need to run as admin
    if (($ret = runas-admin) -eq $false)
    {
        return
    }

    if ($rdWebUrl)
    {
        # go directly to url
        write-host "connecting to rdWebUrl $($rdWebUrl)"
        $certFile = [IO.Path]::GetFullPath("$($rdWebUrl -replace '\W','').cer")
        $cert = get-cert -url $rdWebUrl -certFile $certFile
        $subject = enum-certSubject -cert $cert
        $subject = import-cert -cert $cert -certFile $certFile -subject $subject
        
        if ($subject)
        {
            $ipv4 = ([regex]::Matches($rdWebUrl, "((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])")).Captures
            
            if ($ipv4)
            {
                add-hostsEntry -ipAddress $ipv4[0].Value -subject $subject
            }

            open-RdWebSite -site $rdWebUrl
            return
        }
    }
    
    # connect to azure
    # make sure at least wmf 5.0 installed

    if ($PSVersionTable.PSVersion -lt [version]"5.0.0.0")
    {
        write-host "update version of powershell to at least wmf 5.0. exiting..." -ForegroundColor Yellow
        start-process "https://www.bing.com/search?q=download+windows+management+framework+5.0"
        # start-process "https://www.microsoft.com/en-us/download/details.aspx?id=50395"
        return
    }

    authenticate-azureRm
    $subscriptions = get-subscriptions
    $redisplay = $true

    while ($redisplay -and $subscriptions.Count -gt 0)
    {
        foreach ($sub in $subscriptions)
        {
            $global:resourceList.Clear()

            if ([string]::IsNullOrEmpty($sub))
            {
                continue
            }

            Set-AzureRmContext -SubscriptionId $sub
            write-host "enumerating subscription $($sub)"

            if (!(enum-resourcegroup $sub))
            {
                continue
            }

            if ($global:resourceList.Count -gt 1)
            {
                $idsEntry = Read-Host ("Enter number for site / ip address to connect to")
            }
            elseif ($global:resourceList.Count -eq 1)
            {
                $id = 1
            }
            else
            {
                write-host "no ip addresses found. returning..."

                exit 1
            }

            #check ids for comma and range
            if ($idsEntry.ToLower().Contains("c"))
            {
                # redisplay list to choose again
                $idsEntry = $idsEntry.ToLower().Replace("c", "")
            }
            else
            {
                $redisplay = $false
            }

            if ($idsEntry.Contains(","))
            {
                $ids = @($idsEntry.Split(","))
            }
            else
            {
                $ids = @($idsEntry)
            }

            foreach ($id in $ids)
            {
                if (!([Convert]::ToInt32($id)) -or $id -gt $global:resourceList.Count -or $id -lt 1)
                {
                    write-host "invalid entry $($id)..."
                    continue
                }

                [int]$id = [Convert]::ToInt32($id)

                $resourceGroup = Get-AzureRmResourceGroup -Name $global:resourceList[$id].Values.ResourceGroupName -WarningAction SilentlyContinue
                write-host $resourceGroup.ResourceGroupName
                write-verbose "enum-resourcegroup returning:$($resourceGroup | fl | out-string)"

                $resourceGroup = $global:resourceList[$id].Values
                $ip = $global:resourceList[$id].Keys
        
                # enumerate resource group
                write-host "provision state: $($resourceGroup.ProvisioningState)"

                if (![string]::IsNullOrEmpty($ip.IpAddress))
                {
                    write-host "public loadbalancer ip address: $($ip.IpAddress)"
                    $gatewayUrl = "https://$($ip.IpAddress)/RDWeb"
                }
                
                $certFile = [IO.Path]::GetFullPath("$($gatewayUrl -replace '\W','').cer")
                $cert = get-cert -url $gatewayUrl -certFile $certFile
                $subject = enum-certSubject -cert $cert

                if ($subject -eq $false)
                {
                    start-mstsc -ip $ip
                }
                else
                {
                    $subject = import-cert -cert $cert -certFile $certFile -subject $subject    
                    add-hostsEntry -ipAddress $ip -subject $subject
                    open-RdWebSite -site "https://$($subject)/RDWeb"
                }
            }
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function add-hostsEntry($ipAddress, $subject)
{
    # see if it needs to be added to hosts file
    $dnsresolve = (Resolve-DnsName -Name $subject -ErrorAction SilentlyContinue).IPAddress

    if (!(@($dnsresolve).Contains($ip.IpAddress)))
    {
        write-host "$($ip.IpAddress) not same as $($dnsresolve), checking hosts file"
        if (!$noPrompt -and (read-host "Is it ok to modify hosts file and add $($ipAddress)?[y|n]") -ieq 'n')
        {
            return $false
        }

        # check hosts file
        [string]$hostFileInfo = [IO.File]::ReadAllText($hostsFile)

        if ($hostFileInfo -imatch $subject)
        {
            # remove from hosts file
            [IO.StreamReader]$rStream = [IO.File]::OpenText($hostsFile)
            $newhostFileInfo = New-Object Text.StringBuilder

            while (($line = $rStream.Readline()) -ne $null)
            {
                if (![regex]::IsMatch($line, "(\S+:\S+|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\s+?$($subject)"))
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
                
        [IO.File]::AppendAllText($hostsFile, $newEntry)
        type $hostsFile
    }
    else
    {
        write-host "dns resolution for $($subject) same as loadbalancer ip:$($ip.IpAddress)"
    }
}

# ----------------------------------------------------------------------------------------------------------------
function authenticate-azureRm()
{
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
}

# ----------------------------------------------------------------------------------------------------------------
function enum-certSubject($cert)
{
    # get certificate from RDWeb site

    if ($cert -eq $false -or [string]::IsNullOrEmpty($cert))
    {
        write-host "no cert!"
        return $false
    }

    $subject = $cert.Subject.Replace("CN=", "")   
        
    if (![string]::IsNullOrEmpty($subject))
    {
        return $subject
    }

    return $false
}

# ----------------------------------------------------------------------------------------------------------------
function enum-resourcegroup([string] $subid)
{
    write-verbose "enum-resourcegroup"
    $resourceGroup = $null
    $id = 0
    $message = ""

    try
    {
        # find resource group
        if ([string]::IsNullOrEmpty($resourceGroupName))
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

        foreach ($resourceGroup in $resourceGroups)
        {
            write-verbose "enumerating resourcegroup: $($resourcegroup.ResourceGroupName)"

            # check all vm's
            foreach ($vm in (Get-AzureRmVM -ResourceGroupName $resourceGroup.ResourceGroupName -ErrorAction SilentlyContinue))
            {
                write-verbose "checking vm: $($vm.Name)"
                       
                foreach ($interface in ($vm.NetworkProfile.NetworkInterfaces.Id))
                {
                    $interfaceName = [IO.Path]::GetFileName($interface)
                    $publicIp = Get-AzureRmPublicIpAddress -Name $interfaceName -ResourceGroupName $resourceGroup.ResourceGroupName -ErrorAction SilentlyContinue
                    
                    if ([string]::IsNullOrEmpty($publicIp))
                    {
                        continue
                    }
                        
                    write-verbose "`t $($pubIp.Id)"

                    if ($global:resourceList.Count -gt 0 -and $global:resourceList.Values.Keys.IpAddress.Contains($publicIp.IpAddress))
                    {
                        write-verbose "duplicate entry $($publicIp.IpAddress)"
                        continue
                    }
                        
                    [void]$global:resourceList.Add($count, @{$publicIp = $resourceGroup})
                    $message = "`r`n`tResource Group: $($resourceGroup.ResourceGroupName)`r`n`tIP name: $($publicIp.Name)`r`n`tIP address: $($publicIp.IpAddress)"
                    $message = "$($count). VM: mstsc.exe /v $($publicIp.IpAddress) /admin$($message)"
                    write-host $message                        

                    $count++
                }
            }

            # look for public ips
            foreach ($pubIp in (query-publicIp -resourceName $resourceGroup.ResourceGroupName -ipName $publicIpAddressName))
            {
                if ($pubIp.IpAddress.Length -le 1)
                {
                    continue
                }

                write-verbose "`t public ip: $($pubIp.Id)"
                if ($global:resourceList.Count -gt 0 -and $global:resourceList.Values.Keys.IpAddress.Contains($pubIp.IpAddress))
                {
                    write-verbose "public ip duplicate entry"
                    continue
                }
                
                [void]$global:resourceList.Add($count, @{$pubIp = $resourceGroup})
                $rdwebUrl = "https://$($pubIp.IpAddress)/RDWeb"
                $message = "`r`n`tResource Group: $($resourceGroup.ResourceGroupName)`r`n`tIP name: $($pubIp.Name)`r`n`tIP address: $($pubIp.IpAddress)"
                
                $certInfo = (get-cert -url $rdwebUrl)

                if (![string]::IsNullOrEmpty($certInfo) -and $certInfo -ne $false)
                {
                    $message = "$($count). RDWEB: $($rdwebUrl)$($message)`r`n`tCert Subject: $($certInfo.Subject)"
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

        return $true
    }
    catch
    {
        write-host "enum-resourcegroup:exception: $($error)"
        $error.Clear()
        return $false
    }
}

# ----------------------------------------------------------------------------------------------------------------
function get-cert([string] $url, [string] $certFile)
{
    write-verbose "get-cert:$($url) $($certFile)"
    $error.Clear()
    $webRequest = [Net.WebRequest]::Create($url)
    $webRequest.Timeout = 1000 #ms

    try
    { 
        $webRequest.GetResponse() 
        # return $null
    }
    catch 
    {
        write-verbose "get-cert:first catch getresponse: $($url) $($certFile) $($error)" 
        $error.Clear()
    }

    try
    {
        $webRequest = [Net.WebRequest]::Create($url)
        $crt = $webRequest.ServicePoint.Certificate
        Write-Verbose "checking cert: $($crt | fl * | Out-String)"

        $bytes = $crt.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)

        if ($bytes.Length -gt 0)
        {
            if ([string]::IsNullOrEmpty($certFile))
            {
                $certFile = "$($url -replace '\W','').cer"
            }

            $certFile = [IO.Path]::GetFullPath($certFile)

            if ([IO.File]::Exists($certFile))
            {
                [IO.File]::Delete($certFile)
            }

            set-content -value $bytes -encoding byte -path $certFile
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $cert.Import($certFile)

            return $cert
        }
        else
        {
            return $null
        }
    }
    catch
    {
        write-verbose "get-cert:error: $($error)"
        $error.Clear()
        return $null
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

    if (![string]::IsNullOrEmpty($ip.IpAddress))
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
    $subList = @{}
    $subs = @(Get-AzureRmSubscription -WarningAction SilentlyContinue)
    $newSubFormat = (get-module AzureRM.Resources -ListAvailable).Version.ToString() -ge "4.0.0"
            
    if ($subs.Count -gt 1)
    {
        [int]$count = 1
        foreach ($sub in $subs)
        {
            if ($newSubFormat)
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
            [void]$subList.Add($count, $id)
            $count++
        }
        
        [int]$id = Read-Host ("Enter number for subscription to enumerate or {enter} to query all:")
        $null = Set-AzureRmContext -SubscriptionId $subList[$id].ToString()
        
        if ($id -ne 0 -and $id -le $subs.count)
        {
            return $subList[$id]
        }
    }
    elseif ($subs.Count -eq 1)
    {
        if ($newSubFormat)
        {
            [void]$subList.Add("1", $subs.Id)
        }
        else
        {
            [void]$subList.Add("1", $subs.SubscriptionId)
        }
    }

    write-verbose "get-subscriptions returning:$($subs | fl | out-string)"
    return $subList.Values
}

# ----------------------------------------------------------------------------------------------------------------
function get-update($updateUrl, $destinationFile)
{
    write-verbose "get-update:checking for updated script: $($updateUrl)"

    try 
    {
        $git = Invoke-RestMethod -Method Get -Uri $updateUrl 
        $gitClean = [regex]::Replace($git, '\W+', "")

        if (![IO.File]::Exists($destinationFile))
        {
            $fileClean = ""    
        }
        else
        {
            $fileClean = [regex]::Replace(([IO.File]::ReadAllText($destinationFile)), '\W+', "")
        }

        if (([string]::Compare($gitClean, $fileClean) -ne 0))
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
    if ([string]::IsNullOrEmpty($subject))
    {
        Write-Warning "import-cert:error: subject empty. returning"
        return $false
    }

    if (![IO.File]::Exists($certFile))
    {
        Write-Warning "import-cert:error: certfile not found. returning"
        return $false
    }

    $certList = Get-ChildItem -Recurse -Path cert:\ -DnsName "$($subject)"
    $certSubject = $cert.Subject.Replace("CN=", "").Split(",")[0]

    # see if trusted or non-trusted
    if ($cert.Subject -ieq $cert.Issuer)
    {
        # self signed
        $certStore = "cert:\$($certLocation)\Root"
        $global:selfSigned = $true
    }
    else
    {
        # trusted
        $certStore = "cert:\$($certLocation)\My"
        write-host "cert is trusted. not importing..."
        # shouldnt need to be added
        return $true    
    }
    
    write-host "cert '$certSubject' is self signed:'$global:selfSigned'"
    
    if ($certSubject.StartsWith("*"))
    {
        $global:wildcard = $true   
    }

    write-host "cert '$certSubject' is wildcard:'$global:wildcard'"

    if ($cert.DnsNameList.Count -gt 1)
    {
        write-host $cert.DnsNameList
        $global:san = $true   
    }

    write-host "cert '$certSubject' is SAN cert:'$global:san'"


    # see if cert needs to be imported
    if ($certList.Count -gt 0)
    {
        write-host "$($certList.Count) certificates already installed $($subject) checking thumbprint"
        $count = 0
        foreach ($c in $certList)
        {
            if ($cert.Thumbprint -eq $c.Thumbprint)
            {
                write-host "cert has same thumbprint $($c.Subject) $($c.PSParentPath)"
                $count++
            }
            else
            {
                if ((read-host "cert has different thumbprint, do you want to delete?[y|n]") -ilike 'y')
                {
                    remove-item $c.pspath -Force
                    $count--
                }
            }
        }

        if ($count -gt 2)
        {
            # when importing to LocalMachine it shows up as CurrentUser and LocalMachine
            Write-Warning "warning:cert with same thumbprint is in $($count) locations"
        }
    }
    
    $certList = Get-ChildItem -Recurse -Path cert:\ -DnsName "$($subject)"
    
    if ($certList.Count -lt 1)
    {
        if (!$noprompt -and (read-host "Is it ok to import certificate from RDWeb site into local certificate store?[y|n]") -ieq 'n')
        {
            return $subject
        }
        else
        {
            # installs into personal and local when local is set
            write-host "importing certificate:$($subject) into $($certStore)"
            $certInfo = Import-Certificate -FilePath $certFile -CertStoreLocation $certStore
        }
    }

    # if wildcard prompt for name for hosts entry
    if ($global:wildcard)
    {
        write-host "certificate is wildcard. what host name do you want to use to connect to RDWeb site?"
        $hostName = "$($resourceGroup.ResourceGroupName)$($subject.Replace('*',''))"    
        write-host "https://$($hostname)/RDWeb"    
        $ret = read-host "select {enter} to continue with above name, or type in hostname to use, or {ctrl-c} to quit:"
                        
        if (!$ret)
        {
            $subject = $hostname
        }
        else
        {
            $subject = "$($ret).$($subject.Replace('*',''))"
        }

    }
                    
    write-host "using $($subject) as hostname"
    return $subject
}

# ----------------------------------------------------------------------------------------------------------------
function open-RdWebSite($site)
{
    # launch RDWeb site
    Start-Process $site
}

# ----------------------------------------------------------------------------------------------------------------
function query-publicIp([string] $resourceName, [string] $ipName)
{
    write-verbose "query-publicIp $($resourceName) $($ipName)"

    $count = 0
    $returnList = New-Object Collections.ArrayList
    $ips = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceName
    $ipList = new-object Collections.ArrayList

    foreach ($ip in $ips)
    {
        if ([string]::IsNullOrEmpty($ip.IpAddress) -or $ip.IpAddress -eq "Not Assigned")
        {
            continue
        }

        if ($ip.Name -imatch $ipName -and !$ipList.Contains($ip))
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
    if ($wait -and !$process.HasExited)
    {
        $process.WaitForExit($processWaitMs)
        $exitVal = $process.ExitCode
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        write-host "Process output:$stdOut"
 
        if (![String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
        {
            #write-host "Error:$stdErr `n $Error"
            $Error.Clear()
        }
    }
    elseif ($wait)
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
        if (!$noretry)
        { 
            write-host "restarting script as administrator."
            Write-Host "run-process -processName powershell.exe -arguments -ExecutionPolicy Bypass -File $($SCRIPT:MyInvocation.MyCommand.Path) -noretry"
            if (($retval = run-process -processName "powershell.exe" -arguments "-NoExit -ExecutionPolicy Bypass -File $($SCRIPT:MyInvocation.MyCommand.Path) -noretry") -eq $true)
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
function start-mstsc($ip)
{
    write-host "starting mstsc."
    # add to nag list
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Terminal Server Client\LocalDevices" -Name $ip.IpAddress -Value 0xc5 -PropertyType DWORD -Force 
    run-process -processName "mstsc.exe" -arguments "/v $($ip.IpAddress) /admin" -wait $false
}

# ----------------------------------------------------------------------------------------------------------------
main
write-host "finished"

