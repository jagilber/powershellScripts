param(
    [string]$location = "eastus",
    [string]$vmSize = "BASIC_A1",
    [string]$publisher = "MicrosoftWindowsServer", #"Canonical"
    [string]$offer = "WindowsServer", #"UbuntuServer"
    [string]$imagesku = "2016-Datacenter-with-containers", #"18.04-LTS"
    [switch]$showDetail
)

write-host "checking location $($location)"
$locations = Get-AzureRmLocation

if (!($locations | Where-Object Location -Like $location) -or !$location)
{
    $locations.Location
    write-warning "location: $($location) not found. supply -location using one of the above locations and restart script."
    return
}

if($showDetail)
{
    $locations.location
}

write-host "checking publisher $($publisher)"
$publishers = Get-AzureRmVMImagePublisher -Location $location 

if(!($publishers| Where-Object PublisherName -Match $publisher))
{
    $publishers
    write-warning "publisher: $($publisher) not found. supply -location using one of the above locations and restart script."
    return
}

$publisherName = ($publishers| Where-Object PublisherName -Match $publisher)[0].PublisherName

if($showDetail)
{
    $publishers | fl *
}

write-host "checking vm size $($vmSize) in $($location)"
$vmSizes = Get-AzureRmVMSize -Location $location

if (!($vmSizes | Where-Object Name -Like $vmSize))
{
    $vmSizes
    write-warning "rdshVmSize: $($vmSize) not found in $($location). correct -rdshVmSize using one of the above options and restart script."
    return
}

if($showDetail)
{
    $vmSizes | fl *
}

write-host "checking sku $($publisherName) $($offer) $($imageSku)"
$skus = Get-AzureRmVMImageSku -Location $location -PublisherName $publisherName -Offer $offer

if (!($skus | Where-Object Skus -Like $imageSKU))
{
    $skus
    write-warning "image sku: $($imageSku) not found in $($location). correct -imageSKU using one of the above options and restart script."
    return
}

if($showDetail)
{
    $skus | fl *
}