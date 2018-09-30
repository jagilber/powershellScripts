# script to read sf json files and add comment for convert ticks to timestamp

param(
    $inputFile = "F:\cases\118010717420117\jarvis-nodes-of-a-cluster-180120.1.json"
)

clear-host
$lines = @([io.file]::ReadAllText($inputFile) -split "\r\n")

foreach($line in $lines)
{
    #look for ticks 131607604784229491   
    $pattern = "[0-9]{18}"
    if([regex]::IsMatch($line, $pattern))
    {
        $line -match $pattern | out-null
        $date = (new-object datetime($matches[0].ToString())).ToString("yyMMdd--HH:mm:ss")
        write-host "$($line) // timestamp:$($date)"
    }
    else
    {
        Write-Host $line
    }
}
