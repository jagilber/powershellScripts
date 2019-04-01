<#
script to convert service fabric .etl trace files to .csv text format
script must be run from node
#>

$ErrorActionPreference = "silentlycontinue"
$dir = "d:\svcfab\log\traces"
$output = "d:\temp"
new-item -ItemType Directory -Path $output

foreach($file in [io.directory]::GetFiles($dir,"*.etl"))
{
    $outputFile = "$($file.Replace($dir, $output))!FMT.txt"
    write-host "netsh.exe trace convert input=$file output=$outputFile"
    netsh.exe trace convert input=$file output=$outputFile report=no
}

write-host "complete"