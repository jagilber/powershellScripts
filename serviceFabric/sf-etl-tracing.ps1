<#
.SYNOPSIS 
service fabric etl tracing script

.DESCRIPTION
script will create a dynamic ETL tracing using powershell ETW session cmdlets.
default destination ($traceFilePath) is configured location used by FabricDCA for log staging.
files saved in D:\SvcFab\Log\CrashDumps\ will by uploaded by FabricDCA to 'sflogs' storage account fabriccrashdumps-{{cluster id}} container.
after upload, local files will be deleted by FabricDCA automatically.
default argument values should work for most scenarios.
add / remove etw tracing guids as needed. see get-etwtraceprovider / logman query providers
to remove tracing use -remove switch.

https://docs.microsoft.com/powershell/module/eventtracingmanagement/Start-EtwTraceSession

.LINK
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-etl-tracing.ps1" -outFile "$pwd\sf-etl-tracing.ps1";
.\sf-etl-tracing.ps1

#>

[cmdletbinding()]
param(
    [int]$sleepMinutes = 1,
    [int]$maxSizeMb = 1024,
    [string[]]$traceGuids = @(
            '{2F07E2EE-15DB-40F1-90EF-9D7BA282188A}', # Microsoft-Windows-TCPIP
            '{1C95126E-7EEA-49A9-A3FE-A378B03DDB4D}', # Microsoft-Windows-DNS-Client
            '{B1945E15-4933-460F-8103-AA611DDB663A}', # HttpSysProvider
            '{DD5EF90A-6398-47A4-AD34-4DCECDEF795F}', # HTTP Service Trace
            '{7B6BC78C-898B-4170-BBF8-1A469EA43FC5}' # HttpEvent
        ),
    [string]$traceName = 'sf-etl',
    # new file https://docs.microsoft.com/windows/win32/etw/logging-mode-constants
    $logFileMode = 8,

    # output file name and path
    $traceFilePath = 'D:\SvcFab\Log\CrashDumps\sf%d.etl',

    # output file size in MB
    $maxFileSizeMb = 64,

    # max ETW trace buffers
    $maxBuffers = 16,

    # buffer size in MB
    $bufferSize = 1024,

    # 6 == everything
    $level = 6,

    # 0xFFFFFFFFFFFFFFFF == everything
    $keyword = 18446744073709551615,

    # remove tracing session
    [switch]$remove

)

$ErrorActionPreference = "continue"
write-host "$($psboundparameters | Format-List * | out-string)`r`n" -ForegroundColor green

function main() {
    try {
        $error.clear()
        $timer = get-date
        write-host "$($MyInvocation.ScriptName)`r`n$psboundparameters`r`n"
        if (!(check-admin)) { return }

        # remove existing trace
        stop-command
        if ($remove) { return }

        # start new trace
        start-command
        check-error
        wait-command
        $timer = get-date

        # stop new trace
        stop-command
        check-error

        write-host "$(get-date) timer: $(((get-date) - $timer).tostring())"
        write-host "$(get-date) finished" -ForegroundColor green
    }
    catch {
        write-error "exception:$(get-date) $($_ | out-string)"
        write-error "$(get-date) $($error | out-string)"
    }
}

function check-admin() {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if (!$isAdmin) {
        write-error "error:restart script as administrator"
        return $false
    }

    return $true
}

function check-error() {
    if ($error) {
        write-error "$(get-date) $($error | Format-List * | out-string)"
        write-host "$(get-date) $($error | Format-List * | out-string)"
        $error.Clear()
        return $true
    }
    return $false
}

function stop-command() {
    write-host "$(get-date) stopping existing trace`r`n" -ForegroundColor green
    if ((Get-EtwTraceSession -Name $traceName)) {
        write-warning "Stop-EtwTraceSession -Name $traceName"
        Stop-EtwTraceSession -Name $traceName
    }
}

function start-command() {

    $error.Clear()

    write-host "$(get-date) starting trace" -ForegroundColor green
    
    write-host "
    Start-EtwTraceSession -Name $traceName ``
        -LogFileMode $logFileMode ``
        -LocalFilePath $traceFilePath ``
        -MaximumFileSize $maxFileSizeMb ``
        -MaximumBuffers $maxBuffers ``
        -BufferSize $bufferSize
    " -ForegroundColor Cyan

    Start-EtwTraceSession -Name $traceName `
        -LogFileMode $logFileMode `
        -LocalFilePath $traceFilePath `
        -MaximumFileSize $maxFileSizeMb `
        -MaximumBuffers $maxBuffers `
        -BufferSize $bufferSize

    foreach ($guid in $traceGuids) {
        write-host "adding $guid
        Add-EtwTraceProvider -SessionName $traceName ``
            -Guid $guid ``
            -Level $level ``
            -MatchAnyKeyword $keyword
        " -ForegroundColor Cyan

        Add-EtwTraceProvider -SessionName $traceName `
            -Guid $guid `
            -Level $level `
            -MatchAnyKeyword $keyword

    }

    Get-EtwTraceSession -Name $traceName | format-list *
    logman query -ets $traceName
}

function wait-command($minutes = $sleepMinutes, $currentTimer = $timer) {
    write-host "$(get-date) timer: $(((get-date) - $currentTimer).tostring())"
    write-host "$(get-date) sleeping $minutes minutes" -ForegroundColor green
    start-sleep -Seconds ($minutes * 60)
    write-host "$(get-date) resuming" -ForegroundColor green
    write-host "$(get-date) timer: $(((get-date) - $currentTimer).tostring())"
}

main