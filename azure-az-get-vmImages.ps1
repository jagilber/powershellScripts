<#
    script to enumerate os versions from azure
    iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-get-vmImages.ps1" -out "$pwd\azure-az-get-vmImages.ps1";
    .\azure-az-get-vmImages.ps1
    .\azure-az-get-vmImages.ps1 -location eastus -showDetail > c:\temp\output.json
#>

param(
    [string]$location = "eastus",
    [string]$vmSize = "Basic_A1",
    [string]$publisher = "MicrosoftWindowsServer", #"Canonical"
    [string]$offer = "WindowsServer", #"UbuntuServer"
    [string]$imagesku = "2022-Datacenter", #"18.04-LTS"
    [switch]$showDetail
)

write-host "checking location $($location)"
$locations = Get-azLocation

if (!($locations | Where-Object Location -Like $location) -or !$location) {
    $locations.Location
    write-warning "location: $($location) not found. supply -location using one of the above locations and restart script."
    return
}

if ($showDetail) {
    $locations.location
}

write-host "checking publisher $($publisher)"
write-host "Get-azVMImagePublisher -Location $location"
$publishers = Get-azVMImagePublisher -Location $location 

if (!($publishers | Where-Object PublisherName -Match $publisher)) {
    $publishers
    write-warning "publisher: $($publisher) not found. supply -location using one of the above locations and restart script."
    return
}

$publisherName = ($publishers | Where-Object PublisherName -Match $publisher)[0].PublisherName

if ($showDetail) {
    $publishers | Format-List *
}

write-host "checking vm size $($vmSize) in $($location)"
write-host "Get-azVMSize -Location $location"
$vmSizes = Get-azVMSize -Location $location

if (!($vmSizes | Where-Object Name -Like $vmSize)) {
    $vmSizes
    write-warning "vmSize: $($vmSize) not found in $($location). correct -vmSize using one of the above options and restart script."
    return
}

if ($showDetail) {
    $vmSizes | Format-List *
}

write-host "checking sku $($publisherName) $($offer) $($imageSku)"
write-host "Get-azVMImageSku -Location $location -PublisherName $publisherName -Offer $offer"
if ($showDetail) {
    $skus = Get-azVMImageSku -Location $location -PublisherName $publisherName -Offer $offer
}
else {
    $skus = Get-azVMImageSku -Location $location -PublisherName $publisherName -Offer $offer | Where-Object Skus -Like $imageSKU
}

if (!($skus | Where-Object Skus -Like $imageSKU)) {
    $skus
    write-warning "image sku: $($imageSku) not found in $($location). correct -imageSKU using one of the above options and restart script."
    return
}

if ($showDetail) {
    $skus | Format-List *
}

foreach ($sku in $skus) {
    write-host "checking sku image $($publisherName) $($offer) $($imageSku) $($sku.skus)"
    write-host "Get-azVMImage -Location $location -PublisherName $publisherName -Offer $offer -skus $($sku.skus)" -ForegroundColor Cyan
    $imageSkus = Get-azVMImage -Location $location -PublisherName $publisherName -Offer $offer -skus $sku.skus
    $orderedSkus = [collections.generic.list[version]]::new()
    $orderedList = [collections.arraylist]::new()

    foreach ($image in $imageSkus) {
        [void]$orderedSkus.Add([version]::new($image.Version)) 
    }

    $orderedSkus = $orderedSkus | Sort-Object

    foreach ($orderedSku in $orderedSkus) {
        $sku = $imageSkus | where-object Version -ieq $orderedSku.ToString()
        [void]$orderedList.Add($sku)
    }

    if ($showDetail) {
        $orderedList | Format-List *
    }
    else {
        $orderedList | format-table -Property Version, Skus, Offer, PublisherName
    }
}