<#
script to convert service fabric .etl trace files to .csv text format
script must be run from node
#>
param(
    $sfLogDir = "d:\svcfab\log", # "d:\svcfab\log\traces",
    $outputDir = "d:\temp",
    $fileFilter = "*.etl",
    $sfDownloadManUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-download-man.ps1",
    [string[]]$manFilterList = @("WFPerf.man","KtlLoggerCounters.man")
)

# D:\SvcFab\Log\work\WFEtwMan
$ErrorActionPreference = "silentlycontinue"

function main(){

    $pattern = "([0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4})"
    $count = 0

    # sf manifest installed?
    $sfevtpublisher = wevtutil gp "Microsoft-ServiceFabric"
    $sfPublisherVersion = ([regex]::Match($sfevtpublisher, $pattern, [text.regularexpressions.regexoptions]::ignorecase)).Groups[1].Value
    Write-Host "win event publisher file version: $sfPublisherVersion"

    # etl files?
    New-Item -ItemType Directory -Path $outputDir
    $etlFiles = @([io.directory]::GetFiles($sfLogDir, $fileFilter, [IO.SearchOption]::AllDirectories))
    $totalFiles = $etlFiles.count
    $etlFileVersion = ([regex]::Match(($etlFiles -join ","), "`_$pattern`_", [text.regularexpressions.regexoptions]::ignorecase)).Groups[1].Value
    Write-Host "etl file version: $etlFileVersion"
    Write-Host "etl files count: $totalFiles"
    
    if($etlFiles.count -lt 1) {
        write-error "no $fileFilter files found in $sflogdir"
        return
    }

    $manifestFiles = enum-manifests $sfLogDir
    $importArgument = ""

    if($sfPublisherVersion -ne $etlFileVersion) {
        if($etlFileVersion -ne $manifestFileVersion){
            $sfDownloadManScript = "$pwd\$([io.path]::GetFileName($sfDownloadManUrl))"

            if(!(test-path $sfDownloadManScript)) {
                (new-object net.webclient).DownloadFile($sfDownloadManUrl, $sfDownloadManScript)
            }

            . $sfDownloadManScript -sfversion $etlFileVersion
            $manifestFiles = enum-manifests "$pwd\$etlFileVersion"
            $importArgument = " -import `"$($manifestFiles -join '`" `"')`""
        }
    }

    foreach ($etlFile in $etlFiles) {
        $count++
        write-host "file $count of $totalFiles"
        $outputFile = "$outputDir\$([io.path]::GetFileNameWithoutExtension($etlFile)).dtr.csv"
        del $outputFile
        write-host "tracerpt `"$etlFile`"$importArgument -of CSV -o `"$outputFile`""
        start-process -wait -FilePath "tracerpt" -ArgumentList "`"$etlFile`"$importArgument -of CSV -o `"$outputFile`""
    }

    Write-Host "complete"

}

function enum-manifests($manifestPath) {
    # sf manifest on disk?
    $manDir = "c:\man"
    $manifestFiles = @([io.directory]::GetFiles($manifestPath, "*.man", [IO.SearchOption]::AllDirectories))
    $manifestFileVersion = ([regex]::Match(($manifestFiles -join ","), $pattern, [text.regularexpressions.regexoptions]::ignorecase)).Groups[1].Value
    Write-Host "manifest file version: $manifestFileVersion"
    write-host "manifest files"
    write-host ($manifestFiles | out-string)
    $manList = [collections.arraylist]@()
    remove-item $manDir -recurse -force
    mkdir $manDir
    
    foreach($file in $manifestFiles) {
        $fileName = [io.path]::GetFileName($file)
        [void][io.file]::Copy($file, "$manDir\$fileName")

        if(!($manFilterList -contains $fileName))
        {
            [void]$manList.Add("$manDir\$fileName")
        }
    }

    return $manList
}

main
