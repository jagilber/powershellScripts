<#  
.SYNOPSIS  
    powershell script to connect to quickstart rds deployments after deploying template

.DESCRIPTION  
    https://gallery.technet.microsoft.com/Azure-Resource-Manager-4ea7e328
    
    ** REQUIRES AT LEAST WMF 5.0 AND az SDK **
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
   File Name  : azure-az-rdp-post-deployment.ps1
   Version    : 180721 fix issue where nsg attached to nic didnt have all necessary properties populated
   History    : 
                170908 updated commands to remove public ip
                170809 checking vm for 3389 and 443 for nsg
                170807 fix for $ipAddress.IPAddress
                
.EXAMPLE  
    .\azure-az-rdp-post-deployment.ps1
    query azure rm for all resource groups with for all public ips.

.EXAMPLE
    .\azure-az-rdp-post-deployment.ps1 -rdWebUrl https://contoso.eastus.cloudapp.azure.com/RDWeb
    used to bypass Azure enumeration and to copy cert from url to local cert store

.PARAMETER addPublicIp
    add public ip address and nsg to selected virtual machine

.PARAMETER enumerateSubscriptions
    to query all subscriptions and not just current one

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
    [switch]$addPublicIp,
    [string][ValidateSet('LocalMachine', 'CurrentUser')] $certLocation = "LocalMachine",
    [switch]$enumerateSubscriptions,
    [switch]$noprompt,
    [switch]$noretry,
    [int[]]$ports = @(3389),
    [string]$publicIpAddressName = ".",
    [string]$rdWebUrl = "",
    [string]$resourceGroupName,
    [switch]$update,
    [string]$vmName
)

set-strictmode -version Latest
$ErrorActionPreference = "SilentlyContinue"
$WarningPreference = "SilentlyContinue"
$global:redisplay = $true
$global:selfSigned = $false
$global:san = $false
$global:wildcard = $false
$hostsTag = "added by azure script"
$hostsFile = "$($env:windir)\system32\drivers\etc\hosts"
$updateUrl = "https://aka.ms/azure-az-rdp-post-deployment.ps1"
$profileContext = "$($env:TEMP)\ProfileContext.ctx"
$throttle = 10

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $error.Clear()
    $subList = @{}
    $rg = $null
    $subject = $null
    $certInfo = $null
    $startTime = get-date

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
        #$ipv4 = ([regex]::Matches($rdWebUrl, "((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])")).Captures
        $ipv4 = [regex]::Matches($rdWebUrl, "((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])")
        
        if($ipv4.Count -gt 1)
        {
            $subject = import-cert -cert $cert -certFile $certFile -subject $subject -wildcardname "gateway"
        
            if ($subject)
            {
                add-hostsEntry -ipAddress $ipv4.Captures[0].Value -subject $subject
                open-RdWebSite -site $rdWebUrl
                return
            }
        }
    }
    
    # connect to azure
    authenticate-az
    $subscriptions = @(get-subscriptions)
    $global:redisplay = $true

    if($addPublicIp -and $subscriptions.Count -gt 0)
    {
        add-publicIp
        #return
    }

    while ($global:redisplay -and $subscriptions.Count -gt 0)
    {
        $global:redisplay = $false

        foreach ($sub in $subscriptions)
        {
            $resourceList = New-Object Collections.ArrayList

            if (!$sub)
            {
                continue
            }

            if($enumerateSubscriptions)
            {
                Set-azContext -SubscriptionId $sub
            }

            write-host "subscription id $($sub)"

            $resourceList = enum-resourcegroup $sub
            
            $count = 1
            write-host "Displaying ONLY Azure RM resources with public IP addresses that are currently connectable." -ForegroundColor Cyan
            Write-Host "Green indicates RDWeb site:" -ForegroundColor Green

            foreach($resource in $resourceList)
            {
                if($resource.DisplayMessage)
                {
                    write-host "$($count). $($resource.displayMessage)" -ForegroundColor $resource.displayMessageColor
                    $resource.Id = $count
                    $count++
                }
            }

            if(!$resourceList -or $resourceList.Count -lt 1)
            {
                write-host "no ip addresses found.."
                if((read-host "do you want to add a public ip address to an existing vm?[y|n]") -imatch "y")
                {
                    add-publicIp
                    $global:redisplay = $true
                    #return
                }

                continue
            }
            elseif ($resourceList.Count -gt 1)
            {
                write-verbose "query time: $(((get-date) - $startTime).TotalSeconds)"
                write-host "(advanced) if connection is not listed and vm is running, enter 'p' to add public ip address"
                $idsEntry = Read-Host ("Enter number for site / ip address to connect to.")
            }
            elseif ($resourceList.Count -eq 1)
            {
                $id = 1
            }
            
            $ids = check-response -response $idsEntry


            foreach ($id in $ids)
            {
                if(!([Convert]::ToInt32($id)))
                {
                   write-host "invalid entry $($id)..."
                   continue
                }
                
                [int]$id = [Convert]::ToInt32($id) 
                
                if ($id -gt $resourceList.Count -or $id -lt 1)
                {
                    write-host "entry out of range $($id)..."
                    continue
                }

                $resource = $resourceList | where Id -eq $id
                
                write-host $resource.ResourceGroup
                write-verbose "enum-resourcegroup returning:$($resource | fl | out-string)"

                $ip = $resource.publicIp
        
                #if ($ip.IpAddress)
                if ($resource.certInfo)
                {
                    write-host "public ip address: $($ip.IpAddress)"
                    $gatewayUrl = "https://$($ip.IpAddress)/RDWeb"
                    $certFile = [IO.Path]::GetFullPath("$($gatewayUrl -replace '\W','').cer")
                    $cert = get-cert -url $gatewayUrl -certFile $certFile
                    $subject = enum-certSubject -cert $resource.certInfo
                    $subject = import-cert -cert $cert -certFile $certFile -subject $subject -wildcardname $resource.ResourceGroup
                    add-hostsEntry -ipAddress $ip.IpAddress -subject $subject
                    open-RdWebSite -site "https://$($subject)/RDWeb"
                }
                else
                {
                    start-mstsc -ip $ip
                }
            }
        } # end foreach

        if(!$resourceList)
        {
            write-warning "no machines are available to connect to. exiting"
            break
        }

    } # end while

    if(test-path $profileContext)
    {
        Remove-Item -Path $profileContext -Force
    }

    write-host "finished"
}

