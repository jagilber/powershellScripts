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
$ErrorActionPreference = 'continue'

function main() {
    if (!(connect-az)) { return }

    if (!$build) {
        $build = [convert]::toint32((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId)
        write-host "using local machine build $build"
    }

    enumerate-containerRegistry $build

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
            if ($sku.Id -match "(^|\D)$build(\D|$)") {
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

function connect-az() {
    $moduleList = @('az.accounts','az.compute')
    
    foreach($module in $moduleList) {
        write-host "checking module $module" -ForegroundColor Yellow

        if(!(get-module -name $module -listavailable)) {
            write-host "installing module $module" -ForegroundColor Yellow
            install-module $module -force
            import-module $module
            if(!(get-module -name $module -listavailable)) {
                return $false
            }
        }
    }

    if(!(@(Get-AzResourceGroup).Count)) {
        $error.clear()
        Connect-AzAccount

        if ($error -and ($error | out-string) -match '0x8007007E') {
            $error.Clear()
            Connect-AzAccount -UseDeviceAuthentication
        }
    }

    return $null = get-azcontext
}

function enumerate-containerRegistry($build) {
    $mcrRepositories = Invoke-RestMethod 'https://mcr.microsoft.com/v2/_catalog'
    write-verbose "mcr repositories: $($mcrRepositories.Repositories | fl * | out-string)"
    
    write-verbose "dotnet repositories: $($mcrRepositories.Repositories -match 'dotnet' | fl * | out-string)"

    $serverRepos = $mcrRepositories.Repositories -match 'windows.+server'
    write-verbose "server repositories: $($serverRepos | fl * | out-string)"

    foreach($serverRepo in $serverRepos) {
        write-host "repo tags for repo: $serverRepo" -ForegroundColor Cyan
        $repoTags = Invoke-RestMethod "https://mcr.microsoft.com/v2/$serverRepo/tags/list"
        foreach($tag in $repoTags.tags){
            if($tag -match "(^|\D)$build(\D|$)") {
                write-host "`t$tag"
            }
            else {
                write-verbose "`t$tag"
            }
        }
    }
}

main