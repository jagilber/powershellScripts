# script to download all sf package versions to extract .man file into separate directory for parsing sf .etl files

param(
    [string]$sfversion,
    [switch]$all,
    [string]$sfPackageUrl = "https://go.microsoft.com/fwlink/?LinkID=824848&clcid=0x409"
)

$packages = @(invoke-restmethod $sfPackageUrl).Packages

if(!$all){
    $packages = @($packages[-1])
}
elseif($sfversion) {
    $packages = @($packages -imatch $sfversion)
}

$packages

foreach($package in $packages) {
    $package
    mkdir "$pwd\$($package.Version)"
    invoke-webrequest -uri ($package.TargetPackageLocation) -outfile "$pwd\$($package.Version).cab"
    expand "$pwd\$($package.Version).cab" -F:*.man "$pwd\$($package.Version)"
    remove-item "$pwd\$($package.Version).cab" -Force -Recurse
}