# ----------------------------------------------------------------------------------------------------------------
function add-hostsEntry($ipAddress, $subject)
{
    # see if it needs to be added to hosts file
    $addIp = $false

    try
    {
        try
        {
            $dnsresolve = @(Resolve-DnsName -Name $subject -ErrorAction SilentlyContinue)
            $dnsIP0 = ""

        
            if($error)
            {
                $addIp = $true
                $error.Clear()
            }
            elseif(!$dnsresolve -or $dnsresolve.Count -lt 1)
            {
                $addIp = $true
            }
            elseif(!$dnsresolve.IpAddress -or !$dnsresolve.IpAddress.Contains($ipAddress))
            {
                $addIp = $true
            }
        }
        catch {}

        if ($addIp)
        {
            if($dnsresolve -and $dnsresolve.IpAddress)
            {
                $dnsIP0 = @($dnsresolve.IpAddress)[0]
            }
        
            write-host "$($ipAddress) not same as $($dnsIP0), checking hosts file"
            if (!$noPrompt -and (read-host "Is it ok to modify hosts file and add $($ipAddress)?[y|n]") -ine 'y')
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
                        [void]$newhostFileInfo.AppendLine($line)
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
            $newEntry = "$($ipAddress)`t$($subject)`t# $($hostsTag) $([IO.Path]::GetFileName($MyInvocation.ScriptName)) $([DateTime]::Now.ToShortDateString())`r`n"
            write-host "adding new entry:$($newEntry)"
                
            [IO.File]::AppendAllText($hostsFile, $newEntry)
            type $hostsFile
        }
        else
        {
            write-host "dns resolution for $($subject) same as ip:$($ipAddress)"
        }
    }
    catch
    {
        write-host "add-hostname:exception: $($error | out-string)"
    }
}

