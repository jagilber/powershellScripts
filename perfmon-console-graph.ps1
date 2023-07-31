<#
.SYNOPSIS
script to write output of one or more perfmon counters to console.

.DESCRIPTION
script to write output of one or more perfmon counters to console. 
objects are stored in $global:counterObjs. counters are stored in $global:allCounters.
version 1.0

.PARAMETER counters
[string[]]one or more perfmon counters to write to the console

.PARAMETER scale
[double]the scale of the graph. default is 100

.PARAMETER sleepSeconds
[double]the number of seconds to sleep between samples. default is 1

.PARAMETER maxSamples
[double]the maximum number of samples to take. default is 1

.PARAMETER noChart
[switch]don't show chart output

.PARAMETER noColor
[switch]don't use color in the output

.PARAMETER newLine
[bool]write each sample on a new line. default is to write each sample on the same line

.PARAMETER useScaleAsSymbol
[bool]use the scale as the symbol

.PARAMETER computername
[string]the computer to query. default is the local computer

.PARAMETER matchCounters
[switch]match counters

.PARAMETER listCounters
[string]list counters that match the specified string

.EXAMPLE
perfmon-console-graph.ps1 -counters "\\$env:computername\memory\Available MBytes", "\\$env:computername\memory\% committed bytes in use", "\\$env:computername\Process(fabric*)\% Processor Time", "\\$env:computername\Processor(_Total)\% Processor Time", "\\$env:computername\PhysicalDisk(*:)\Avg. Disk Queue Length", "\\$env:computername\Paging File(*\pagefile.sys)\*", "\\$env:computername\Tcpv4\Segments Received/sec", "\\$env:computername\Tcpv4\Segments Sent/sec", "\\$env:computername\Tcpv4\Segments Retransmitted/sec"

.EXAMPLE
perfmon-console-graph.ps1 -counters "\\$env:computername\memory\Available MBytes" -scale 100 -sleepSeconds 1 -maxSamples 1 

.EXAMPLE
perfmon-console-graph.ps1 -counters "current disk queue" -matchCounters

.EXAMPLE
perfmon-console-graph.ps1 -list "pagefile"

.LINK
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/perfmon-console-graph.ps1" -outfile $pwd/perfmon-console-graph.ps1

#>
[cmdletbinding()]
param(
    [string]$computername = $env:computername,
    [string[]]$counters = @(
        "\\$computername\memory\Available MBytes", 
        "\\$computername\memory\% committed bytes in use", 
        "\\$computername\Process(fabric*)\% Processor Time",
        "\\$computername\Processor(_Total)\% Processor Time",
        "\\$computername\PhysicalDisk(*:)\Avg. Disk Queue Length",
        "\\$computername\Paging File(*\pagefile.sys)\*",
        "\\$computername\Tcpv4\Segments Received/sec",
        "\\$computername\Tcpv4\Segments Sent/sec",
        "\\$computername\Tcpv4\Segments Retransmitted/sec"
    ),
    [double]$scale = 100,
    [double]$sleepSeconds = 1,
    [double]$maxSamples = 1,
    [switch]$noChart,
    [switch]$noColor,
    [bool]$newLine = $true,
    [bool]$useScaleAsSymbol = $false,
    [switch]$matchCounters,
    [string]$listCounters,
    [switch]$force
)

$ErrorActionPreference = 'continue'
$global:counterObjs = @{}
$script:colorCount = 0
$script:bgColorCount = 0
$consoleColors = [enum]::GetNames([consolecolor])
$currentBackgroundColor = [console]::BackgroundColor
$currentForegroundColor = [console]::ForegroundColor

function main() {
    try {
        add-counters $force

        if ($listCounters) {
            $global:allCounters.Counter -imatch $listCounters
            return
        }

        #remove-counters
        monitor-counters        
    }
    finally {
        [console]::BackgroundColor = $currentBackgroundColor
        [console]::ForegroundColor = $currentForegroundColor
        write-host "values stored in `$global:counterObjs" -ForegroundColor Green
        write-host "counters stored in `$global:allCounters" -ForegroundColor Green
    }
}

