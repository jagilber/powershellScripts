<#
.SYNOPSIS
    powershell script to match local / given windows image build number with matching azure image skus

.LINK
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-image-build-match.ps1" -outFile "$pwd\azure-az-image-build-match.ps1";
    .\azure-az-image-build-match.ps1 -location {{ location }} -build {{ build }}

.DESCRIPTION  

.NOTES  
    File Name  : azure-az-image-build-match.ps1
    Author     : jagilber
    Version    : 200801
    History    : 

.EXAMPLE 
    .\azure-az-image-build-match.ps1
    query local machine for build number and use defaults for location, publisher, and imagesku

.EXAMPLE 
    .\azure-az-image-build-match.ps1 -location eastus
    query local machine for build number using location eastus and use defaults for publisher, and imagesku

.EXAMPLE 
    .\azure-az-image-build-match.ps1 -build 2004
    use build number 2004 and use defaults for location, publisher, and imagesku

#>

[cmdletbinding()]
param(
    [int]$build , #= 1803, #= 1903, #= 2004,
    [string]$location = "westus",
    [string]$publisher = "MicrosoftWindowsServer", #"Canonical"
    [string]$offerName = "WindowsServer", #"UbuntuServer"
    [string]$imagesku = "2019-Datacenter-with-containers" #"2016-Datacenter-with-containers" #"18.04-LTS"
)

$error.Clear()
set-strictMode -Version 3.0
$PSModuleAutoLoadingPreference = 2

function main() {
    if (!(check-module)) { return }

    if (!(Get-AzContext)) {
        Connect-AzAccount
    }

    if (!$build) {
        $build = [convert]::toint32((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId)
        write-host "using local machine build $build"
    }

    $skus = $null
    foreach ($offerInfo in (get-azvmimageoffer -Location $location -PublisherName $publisher | ? Offer -imatch $offerName)) {
        $offer = $offerInfo.Offer
        write-host "checking sku $($publisher) $($offer) $($imageSku)" -ForegroundColor Magenta
        write-host "Get-azVMImageSku -Location $location -PublisherName $publisher -Offer $offer"
        $skus += Get-azVMImageSku -Location $location -PublisherName $publisher -Offer $offer
        Write-Verbose "all skus:"

        foreach ($sku in $skus) {
            Write-Verbose ($sku.Id)
        }

        write-host "filtered skus:" -ForegroundColor Yellow

        foreach ($sku in $skus) {
            if ($sku.Id.contains("-$build-")) {
                Write-Verbose ($sku | fl * | out-string)
                $image = Get-AzVMImage -Location $location -PublisherName $publisher -Offer $offer -Skus $sku.Skus -ErrorAction SilentlyContinue
                
                if ($image) {
                    write-host "Get-AzVMImage -Location $location -PublisherName $publisher -Offer $offer -Skus $($sku.Skus)"
                    write-host "image: $($image | fl * | out-string)" -ForegroundColor Magenta
                }
            }
        }
    }
}

function check-module() {
    $error.clear()
    get-command Connect-AzAccount -ErrorAction SilentlyContinue
    
    if ($error) {
        $error.clear()
        write-warning "azure module for Connect-AzAccount not installed."

        if ((read-host "is it ok to install latest azure az module?[y|n]") -imatch "y") {
            $error.clear()
            install-module az.accounts
            install-module az.compute

            import-module az.accounts
            import-module az.compute
        }
        else {
            return $false
        }

        if ($error) {
            return $false
        }
    }

    return $true
}

main