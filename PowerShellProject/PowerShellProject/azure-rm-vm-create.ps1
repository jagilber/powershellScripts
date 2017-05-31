# script to create multiple vm's into existing azure rm infrastructure
# 161120

param(
    [string]$admin="vmadmin", # todo:remove
    [string]$adminPassword="", # todo:remove
    [switch]$enumerateSub,
    [switch]$force,
    [string]$galleryImage="2016-Datacenter",
    [string]$location="eastus", # todo:remove
    [string]$offername="WindowsServer",
    [switch]$publicIp=$true,
    [string]$pubName="MicrosoftWindowsServer",
    [string]$resourceGroupName,
    [string]$StorageAccountName,
    [string]$StorageType = "Standard_GRS",
    [string]$subnetName="",
    [string]$subscription,
    
    [string]$vmBaseName="tpl", # todo:remove
    [int]$vmCount= 1,
    [string]$vmSize="Standard_A1",
    [int]$vmStartCount=1,
    [string]$VNetAddressPrefix = "10.0.0.0/16",
    [string]$VNetSubnetAddressPrefix = "10.0.0.0/24",
    [string]$vnetName=""
)

$ErrorActionPreference = "SilentlyContinue"
$vnetNamePrefix = "ADVNET"
$subnetNamePrefix = "ADStaticSubnet"
$storagePrefix = "storage"
$global:credential
$global:storageAccount
$global:vnet

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    authenticate-azureRm
    
    manage-credential

    if($enumerateSub)
    {
        enum-subscription
        return
    }

    if([string]::IsNullOrEmpty($location) -or `
        [string]::IsNullOrEmpty($resourceGroupName) -or `
        [string]::IsNullOrEmpty($galleryImage) -or `
        [string]::IsNullOrEmpty($pubName) -or `
        [string]::IsNullOrEmpty($VMSize))
        {
            write-host "missing required argument"
            return
        }


    # check to make sure vm doesnt exist
    $i = $startCount
    $jobs = @()
    $newVmNames = new-object Collections.ArrayList
    $Error.Clear()

    $resourceGroupName = check-resourceGroupName -resourceGroupName $resourceGroupName

    $storageAccountName = check-storageAccountName -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName

    $vnetName = check-vnetName -resourceGroupName $resourceGroupName -vnetName $vnetName
    
    $subnetName = check-subnetName -resourceGroupName $resourceGroupName -vnetName $vnetName -subnetName $subnetName

    foreach($VMName in $newVMNames)
    {
        # todo make concurrent with start-job?
        # would need cert conn to azure

        Write-Host "creating vm $VMName"
        $OSDiskName = $VMName + "OSDisk"
        $InterfaceName = "$($vmName)Interface1"

        # Network
        if($publicIp)
        {
            write-host "creating public ip"
            $PIp = New-AzureRmPublicIpAddress -Name $InterfaceName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Dynamic
            $Interface = New-AzureRmNetworkInterface -Name $InterfaceName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $global:vnet.Subnets[0].Id -PublicIpAddressId $PIp.Id
        }
        else
        {
            $Interface = New-AzureRmNetworkInterface -Name $InterfaceName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $global:vnet.Subnets[0].Id
        }

        # Compute
        ## Setup local VM object

        $VirtualMachine = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize
        $VirtualMachine = Set-AzureRmVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $VMName -Credential $global:Credential -ProvisionVMAgent -EnableAutoUpdate
        $VirtualMachine = Set-AzureRmVMSourceImage -VM $VirtualMachine -PublisherName $pubName -Offer $offerName -Skus $galleryImage -Version "latest"
        $VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $Interface.Id
        $OSDiskUri = $global:StorageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/" + $OSDiskName + ".vhd"
        $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -Name $OSDiskName -VhdUri $OSDiskUri -CreateOption FromImage

        ## Create the VM in Azure
        New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VirtualMachine
    }

    write-host "finished"
    return $newVmNames
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
}
# ----------------------------------------------------------------------------------------------------------------

function check-resourceGroupName($resourceGroupName)
{
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

    return $resourceGroupName
}
# ----------------------------------------------------------------------------------------------------------------