function add-counterObj($counter, $match = $false) {
    $backgroundColor = $currentBackgroundColor
    $foregroundColor = $currentForegroundColor
    write-host "adding counter $counter" -ForegroundColor Cyan
    $noRootCounter = [regex]::replace($counter, '^\\\\.*?\\','\')
    if (!$noRootCounter) {
        $noRootCounter = $counter
    }

    $withRootCounter = "\\$computername\$($noRootCounter.TrimStart('\'))"

    if ($match) {
        $counterItems = @($global:allCounters.paths -imatch [regex]::Escape($noRootCounter))
        $counterItems += @($global:allCounters.pathsWithInstances -imatch [regex]::Escape($noRootCounter))

        if ($counterItems.Count -gt 0) {
            write-host "multiple counters found for $counter" -ForegroundColor Cyan
            foreach ($counterItem in $counterItems) {
                #write-host $counter
                add-counterObj $counterItem $false
            }
            return
        }
        else {
            $counter = $counterItems[0]
        }
    }
    elseif (!($global:allCounters.paths -contains $noRootCounter) -and !($global:allCounters.paths -contains $withRootCounter) `
        -and !($global:allCounters.pathsWithInstances -contains $noRootCounter) -and !($global:allCounters.pathsWithInstances -contains $withRootCounter)) {
        write-host "counter $counter not found" -ForegroundColor Yellow
    }

    do {
        $backgroundColor = $consoleColors[[math]::Min($consoleColors.Count - 1, $script:bgColorCount++)]
    }while ($backgroundColor -ieq $currentForegroundColor)

    $script:colorCount = 0

    $backgroundColor = $consoleColors[[math]::Min($consoleColors.Count - 1, $script:bgColorCount)]
    
    do {
        $foregroundColor = $consoleColors[[math]::Min($consoleColors.Count - 1, $script:colorCount++)]
    }while ($foregroundColor -ieq $currentBackgroundColor)

    $counterInfo = @{
        backgroundColor = $backgroundColor
        foregroundColor = $foregroundColor
        lastScale       = $scale
        lastCounter     = 0
        counterSamples  = 0
        averageCounter  = 0
        maxCounter      = 0
        minCounter      = [double]::MaxValue
    }

    if (!$global:counterObjs.Contains($withRootCounter)) {
        $global:counterObjs.Add($withRootCounter, $counterInfo)
    }
}

function add-counters($force = $false) {
    if (!$global:AllCounters -or $force) {
        Write-Host "loading counter list..."
        $global:allCounters = Get-Counter -ListSet * -ComputerName $computername
        Write-Host "done loading counter list" -ForegroundColor Green
    }

    foreach ($counter in $counters) {
        add-counterObj $counter $matchCounters
    }
}

function monitor-counters() {
    write-host "monitoring counters..." -ForegroundColor Green
    while ($global:counterObjs.Count -gt 0) {
        write-verbose "get-counter -counter @($($global:counterObjs.Keys | out-string)) -SampleInterval ([math]::max(1, $sleepSeconds)) -MaxSamples $maxSamples"
        $error.clear()
        $counterSamples = get-counter -counter @($global:counterObjs.Keys) -SampleInterval ([math]::max(1, $sleepSeconds)) -MaxSamples $maxSamples -ComputerName $computername
        if ($error) {
            # todo - remove counters that don't exist
            #add-counters $true
            remove-counters
            $error.clear()
        }
        
        foreach ($sample in $counterSamples.CounterSamples) {
            $data = $sample.CookedValue
            $sampleName = $sample.Path # $sample.Readings.split(' :')[0]
            $sizedScale = $scale
            $percentSize = 101

            if (!$global:counterObjs[$sampleName]) {
                add-counterObj $sampleName $matchCounters
            }

            while ($percentSize -gt 100) {
                $percentSize = ($data * 100) / $sizedScale
                if ($percentSize -gt 100) {
                    $sizedScale *= 10
                }
            }

            $hostForegroundColor = $currentForegroundColor
            $hostBackgroundColor = $currentBackgroundColor
            $lastScale = $minCounter = $global:counterObjs[$sampleName].lastScale
            $lastCounter = $minCounter = $global:counterObjs[$sampleName].lastCounter

            $hostForegroundColor = $global:counterObjs[$sampleName].foregroundColor
            $hostBackgroundColor = $global:counterObjs[$sampleName].backgroundColor
            
            $global:counterObjs[$sampleName].counterSamples++
            $avgCounter = $global:counterObjs[$sampleName].averageCounter = (($global:counterObjs[$sampleName].averageCounter * ($global:counterObjs[$sampleName].counterSamples - 1)) + $data) / $global:counterObjs[$sampleName].counterSamples
            $maxCounter = $global:counterObjs[$sampleName].maxCounter = [math]::Max([double]$global:counterObjs[$sampleName].maxCounter, [double]$data)
            $minCounter = $global:counterObjs[$sampleName].minCounter = [math]::Min([double]$global:counterObjs[$sampleName].minCounter, [double]$data)
            $global:counterObjs[$sampleName].lastScale = $sizedScale
            $global:counterObjs[$sampleName].lastCounter = $data

            $counterDetails = "scale:$sizedScale avg:$($avgCounter.ToString("0.0")) min:$minCounter max:$maxCounter counter:$($sampleName.replace("\\$env:computername".tolower(),[string]::Empty))"

            $trendSize = [math]::Abs($sizedScale.tostring().length - $lastScale.tostring().length) + 1
            $trend = ">"
            $graphSymbol = "X"
            $diffSymbol = ""
            $diffSize = (([double]$data - [double]$lastCounter) * 100) / $sizedScale
            $graphSymbolMultiplier = $percentSize
            $diffSymbolMultiplier = 0

            if ($diffSize -gt 0) {
                $trend = "^" * $trendSize
                $graphSymbol = ">"
                $diffSymbol = "+"
                $graphSymbolMultiplier = [math]::min($percentSize, [math]::abs($percentSize - $diffSize))
                $diffSymbolMultiplier = [math]::min($percentSize, [math]::abs($diffSize))
            }
            elseif ($diffSize -lt 0) {
                $trend = "v" * $trendSize
                $graphSymbol = "<"
                $diffSymbol = "-"
                $graphSymbolMultiplier = [math]::min($percentSize, [math]::abs($percentSize - $diffSize))
                $diffSymbolMultiplier = [math]::min($scale - $percentSize, [math]::abs($diffSize))
            }

            if ($useScaleAsSymbol) {
                $graphSymbol = $(($sizedScale.tostring().length - $scale.tostring().length).tostring())
            }

            $graph = "[$((($graphSymbol * $graphSymbolMultiplier) + ($diffSymbol * $diffSymbolMultiplier)).tostring().padright($scale))]"

            if ($noChart) {
                $output = "$trend $($data.ToString("0.0")) $counterDetails"
            }
            else {
                if ($newLine) {
                    $output = "$trend $($data.ToString("0.0")) $counterDetails`r`n`t$graph"
                }
                else {
                    $output = "$graph $trend $($data.ToString("0.0")) $counterDetails"
                }
            }

            if ($noColor) {
                write-host $output
            }
            else {
                write-host $output -ForegroundColor $hostForegroundColor -BackgroundColor $hostBackgroundColor
            }
        }

        start-sleep -Milliseconds ($sleepSeconds * 1000)
    }
}

function remove-counters() {
    # remove counters that don't exist
    foreach ($key in $global:counterObjs.clone().Keys) {
        $error.clear()
        Write-Verbose "get-counter -counter @($key) -SampleInterval ([math]::max(1, $sleepSeconds)) -MaxSamples $maxSamples"
        get-counter -counter @($key) -SampleInterval ([math]::max(1, $sleepSeconds)) -MaxSamples $maxSamples -ComputerName $computername -ErrorAction SilentlyContinue
            
        if ($error) {
            write-host "error getting counter '$key'. $error removing from list..." -ForegroundColor Yellow
            $error.clear()
            $global:counterObjs.Remove($key)
        }
    }    
}

main