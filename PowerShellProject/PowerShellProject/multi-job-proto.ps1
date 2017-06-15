
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
        $this = @{}
        $this.jobName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.Scriptname)
        $this.invocation = $MyInvocation
        $this.action = "test"

        while ($true)
        {
            if (((get-job).State -eq "Running").Count -le $throttle)
            {
                $global:jobs.Add((start-backgroundJob -this $this))
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
function do-backgroundJob($this)
{
    while ($true)
    {
        log-info "doing background job $($this.action)"
        log-info ($this.action)
        "================"
        Start-Sleep -Seconds 1
    }
}


#-------------------------------------------------------------------
function start-backgroundJob($this)
{
    log-info "starting background job"
        
    $job = Start-Job -ScriptBlock `
 { 
        param($this)

        . $($this.invocation.scriptname)
        log-info ($this.action)
        do-backgroundJob -this $this

    } -Name $this.jobName -ArgumentList $this
    
    return $job
}

#-------------------------------------------------------------------
if ($host.Name -ine "ServerRemoteHost")
{
    main
}
