param(
    [string]$location = "eastus",
    [string]$vmSize = "Basic_A1",
    [string]$publisher = "MicrosoftWindowsServer", #"Canonical"
    [string]$offer = "WindowsServer", #"UbuntuServer"
    [string]$imagesku = "2019-Datacenter-with-containers", #"18.04-LTS"
    [switch]$showDetail
)

write-host "checking location $($location)"
$locations = Get-azLocation

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
$publishers = Get-azVMImagePublisher -Location $location 

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
$vmSizes = Get-azVMSize -Location $location

if (!($vmSizes | Where-Object Name -Like $vmSize))
{
    $vmSizes
    write-warning "vmSize: $($vmSize) not found in $($location). correct -vmSize using one of the above options and restart script."
    return
}

if($showDetail)
{
    $vmSizes | fl *
}

write-host "checking sku $($publisherName) $($offer) $($imageSku)"
write-host "Get-azVMImageSku -Location $location -PublisherName $publisherName -Offer $offer"
$skus = Get-azVMImageSku -Location $location -PublisherName $publisherName -Offer $offer

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

if($showDetail)
{
    foreach($sku in $skus)
    {
        write-host "checking sku image $($publisherName) $($offer) $($imageSku) $($sku.skus)"
        $imageskus = Get-azVMImage -Location $location -PublisherName $publisherName -Offer $offer -skus $sku.skus
        $imageskus | fl *
    }
}