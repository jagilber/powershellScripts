<#
.SYNOPSIS
    powershell script to generate .rdg file for remote desktop connection manager 'rdcman'

.DESCRIPTION
    powershell script to generate .rdg file for remote desktop connection manager 'rdcman'
    script to generate rdcman rdg file from azure services
    for use with latest rdcman 2.7
    https://www.microsoft.com/en-us/download/confirmation.aspx?id=44989

    Requirements:
        - administrator powershell prompt
        - azure powershell sdk (will install if not)
        - access to azure rm subscription

.NOTES
    File Name  : azure-rm-create-rdg-file.ps1
    Author     : jagilber
    Version    : 170708 original
    History    : 
    
.EXAMPLE
    .\azure-rm-create-rdg-file.ps1 
    Example command to query azure rm for internal and public IaaS ip addresses

.PARAMETER rdgFile
    path and file name for output .rdg file. default is azure-ms.rdg in script directory

.LINK
    https://www.microsoft.com/en-us/download/confirmation.aspx?id=44989
#>

Param(
    [string]$rdgFile = ".\azure-ms.rdg",
    [string[]]$resourceGroupNames# = @("rdsdepsa20")
)

$ErrorActionPreference = "Stop"
$profileContext = "$($env:TEMP)\ProfileContext.ctx"