# ----------------------------------------------------------------------------------------------------------------
function add-publicIp()
{
    try
    {
        # verify 
        Write-host "This process will add a dynamic public ip address to an existing vm that only has a private ip address" -ForegroundColor Yellow
        Write-host "It will use an existing NSG or will create a new one. The only port open will be 3389 for RDP" -ForegroundColor Yellow
        Write-host "WARNING: this is exposing the selected virtual machines TCP port 3389 externally on internet." -ForegroundColor Yellow
        Write-host "If this is NOT correct, press ctrl-c to exit script." -ForegroundColor Yellow

        if((Read-Host "Confirm you want to continue:[y|n]") -inotmatch "y")
        {
            exit
        }
        
        $nsgnames = $Null
        $ret = $null
        $resourceGroups = Get-azResourceGroup
        $vms = new-object Collections.ArrayList

        if(!$resourceGroupName -and $resourceGroups -or !($resourceGroups.ResourceGroupName -imatch $resourceGroupName))
        {
            write-host "resource groups:" -ForegroundColor Cyan
            write-host ($resourceGroups.ResourceGroupName | out-string)
            $resourceGroupName = read-host "Enter name of resource group to enumerate"
        }

        if(!$resourceGroupName)
        {
            exit
        }

        foreach($vm in (Get-azVM -ResourceGroupName $resourceGroupName))
        {
            [void]$vms.Add($vm)
        }

        if(!$vmName)
        {
            write-host "virtual machines:" -ForegroundColor Cyan
            write-host ($vms.Name | out-string)
            $modifiedVmName = read-host "Enter name of vm to add public ip address"
        }
        else
        {
            $modifiedVmName = $vmName
        }

        if(!$modifiedVmName)
        {
            exit
        }

        $modifiedVm = get-azvm -ResourceGroupName $resourceGroupName -Name $modifiedVmName

        $vmNicName = [IO.Path]::GetFileName(@($modifiedVm.NetworkProfile.NetworkInterfaces.Id)[0])
        $vmNic = Get-azNetworkInterface -ResourceGroupName $resourceGroupName -Name $vmNicName
        $vmSubnetName = [IO.Path]::GetFileName(@($vmNic.IpConfigurations)[0].subnet.id)
        $vmPrivateIpAddress = $vmNic.IpConfigurations.privateipaddress
        $vmPublicIpAddress = $vmNic.IpConfigurations.publicipaddress
        #$publicIp = Get-azPublicIpAddress -ResourceGroupName $resourceGroupName -Name $vmNicName -ErrorAction SilentlyContinue
        $vmStatus = (get-azvm -ResourceGroupName $resourceGroupName -Name $modifiedVmName -Status).Statuses

        if(!($vmStatus.Code -imatch "running"))
        {
            write-host "error: vm is NOT running! start vm and restart script. exiting" -ForegroundColor Red
            exit    
        }

        write-host "vm name: $($modifiedVm.Name)"
        write-host "`tprivate ip address: $($vmPrivateIpAddress)"
        write-host "`tpublic ip address: $($vmPublicIpAddress)"
        write-host "`tsubnet: $($vmSubnetName)"
        write-host "`tstatus: running"
        

        if($vmPublicIpAddress)
        {
            write-host "vm $($modifiedVm.Name) already has public ip address $($vmPublicIpAddress). exiting" -ForegroundColor Red
            exit
        }
        
        $rgLocation = (get-azresourcegroup -Name $resourceGroupName).Location
        write-host "using location: $($rgLocation)"
        
        $newNsgName = $nsgName = "$($modifiedVmName)-nsg"
        $nsg = $vmNic.NetworkSecurityGroup
        
        if($nsg)
        {
            # may not be populated but needs to be
            if(!$nsg.ResourceGroupName) {$nsg.ResourceGroupName = $resourceGroupName}
            if(!$nsg.Location) {$nsg.Location = $rgLocation}
            if(!$nsg.Name) {$nsg.Name = $newNsgName}
        }

        $nsgs = @(Get-azNetworkSecurityGroup -ResourceGroupName $resourceGroupName)

        if(!$nsg)
        {
            if($nsgs)
            {
                write-host "all nsg's in resource group:" -ForegroundColor Cyan
                write-host ($nsgs.Name | out-string)
                write-host "nsg's in resource group on same subnet:" -ForegroundColor Cyan

                try
                {
                    $nsgNames = @([Linq.Enumerable]::Where($nsgs, [Func[object,bool]]{ param($x) $x.Subnets.Id -imatch $vmSubnetName }).Name)
                }
                catch 
                {
                    $error.Clear()
                }

                write-host ($nsgNames | out-string)

                write-host "nsg's in resource group with TCP 3389 Allow Rule:" -ForegroundColor Cyan
                try
                {
                    $nsgNames = @([Linq.Enumerable]::Where($nsgs, [Func[object,bool]]{ param($x) $x.SecurityRules.DestinationPortRange -imatch 3389 }).Name)
                }
                catch 
                {
                    $error.Clear()
                }

                write-host ($nsgNames | out-string)
            }

            $nsgName = read-host "enter name of existing nsg to use, new nsg name to create new nsg, or press {enter} to use new name '$($newNsgName)'"

            if(!$nsgName)
            {
                $nsgName = $newNsgName
            }

            if($nsgName -and !($nsgNames -imatch $nsgName))
            {
                write-host "creating new nsg $($nsgName). please wait..." -ForegroundColor Yellow
                write-host "`t New-azNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Name $nsgName -Location $rgLocation" -ForegroundColor Gray
                $nsg = New-azNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Name $nsgName -Location $rgLocation
            }
            elseif($nsgName -and ($nsgNames -imatch $nsgName))
            {
                # on same subnet
                $nsg = Get-azNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Name $nsgName
            }
            else
            {
                exit
            }
        }

        if(!$nsg)
        {
            exit
        }

        foreach($port in $ports)
        {
            #if(test-port -ipAddress $vmPrivateIpAddress -port $port)
            $foundRule = $false

            if($true)
            {

                write-host "checking for security rule for $($port)"
                foreach($rule in $nsg.SecurityRules)
                {
                    if($rule.DestinationPortRange -imatch $port -and $rule.DestinationAddressPrefix -eq "*")
                    {
                        $foundRule = $true
                    }
                }

                if($foundRule)
                {
                    write-host "using existing security rule for $($port)..." -ForegroundColor Green
                }
                else
                {
                    write-host "creating security rule for $($port)"
                    # check for open priority
                    $priority = $Null
            
                    if($nsg.SecurityRules.Count -gt 0)
                    {            
            
                    $priorities = $nsg.SecurityRules.Priority

                    foreach($priority in 100..4096)
                    {
                            if ($priorities -ieq $priority)
                            {
                                continue
                            }
                            else
                            {
                                break
                            }
                        }
                    }
                    else
                    {
                        $priority = 100
                    }

                    write-host "`t Add-azNetworkSecurityRuleConfig -NetworkSecurityGroup $nsg `
                        -Name AllowRDP `
                        -Direction Inbound `
                        -Priority $priority `
                        -Access Allow `
                        -SourceAddressPrefix '*' `
                        -SourcePortRange '*' `
                        -DestinationAddressPrefix '*' `
                        -DestinationPortRange $($port) `
                        -Protocol TCP `
                        -ErrorAction Stop" -foregroundColor Gray

                    $ret = Add-azNetworkSecurityRuleConfig -NetworkSecurityGroup $nsg `
                        -Name "Allow$($port)" `
                        -Direction Inbound `
                        -Priority $priority `
                        -Access Allow `
                        -SourceAddressPrefix '*' `
                        -SourcePortRange '*' `
                        -DestinationAddressPrefix '*' `
                        -DestinationPortRange $($port) `
                        -Protocol TCP `
                        -ErrorAction Stop
                        #$vmPrivateIPAddress `
                }
            
                write-host "saving security rule for TCP RDP $($port). please wait..." -ForegroundColor Yellow
                $ret = Set-azNetworkSecurityGroup -NetworkSecurityGroup $nsg -ErrorAction Stop
                $vmNic.NetworkSecurityGroup = $nsg

            }
            else
            {
                write-host "warning:port $($port) not responding. skipping"
            }

        } # end foreach

        write-host "creating public ip. please wait..." -ForegroundColor Yellow
        write-host "`t New-azPublicIpAddress -Name $($modifiedVmName)-pubIp `
            -ResourceGroupName $resourceGroupName `
            -AllocationMethod Dynamic `
            -Location $rgLocation" -ForegroundColor Gray

        $vmPublicIP = New-azPublicIpAddress -Name "$($modifiedVmName)-pubIp" `
            -ResourceGroupName $resourceGroupName `
            -AllocationMethod Dynamic `
            -Location $rgLocation

        write-host "setting vm $($modifiedVmName) network interface to use public ip. please wait..." -ForegroundColor Yellow
        #$ret = Add-azNetworkInterfaceIpConfig -Name $vmPublicIP.Name -NetworkInterface $vmNic
        #$ret = Set-azNetworkInterfaceIpConfig -name $vmPublicIP.Name -NetworkInterface $vmNic -PublicIpAddress $vmPublicIP
        $vmNic.IpConfigurations[0].PublicIpAddress = $vmPublicIp
        $ret = Set-azNetworkInterface -NetworkInterface $vmNic
        
        write-host "`t (get-azPublicIpAddress -ResourceGroupName $resourceGroupName -Name $vmPublicIP.Name).IpAddress" -ForegroundColor Gray
        $vmPublicIpAddress = (get-azPublicIpAddress -ResourceGroupName $resourceGroupName -Name $vmPublicIP.Name).IpAddress

        if($vmPublicIpAddress)
        {
            write-host "new public ip address: $($vmPublicIpAddress)" -ForegroundColor Green
        }
        else
        {
            write-host "unable to acquire public ip address. exiting" -ForegroundColor Red
            exit
        }
        
        write-host "successfully added public ip address $($vmPublicIPAddress) to vm $($modifiedVmName)" -ForegroundColor Green
        write-host "To remove public ip address and nsg, use the following commands:" -ForegroundColor Magenta
        write-host "`t `$nic = (Get-azNetworkInterface -ResourceGroupName $($resourceGroupName) -Name $($vmNicName))" -ForegroundColor Cyan
        write-host "`t `$nic.IpConfigurations.publicipaddress = `$null" -ForegroundColor Cyan
        write-host "`t `$nic.NetworkSecurityGroup = `$null" -ForegroundColor Cyan
        write-host "`t Set-azNetworkInterface -NetworkInterface `$nic" -ForegroundColor Cyan
        write-host "`t Remove-azPublicIpAddress -Name $($modifiedVmName)-pubIp -ResourceGroupName $($resourceGroupName) -Force" -ForegroundColor Cyan
        write-host "`t Remove-azNetworkSecurityGroup -Name $($nsgName) -ResourceGroupName $($resourceGroupName) -Force" -ForegroundColor Cyan
        write-host ""
    }
    catch
    {
        write-host "add-publicIp:error: $($error | out-string)"
        exit
    }
}

