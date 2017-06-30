# script to create multiple vm's into existing infrastructure
# 150722

# vm name prefix
#$VMNames = @("rds-dc-";"rds-rds-";"rds-cb-";"rds-gw-";"rds-lic-")
$VMNames = @("rds-lic-")

# number of vms to create
$VMCount = 1
$startCount = 1

$subscriptionId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$ServiceName = 'rds-ms'

$AdminPassword = '%password%'
$User = '%user%'

# needs to exist
$Location = 'East US 2'
# needs to exist
# datacenter 2012 r2
#$imagelist = Get-AzureVMImage
#$imageList | ? Label -match "datacenter" | Select Label,ImageName

#2012r2 datacenter
$Image = 'a699494373c04fc0bc8f2bb1389d6106__Windows-Server-2012-R2-201506.01-en.us-127GB.vhd'

#2014 sql
$Image = 'fb83b3509582419d99629ce476bcb5c8__SQL-Server-20140SP1-12.0.4100.1-Ent-ENU-Win2012R2-cy15su05'

$InstanceSize = 'Small' #extra small only for testing

# needs to exist
$VNetName = 'msvnetbase'
# needs to exist
$SubnetName = 'Subnet-1'

# needs to exist
$StorageAccountName = '%storagename%'
$StorageLocation = "https://$($StorageAccountName).blob.core.windows.net/vhds/"

Set-AzureSubscription -SubscriptionId $subscriptionId -CurrentStorageAccountName $StorageAccountName
Select-AzureSubscription -SubscriptionId $subscriptionId 

# see if we need to auth
try
{
    $ret = Get-AzureService 
}
catch 
{
    Add-AzureAccount
}

# check to make sure vm doesnt exist

$jobs = @()
$newVmNames = @()
$Error.Clear()

foreach($VMName in $VMNames)
{
    $i = $startCount
    while(Get-AzureVM -ServiceName $ServiceName -Name $VMName$i)
    {
        Write-Host "vm already exists $VMName$i"
        $i++
        
    }

    $VMStartCount = $i

    Write-Host "starting vm name $VMName$i"

    for ($i; $i -lt ($VMCount + $VMStartCount); $i++)
    {
        Write-Host "creating vm $VMName$i"
        $newVmName = "$VMName$i"
        #Test-AzureStaticVNetIP –VNetName $jVNetName –IPAddress <IP address>
        
        if(!(Get-AzureService -ServiceName $ServiceName))
        {
            New-AzureService -ServiceName $ServiceName -Location $Location -Label $ServiceName -Description $ServiceName    
        }

        $newVm = $null
        $newVM = New-AzureVMConfig -Name $newVmName -InstanceSize $InstanceSize -ImageName $Image -MediaLocation "$StorageLocation$newVmName.vhd"
        $newVM = Add-AzureProvisioningConfig -VM $newVM -Windows -AdminUsername $User -Password $AdminPassword 
        $newVM = Set-AzureSubnet -VM $newVM -SubnetNames $SubnetName 
        #$newVM = Set-AzureStaticVNetIP -VM $newVm -IPAddress <IP address>
    
        New-AzureVM -VMs $newVM -ServiceName $ServiceName -VNetName $VNetName
      #  New-AzureVM -VMs $newVM -ServiceName $ServiceName -ServiceLabel $ServiceName -ServiceDescription $ServiceName -VNetName $VNetName -Location $Location
    
        $newVmNames += $newVmName
    }

}


foreach($vmName in $newVMNames)
{
    $vm = get-azurevm -ServiceName $ServiceName -Name $vmName
    write-host "$(get-date) final vm powerstate $($vm.name):$($vm.PowerState)"
}


write-host "finished"