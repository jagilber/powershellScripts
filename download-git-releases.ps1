<#
.SYNOPSIS
downloads a release from git

.LINK
to run with no arguments:
iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/download-git-releases.ps1" -UseBasicParsing|iex

or use the following to save and pass arguments:
(new-object net.webclient).downloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/download-git-releases.ps1","$pwd/download-git-releases.ps1");
.\download-git-releases.ps1 -owner {{ git owner }} -repository {{ git repository }} [-latest]
#>
[cmdletbinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$owner = "microsoft",
    [Parameter(Mandatory = $true)]
    [string]$repository = "winget-cli",
    [string]$destPath = $pwd,
    [switch]$latest,
    [switch]$execute,
    [switch]$force,
    [string]$gitReleaseApi = "https://api.github.com/repos/$owner/$repository/releases"
)

$PSModuleAutoLoadingPreference = 2
[net.servicePointManager]::Expect100Continue = $true;
[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
$erroractionpreference = "continue"
$error.clear()

function main() {
    if ($latest) {
        $gitReleaseApi = "$gitReleaseApi/latest"
    }

    # -usebasicparsing deprecated but needed for nano / legacy
    write-host "Invoke-WebRequest $gitReleaseApi -UseBasicParsing" -ForegroundColor Magenta
    $global:apiResults = convertfrom-json (Invoke-WebRequest $gitReleaseApi -UseBasicParsing)
    
    write-verbose "releases:`r`n$($global:apiResults | convertto-json)"
    write-host "$($global:apiResults) releases:" -ForegroundColor Cyan

    for ($count = 1; $count -le $global:apiResults.count; $count++) {
        $release = $global:apiResults[$count - 1]
        write-host "$($count). $($release.name) $($release.tag_name) $($release.created_at)" -ForegroundColor Green
    }

    $selection = 0
    if ($global:apiResults.count -gt 1) {
        $selection = [convert]::ToInt32((read-host -Prompt 'enter number of release to download:')) - 1
    }

    $release = $global:apiResults[$selection]
    write-verbose "assets:`r`n$($release.assets | convertto-json)"
    write-host "$($release.assets.count) assets:" -ForegroundColor Cyan

    for ($count = 1; $count -le $release.assets.count; $count++) {
        $releaseAsset = $release.assets[$count - 1]
        write-host "$($count). $($releaseAsset.name) $($releaseAsset.size) $($releaseAsset.created_at)" -ForegroundColor Green
    }

    $assetSelection = 0
    if ($release.assets.count -gt 1) {
        $assetSelection = [convert]::ToInt32((read-host -Prompt 'enter number of asset to download:')) - 1
    }

    $downloadUrl = $global:apiResults[$selection].assets[$assetSelection].browser_download_url
    $destinationFile = "$($destPath)\$($global:apiResults[$selection].assets[$assetSelection].name)"

    if (!$downloadUrl) {
        $global:apiResults
        write-warning "unable to find download url"
        return
    }

    write-host $downloadUrl -ForegroundColor Green

    if (!(test-path $destPath)) {
        mkdir $destPath
    }

    if ((test-path $destinationFile) -and $force) {
        remove-item $destinationFile -Force:$force
    }
    elseif ((test-path $destinationFile)) {
        write-warning "file $destinationfile exists. use -force to overwrite"
        return
    }

    write-host "downloading $downloadUrl to $destinationFile" -ForegroundColor Magenta
    invoke-webrequest $downloadUrl -OutFile $destinationFile

    if ($destinationFile -imatch ".zip") {
        Expand-Archive -path $destinationFile -destinationpath $destPath -force:$force
    }
    elseif ($execute) {
        . $destinationFile
    }

    write-host "$(Get-ChildItem $destinationFile | Format-List * | out-string)"
    write-host "finished: $destinationFile" -ForegroundColor Cyan
}

main