# ----------------------------------------------------------------------------------------------------------------
function authenticate-az()
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

    $allModules = (get-module az* -ListAvailable).Name

	#  install az module
	if ($allModules -inotcontains "Az")
	{
        # each has different az module requirements
        # installing az slowest but complete method
        # if wanting to do minimum install, run the following script against script being deployed
        # https://raw.githubusercontent.com/jagilber/powershellScripts/master/script-az-module-enumerator.ps1
        # this will parse scripts in given directory and output which azure modules are needed to populate the below

        # at least need profile, resources, insights, logicapp for this script
        if ($allModules -inotcontains "az.profile")
        {
            write-host "installing az.profile powershell module..."
            install-module az.profile -force
        }
        if ($allModules -inotcontains "az.resources")
        {
            write-host "installing az.resources powershell module..."
            install-module az.resources -force
        }
        if ($allModules -inotcontains "az.compute")
        {
            write-host "installing az.compute powershell module..."
            install-module az.compute -force
        }
        if ($allModules -inotcontains "az.network")
        {
            write-host "installing az.network powershell module..."
            install-module az.network -force

        }
            
        Import-Module az.profile        
        Import-Module az.resources        
        Import-Module az.compute
        Import-Module az.network
		#write-host "installing az powershell module..."
		#install-module az -force
        
	}
    else
    {
        Import-Module az
    }

    # authenticate
    try
    {
        $rg = @(Get-azTenant)
                
        if($rg)
        {
            write-host "auth passed $($rg.Count)"
        }
        else
        {
            write-host "auth error $($error)" -ForegroundColor Yellow
            throw [Exception]
        }
    }
    catch
    {
        if(!(connect-azaccount))
        {
           log-info "exception authenticating. exiting $($error | out-string)" -ForegroundColor Yellow
            exit 1
        }
    }

    Save-azContext -Path $profileContext -Force
}

