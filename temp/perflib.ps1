<#
  iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/temp/perflib.ps1" -outFile "$pwd\perflib.ps1";.\perflib.ps1
#>
param(
    $logFile = "$PSScriptRoot\perf.log",
    $sleepMs = 100,
    [switch]$appendLogFile,
    $logToFile = $true
)

$erroractionpreferencce = 'continue'
$global:counterValue = $null
$global:help = $null
$global:providers = $null
$global:subkeys = $null

function main() {
    $perfKey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib'
    $009 = "$perfKey\009"
    $v2Providers = $perfKey + '\_V2Providers'


    if (!$appendLogFile -and $logToFile -and $logFile) {
        remove-item $logfile
    }

    try {
        while ($true) {
            "//$(get-date)--------------------" | out-file -Append -FilePath $logFile
            write-host "." -NoNewline
            monitor-key $logToFile
            start-sleep -milliseconds $sleepMs
            #$logToFile = $false
        }
    }
    catch {
        write-error "$($error | out-string)"
    }
    finally {
        monitor-key $true
    }
}

function compare-objects($a, $b) {
    if (!$a -and !$b) { return }
    
    if ([string]::Compare(($a | out-string), ($b | out-string)) -ne 0) {
            Write-Warning "difference in objects a:"
            write-host ($a | ConvertTo-Json)
            Write-Warning "difference in objects b:"
            write-host ($b | ConvertTo-Json)
            Write-Warning "difference in objects end"
        }
    }

    function monitor-key($logToFile = $false) {
        $subKeys = get-properties $perfKey
        compare-objects $global:subkeys $subKeys
        $global:subkeys = $subKeys
        if ($logToFile) {
            log-file $subKeys
        }

        $baseIndex = $subKeys.'Base Index'
        $lastCounter = $subKeys.'Last Counter'
        $lastHelp = $subKeys.'Last Help'
        $version = $subKeys.Version
        $extcounterTestLevel = $subKeys.ExtCounterTestLevel

        $counterValue = get-propertyValue $009 "Counter"
        compare-objects $global:counterValue $counterValue
        $global:counterValue = $counterValue
        if ($logToFile) {
            log-file $counterValue
        }

        $help = get-propertyValue $009 "Help"
        compare-objects $global:help $help
        $global:help = $help
        if ($logToFile) {
            log-file $help
        }
    
        $providers = get-subKeys $v2Providers
        compare-objects $global:providers $providers
        $global:providers = $providers
        if ($logToFile) {
            log-file $providers
        }

        $error.clear()
        try{
            $count = [microsoft.win32.registry]::PerformanceData.GetValue("Global").Count
            "//$(get-date) global count:$count" | out-file -Append -FilePath $logFile
        }
        catch{
            $er = "//$(get-date) error trying to enumerate global"
            write-error $er
            $er  | out-file -Append -FilePath $logFile
        }
    }

    function get-propertyValue($key, $property) {
        $value = Get-ItemPropertyValue $key $property #| select-object -ExcludeProperty PsPath,PsParentPath,PsProvider,PsChildName #|convertto-json 
        "//$key\$property $(get-date)" | out-file -Append -FilePath $logFile
        return $value
    }

    function get-subKeys($key) {
        $retval = @{} #[collections.arraylist]::new()
        $subkeys = get-childItem $key -recurse | select-object -ExcludeProperty PsPath, PsParentPath, PsProvider, PsChildName #|convertto-json
        foreach ($subKey in $subKeys) {
            [void]$retval.add(($subkey.name), (get-properties "Registry::$($subkey.name)"))
        }
        return $retval
    }

    function get-properties($key) {
        return Get-ItemProperty $key | select-object -ExcludeProperty PsPath, PsParentPath, PsProvider, PsChildName #|convertto-json
    }

    function log-file($data) {
        "//$((get-date).ToString('o'))"| out-file -Append -FilePath $logFile
        "$($data | ConvertTo-Json)," | out-file -Append -FilePath $logFile
    }

    main