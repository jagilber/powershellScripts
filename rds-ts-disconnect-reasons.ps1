# script to return friendly name of rds client decimal error codes

Param(

    [parameter(Position=0,Mandatory=$true,HelpMessage="Enter the disconnect reason code in decimal from client side rds trace")]
    [string] $disconnectReason
    )


$mstsc = New-Object -ComObject MSTscAx.MsTscAx
write-host "description: $($mstsc.GetErrorDescription($disconnectReason,0))"