# ----------------------------------------------------------------------------------------------------------------
function check-jobs()
{
    $resultList = new-object Collections.ArrayList
    $ret = $null
    $jobInfos = $null

    foreach($job in get-job)
    {
        if($job.State -ine "Running")
        {
            $jobInfos = (Receive-Job -Job $job)

            foreach($jobInfo in $jobInfos)
            {
                if($jobInfo -and ($jobInfo.GetType().Name -eq "HashTable"))
                {
                    [void]$resultList.Add($jobInfo)
                }
                elseif($jobInfo)
                {
                    Write-Warning $jobInfo | out-string
                }
                else
                {
                    Write-verbose "job returned empty result"
                }
            }
            $ret = Remove-Job -Job $job -Force
        }
    }

    return $resultList
}

# ----------------------------------------------------------------------------------------------------------------
function check-response($response)
{
    [string[]] $ids = @()
    #check ids for comma and range
    if ($response.ToLower().Contains("c"))
    {
        # redisplay list to choose again
        $response = $response.ToLower().Replace("c", "")
        $global:redisplay = $true
    }
    elseif ($response.ToLower().Contains("p"))
    {
        # go through public ip setup
        $response = $response.ToLower().Replace("p", "")
        add-publicIp
        $global:redisplay = $true
        return
    }
    else
    {
        $global:redisplay = $false
    }

    if ($response.Contains(","))
    {
        $ids = @($response.Split(","))
    }
    else
    {
        $ids = @($response)
    }

    return $ids
}

