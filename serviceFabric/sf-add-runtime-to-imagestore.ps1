param(
    $downgradePackageName = '10.0.1949.9590',
    $downgradePackage = '', #"C:\Packages\Plugins\Microsoft.Powershell.DSC\2.83.5\DSCWork\DSC.0\MicrosoftAzureServiceFabric.10.0.1949.9590.cab",
    $clusterManifest = "$pwd\ClusterManifest.xml",
    [switch]$whatIf,
    [switch]$force,
    [switch]$upgrade
)

# $force = $true

$ErrorActionPreference = 'continue'
$disabledConfig = "$pwd\config-upgrade-disabled.json"
$enabledConfig = "$pwd\config-upgrade-enabled.json"

function main() {
    if (!(get-module servicefabric)) {
        import-module servicefabric
          
    }
    if (!(Get-ServiceFabricClusterConnection)) {
        connect-servicefabriccluster
    }

    if (!(Get-ServiceFabricClusterConnection)) {
        write-error "error connecting to cluster. troubleshoot connect-servicefabriccluster cmdlet"
        return
    }

    $supportedVersions = Get-ServiceFabricRuntimeSupportedVersion
    write-host "supported versions:`r`n$($supportedVersions | out-string)"

    if (!$downgradePackage -and !$downgradePackageName) {
        write-error "supply `$downgradePackageName"
        return
    }
    if (!$downgradePackage) { $downgradePackage = "$downgradePackageName.cab" }
    if (!(test-path $downgradePackage)) {
        write-error "$downgradePackage does not exist"
        if ($supportedVersions.Version.Contains($downgradePackageName)) {
            $supportedVersion = $supportedVersions | where-object Version -ieq $downgradePackageName
            $downgradePackage = "$pwd\$downgradePackageName.cab"
            write-host "downloading version $downgradePackageName to $downgradePackage"
            if (!(test-path $downgradePackage) -and !$force) {
                [net.webclient]::new().downloadFile($supportedVersion.TargetPackageLocation, $downgradePackage)
            }
            else {
                write-host "$downgradePackage exists"
            }
        }
        else {
            write-error "unabled to download version requested. download runtime cab and restart script with `$downloadPackage"
            return
        }
    }

    $currentConfigJson = Get-ServiceFabricClusterConfiguration
    write-host "current configuration:`r`n$currentConfigJson"
    $currentConfig = ConvertFrom-Json $currentConfigJson
    if ($currentConfig.Properties.FabricClusterAutoupgradeEnabled) {
        write-warning "Automatic cluster upgrade is enabled. saving enabled configuration"
        out-file -InputObject $currentConfigJson -FilePath $enabledConfig

        write-warning "Automatic cluster upgrade is enabled. saving disabled configuration"
        $currentConfig.Properties.FabricClusterAutoupgradeEnabled = $false
        $version = 1
        if ([int]::TryParse($currentConfig.ClusterConfigurationVersion, [ref] $version)) {
            $currentConfig.ClusterConfigurationVersion = ($version + 1).ToString()
        }
        else {
            $currentConfig.ClusterConfigurationVersion = "1"
        }
        $disabledConfigJson = ConvertTo-Json $currentConfig -Depth 99 
        out-file -InputObject $disabledConfigJson -FilePath $disabledConfig
        write-host "Start-ServiceFabricClusterConfigurationUpgrade -ClusterConfigPath `"$disabledConfig`"" -ForegroundColor Green
        if (!$whatIf -and $force) {
            Start-ServiceFabricClusterConfigurationUpgrade -ClusterConfigPath $disabledConfig
        }
        else {
            write-host "review configuations and run the above command to disable automatic runtime upgrade before downgrading and restart script"
            return
        }
    }

    if (!(test-path $clusterManifest)) {
        $clusterManifestName = $clusterManifest
        $currentManifestXml = Get-ServiceFabricClusterManifest
        $clusterManifest = "$pwd\$clusterManifest"
        write-host "saving manifest xml to file $clusterManifest"
        out-file -InputObject $currentManifestXml -FilePath $clusterManifest
    }
    else {
        $clusterManifestName = [io.path]::GetFileName($clusterManifest)
    }
    
    $currentRegisteredRuntimeVersions = @(Get-ServiceFabricRegisteredClusterCodeVersion)

    $imageStoreContainsDowngradeVersion = $currentRegisteredRuntimeVersions.CodeVersion.Contains($downgradePackageName)
    write-host "current registered runtime versions:$($currentRegisteredRuntimeVersions | out-string)"
    write-host "image store contains downgrade version: $imageStoreContainsDowngradeVersion"

    $currentImageStoreContent = Get-ServiceFabricImageStoreContent
    write-host "current packages:$($currentImageStoreContent | out-string)"
      
      
    write-host "using downgrade package name $downgradePackageName"
    if ($currentImageStoreContent.StoreRelativePath.Contains($downgradePackageName) -and $force) {
        write-warning "$downgradePackageName already exists. removing"
        #write-host "Unregister-ServiceFabricClusterPackage -ClusterManifestVersion $clusterManifestName -CodePackageVersion $downgradePackageName"
        write-host "Unregister-ServiceFabricClusterPackage -Code -CodePackageVersion $downgradePackageName"
        if (!$whatIf) {
            #Unregister-ServiceFabricClusterPackage -ClusterManifestVersion $clusterManifestName -CodePackageVersion $downgradePackageName
            Unregister-ServiceFabricClusterPackage -Code -CodePackageVersion $downgradePackageName
        }
    }
    elseif ($currentImageStoreContent.StoreRelativePath.Contains($downgradePackageName)) {
        write-warning "$downgradePackageName already exists"
        if (!$whatIf) { return }
    }

    
    write-host "copying package to image store"
    # write-host "Copy-ServiceFabricClusterPackage -Code ``
    #     -CodePackagePath $downgradePackage ``
    #     -CodePackagePathInImageStore $downgradePackageName ``
    #     -ImageStoreConnectionString 'fabric:ImageStore'
    # "

    # if (!$whatIf) {
    #     Copy-ServiceFabricClusterPackage -Code `
    #         -CodePackagePath $downgradePackage `
    #         -CodePackagePathInImageStore $downgradePackageName `
    #         -ImageStoreConnectionString 'fabric:ImageStore'
    # }

    write-host "Copy-ServiceFabricClusterPackage ``
              -ClusterManifestPath $clusterManifest ``
              -ClusterManifestPathInImageStore $clusterManifestName ``
              -CodePackagePath $downgradePackage ``
              -CodePackagePathInImageStore $downgradePackageName ``
              -ImageStoreConnectionString 'fabric:ImageStore' ``
              -Verbose
          "

    if (!$whatIf) {
        Copy-ServiceFabricClusterPackage `
            -ClusterManifestPath $clusterManifest `
            -ClusterManifestPathInImageStore $clusterManifestName `
            -CodePackagePath $downgradePackage `
            -CodePackagePathInImageStore $downgradePackageName `
            -ImageStoreConnectionString 'fabric:ImageStore' `
            -Verbose
    }

    write-host "Register-ServiceFabricClusterPackage -ClusterManifestPath $clusterManifestName -CodePackagePath $downgradePackageName"
    #write-host "Register-ServiceFabricClusterPackage -Code -CodePackagePath $downgradePackageName"
    if (!$whatIf) {
        Register-ServiceFabricClusterPackage -ClusterManifestPath $clusterManifestName -CodePackagePath $downgradePackageName
        #Register-ServiceFabricClusterPackage -Code -CodePackagePath $downgradePackageName
    }
    
    if ($upgrade) {
        write-host "Start-ServiceFabricClusterUpgrade -ClusterManifestVersion $clusterManifestName -CodePackageVersion $downgradePackageName -UnmonitoredAuto"
        if (!$whatIf) {
            Start-ServiceFabricClusterUpgrade -ClusterManifestVersion $clusterManifestName -CodePackageVersion $downgradePackageName -UnmonitoredAuto
        }    
    }
}

main