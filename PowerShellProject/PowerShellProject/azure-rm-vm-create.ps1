# script to create multiple vm's into existing azure rm infrastructure
# 161120

param(
#    [string]$adminPassword="", # todo:remove
    [switch]$enumerateSub,
    [switch]$force,
    [string]$galleryImage="2016-Datacenter",
    [string]$location="eastus", # todo:remove
    [string]$offername="WindowsServer",
    [string]$pubName="MicrosoftWindowsServer",
    [string]$resourceGroupName="", # todo:remove
    [string]$StorageAccountName="", # todo:remove
    [string]$StorageType = "Standard_GRS",
    [string]$subnetName="",
    [string]$subscription,
#    [string]$user="vmadmin",
    [string]$vmBaseName="rdsh-tpl",
    [int]$vmCount= 1,
    [string]$vmSize="Standard_A4",
    [int]$vmStartCount=1,
    [string]$VNetAddressPrefix = "10.0.0.0/16",
    [string]$VNetSubnetAddressPrefix = "10.0.0.0/24",
    [string]$vnetName=""
)

$vnetNamePrefix = "ADVNET"
$subnetNamePrefix = "ADStaticSubnet"
$global:credential

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    authenticate-azureRm

    if($enumerateSub)
    {
        enum-subscription
        return
    }

    # check to make sure vm doesnt exist
    $i = $startCount
    $jobs = @()
    $newVmNames = new-object Collections.ArrayList
    $Error.Clear()

    if([string]::IsNullOrEmpty($resourceGroupName) -and @(Get-AzureRmResourceGroup).Count -eq 1)
    {
        $resourceGroupName = (Get-AzureRmResourceGroup).Name
        
    }
    elseif([string]::IsNullOrEmpty($resourceGroupName))
    {
        write-host (Get-AzureRmResourceGroup | fl * | out-string)
        $resourceGroupName = read-host "enter resource group"
    }
    elseif(!(Get-AzureRmResourceGroup $resourceGroupName))
    {
        write-host "creating resource group: $($resourceGroupName)"
        New-AzureRmResourceGroup -Name $resourceGroupName -Location $Location 
    }

    # see if only one storage account if name empty and use that
    if([string]::IsNullOrEmpty($storageAccountName) -and @(Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName).Count -eq 1)
    {
        $storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName
        write-host = "using default storage account:$($storageAccount.Name)"
    }
    elseif([string]::IsNullOrEmpty($storageAccountName))
    {
        write-host (Get-AzureRmStorageAccount | fl * | out-string)
        $storageAccountName = read-host "enter storage account"
        $storageAccount = Get-AzureRmStorageAccount -Name $StorageAccountName -ResourceGroupName $resourceGroupName
    }
    elseif(!(Get-AzureRmStorageAccount -Name $StorageAccountName -ResourceGroupName $resourceGroupName))
    {
        write-host "creating storage account: $($storageAccountName)"
        $StorageAccount = New-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -Type $StorageType -Location $Location
    }
    else
    {
        $StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
    }

    # see if only one vnet if name empty and use that
    if([string]::IsNullOrEmpty($vnetName) -and @(Get-AzureRmVirtualNetwork -ResourceGroupName $resourceGroupName).Count -eq 1)
    {
        $vNet = Get-AzureRmVirtualNetwork -ResourceGroupName $resourceGroupName
        write-host = "using default vnet:$($vnet.Name)"
    }
    elseif(!(Get-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName $resourceGroupName))
    {
        if([string]::IsNullOrEmpty($VNetName))
        {
            $VNetName = "$vnetNamePrefix$($resourceGroupName)"
        }

        if([string]::IsNullOrEmpty($subnetName))
        {
            $subNetName = "$subnetNamePrefix$($resourceGroupName)"
        }

        write-host "creating vnet: $($vnetName)"
        write-host "creating subnet: $($subnetName)"
        $SubnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $VNetSubnetAddressPrefix 
        $VNet = New-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix $VNetAddressPrefix -Subnet $SubnetConfig
    }
    else
    {
        $VNet = Get-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -Location $Location
    }

    # see if only one subnet if name empty and use that
    if([string]::IsNullOrEmpty($subnetName) -and @(Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet).Count -eq 1)
    {
        $subnetConfig = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet
        write-host = "using default subnet:$($subnetConfig.Name)"
    }
    elseif(!(Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName))
    {
        write-host "creating subnet: $($subnetName)"
        $SubnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $VNetSubnetAddressPrefix
        $vnet.Subnets.Add($SubnetConfig)
    }
    else
    {
        $SubnetConfig = Get-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $VNetName
    }

    for($i = $vmstartCount;$i -lt $vmstartcount + $VMCount;$i++)
    {
        $newVmName = "$($vmBaseName)-$($i.ToString("D3"))"
        
        if(Get-AzureRMVM -resourceGroupName $resourceGroupName -Name $newVMName -ErrorAction SilentlyContinue)
        {
            Write-Host "vm already exists $newVMName. skipping..."
        }
        else
        {
            write-host "adding new machine name to list: $($newvmName)"
            $newVmNames.Add($newVmName)
        }
    }

    foreach($VMName in $newVMNames)
    {
        # todo make concurrent with start-job?

        Write-Host "creating vm $VMName"
        $OSDiskName = $VMName + "OSDisk"
        $InterfaceName = "$($vmName)Interface1"

        # Network
        if($publicIp)
        {
            write-host "creating public ip"
            $PIp = New-AzureRmPublicIpAddress -Name $InterfaceName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Dynamic
            $Interface = New-AzureRmNetworkInterface -Name $InterfaceName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $VNet.Subnets[0].Id -PublicIpAddressId $PIp.Id
        }
        else
        {
            $Interface = New-AzureRmNetworkInterface -Name $InterfaceName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $VNet.Subnets[0].Id
        }

        # Compute
        ## Setup local VM object

        $VirtualMachine = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize
        $VirtualMachine = Set-AzureRmVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $VMName -Credential $global:Credential -ProvisionVMAgent -EnableAutoUpdate
        $VirtualMachine = Set-AzureRmVMSourceImage -VM $VirtualMachine -PublisherName $pubName -Offer $offerName -Skus $galleryImage -Version "latest"
        $VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $Interface.Id
        $OSDiskUri = $StorageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/" + $OSDiskName + ".vhd"
        $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -Name $OSDiskName -VhdUri $OSDiskUri -CreateOption FromImage

        ## Create the VM in Azure
        New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VirtualMachine
    }

    write-host "finished"
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
        Add-AzureRmAccount
    }

    if($force)
    {
        Login-AzureRmAccount
    }


    #if($force -or ([string]::IsNullOrEmpty($adminPassword) -or [string]::IsNullOrEmpty($user)))
    #{
        if($global:credential -eq $null)
        {
            $global:Credential = Get-Credential
        }
    #}
}
# ----------------------------------------------------------------------------------------------------------------

