param(
    [int]$sleepMinutes = 1,
    [string]$traceFile = "$env:TEMP\net.etl",
    [int]$maxSizeMb = 1024,
    [string]$session = "nettrace",
    [string]$csvFile = "$env:TEMP\net.csv",
    [switch]$withCommonProviders
)

$ErrorActionPreference = "continue"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if(!$isAdmin){
    Write-Warning "restart script as administrator"
    return
}

if(Get-NetEventSession -Name $session) {
    write-host "$(get-date) removing old trace"
    Stop-NetEventSession -Name $session
    Remove-NetEventSession -Name $session
}

$error.Clear()
New-NetEventSession -Name $session `
    -CaptureMode SaveToFile `
    -MaxFileSize $maxSizeMb `
    -MaxNumberOfBuffers 15 `
    -TraceBufferSize 1024 `
    -LocalFilePath $traceFile

if($withCommonProviders) {
    Add-NetEventProvider -Name "Microsoft-Windows-TCPIP" -SessionName $session `
        -Level 4 `
        -MatchAnyKeyword ([UInt64]::MaxValue) `
        -MatchAllKeyword 0x0 `

        Add-NetEventProvider -Name "{DD5EF90A-6398-47A4-AD34-4DCECDEF795F}" -SessionName $session `
        -Level 4 `
        -MatchAnyKeyword ([UInt64]::MaxValue) `
        -MatchAllKeyword 0x0 `

        Add-NetEventProvider -Name "{20F61733-57F1-4127-9F48-4AB7A9308AE2}" -SessionName $session `
        -Level 4 `
        -MatchAnyKeyword ([UInt64]::MaxValue) `
        -MatchAllKeyword 0x0 `

        Add-NetEventProvider -Name "Microsoft-Windows-HttpLog" -SessionName $session `
        -Level 4 `
        -MatchAnyKeyword ([UInt64]::MaxValue) `
        -MatchAllKeyword 0x0 `

        Add-NetEventProvider -Name "Microsoft-Windows-HttpService" -SessionName $session `
        -Level 4 `
        -MatchAnyKeyword ([UInt64]::MaxValue) `
        -MatchAllKeyword 0x0 `

        Add-NetEventProvider -Name "Microsoft-Windows-HttpEvent" -SessionName $session `
        -Level 4 `
        -MatchAnyKeyword ([UInt64]::MaxValue) `
        -MatchAllKeyword 0x0 `

        Add-NetEventProvider -Name "Microsoft-Windows-Http-SQM-Provider" -SessionName $session `
        -Level 4 `
        -MatchAnyKeyword ([UInt64]::MaxValue) `
        -MatchAllKeyword 0x0 `

    <#
        logman create trace "minio_http" -ow -o c:\minio_http.etl -p {DD5EF90A-6398-47A4-AD34-4DCECDEF795F} 0xffffffffffffffff 0xff -nb 16 16 -bs 1024 -mode Circular -f bincirc -max 4096 -ets
        logman update trace "minio_http" -p {20F61733-57F1-4127-9F48-4AB7A9308AE2} 0xffffffffffffffff 0xff -ets
        logman update trace "minio_http" -p "Microsoft-Windows-HttpLog" 0xffffffffffffffff 0xff -ets
        logman update trace "minio_http" -p "Microsoft-Windows-HttpService" 0xffffffffffffffff 0xff -ets
        logman update trace "minio_http" -p "Microsoft-Windows-HttpEvent" 0xffffffffffffffff 0xff -ets
        logman update trace "minio_http" -p "Microsoft-Windows-Http-SQM-Provider" 0xffffffffffffffff 0xff -ets
    #>
}

Add-NetEventPacketCaptureProvider -SessionName $session `
    -Level 4 `
    -MatchAnyKeyword ([UInt64]::MaxValue) `
    -MatchAllKeyword 0x0 `
    -MultiLayer $true

write-host "$(get-date) starting trace" -ForegroundColor green
Start-NetEventSession -Name $session
Get-NetEventSession -Name $session

write-host "$(get-date) sleeping $sleepMinutes minutes" -ForegroundColor green
start-sleep -Seconds ($sleepMinutes * 60)

write-host "$(get-date) checking trace" -ForegroundColor green
Get-NetEventSession -Name $session

write-host "$(get-date) stopping trace" -ForegroundColor green
Stop-NetEventSession -Name $session

write-host "$(get-date) removing trace" -ForegroundColor green
Remove-NetEventSession -Name $session

Get-WinEvent -Path $traceFile -Oldest | Select-Object TimeCreated, ProcessId, ThreadId, RecordId, Message | ConvertTo-Csv | out-file $csvFile

write-host "$(get-date) finished" -ForegroundColor green