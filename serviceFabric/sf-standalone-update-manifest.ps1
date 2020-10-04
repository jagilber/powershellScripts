<#
.SYNOPSIS
    update standalone cluster manifest

.LINK
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-standalone-update-manifest.ps1" -outFile "$pwd\sf-standalone-update-manifest.ps1";
    .\sf-standalone-update-manifest.ps1 -resourceGroupName {{ resource group name }} -vmScaleSetName {{ vm scaleset name }}
#>

param(
    $newManifest = "$pwd\ClusterManifest.new.xml",
    $imagePath = 'ClusterManifest.xml'
)

$ErrorActionPreference = 'stop'
$xml = [xml]::new()

if (!(Get-ServiceFabricClusterConnection)) {
    import-module servicefabric
    connect-servicefabriccluster
}

if (!(test-path $newManifest)) {
    Get-ServiceFabricClusterManifest | out-file $newManifest
    $xml.Load($newManifest)
    $currentVersion = [convert]::ToInt32($xml.ClusterManifest.Version)
    $newVersion = $currentVersion + 1
    write-host "current cluster manifest version: $($currentVersion)"

    notepad $newManifest
    
    write-host "modify $($newManifest) with changes and use Version=`"$($newVersion)`" in cluster manifest xml schema"
    write-host "restart script to update configuration"
}
else {
    $xml.Load($newManifest)
    $version = [convert]::ToInt32($xml.ClusterManifest.Version)

    write-host "Copy-ServiceFabricClusterPackage -Config `
        -ClusterManifestPath $newManifest `
        -ClusterManifestPathInImageStore $imagePath `
        -ImageStoreConnectionString 'fabric:ImageStore'
    "
    Copy-ServiceFabricClusterPackage -Config `
        -ClusterManifestPath $newManifest `
        -ClusterManifestPathInImageStore $imagePath `
        -ImageStoreConnectionString 'fabric:ImageStore'

    write-host "Register-ServiceFabricClusterPackage -Config -ClusterManifestPath $imagePath"

    Register-ServiceFabricClusterPackage -Config -ClusterManifestPath $imagePath
    
    write-host "Start-ServiceFabricClusterUpgrade -Config `
        -ClusterManifestVersion $version `
        -FailureAction Rollback `
        -Monitored
    "
    Start-ServiceFabricClusterUpgrade -Config `
        -ClusterManifestVersion $version `
        -FailureAction Rollback `
        -Monitored

    while($true) {
        $status = Get-ServiceFabricClusterUpgrade
        if($status -inotmatch 'rolling') {
            write-host $status
            return
        }

        $status
        start-sleep -Seconds 1
    }
}
