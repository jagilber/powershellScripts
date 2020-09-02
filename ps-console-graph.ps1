<#
.SYNOPSIS
script to write output of one or more perfmon counters
iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/ps-console-graph.ps1" -outfile $pwd/ps-console-graph.ps1

#>

param(
    $scale = 100,
    $sleepSeconds = 1,
    $maxSamples = 1,
    [switch]$noChart,
    [switch]$noColor,
    [bool]$newLine = $true,
    [bool]$useScaleAsSymbol = $false,
    $counters = @(
        "\\$env:computername\memory\Available MBytes", 
        "\\$env:computername\memory\% committed bytes in use", 
        "\\$env:computername\Process(fabric*)\% Processor Time",
        "\\$env:computername\Processor(_Total)\% Processor Time",
        "\\$env:computername\PhysicalDisk(*:)\Avg. Disk Queue Length",
        "\\$env:computername\Paging File(*\pagefile.sys)\*",
        "\\$env:computername\Tcpv4\Segments Received/sec",
        "\\$env:computername\Tcpv4\Segments Sent/sec",
        "\\$env:computername\Tcpv4\Segments Retransmitted/sec"
    )
)

$counterObj = @{ }
$currentBackgroundColor = [console]::BackgroundColor
$currentForegroundColor = [console]::ForegroundColor
$consoleColors = [enum]::GetNames([consolecolor])
$script:colorCount = 0
$script:bgColorCount = 0


function main() {
    try {

        if (!$global:AllCounters) {
            Write-Host "loading counter list..."
            $global:allCounters = Get-Counter -ListSet *
        }

        foreach ($counter in $counters) {
            add-counterObj($counter)
        }

        while ($true) {
            $counterSamples = get-counter -counter $counters -SampleInterval ([math]::max(1, $sleepSeconds)) -MaxSamples $maxSamples
            foreach ($sample in $counterSamples.CounterSamples) {
                $data = $sample.CookedValue
                $sampleName = $sample.Path # $sample.Readings.split(' :')[0]
                $sizedScale = $scale
                $percentSize = 101

                if (!$counterObj[$sampleName]) {
                    add-counterObj $sampleName
                }

                while ($percentSize -gt 100) {
                    $percentSize = ($data * 100) / $sizedScale
                    if ($percentSize -gt 100) {
                        $sizedScale *= 10
                    }
                }

                $hostForegroundColor = $currentForegroundColor
                $hostBackgroundColor = $currentBackgroundColor
                $lastScale = $minCounter = $counterObj[$sampleName].lastScale
                $lastCounter = $minCounter = $counterObj[$sampleName].lastCounter

                $hostForegroundColor = $counterObj[$sampleName].foregroundColor
                $hostBackgroundColor = $counterObj[$sampleName].backgroundColor
                $counterObj[$sampleName].counterSamples++
                $avgCounter = $counterObj[$sampleName].averageCounter = (($counterObj[$sampleName].averageCounter * ($counterObj[$sampleName].counterSamples - 1)) + $data) / $counterObj[$sampleName].counterSamples
                $maxCounter = $counterObj[$sampleName].maxCounter = [math]::Max($counterObj[$sampleName].maxCounter, $data)
                $minCounter = $counterObj[$sampleName].minCounter = [math]::Min($counterObj[$sampleName].minCounter, $data)
                $counterObj[$sampleName].lastScale = $sizedScale
                $counterObj[$sampleName].lastCounter = $data

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

                #$graph = "[$(($graphSymbol * ($percentSize)).tostring().padright($scale))]"
                #$graph = "[$(($graphSymbol * ($percentSize)))$(('_' * ($scale - $percentSize)))]"

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

    }
}

function add-counterObj($counter) {
    $backgroundColor = $currentBackgroundColor
    $foregroundColor = $currentForegroundColor

    write-host "adding counter $counter" -ForegroundColor Yellow
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

    $counterObj.Add($counter, $counterInfo)
}

main