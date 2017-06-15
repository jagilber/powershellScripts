
param(
    [switch]$start,
    [int]$throttle = 2
)

$global:jobs = New-Object Collections.ArrayList

#-------------------------------------------------------------------
function main()
{
    try
    {
        get-job | remove-job -Force

        # add values here to pass to jobs
        $jobInfo = @{}
        $jobInfo.jobName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.Scriptname)
        $jobInfo.invocation = $MyInvocation
        $jobInfo.action = "test"

        while ($true)
        {
            if (((get-job).State -eq "Running").Count -le $throttle)
            {
                $global:jobs.Add((start-backgroundJob -jobInfo $jobInfo))
            }

            foreach ($job in get-job)
            {
                if ($job.State -ine "Running")
                {
                    get-job -Id $job.Id  
                    Receive-Job -Job $job
                    Remove-Job -Id $job.Id -Force  
                }
            }

            get-job | Receive-Job
            Start-Sleep -Seconds 1
        } 
          
        log-info "finished"
    }
    finally
    {
        get-job | remove-job -Force
    }
}

#-------------------------------------------------------------------
function log-info ([string]$data)
{
    write-host ("$((get-date).ToString("o")):$([Diagnostics.Process]::GetCurrentProcess().Id) $data")
}

#-------------------------------------------------------------------
function do-backgroundJob($jobInfo)
{
    while ($true)
    {
        log-info "doing background job $($jobInfo.action)"
        log-info ($jobInfo.action)
        "================"
        Start-Sleep -Seconds 1
    }
}


#-------------------------------------------------------------------
function start-backgroundJob($jobInfo)
{
    log-info "starting background job"
        
    $job = Start-Job -ScriptBlock `
    { 
        param($jobInfo)

        . $($jobInfo.invocation.scriptname)
        log-info ($jobInfo.action)
        do-backgroundJob -jobInfo $jobInfo

    } -Name $jobInfo.jobName -ArgumentList $jobInfo
    
    return $job
}

#-------------------------------------------------------------------
if ($host.Name -ine "ServerRemoteHost")
{
    main
}
