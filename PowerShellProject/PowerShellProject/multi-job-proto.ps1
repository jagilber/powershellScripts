
param(
    [switch]$start,
    [int]$throttle = 20
)

$global:jobs = New-Object Collections.ArrayList

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    try
    {
        get-job | remove-job -Force

        $jobInfos = New-Object Collections.ArrayList

        # add values here to pass to jobs
        $jobInfo = @{}
        $jobInfo.jobName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.Scriptname)
        $jobInfo.invocation = $MyInvocation
        $JobInfo.backgroundJobFunction = (get-item function:do-backgroundJob)
        $jobInfo.action = "test"
        $jobInfo.result = $null

        $jobInfos.Add($jobInfo)

        start-backgroundJobs -jobInfos $jobInfos -throttle $throttle

        monitor-backgroundJobs 
                  
        log-info "finished"
    }
    finally
    {
        get-job | remove-job -Force
    }
}

# ----------------------------------------------------------------------------------------------------------------
function log-info ([string]$data)
{
    write-host ("$((get-date).ToString("o")):$([Diagnostics.Process]::GetCurrentProcess().Id) $data")
}

# ----------------------------------------------------------------------------------------------------------------
function do-backgroundJob($jobInfo)
{
    $count = 0
    while ($true)
    {
        log-info "doing background job $($jobInfo.action)"
        log-info ($jobInfo.action)
        "================"
        $jobInfo.result = $count
        

        $jobInfo
        Start-Sleep -Seconds 1
        $count++
    }
}

# ----------------------------------------------------------------------------------------------------------------
function monitor-backgroundJobs()
{
    while (get-job)
    {
        foreach ($job in get-job)
        {
            if ($job.State -ine "Running")
            {
                $job
                Remove-Job -Id $job.Id -Force  
            }
            else
            {
                $jobInfo = Receive-Job -Job $job
                $jobInfo
            }            

            Start-Sleep -Seconds 1
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function start-backgroundJob($jobInfo)
{
    log-info "starting background job"
        
    $job = Start-Job -ScriptBlock `
    { 
        param($jobInfo)

        . $($jobInfo.invocation.scriptname)
        log-info ($jobInfo.action)
        #do-backgroundJob -jobInfo $jobInfo
        & $jobInfo.backgroundJobFunction $jobInfo

    } -Name $jobInfo.jobName -ArgumentList $jobInfo
    
    return $job
}

# ----------------------------------------------------------------------------------------------------------------
function start-backgroundJobs($jobInfos, $throttle)
{
    log-info "starting background jobs"

    foreach ($jobInfo in $jobInfos)
    {
        while (((get-job).State -eq "Running").Count -gt $throttle)
        {
            Write-Verbose "throttled"
            Start-Sleep -Seconds 1
        }

        $global:jobs.Add((start-backgroundJob -jobInfo $jobInfo))
    }
}

# ----------------------------------------------------------------------------------------------------------------
if ($host.Name -ine "ServerRemoteHost")
{
    main
}
