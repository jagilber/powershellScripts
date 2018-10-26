
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
function log-info($data)
{
    
    $dataWritten = $false
    $data = "$([System.DateTime]::Now):$($data)`n"
    write-host $data
    $counter = 0
    
    while (!$dataWritten -and $counter -lt 1000)
    {
        try
        {
            out-file -Append -InputObject $data -FilePath $logFile
            $dataWritten = $true
        }
        catch
        {
            Start-Sleep -Milliseconds 10
            $counter++
        }
    }
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
function check-backgroundJobs()
{
    foreach ($job in get-job)
    {
        if ($job.State -ine "Running")
        {
            #log-info ($job | fl * | out-string)
            Remove-Job -Id $job.Id -Force  
        }
        else
        {
            $jobInfo = Receive-Job -Job $job
            #log-info ($jobInfo | fl * | out-string)
        }            

        Start-Sleep -Seconds 1
    }

    return @(get-job).Count
}

# ----------------------------------------------------------------------------------------------------------------
function monitor-backgroundJobs()
{
    while ((check-backgroundJobs))
    {
        Start-Sleep -Seconds 1
    }
}

# ----------------------------------------------------------------------------------------------------------------
function remove-backgroundJobs()
{
    foreach($job in get-job)
    {
        write-verbose "removing job"
        write-verbose (Receive-Job -Job $Job | fl * | out-string)
        Write-Verbose (Remove-Job -Job $job -Force)
    }
}

#-------------------------------------------------------------------
function start-backgroundJob($jobInfo)
{
    log-info "starting background job"
        
    $job = Start-Job -ScriptBlock `
    { 
        param($jobInfo)
        $ctx = $null
        #background job for bug https://github.com/Azure/azure-powershell/issues/7110
        #Disable-AzureRmContextAutosave -scope Process -ErrorAction SilentlyContinue | Out-Null

        . $($jobInfo.invocation.scriptname)
        $ctx = Import-AzureRmContext -Path $jobInfo.profileContext
        # bug to be fixed 8/2017
        # From <https://github.com/Azure/azure-powershell/issues/3954> 
        [void]$ctx.Context.TokenCache.Deserialize($ctx.Context.TokenCache.CacheData)

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
        while ((check-backgroundJobs) -gt $throttle)
        {
            Write-Verbose "throttled"
            Start-Sleep -Seconds 1
        }

        [void]$global:jobs.Add((start-backgroundJob -jobInfo $jobInfo))
    }
}

# ----------------------------------------------------------------------------------------------------------------
if ($host.Name -ine "ServerRemoteHost")
{
    main
}
