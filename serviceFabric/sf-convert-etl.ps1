<#
script to convert service fabric .etl trace files to .csv text format
script must be run from node
#>
param(
    $sfLogDir = "d:\svcfab\log\traces",
    $outputDir = "d:\temp",
    $fileFilter = "*.etl"
)

$ErrorActionPreference = "silentlycontinue"

New-Item -ItemType Directory -Path $outputDir
$inputFiles = @([io.directory]::GetFiles($sfLogDir, $fileFilter))
$totalFiles = $inputFiles.count
Write-Host "input files count: $totalFiles"
$count = 0

foreach ($inputFile in $inputFiles)
{
    $count++
    write-host "file $count of $totalFiles"
    $outputFile = "$($inputFile.Replace($sfLogDir, $outputDir))!FMT.txt"
    Write-Host "netsh.exe trace convert input=$inputFile output=$outputFile"
    netsh.exe trace convert input=$inputFile output=$outputFile report=no
}

Write-Host "complete"