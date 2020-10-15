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

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'stop'#'continue'
$xml = [xml]::new()

if (!(get-command Get-ServiceFabricClusterConnection)) {
    import-module servicefabric
    connect-servicefabriccluster
}

write-host "image store content:root" -ForegroundColor Yellow
Get-ServiceFabricImageStoreContent
write-host "image store content:clusterconfigstore" -ForegroundColor Yellow
Get-ServiceFabricImageStoreContent -remoteRelativePath ClusterConfigStore
write-host "image store content:windowsfabricstore" -ForegroundColor Yellow
Get-ServiceFabricImageStoreContent -remoteRelativePath WindowsFabricStore

if((Get-ServiceFabricClusterUpgrade).upgradestate -inotmatch 'completed|failed') {
    Get-ServiceFabricClusterUpgrade #| convertto-json
    (Get-ServiceFabricClusterUpgrade).upgradedomainsstatus
    write-error "cluster currently upgrading"
    return
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

    $status = $null

    $ErrorActionPreference = 'continue'
    while($true) {
        $newStatus = Get-ServiceFabricClusterUpgrade
        if($newStatus.upgradestate -imatch 'complete|fail') {
            write-host $newStatus | convertto-json
            return
        }

        if($status -and (compare-object -ReferenceObject $status -DifferenceObject $newStatus -Property upgradedomains)){
            write-host ""
            write-host $newStatus
        }
        else {
            write-host "." -NoNewline
        }
        $status = $newStatus
        start-sleep -Seconds 1
    }
}
