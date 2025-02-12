<#
.SYNOPSIS 
service fabric persistent etl tracing script

.DESCRIPTION
script will create a realtime ETL tracing session using pktmon and powershell cmdlets

Microsoft Privacy Statement: https://privacy.microsoft.com/en-US/privacystatement

MIT License

Copyright (c) Microsoft Corporation. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE

.LINK
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-realtime-tracing.ps1" -outFile "$pwd\sf-realtime-tracing.ps1";
.\sf-realtime-tracing.ps1

#>


[cmdletbinding()]
param(
    $traceFilePath = "$pwd\sf.csv",
    $maxFileSizeMb = 1024,
    [int]$logLevel = 5,
    [switch]$remove,
    [string]$commandToExecuteOnMatch = 'write-host "match found $($psitem.Length)" -ForegroundColor Green',
    [string[]]$filters = @(
        'exception',
        'fail'
    ),
    [string[]]$traceProviders = @(
        'Microsoft-Windows-HttpService',
        'Microsoft-ServiceFabric'#,
        #'Microsoft-Windows-TCPIP'
    )
)

$pktmonNotRunningStatus = 'Packet Monitor is not running.'

function main() {
    if (!(is-admin)) {
        return
    }

    $error.Clear()
    $timer = get-date

    if (!(get-command pktmon -ErrorAction SilentlyContinue)) {
        write-host "pktmon not found. this is only available in Windows 10 21H1 and later." -ForegroundColor Red
        return
    }

    stop-pktmon

    if ($remove) { return }
    try {
        start-pktmonProvider $traceFilePath $traceProviders

        start-pktmonConsumer $traceFilePath $filters $commandToExecuteOnMatch

    }
    catch {
        write-warning "Error: $($_.Exception.Message)"
        return
    }
    finally {
        write-host "removing pktmon provider..." -ForegroundColor Yellow
        stop-pktmon
        write-host "script completed in $((get-date) - $timer)" -ForegroundColor Green
        write-host "output file: $traceFilePath" -ForegroundColor Green
    }
}

function is-admin() {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Warning "restarting script as administrator..."
        $command = 'pwsh'
        $commandLine = $global:myinvocation.myCommand.definition
  
        if ($psedition -eq 'Desktop') {
            $command = 'powershell'
        }
        write-host "Start-Process $command -Verb RunAs -ArgumentList `"-NoExit -File $commandLine`""
        Start-Process $command  -Verb RunAs -ArgumentList "-NoExit -File $commandLine"
  
        return $false
    }
    return $true
}

function start-pktmonConsumer($file, $filters, $command) {
    $regexFilter = $filters -join '|'
    while (!(test-path $file)) {
        write-host "waiting for $file to be created..." -ForegroundColor Yellow
        start-sleep -seconds 5
    }

    write-host "tailing $file with filter '$regexFilter'" -ForegroundColor Green
    get-content -Tail 100 -Path $file -Wait | Where-Object {
        if ($psitem -imatch $regexFilter) {
            write-host  $psitem -ForegroundColor cyan;
            # do something
            # if ($psitem -imatch 'fail') { write-host 'fail' -ForegroundColor Red }
            Invoke-Expression $command
        }
    }     
}

function start-pktmonProvider($traceFilePath, $traceProviders) {
    $providers = $traceProviders -join ' -p '
    write-host "pktmon start -t -m real-time -p $providers | tee-object $traceFilePath" -ForegroundColor Cyan
    # start in new window
    start-process powershell -ArgumentList "-Command pktmon start -t -m real-time -p $providers | tee-object $traceFilePath"
    #pktmon start -t -m real-time -p $providers

    if ($error.Count -gt 0) {
        write-warning "Error starting pktmon."
        return
    }

    write-host "pktmon started." -ForegroundColor Green
    #return $process
}

function stop-pktmon() {
    $pktmonStatus = pktmon status
    if ($pktmonStatus -imatch $pktmonNotRunningStatus) {
        write-host "pktmon not running." -ForegroundColor Green
        return
    }

    write-host "stopping pktmon..." -ForegroundColor Yellow
    pktmon stop

    if ($error.Count -gt 0) {
        write-warning "Error stopping pktmon."
        return
    }

    write-host "pktmon stopped." -ForegroundColor Green
}

main