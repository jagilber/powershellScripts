# script to return friendly name of rds client hex /decimal error codes
cls
$dupes = new-object Collections.ArrayList
$mstsc = New-Object -ComObject MSTscAx.MsTscAx
$outFile = "c:\temp\clientcodes.txt"
if([IO.File]::Exists($outFile))
{
    [IO.File]::Delete($outFile)
}


for($id = 0;$id -lt 100000000;$id++)
{
    
    # 2nd parameter is extended error code
    $reason = $($mstsc.GetErrorDescription($id,0))
    if($dupes.Contains($reason))
    {
        continue
    }
   
    [void]$dupes.Add($reason)

    #weird return
    if($reason.Contains("Because of a protocol error"))
    {
        continue
    }

    # clean up return
    if($reason.Contains("`n"))
    {
        $reason = $reason.Replace("`n"," ")
    }

    write-host "$($id)**$($reason)"
    out-file -InputObject "$($id)**$($reason)" -FilePath  $outFile -Append
}

$dupes.Clear()

for($id = 0;$id -lt 100000000;$id++)
{
    
    # 2nd parameter is extended error code
    #$reason = $($mstsc.GetErrorDescription($id,0))
    $reason = $($mstsc.GetErrorDescription(0,$id))
    if($dupes.Contains($reason))
    {
        continue
    }
    

    [void]$dupes.Add($reason)

    #weird return
    if($reason.Contains("Because of a protocol error"))
    {
        continue
    }

    # clean up return
    if($reason.Contains("`n"))
    {
        $reason = $reason.Replace("`n"," ")
    }

    write-host "$($id)**Extended Reason:$($reason)"
    out-file -InputObject "$($id)**Extended Reason: $($reason)" -FilePath  $outFile -Append
}