function check-storageAccountName($resourceGroupName, $StorageAccountName)
{
    # see if only one storage account if name empty and use that
    if([string]::IsNullOrEmpty($storageAccountName) -and @(Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName).Count -eq 1)
    {
        $global:storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName
        write-host = "using default storage account:$($storageAccount.Name)"
    }
    elseif([string]::IsNullOrEmpty($storageAccountName) -and @(Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName).Count -gt 1)
    {
        foreach($storageName in Get-AzureRmStorageAccount -resourcegroupname $resourcegroupname)
        {
            write-host $storageName.StorageAccountName
        }

        $storageAccountName = read-host "enter storage account"
        if([string]::IsNullOrEmpty($storageAccountName))
        {
            return
        }

        $global:storageAccount = Get-AzureRmStorageAccount -Name $StorageAccountName -ResourceGroupName $resourceGroupName
    }
    elseif(([string]::IsNullOrEmpty($storageAccountName) -and @(Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName).Count -lt 1) `
        -or !(Get-AzureRmStorageAccount -Name $StorageAccountName -ResourceGroupName $resourceGroupName))
    {
        if([string]::IsNullOrEmpty($storageAccountName))
        {

            $storageAccountName = ("$($storagePrefix)$($resourceGroupName)").ToLower()
            $storageAccountName = $storageAccountName.Substring(0,[Math]::Min($storageAccountName.Length,23))
        }

        write-host "creating storage account: $($storageAccountName)"
        $global:StorageAccount = New-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -Type $StorageType -Location $Location
    }
    elseif((Get-AzureRmStorageAccount -Name $StorageAccountName -ResourceGroupName $resourceGroupName))
    {
        $global:StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
    }
    else
    {
        write-host "need storage account name. exiting"
        return
    }

    return $storageAccountName
}
# ----------------------------------------------------------------------------------------------------------------

function check-vnetName($resourceGroupName, $vnetName)
{
    $global:vnet = @(Get-AzureRmVirtualNetwork -ResourceGroupName $resourceGroupName)

    if(!$vnetName -and $global:vnet.Count -eq 1)
    {
        $vnetName = $global:vnet[0]
    }
    elseif(!$vnetName -and $global:vnet.count -gt 1)
    {
        $global:vnet
        $vnetName = read-host "Enter vnet name to use:"
    }
    elseif((!$vnetName -and $global:vnet.Count -lt 1) -or ($vnetName -and !(Get-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName $resourceGroupName)))
    {
        $VNetName = "$vnetNamePrefix$($resourceGroupName)"
        $subNetName = "$subnetNamePrefix$($resourceGroupName)"
        write-host "creating vnet: $($vnetName)"
        write-host "creating subnet: $($subnetName)"
        $SubnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $VNetSubnetAddressPrefix 
        $global:vnet = New-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix $VNetAddressPrefix -Subnet $SubnetConfig

    }
    elseif($vnetName -and (Get-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName $resourceGroupName))
    {
        return $vnetName
    }
    else
    {
        Write-Host "error determining vnet name. exiting"
        exit
    }


    return $vnetName
}
# ----------------------------------------------------------------------------------------------------------------

function check-subnetName($resourceGroupName, $vnetName, $subnetName)
{
    # see if only one subnet if name empty and use that
    if([string]::IsNullOrEmpty($subnetName) -and @(Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnetName).Count -eq 1)
    {
        $subnetConfig = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnetName
        write-host = "using default subnet:$($subnetConfig.Name)"
    }
    elseif(!(Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnetName -Name $subnetName))
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

function manage-credential()
{
    
    if([string]::IsNullOrEmpty($adminPassword) -or [string]::IsNullOrEmpty($admin))
    {
        write-host "either admin and / or adminpassword were empty, returning."
        return
    }

    $SecurePassword = $adminPassword | ConvertTo-SecureString -AsPlainText -Force  
    $global:credential = new-object System.Management.Automation.PSCredential -ArgumentList $admin, $SecurePassword
}
# ----------------------------------------------------------------------------------------------------------------

main