# ----------------------------------------------------------------------------------------------------------------
function enum-certSubject($cert)
{
    # get certificate from RDWeb site

    if (!$cert)
    {
        write-host "no cert!"
        return $false
    }

    $subject = $cert.Subject.Replace("CN=", "")   
        
    if ($subject)
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
    $displayMessage = ""
    $pubIps = @()
    $vms = @()
    $resourceList =  New-Object Collections.ArrayList
    $resultList =  New-Object Collections.ArrayList
    $ret =  New-Object Collections.ArrayList
    $response = $null

    # cleanup
    if(get-job)
    {
        write-host "removing $(@(get-job).Count) old jobs..."
        get-job | remove-job -Force
    }

    try
    {
        if(!$noprompt -and !$resourceGroupName)
        {
            write-host "resource group names:" -ForegroundColor Cyan
            $resourceGroupNames = [collections.ArrayList]@((Get-azResourceGroup).ResourceGroupName)
            $count = 1

            foreach($name in $resourceGroupNames)
            {
                write-host "$($count). $($name)"
                $count++
            }

            Write-Host
            $response = read-host "enter number for resource group to enumerate or press {enter} to enumerate all:"
            $resourceGroupName = check-response -response $response
        }

        # find resource group
        if (!$resourceGroupName)
        {
            #$Null = Set-azContext -SubscriptionId $subid
            $resourceGroups = Get-azResourceGroup -WarningAction SilentlyContinue
            $count = 1
        }
        else
        {
            try
            {
                if([Convert]::ToInt32($resourceGroupName))
                {
                    $resourceGroups = @(Get-azResourceGroup -Name ($resourceGroupNames[$resourceGroupName - 1]) -WarningAction SilentlyContinue)
                }
            }
            catch 
            {
                $resourceGroups = @(Get-azResourceGroup -Name $resourceGroupName -WarningAction SilentlyContinue)
            }
        }

        foreach($resourceGroup in $resourceGroups.ResourceGroupName)
        {
            $pubIps = @(Get-azPublicIpAddress -ResourceGroupName $resourceGroup | ? IpAddress -ine "Not Assigned")
            write-host "checking $($pubIps.count) ip addresses in $($resourceGroup)."

            foreach($ip in $pubIps)
            {
                if($resourceGroup -imatch $ip.ResourceGroupName)
                {
                    $resource = @{}
                    $resource.Id = 0
                    $resource.publicIp = $ip
                    $resource.subId = $subid
                    $resource.displayMessage = "`r`n`tResource Group: $($resourceGroup)`r`n`tIP name: $($ip.Name)`r`n`tIP address: $($ip.IpAddress)"
                    $resource.resourceGroup = $resourceGroup
                    $resource.rdWebUrl = ""
                    $resource.certInfo = $null
                    $resource.displayMessageColor = "White"
                    $resource.profileContext = $profileContext
                    $resource.invocation = $MyInvocation

                    [void]$resourceList.Add($resource)
                }
            }
        }


        $jobs = New-Object Collections.ArrayList
         
        foreach($resource in $resourceList)
        {
            while((get-job) -and (@(get-job | where-object State -eq "Running").Count -gt $throttle))
            {
                Write-Verbose "throttled"
                $ret = check-jobs

                if($ret)
                {
                    if($ret.gettype().Name -eq "Object[]")
                    {
                        $resultList.AddRange($ret)
                    }
                    else
                    {
                        $resultList.Add($ret)
                    }
                }
                Start-Sleep -Seconds 1
            }

            $job = start-job -ScriptBlock `
            {
                param($resource)
                $ctx = $null
                $displayMessage = $null
                $t = $null
                #background job for bug https://github.com/Azure/azure-powershell/issues/7110
                Disable-azContextAutosave -scope Process -ErrorAction SilentlyContinue | Out-Null

                $ctx = Import-azContext -Path $resource.profileContext
                # bug to be fixed 8/2017
                # From <https://github.com/Azure/azure-powershell/issues/3954> 
                [void]$ctx.Context.TokenCache.Deserialize($ctx.Context.TokenCache.CacheData)
                . $($resource.invocation.scriptname)

                $displayMessage = $resource.displayMessage
                $t = New-Object Net.Sockets.TcpClient

                try
                {
                    $t.Connect($resource.publicIp.IpAddress,3389)
                    $resource.displayMessage = " VM: mstsc.exe /v $($resource.publicIp.IpAddress) /admin$($displayMessage)"
                    # write results to pipe
                    $resource
                }
                catch {}

                [void]$t.Dispose()
                $t = New-Object Net.Sockets.TcpClient

                try                
                {
                    $t.Connect($resource.publicIp.IpAddress,443)
                    $resource.rdWebUrl = "https://$($resource.publicIp.IpAddress)/RDWeb"
                    $resource.certInfo = (get-cert -url $resource.rdWebUrl)

                    if ($resource.certInfo)
                    {
                        $resource.displayMessage = " RDWEB: $($resource.rdWebUrl)$($displayMessage)`r`n`tCert Subject: $(enum-certSubject -cert $resource.certInfo)"
                        $resource.displayMessageColor = "Green"
                        # write results to pipe
                        $resource
                    }
                }
                catch {}

                [void]$t.Dispose()
            } -ArgumentList $resource

            [void]$jobs.Add($job)
        }

        $jobsCount = $jobs.Count
        $activity = "checking connectivity to $($jobsCount) public ips. please wait.."

        while(get-job)
        {
            $jobCount = @(get-job).Count
            Write-Progress -Activity $activity -Status "$($jobsCount - $jobCount) of $($jobsCount) completed" -PercentComplete (($jobsCount - $jobCount) / $jobsCount * 100)
            $ret = check-jobs

            if($ret)
            {
                if($ret.gettype().Name -eq "Object[]")
                {
                    $resultList.AddRange($ret)
                }
                else
                {
                    $resultList.Add($ret)
                }
            }

            Start-Sleep -Seconds 1
        }

        Write-Progress -Activity $activity -Completed

        if($resultList.Count)
        {
            return $resultList
        }
        else
        {
            return $false
        }
    }
    catch
    {
        write-host "enum-resourcegroup:exception: $($error | out-string )"
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
            if (!$certFile)
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

    if ($ip.IpAddress)
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
    write-verbose "enumerating subscriptions"
    $subList = new-object Collections.ArrayList
    $returnList = new-object Collections.ArrayList

    if($enumerateSubscriptions)
    {
        $subs = @(Get-azSubscription -WarningAction SilentlyContinue | Sort-Object -Property Name )
    }
    else
    {
        $subs = @(Get-azContext)
    }

    # check format    
    foreach ($sub in $subs)
    {
        $id = $null
        $name = ""
        if($sub | get-member -name id)
        {
            $id = $sub.id
            $name = $sub.name
        }
        elseif($sub | get-member -name subscriptionid)
        {
            $id = $sub.subscriptionid
            $name = $sub.subscriptionname
        }
        elseif($sub | get-member -name subscription)
        {
            $id = $sub.subscription.id
            $name = $sub.subscription.name
        }
        else
        {
            Write-verbose "unable to find subscription id"
            continue
        }

        #write-host "enumerating subscription $($name)"
        [void]$subList.Add($name + ": " + $id)
    }

    if($subList.Count -gt 1)
    {
        write-host "subscriptions:" -ForegroundColor Cyan
        $count = 1

        foreach($name in $subList)
        {
            write-host "$($count). $($name)"
            $count++
        }

        Write-Host
        $response = read-host "enter number of subscription to enumerate:"

        foreach($id in @(check-response -response $response))
        {
            $returnList.Add($subList[$id-1])
        }

    }   
    else
    {
        $returnList = $subList
    }    

    write-verbose "get-subscriptions returning:$($subs | fl | out-string)"
    return $returnList
}