function enum-subscription()
{
    If([string]::IsNullOrEmpty($location))
    {
        write-host "AVAILABLE LOCATIONS:" -ForegroundColor Green
        write-host (Get-AzureRmLocation | fl * | out-string)
        write-host "need location:exiting"
        return
    }

    write-host "CURRENT SUBSCRIPTION:" -ForegroundColor Green
    Get-AzureRmSubscription

    write-host "CURRENT VMS:" -ForegroundColor Green
    Get-AzureRmVM | out-gridview

    write-host "AVAILABLE LOCATIONS:" -ForegroundColor Green
    Get-AzureRmLocation | out-gridview
    write-host "AVAILABLE IMAGES:" -ForegroundColor Green
    Get-AzureRMVMImage -Location $location -PublisherName $pubName -Offer $offerName -Skus $galleryImage | out-gridview
    write-host "AVAILABLE ROLES:" -ForegroundColor Green
    Get-AzureRoleSize | out-gridview
    write-host "AVAILABLE STORGE:" -ForegroundColor Green
    Get-AzureRmStorageAccount | out-gridview
    write-host "AVAILABLE NETWORKS:" -ForegroundColor Green
    Get-AzureRmVirtualNetwork | out-gridview
    write-host "AVAILABLE SUBNETS:" -ForegroundColor Green
    #write-host (Get-AzureRmVirtualNetworkSubnetConfig | fl * | out-gridview)
}
# ----------------------------------------------------------------------------------------------------------------

main