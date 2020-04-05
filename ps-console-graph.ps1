<#
.SYNOPSIS
script to write output of one or more perfmon counters

#>

param(
    $scale = 100,
    $sleepSeconds = 1,
    $maxSamples = 1,
    [switch]$noChart,
    [switch]$noColor,
    $counters = @(
        "\\$env:computername\memory\Available MBytes", 
        "\\$env:computername\memory\% committed bytes in use", 
        "\\$env:computername\Process(fabric*)\% Processor Time",
        "\\$env:computername\Processor(_Total)\% Processor Time",
        "\\$env:computername\PhysicalDisk(*)\Avg. Disk Queue Length",
        "\\$env:computername\Paging File(*)\*"
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

                while ($percentSize -gt 100) {
                    $percentSize = ($data * 100) / $sizedScale
                    if ($percentSize -gt 100) {
                        $sizedScale *= 10
                    }
                }

                $hostForegroundColor = $currentForegroundColor
                $hostBackgroundColor = $currentBackgroundColor
                
                if (!$counterObj[$sampleName]) {
                    add-counterObj $sampleName
                }

                $hostForegroundColor = $counterObj[$sampleName].foregroundColor
                $hostBackgroundColor = $counterObj[$sampleName].backgroundColor
                if ($noChart) {
                    $output = "$($sample.Timestamp) value:$($data.ToString("0.0")) scale:$sizedScale counter:$sampleName"
                }
                else {
                    $output = ">$($data.ToString("0.0")) scale:$sizedScale counter:$sampleName`r`n`t[$(('X' * ($percentSize)).tostring().padright($scale))]"
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
    
    if ($script:colorCount -ge $consoleColors.Count) {
        do {
            $backgroundColor = $consoleColors[[math]::Min($consoleColors.Count - 1, $script:bgColorCount++)]
        }while ($backgroundColor -ieq $currentForegroundColor)

        $script:colorCount = 0
    }

    $backgroundColor = $consoleColors[[math]::Min($consoleColors.Count - 1, $script:bgColorCount)]
    
    do {
        $foregroundColor = $consoleColors[[math]::Min($consoleColors.Count - 1, $script:colorCount++)]
    }while ($foregroundColor -ieq $currentBackgroundColor)

    $counterInfo = @{
        backgroundColor = $backgroundColor
        foregroundColor = $foregroundColor
    }

    $counterObj.Add($counter, $counterInfo)
}

main