# ----------------------------------------------------------------------------------------------------------------
function get-update($updateUrl, $destinationFile)
{
    write-verbose "get-update:checking for updated script: $($updateUrl)"

    try 
    {
        $git = Invoke-RestMethod -Method Get -Uri $updateUrl 

        # git  may not have carriage return
        if ([regex]::Matches($git, "`r").Count -eq 0)
        {
            $git = [regex]::Replace($git, "`n", "`r`n")
        }

        if (![IO.File]::Exists($destinationFile))
        {
            $file = ""    
        }
        else
        {
            $file = [IO.File]::ReadAllText($destinationFile)
        }

        if (([string]::Compare($git, $file) -ne 0))
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
        write-host "get-update:exception: $($error)"
        $error.Clear()
        return $false    
    }
}

# ----------------------------------------------------------------------------------------------------------------
function import-cert($cert, $certFile, $subject, $wildcardName)
{
    write-verbose "import-cert $($certFile) $($subject)"
    if (!$subject)
    {
        Write-Warning "import-cert:error: subject empty. returning"
        return $false
    }

    if (![IO.File]::Exists($certFile))
    {
        Write-Warning "import-cert:error: certfile not found. returning"
        return $false
    }

    $certList = @(Get-ChildItem -Recurse -Path cert:\ -DnsName "$($subject)")
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
        return $subject    
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
                if ((read-host "cert '$($c.pspath)' has different thumbprint, do you want to delete?[y|n]") -imatch 'y')
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
    
    $certList = @(Get-ChildItem -Recurse -Path $certStore -DnsName "$($subject)")
    
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
        write-host "certificate is wildcard. what host name do you want to use to connect to RDWeb site? this most likely needs to be same fqdn as rdweb and rdgateway." -ForegroundColor Yellow
        $domainName = "$($wildcardName)$($subject.Replace('*',''))"    
        write-host "https://<hostname>$($subject.Replace('*',''))/RDWeb"    
        write-host "https://$($domainName)/RDWeb"    
        $ret = read-host "select {enter} to continue with '$($domainName)' hostname above, or enter <hostname> to use, or {ctrl-c} to quit:"
                        
        if (!$ret)
        {
            $subject = $domainName
        }
        else
        {
            $subject = "$($ret)$($subject.Replace('*',''))"
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
    $ips = Get-azPublicIpAddress -ResourceGroupName $resourceName
    $ipList = new-object Collections.ArrayList

    foreach ($ip in $ips)
    {
        if (!$ip.IpAddress -or $ip.IpAddress -eq "Not Assigned")
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
 
        if ($stdErr -and $stdErr -notlike "0")
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
function test-port($ipAddress,$port)
{
   $t = New-Object Net.Sockets.TcpClient

    try
    {
        $t.Connect($ipAddress,$port)
        return $true
    }
    catch 
    {
        return $false
    }
    finally
    {
        [void]$t.Dispose()
    }
}

# ----------------------------------------------------------------------------------------------------------------
if ($host.Name -ine "ServerRemoteHost")
{
    main
}
else 
{
    #background job for bug https://github.com/Azure/azure-powershell/issues/7110
    Disable-azContextAutosave -scope Process -ErrorAction SilentlyContinue | Out-Null
}

