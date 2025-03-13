<#
.SYNOPSIS
Add a runtime package to the image store and register it with the cluster.

.DESCRIPTION
This script will download a runtime package from the service fabric runtime repository and add it to the image store. 
The package will be registered with the cluster and can be used to upgrade the cluster runtime.

.NOTES
  File Name      : sf-add-runtime-to-imagestore.ps1
  Author         : jagilber
  Prerequisite   : Service Fabric SDK

.PARAMETER newPackageVersion
  The version of the package to download and add to the image store.

.PARAMETER newPackagePath
  The path to the package to add to the image store. If not supplied, the package will be downloaded from the service fabric runtime repository.

.PARAMETER clusterManifest
  The path to the cluster manifest file. If not supplied, the current cluster manifest will be saved to the current directory.

.PARAMETER whatIf
  If present, the script will not make any changes.

.PARAMETER force
  If present, the script will remove the package from the image store if it already exists.

.PARAMETER upgrade
  If present, the script will start an upgrade of the cluster to the new package version.

.EXAMPLE
  .\sf-add-runtime-to-imagestore.ps1 -newPackageVersion 10.0.1949.9590 -upgrade
  Downloads the runtime package version 10.0.1949.9590 from the service fabric runtime repository and adds it to the image store. 
  The package is registered with the cluster and an upgrade is started.

.EXAMPLE
  .\sf-add-runtime-to-imagestore.ps1 -newPackagePath "C:\Packages\Plugins\Microsoft.Powershell.DSC\2.83.5\DSCWork\DSC.0\MicrosoftAzureServiceFabric.10.0.1949.9590.cab" -upgrade
  Adds the package at the specified path to the image store. The package is registered with the cluster and an upgrade is started.

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-add-runtime-to-imagestore.ps1" -outFile "$pwd/sf-add-runtime-to-imagestore.ps1";
    ./sf-add-runtime-to-imagestore.ps1 -newPackageVersion 10.0.1949.9590 -whatIf

#>

param(
  $newPackageVersion = '10.0.1949.9590',
  $newPackagePath = '', #"C:\Packages\Plugins\Microsoft.Powershell.DSC\2.83.5\DSCWork\DSC.0\MicrosoftAzureServiceFabric.10.0.1949.9590.cab",
  $clusterManifest = "$pwd\ClusterManifest.xml",
  [switch]$whatIf,
  [switch]$force,
  [switch]$upgrade
)

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

  if (!$newPackagePath -and !$newPackageVersion) {
    write-error "supply `$newPackageVersion"
    return
  }
  if (!$newPackagePath) { 
    $newPackagePath = "$pwd\$newPackageVersion.cab"
  }
  if (!(test-path $newPackagePath)) {
    write-error "$newPackagePath does not exist"
    
    if ($supportedVersions.Version.Contains($newPackageVersion)) {
      $supportedVersion = $supportedVersions | where-object Version -ieq $newPackageVersion
      
      write-host "downloading version $newPackageVersion to $newPackagePath"
      if (!(test-path $newPackagePath) -or $force) {
        write-host "[net.webclient]::new().downloadFile($($supportedVersion.TargetPackageLocation), $newPackagePath)"
        [net.webclient]::new().downloadFile($supportedVersion.TargetPackageLocation, $newPackagePath)
      }
      else {
        write-host "$newPackagePath exists"
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
      while ($true) {
        $status = Get-ServiceFabricClusterConfigurationUpgradeStatus
        if ($status.UpgradeState -ieq "RollingBackCompleted" -or $status.UpgradeState -ieq "RollingForwardCompleted") {
          break
        }
        start-sleep -Seconds 5
      }
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

  $imageStoreContainsDowngradeVersion = $currentRegisteredRuntimeVersions.CodeVersion.Contains($newPackageVersion)
  write-host "current registered runtime versions:$($currentRegisteredRuntimeVersions | out-string)"
  write-host "image store contains downgrade version: $imageStoreContainsDowngradeVersion"

  $currentImageStoreContent = Get-ServiceFabricImageStoreContent
  write-host "current packages:$($currentImageStoreContent | out-string)"
      
      
  write-host "using downgrade package name $newPackageVersion"
  if ($currentImageStoreContent.StoreRelativePath.Contains($newPackageVersion) -and $force) {
    write-warning "$newPackageVersion already exists. removing"
    #write-host "Unregister-ServiceFabricClusterPackage -ClusterManifestVersion $clusterManifestName -CodePackageVersion $newPackageVersion"
    write-host "Unregister-ServiceFabricClusterPackage -Code -CodePackageVersion $newPackageVersion"
    if (!$whatIf) {
      #Unregister-ServiceFabricClusterPackage -ClusterManifestVersion $clusterManifestName -CodePackageVersion $newPackageVersion
      Unregister-ServiceFabricClusterPackage -Code -CodePackageVersion $newPackageVersion
    }
  }
  elseif ($currentImageStoreContent.StoreRelativePath.Contains($newPackageVersion)) {
    write-warning "$newPackageVersion already exists"
  }
  else {
    
    write-host "copying package to image store"
    $newPackagePathFile = [io.path]::GetFileName($newPackagePath)
    $clusterManifestFile = [io.path]::GetFileName($clusterManifest)

    write-host "Copy-ServiceFabricClusterPackage ``
        -ClusterManifestPath $clusterManifest ``
        -ClusterManifestPathInImageStore $clusterManifestFile ``
        -CodePackagePath $newPackagePath ``
        -CodePackagePathInImageStore $newPackagePathFile ``
        -ImageStoreConnectionString 'fabric:ImageStore' ``
        -Verbose
    "

    if (!$whatIf) {
      Copy-ServiceFabricClusterPackage `
        -ClusterManifestPath $clusterManifest `
        -ClusterManifestPathInImageStore $clusterManifestFile `
        -CodePackagePath $newPackagePath `
        -CodePackagePathInImageStore $newPackagePathFile `
        -ImageStoreConnectionString 'fabric:ImageStore' `
        -Verbose
    }
  }
  write-host "Register-ServiceFabricClusterPackage -ClusterManifestPath $clusterManifestFile -CodePackagePath $newPackagePathFile"
  if (!$whatIf) {
    Register-ServiceFabricClusterPackage -ClusterManifestPath $clusterManifestFile -CodePackagePath $newPackagePathFile
  }
    
  if ($upgrade) {
    write-host "Start-ServiceFabricClusterUpgrade -Code -CodePackageVersion $newPackageVersion -UnmonitoredAuto"
    if (!$whatIf) {
      Start-ServiceFabricClusterUpgrade -Code -CodePackageVersion $newPackageVersion -UnmonitoredAuto
    }    
  }
}

main