# ----------------------------------------------------------------------------------------------------------------
function main()
{

    try
    {
        $error.Clear()
        get-workingDirectory
        $rdgFile = $rdgFile.Replace(".\",(get-location))

        # check if we need to sign on
        authenticate-azureRm

        # Create a new XML File with config root node
        [XML.XMLDocument]$doc=New-Object XML.XMLDocument
        $xmlDec = $doc.CreateXmlDeclaration("1.0","utf-8","")

        # set delaration
        [XML.XMLElement]$root=$doc.DocumentElement
        $doc.InsertBefore($xmlDec, $root)

        # Append as child to an existing node
        [XML.XMLElement]$element=$doc.CreateElement("RDCMan")
        $doc.appendChild($element)

        # Add Attributes
        $element.SetAttribute("programVersion","2.7")
        $element.SetAttribute("schemaVersion","3")


        [XML.XMLElement]$fileElement = $element.appendChild($doc.CreateElement("file"))
        [XML.XMLElement]$credElement = $fileElement.appendChild($doc.CreateElement("credentialsProfiles"))
        [XML.XMLElement]$propertiesElement = $fileElement.appendChild($doc.CreateElement("properties"))
        [XML.XMLElement]$expandedElement = $propertiesElement.appendChild($doc.CreateElement("expanded"))
        $expandedElement.InnerText = "True"
        [XML.XMLElement]$nameElement = $propertiesElement.appendChild($doc.CreateElement("name"))
        $nameElement.InnerText = "Azure RM $((Get-AzurermSubscription).Id)"

        $allVms = @(Get-AzureRmResource -ResourceType Microsoft.Compute/virtualMachines)

        if(!$resourceGroupNames)
        {
            $resourceGroupNames = @(Get-AzureRmResourceGroup).ResourceGroupName
        }


        foreach($resourceGroupName in $resourceGroupNames)
        {
            
            write-host "resourcegroup:$($resourceGroupName)"
            if(!($allVms.ResourceGroupName -imatch $resourceGroupName))
            {
                continue
            }

            [XML.XMLElement]$groupElement = $fileElement.appendChild($doc.CreateElement("group"))
            [XML.XMLElement]$propertiesElement = $groupElement.appendChild($doc.CreateElement("properties"))
            [XML.XMLElement]$expandedElement = $propertiesElement.appendChild($doc.CreateElement("expanded"))
            $expandedElement.InnerText = "True"
            [XML.XMLElement]$nameElement = $propertiesElement.appendChild($doc.CreateElement("name"))
            $nameElement.InnerText = $resourceGroupName

            $allIps = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroupName
            $allInterfaces = @(Get-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName)
            $allLbs = @(Get-AzureRmLoadBalancer -ResourceGroupName $resourceGroupName)
           
            # check loadbalancers
            $lbInfos = New-Object Collections.ArrayList

            foreach($publicIp in $allIps)
            {
                $lbInfo = @{}
                $lbInfo.PublicIPAddress = $publicIp.IpAddress
                $lbInfo.PrivateIPAddress = ""
                $lbInfo.FQDN = $publicIp.DnsSettings.Fqdn
                $lbInfo.LBName = $publicIp.Name
                $lbInfo.RDPPort = $false
                $lbInfo.SSLPort = $false
                $lbInfo.VMs = New-Object Collections.ArrayList
                $lbInfo.resourceGroupName = ""
                
                $lbInfos.Add($lbinfo)        
            }


            foreach($lb in $lbInfos)
            {
                $lbmatches = @([Linq.Enumerable]::Where($allLbs, 
                    [Func[object,bool]]{ param($x) $x.FrontEndIpConfigurations.PublicIpAddress.Id -imatch $lb.LBName }))

                if($lbmatches.count -eq 1)
                {
                    $lbmatch = $lbmatches[0]

                    $lb.resourceGroupName = $lbmatch.ResourceGroupName

                    $lb.SSLPort = @([Linq.Enumerable]::Where($lbMatches, 
                        [Func[object,bool]]{ param($x) $x.LoadBalancingRules.FrontendPort -imatch "443"  -or $x.InboundNatRules.FrontendPort -imatch "433" })).Count -gt 0

                    $lb.RDPPort = @([Linq.Enumerable]::Where($lbMatches, 
                        [Func[object,bool]]{ param($x) $x.LoadBalancingRules.FrontendPort -imatch "3389" -or $x.InboundNatRules.FrontendPort -imatch "3389" })).Count -gt 0

                    $interfaceMatches = @([Linq.Enumerable]::Where($allInterfaces, 
                        [Func[object,bool]]{ param($x) $x.IpConfigurations.LoadbalancerBackendAddressPools.Id -imatch $lbmatch.BackendAddressPools.Name }))

                    if($lb.SSLPort)
                    {
                        # check if gateway
                        #https://40.71.47.111/rpc

                        # if not, set to false
                        # $lb.SSLPort = $false
                    }


                    if($lb.SSlPort -or $lb.RDPPort)
                    {
                        [XML.XMLElement]$serverElement = $groupElement.appendChild($doc.CreateElement("server"))
                        [XML.XMLElement]$propertiesElement = $serverElement.appendChild($doc.CreateElement("properties"))
                        [XML.XMLElement]$displayNameElement = $propertiesElement.appendChild($doc.CreateElement("displayName"))
                        $displayNameElement.InnerText = "LB:$($lb.LBName) $($lb.PublicIpAddress) SSL:$($lb.SSLPort) RDP:$($lb.RDPPort)"
                        [XML.XMLElement]$nameElement = $propertiesElement.appendChild($doc.CreateElement("name"))
                        $nameElement.InnerText = $lb.PublicIPAddress

                        if($lb.SSLPort)
                        {
                            # check if gateway
                            #https://40.71.47.111/rpc
                        }
                    }


#                    foreach($interfaceMatch in $interfaceMatches)
#                    {
#                        $vmInfo = @{}
#
#                        $vmInfo.vmName = [IO.Path]::GetFileName($interfaceMatch.VirtualMachine.Id)
#                        $vmInfo.vmNic = [IO.Path]::GetFileName($interfaceMatch.Id)
#                        $vmInfo.privateIpAddresses = @($interfaceMatch.IpConfigurations.PrivateIpAddress)
#                        $vmInfo.publicIpAddresses = @($interfaceMatch.IpConfigurations.PublicIpAddress)
#
#                        $lb.VMs.Add($vmInfo)
#                        #$filteredLbInfos.Add($lb)
#
#                        [XML.XMLElement]$serverElement = $groupElement.appendChild($doc.CreateElement("server"))
#                        [XML.XMLElement]$propertiesElement = $serverElement.appendChild($doc.CreateElement("properties"))
#                        [XML.XMLElement]$displayNameElement = $propertiesElement.appendChild($doc.CreateElement("displayName"))
#                        $displayNameElement.InnerText = "LB:$($lb.LBName) $($lb.PublicIpAddress) SSL:$($lb.SSLPort) RDP:$($lb.RDPPort)"
#                        [XML.XMLElement]$nameElement = $propertiesElement.appendChild($doc.CreateElement("name"))
#                        $nameElement.InnerText = $lb.PublicIPAddress
#
#                    }
                }
            }

            foreach($interface in $allInterfaces)
            {
                write-host "`tinterface:$($interface.Name)"
                # get vm
                $vmName = [IO.Path]::GetFileName($interface.VirtualMachine.Id)

                #if(!($allVms.Name -imatch $vmName))
                #{
                #    continue
                #}

                # get private address
                $privateIpAddresses = @($interface.IpConfigurations.PrivateIpAddress)
                # get public address
                $publicIpAddresses = @($interface.IpConfigurations.PublicIpAddress)
                
                foreach($privateIpAddress in $privateIpAddresses)
                {
                    if(!$privateIpAddress)
                    {
                        continue
                    }

                    [XML.XMLElement]$serverElement = $groupElement.appendChild($doc.CreateElement("server"))
                    [XML.XMLElement]$propertiesElement = $serverElement.appendChild($doc.CreateElement("properties"))
                    [XML.XMLElement]$displayNameElement = $propertiesElement.appendChild($doc.CreateElement("displayName"))
                    $displayNameElement.InnerText = "$($vmName) $($privateIpAddress)"
                    [XML.XMLElement]$nameElement = $propertiesElement.appendChild($doc.CreateElement("name"))
                    $nameElement.InnerText = $privateIpAddress
                }

                foreach($publicIpAddress in $publicIpAddresses)
                {
                    if(!$publicIpAddress)# -or !$publicIpAddress.IpAddress)
                    {
                        continue
                    }


                    $publicIpInterfaceName = [IO.Path]::GetFileName($interface.IpConfigurations.publicipaddress.Id)
                    $publicIp = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroupName -Name $publicIpInterfaceName

                    [XML.XMLElement]$serverElement = $groupElement.appendChild($doc.CreateElement("server"))
                    [XML.XMLElement]$propertiesElement = $serverElement.appendChild($doc.CreateElement("properties"))
                    [XML.XMLElement]$displayNameElement = $propertiesElement.appendChild($doc.CreateElement("displayName"))
                    $displayNameElement.InnerText = "$($vmName) PUBLIC $($publicIp.IpAddress)"
                    [XML.XMLElement]$nameElement = $propertiesElement.appendChild($doc.CreateElement("name"))
                    $nameElement.InnerText = $publicIp.IpAddress
                }
            }
        }

        [XML.XMLElement]$connectedElement = $element.appendChild($doc.CreateElement("connected"))
        [XML.XMLElement]$favoritesElement = $element.appendChild($doc.CreateElement("favorites"))
        [XML.XMLElement]$recentlyUsedElement = $element.appendChild($doc.CreateElement("recentlyUsed"))
    
        # Save File
        if(!([IO.Directory]::Exists([IO.Path]::GetDirectoryName($rdgFile))))
        {
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($rdgFile))
        }

        $doc.Save($rdgFile)
        Invoke-Item $rdgFile
        write-host "finished"
    }
    catch
    {
        Write-Warning "exception:main:$($error)"
    }
    finally
    {
        if(test-path $profileContext)
        {
            Remove-Item -Path $profileContext -Force
        }
    }
}
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
        # https://raw.githubusercontent.com/jagilber/powershellScripts/master/script-azurerm-module-enumerator.ps1
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

    Save-AzureRmContext -Path $profileContext -Force
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
        write-host "get-workingDirectory: Powershell Host $($Host.name) may not be compatible with this function, the current directory $retVal will be used."
        
    } 
 
    Set-Location $retVal | out-null
    return $retVal
}
# ----------------------------------------------------------------------------------------------------------------

main
