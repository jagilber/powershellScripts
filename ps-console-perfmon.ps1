<#
.SYNOPSIS
script to write output of one or more perfmon counters

.DESCRIPTION
script to write output of one or more perfmon counters

.PARAMETER counters
one or more perfmon counters to write to the console

.PARAMETER scale
the scale of the graph

.PARAMETER sleepSeconds
the number of seconds to sleep between samples

.PARAMETER maxSamples
the maximum number of samples to take

.PARAMETER noChart
don't show the chart output

.PARAMETER noColor
don't use color in the output

.PARAMETER newLine
write each sample on a new line

.PARAMETER useScaleAsSymbol
use the scale as the symbol

.PARAMETER computername
the computer to query

.PARAMETER matchCounters
match counters

.PARAMETER listCounters
list counters that match the specified string

.EXAMPLE
ps-console-perfmon.ps1 -counters "\\$env:computername\memory\Available MBytes", "\\$env:computername\memory\% committed bytes in use", "\\$env:computername\Process(fabric*)\% Processor Time", "\\$env:computername\Processor(_Total)\% Processor Time", "\\$env:computername\PhysicalDisk(*:)\Avg. Disk Queue Length", "\\$env:computername\Paging File(*\pagefile.sys)\*", "\\$env:computername\Tcpv4\Segments Received/sec", "\\$env:computername\Tcpv4\Segments Sent/sec", "\\$env:computername\Tcpv4\Segments Retransmitted/sec" -scale 100 -sleepSeconds 1 -maxSamples 1 -noChart -noColor -newLine -useScaleAsSymbol -computername $env:computername -matchCounters

.LINK
iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/ps-console-perfmon.ps1" -outfile $pwd/ps-console-perfmon.ps1

#>

param(
    $scale = 100,
    $sleepSeconds = 1,
    $maxSamples = 1,
    [switch]$noChart,
    [switch]$noColor,
    [bool]$newLine = $true,
    [bool]$useScaleAsSymbol = $false,
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
    [switch]$matchCounters,
    [string]$listCounters,
    [switch]$force
)

$global:counterObjs = [ordered]@{}
$currentBackgroundColor = [console]::BackgroundColor
$currentForegroundColor = [console]::ForegroundColor
$consoleColors = [enum]::GetNames([consolecolor])
$script:colorCount = 0
$script:bgColorCount = 0

function main() {
    try {

        if (!$global:AllCounters -or $force) {
            Write-Host "loading counter list..."
            $global:allCounters = Get-Counter -ListSet *
        }

        if ($listCounters) {
            $global:allCounters.Counter -imatch $listCounters
            return
        }

        foreach ($counter in $counters) {
            add-counterObj $counter $matchCounters
        }

        while ($global:counterObjs.Count -gt 0) {
            #write-host "get-counter -counter @($counterItemsString) -SampleInterval ([math]::max(1, $sleepSeconds)) -MaxSamples $maxSamples" -ForegroundColor Cyan
            $counterSamples = get-counter -counter @($global:counterObjs.Keys) -SampleInterval ([math]::max(1, $sleepSeconds)) -MaxSamples $maxSamples
            
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
                $maxCounter = $global:counterObjs[$sampleName].maxCounter = [math]::Max($global:counterObjs[$sampleName].maxCounter, $data)
                $minCounter = $global:counterObjs[$sampleName].minCounter = [math]::Min($global:counterObjs[$sampleName].minCounter, $data)
                $global:counterObjs[$sampleName].lastScale = $sizedScale
                $global:counterObjs[$sampleName].lastCounter = $data

                $counterDetails = "scale:$sizedScale avg:$($avgCounter.ToString("0.0")) min:$minCounter max:$maxCounter counter:$($sampleName.replace("\\$env:computername".tolower(),[string]::Empty))"

                $trendSize = [math]::Abs($sizedScale.tostring().length - $lastScale.tostring().length) + 1
                $trend = ">"
                $graphSymbol = "X"
                $diffSymbol = ""
                $diffSize = (([int]$data - [int]$lastCounter) * 100) / $sizedScale
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
    finally {
        [console]::BackgroundColor = $currentBackgroundColor
        [console]::ForegroundColor = $currentForegroundColor
        write-host "values stored in `$global:counterObjs" -ForegroundColor Green
        write-host "counters stored in `$global:allCounters" -ForegroundColor Green
    }
}

function add-counterObj($counter, $noMatch = $false) {
    $backgroundColor = $currentBackgroundColor
    $foregroundColor = $currentForegroundColor
    write-host "adding counter $counter" -ForegroundColor Cyan
    $noRootCounter = [regex]::match($counter, '[^\\](\\.+?\\.+)').groups[1].value
    if (!$noRootCounter) {
        $noRootCounter = $counter
    }

    $withRootCounter = "\\$computername\$($noRootCounter.TrimStart('\'))"

    if ($noMatch) {
        $counters = @($global:allCounters.paths -imatch [regex]::Escape($noRootCounter))
        if ($counters.Count -gt 0) {
            write-host "multiple counters found for $counter" -ForegroundColor Cyan
            foreach ($counter in $counters) {
                #write-host $counter
                add-counterObj "\\$computername\$($counter.TrimStart('\'))" $false
            }
            return
        }
        else {
            $counter = $counters[0]
        }
    }
    elseif (!($global:allCounters.paths -contains $noRootCounter)) {
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
        minCounter      = [int]::MaxValue
    }

    if (!$global:counterObjs.Contains($withRootCounter)) {
        $global:counterObjs.Add($withRootCounter, $counterInfo)
    }
}

main