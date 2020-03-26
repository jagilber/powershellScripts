# script to monitor docker stderr .err and stdout .out sf files
# get-content ((dir D:\SvcFab\Log\_sf_docker_logs\*.out)|sort LastWriteTime| select -last 1) -tail 1000 -Wait
[cmdletbinding()]
param(
    $sfDockerLogDir = 'D:\SvcFab\Log\_sf_docker_logs\'
)

$ErrorActionPreference = 'continue'

function main() {
    $currentConsoleFiles = @()
    $error.clear()
    if (!(test-path $sfDockerLogDir)) {
        write-warning "$sfDockerLogDir does not exist"
        return
    }

    while ($true) {
        check-jobs

        if (compare-object -ReferenceObject $currentConsoleFiles -DifferenceObject @(dir $sfDockerLogDir\*)) {
            $currentConsoleFiles = @(dir $sfDockerLogDir\*)
            get-job | remove-job -Force
            
            Start-Job -Name "err" -ScriptBlock {
                param($consoleFile)
                get-content ((dir $consoleFile) | sort LastWriteTime | select -last 1) -tail 1000 -Wait
            } -ArgumentList "$sfDockerLogDir\*.err"
    
            Start-Job -Name "out" -ScriptBlock {
                param($consoleFile)
                get-content ((dir $consoleFile) | sort LastWriteTime | select -last 1) -tail 1000 -Wait
            } -ArgumentList "$sfDockerLogDir\*.out"
    
        }

    }

}
function check-jobs() {
    write-verbose "checking jobs"
    #while (get-job) {
    foreach ($job in get-job) {
        $jobInfo = (receive-job -Id $job.id)
        if ($jobInfo) {
            write-log -data $jobInfo
        }
        else {
            write-log -data $job
        }

        if ($job.state -ine "running") {
            write-log -data $job

            if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                write-log -data $job
            }

            write-log -data $job
            remove-job -Id $job.Id -Force  
        }
        #            else {
        #                $jobInfo = (receive-job -Id $job.id)
        #                if ($jobInfo) {
        #                    write-log -data $jobInfo
        #                }
        #            }

        #start-sleep -Seconds $sleepSeconds
    }
    #}
}

function write-log($data) {
    if (!$data) { return }
    [text.stringbuilder]$stringData = New-Object text.stringbuilder
    
    if ($data.GetType().Name -eq "PSRemotingJob") {
        foreach ($job in $data.childjobs) {
            if ($job.Information) {
                $stringData.appendline(@($job.Information.ReadAll()) -join "`r`n")
            }
            if ($job.Verbose) {
                $stringData.appendline(@($job.Verbose.ReadAll()) -join "`r`n")
            }
            if ($job.Debug) {
                $stringData.appendline(@($job.Debug.ReadAll()) -join "`r`n")
            }
            if ($job.Output) {
                $stringData.appendline(@($job.Output.ReadAll()) -join "`r`n")
            }
            if ($job.Warning) {
                write-warning (@($job.Warning.ReadAll()) -join "`r`n")
                $stringData.appendline(@($job.Warning.ReadAll()) -join "`r`n")
                $stringData.appendline(($job | fl * | out-string))
            }
            if ($job.Error) {
                write-error (@($job.Error.ReadAll()) -join "`r`n")
                $stringData.appendline(@($job.Error.ReadAll()) -join "`r`n")
                $stringData.appendline(($job | fl * | out-string))
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
        $stringData = "$(get-date):$($data | fl * | out-string)"
    }

    $status += $stringData.ToString().trim()
    write-host $stringData
}

main