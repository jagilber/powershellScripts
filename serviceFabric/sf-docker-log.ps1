<# script to monitor docker console stderr .err and stdout .out sf files
(new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-docker-log.ps1","$pwd\sf-docker-log.ps1");
.\sf-docker-log.ps1;
#>

[cmdletbinding()]
param(
    $sfDockerLogDir = 'D:\SvcFab\Log\_sf_docker_logs\',
    $tailLength = 1000,
    $sleepMilliseconds = 500
)

$ErrorActionPreference = 'continue'

function main() {
    $currentConsoleFiles = @()
    get-job | remove-job -Force
    $error.clear()

    if (!(test-path $sfDockerLogDir)) {
        write-warning "$sfDockerLogDir does not exist"
        return
    }

    try {
        while ($true) {
            check-jobs

            if (compare-object -ReferenceObject $currentConsoleFiles -DifferenceObject @(get-childitem $sfDockerLogDir\*)) {
                write-warning "starting new jobs"
                $currentConsoleFiles = @(get-childitem $sfDockerLogDir\*)
                get-job | remove-job -Force
            
                Start-Job -Name "err" -ScriptBlock {
                    param($consoleFile, $tailLength)
                    get-content ((get-childitem $consoleFile) | sort-object LastWriteTime | select-object -last 1) -tail $tailLength -Wait
                } -ArgumentList "$sfDockerLogDir\*.err", $tailLength
    
                Start-Job -Name "out" -ScriptBlock {
                    param($consoleFile, $tailLength)
                    get-content ((get-childitem $consoleFile) | sort-object LastWriteTime | select-object -last 1) -tail $tailLength -Wait
                } -ArgumentList "$sfDockerLogDir\*.out", $tailLength
    
            }
            start-sleep -milliseconds $sleepMilliseconds
        }
    }
    catch {
        write-warning "exception: $($_ | out-string)`r`n$($error | out-string)"
    }
    finally {
        get-job | remove-job -Force
    }

}
function check-jobs() {
    write-verbose "checking jobs"

    foreach ($job in get-job) {
        $jobInfo = (receive-job -Id $job.id)
        if ($jobInfo) {
            write-log -data $jobInfo
        }
        else {
            #write-log -data $job
        }

        if ($job.state -ine "running") {
            write-log -data $job

            if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                write-log -data $job
            }

            write-log -data $job
            remove-job -Id $job.Id -Force  
        }
    }
}

function write-log($data) {
    if (!$data) { return }
    [text.stringbuilder]$stringData = New-Object text.stringbuilder
    
    if ($data.GetType().Name -eq "PSRemotingJob") {
        foreach ($job in $data.childjobs) {
            if ($job.Information) {
                [void]$stringData.appendline(@($job.Information.ReadAll()) -join "`r`n")
            }
            if ($job.Verbose) {
                [void]$stringData.appendline(@($job.Verbose.ReadAll()) -join "`r`n")
            }
            if ($job.Debug) {
                [void]$stringData.appendline(@($job.Debug.ReadAll()) -join "`r`n")
            }
            if ($job.Output) {
                [void]$stringData.appendline(@($job.Output.ReadAll()) -join "`r`n")
            }
            if ($job.Warning) {
                write-warning (@($job.Warning.ReadAll()) -join "`r`n")
                [void]$stringData.appendline(@($job.Warning.ReadAll()) -join "`r`n")
                [void]$stringData.appendline(($job | fl * | out-string))
            }
            if ($job.Error) {
                write-error (@($job.Error.ReadAll()) -join "`r`n")
                [void]$stringData.appendline(@($job.Error.ReadAll()) -join "`r`n")
                [void]$stringData.appendline(($job | fl * | out-string))
            }
    
            if ($stringData.tostring().Trim().Length -gt 0) {
                #$stringData += "`r`nname: $($data.Name) state: $($job.State) $($job.Status)`r`n"     
            }
            else {
                return
            }
        }
    }
    else {
        $stringData = "$($data | fl * | out-string)"
    }

    write-host $stringData
}

main