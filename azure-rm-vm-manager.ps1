<#  
.SYNOPSIS  
    powershell script to manage IaaS virtual machines in Azure Resource Manager
    
.DESCRIPTION  
    powershell script to manage IaaS virtual machines in Azure Resource Manager
    requires azure powershell sdk (install-module azurerm)
    script does the following:
 
.NOTES  
   File Name  : azure-rm-vm-manager.ps1
   Author     : jagilber
   Version    : 170902 added 'deallocate' action
   History    : 
                170723 fix for $vms filter. fix for jobs count v2
                170717 fix $jobsCount for single machine
                170713 add progress

.EXAMPLE  
    .\azure-rm-vm-manager.ps1 -action stop
    will stop all vm's in subscription!

.EXAMPLE  
    .\azure-rm-vm-manager.ps1 -resourceGroupName existingResourceGroup -action start
    will start all vm's in resource group existingResoureGroup

.EXAMPLE  
    .\azure-rm-vm-manager.ps1 -resourceGroupName existingResourceGroup -action listRunning
    will list all running vm's in resource group existingResourceGroup

.EXAMPLE  
    .\azure-rm-vm-manager.ps1 -resourceGroupName existingResourceGroup -action start -timerAction stop -timerHours 8
    will start all vm's in resource group existingResourceGroup and 8 hours after start, will stop all vm's in same resource group

.PARAMETER action
    required. action to perform. start, stop, restart, list, listDeallocated, listRunning

.PARAMETER excludeResourceGroupNames
    string array list of resource groups to exclude from command

.PARAMETER excludeVms
    string array list of vm's to exclude from command

.PARAMETER getUpdate
    compare the current script against the location in github and will update if different.

.PARAMETER noLog
    disable writing log file

.PARAMETER resourceGroupName
    string array of resource group names of the resource groups containg the vm's to manage
    if NOT specified, all resource groups will be managed

.PARAMETER timerAction
    action to perform at timerHours

.PARAMETER timerHours
    if specified, decimal for hours to wait until performing timeraction. see example.

.PARAMETER vms
    string array list of vm's to include for command

.PARAMETER vmsss
    enumerate virtual machine scale set information
#>  

[CmdletBinding()]
param(
    [ValidateSet('start', 'stop', 'restart', 'listRunning', 'listDeallocated', 'list', 'deallocate')]
    [string]$action = 'list',
    [string[]]$resourceGroupNames = @(),
    [string[]]$vms = @(),
    [switch]$vmss,
    [string[]]$excludeResourceGroupNames = @(),
    [string[]]$excludeVms = @(),
    [switch]$getUpdate,
    [switch]$noLog,
    [int]$throttle = 20,
    [float]$timerHours = 0,
    [ValidateSet('start', 'stop', 'restart', 'listRunning', 'listDeallocated', 'list', 'deallocate')]
    [string]$timerAction
)

$ErrorActionPreference = "Continue"
$logFile = "azure-rm-vm-manager.log.txt"
$profileContext = "$($env:TEMP)\ProfileContext.ctx"
$global:jobs = New-Object Collections.ArrayList
$action = $action.ToLower()
$updateUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-rm-vm-manager.ps1"
$global:jobInfos = New-Object Collections.ArrayList
$global:jobsCount = 0
$global:startTime = get-date

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $error.Clear()
    $allVms = New-Object Collections.ArrayList
    $allVmss = New-Object Collections.ArrayList
    $filteredVms = New-Object Collections.ArrayList

    try
    {
        log-info "$(get-date) enumerating vms for action '$($action) vms'. Ctrl-C to stop script."

        # see if new (different) version of file
        if ($getUpdate)
        {
            get-update -updateUrl $updateUrl -destinationFile $MyInvocation.ScriptName
            exit 0
        }

        remove-backgroundJobs

        # see if we need to auth
        authenticate-azureRm
        $allVms = New-Object Collections.ArrayList (,(Find-AzureRmResource -ResourceType Microsoft.Compute/virtualMachines))

        if($vmss)
        {
            log-info "checking virtual machine scale sets"
            #$vmssvms = Get-AzureRmVmss -ResourceGroupName 
            $allVmss = New-Object Collections.ArrayList (,(Find-AzureRmResource -ResourceType Microsoft.Compute/virtualMachineScaleSets))
            
            if($allVmss.Count -gt 1)
            {
                $allVms.AddRange($allVmss)
            }
            elseif($allVmss.Count -eq 1)
            {
                $allVms.Add($allVmss)
            }
        }

        if (!$allVms)
        {
            log-info "warning:no vm's found. exiting"
            exit 1
        }

        # if neither passed in use all
        if (!$vms -and !$resourceGroupNames -and !$excludeVms -and !$excludeResourceGroupNames -and !($action -imatch 'list'))
        {
            log-info "warning: managing all vm's in subscription! use -resourcegroupnames or -vms to filter.`r`nif this is wrong, press ctrl-c to exit..."
        }

        if (!$resourceGroupNames)
        {
            $resourceGroupNames = (Get-AzureRmResourceGroup).ResourceGroupName
        }

        # check passed in resource group names
        foreach ($resourceGroupName in $resourceGroupNames)
        {
            foreach ($vm in $allVms)
            {
                if ($resourceGroupName -ieq $vm.ResourceGroupName)
                {
                    [void]$filteredVms.Add($vm)
                }
            }
        }

        # check for excludeResourceGroup names
        foreach ($excludeResourceGroup in $excludeResourceGroupNames)
        {
            foreach ($vm in $allVms)
            {
                if ($excludeResourceGroup -ieq $vm.ResourceGroupName -and $filteredVms.Contains($vm))
                {
                    log-info "verbose: removing vm $($vm)"
                    [void]$filteredVms.Remove($vm)
                }
            }
        }

        if ($vms -and $filteredVms)
        {
            # remove vm's not matching $vms list
            foreach ($filteredVm in (new-object Collections.ArrayList (, $filteredVms)))
            {
                if (!($vms -ieq $filteredVm.Name))
                {
                    log-info "verbose: removing vm $($filteredVm)"
                    [void]$filteredVms.Remove($filteredVm)
                }
            }
        }

        # check for excludeVms names
        foreach ($excludeVm in $excludeVms)
        {
            if (($filteredVms.Name -ieq $excludeVm) -and ($allVms.Name -ieq $excludeVm))
            {
                log-info "verbose: removing excluded vm $($excludeVm)"
                
                foreach ($vm in @($allVms | Where-Object Name -ieq $excludeVm))
                {
                    [void]$filteredVms.Remove($vm)
                }
            }
        }

        if (!$filteredVms -or $filteredVms.Count -lt 1)
        {
            log-info "0 vms matched command given."
            return
        }

        foreach ($filteredVm in $filteredVms)
        {
            log-info "$($filteredVm.resourceGroupName)\$($filteredVm.Name)"
        }

        log-info "checking $($filteredVms.Count) vms for current power state. please wait ..." 
    
        foreach ($vm in $filteredVms)
        {
            log-info "verbose:adding vm $($vm.resourceGroupName)\$($vm.name)"
            $jobInfo = @{}
            $jobInfo.vm = ""
            $jobInfo.profileContext = $profileContext
            $jobInfo.action = $action
            $jobInfo.invocation = $MyInvocation
            $JobInfo.backgroundJobFunction = (get-item function:do-backgroundJob)
            $jobInfo.jobName = $action
            $jobInfo.vm = $vm
            $jobInfo.jobName = "$($action):$($vm.resourceGroupName)\$($vm.name)"
            $jobInfo.verbosePreference = $VerbosePreference
            $jobInfo.debugPreference = $DebugPreference
            $jobInfo.vmRunning = ""
            $jobInfo.powerState = ""
            $jobInfo.provisioningState = ""
            # quicker to not use jobs for checking power state
            $jobInfo = check-vmRunning -jobInfo $jobInfo

            [void]$global:jobInfos.Add($jobInfo)
        } 

        # perform action
        perform-action -currentAction $action

        # wait for action to complete
        monitor-backgroundJobs 

        if ($timerAction -and $timerHours -ne 0)
        {
            $totalMinutes = ($global:startTime.AddHours($timerHours) - $global:startTime).TotalMinutes

            while ($true)
            {
                $minutesLeft = ($global:startTime.AddHours($timerHours) - (get-date)).TotalMinutes
                Write-Progress -Activity "timer for timerAction '$($timerAction) vms'. Ctrl-C to stop script / timerAction." `
                    -Status "minutes left until timerAction starts: $($minutesLeft.ToString("0.0"))" `
                    -PercentComplete ($minutesLeft / $totalMinutes * 100)

                if ($minutesLeft -le 0)
                {
                    # perform action
                    perform-action -currentAction $timerAction

                    # wait for action to complete
                    monitor-backgroundJobs 

                    break
                }

                Start-Sleep -seconds 5
            }
        }
    }
    catch
    {
        log-info "main:exception:$($error | out-string)"
    }
    finally
    {
        remove-backgroundJobs

        if (test-path $profileContext)
        {
            Remove-Item -Path $profileContext -Force
        }

        log-info "$(get-date) finished script. total minutes: $(((get-date) - $global:startTime).totalminutes.ToString("0.00"))"
    }
}

# ----------------------------------------------------------------------------------------------------------------
function authenticate-azureRm()
{
    # make sure at least wmf 5.0 installed
    if ($PSVersionTable.PSVersion -lt [version]"5.0.0.0")
    {
        log-info "update version of powershell to at least wmf 5.0. exiting..." -ForegroundColor Yellow
        start-process "https://www.bing.com/search?q=download+windows+management+framework+5.0"
        # start-process "https://www.microsoft.com/en-us/download/details.aspx?id=50395"
        exit
    }

    #  verify NuGet package
    $nuget = get-packageprovider nuget -Force

    if (-not $nuget -or ($nuget.Version -lt [version]::New("2.8.5.22")))
    {
        log-info "installing nuget package..."
        install-packageprovider -name NuGet -minimumversion ([version]::New("2.8.5.201")) -force
    }

    $allModules = (get-module azure* -ListAvailable).Name
    #  install AzureRM module
    if ($allModules -inotcontains "AzureRM")
    {
        # at least need profile, resources, compute, network
        if ($allModules -inotcontains "AzureRM.profile")
        {
            log-info "installing AzureRm.profile powershell module..."
            install-module AzureRM.profile -force
        }
        if ($allModules -inotcontains "AzureRM.resources")
        {
            log-info "installing AzureRm.resources powershell module..."
            install-module AzureRM.resources -force
        }
        if ($allModules -inotcontains "AzureRM.compute")
        {
            log-info "installing AzureRm.compute powershell module..."
            install-module AzureRM.compute -force
        }
            
        Import-Module azurerm.profile        
        Import-Module azurerm.resources        
        Import-Module azurerm.compute            
    }
    else
    {
        Import-Module azurerm
    }

    # authenticate
    try
    {
        Get-AzureRmResourceGroup | Out-Null
    }
    catch
    {
        try
        {
            Add-AzureRmAccount
        }
        catch
        {
            log-info "exception authenticating. exiting $($error | out-string)" -ForegroundColor Yellow
            exit 1
        }
    }

    Save-AzureRmContext -Path $profileContext -Force
}

# ----------------------------------------------------------------------------------------------------------------
function check-backgroundJobs($writeStatus = $false)
{
    $ret = $null
    update-progress

    foreach ($job in get-job)
    {
        $jobInfo = "$(get-date) job name:$($job.Name)  job state:$($job.JobStateInfo)"

        if ($job.State -ine "Running")
        {
            Remove-Job -Id $job.Id -Force
            log-info "`tjob status: $($jobInfo)"
            update-progress
            continue
        }
        else
        {
            $ret = Receive-Job -Job $job

            if ($ret)
            {
                log-info "`twarning:receive job $($job.Name) data: $($ret)"
            }
        }            

        if ($writeStatus)
        {
            log-info "`tjob status: $($jobInfo)"
        }
        else
        {
            log-info "`tverbose: job status: $($jobInfo)"
        }

    }

    return @(get-job).Count
}

# ----------------------------------------------------------------------------------------------------------------
function check-vmRunning($jobInfo)
{
    log-info "verbose:checking vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"

    $jobInfo.vmRunning = $null
    $jobInfo.powerState = "unknown"
    $jobInfo.provisioningState = "unknown"

    foreach ($status in (get-azurermvm -resourceGroupName $jobInfo.vm.resourceGroupName -Name $jobInfo.vm.Name -status).Statuses)
    {
        if ($status.Code -imatch "PowerState")
        {
            $jobInfo.powerState = $status.Code.ToString().Replace("PowerState/", "")
        }
        
        if ($status.Code -imatch "ProvisioningState")
        {
            $jobInfo.provisioningState = $status.Code.ToString().Replace("ProvisioningState/", "")
        }

        if ($status.Code -eq "PowerState/running")
        {
            $jobInfo.vmRunning = $true
        }
        elseif ($status.Code -ieq "PowerState/deallocated" -or $status.Code -ieq "PowerState/stopped")
        {
            $jobInfo.vmRunning = $false
        }
    }    

    log-info "verbose:`tvm $($jobInfo.vm.resourceGroupName):$($jobInfo.vm.name):$($jobInfo.provisioningState):$($jobInfo.powerState)"
    return $jobInfo
}

# ----------------------------------------------------------------------------------------------------------------
function do-backgroundJob($jobInfo)
{
    $powerState = $null
    $VerbosePreference = $jobInfo.verbosePreference.Value
    log-info "verbose:doing background job $($jobInfo.action)"
   
    # for job debugging
    # when attached with -debug switch, set $jobInfo.debugPreference to SilentlyContinue to debug
    while ($jobInfo.debugPreference -imatch "Inquire")
    {
        log-info "waiting to debug background job $($jobInfo.action) : $($jobInfo.debugPreference)"
        log-info "set $jobInfo.debugPreference = SilentlyContinue to break debug loop"
        start-sleep -Seconds 1
    }
    
    $jobInfo = check-vmRunning -jobInfo $jobInfo

    switch ($jobInfo.vmRunning)
    {
        $true 
        {
            switch ($jobInfo.action)
            {
                "deallocate" 
                {
                    log-info "`tdeallocating vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    Stop-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName -Force
                    log-info "verbose:`tvm deallocated $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                }

                "stop" 
                {
                    log-info "`tstopping vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    Stop-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName -Force -StayProvisioned
                    log-info "verbose:`tvm stopped $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                }

                "restart" 
                {
                    log-info "`trestarting vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    #Restart-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName
                    Stop-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName -Force
                    log-info "`tvm stopped $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    Start-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName
                    log-info "verbose:`tvm restarted $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                }

                default: {}
            }
        }

        $false 
        {
            switch ($jobInfo.action)
            {
                "deallocate" 
                {
                    log-info "`tdeallocating vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    Stop-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName -Force
                    log-info "verbose:`tvm deallocated $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                }

                "start" 
                {
                    log-info "`tstarting vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    Start-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName
                    log-info "verbose:`tvm started $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                }

                default: {}
            }
        }

        default: 
        {
            log-info "error:vm power state unknown $($jobInfo.vm.name)"
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function get-update($updateUrl, $destinationFile)
{
    log-info "get-update:checking for updated script: $($updateUrl)"
    $file = ""
    $git = $null

    try 
    {
        $git = Invoke-RestMethod -Method Get -Uri $updateUrl 

        # git may not have carriage return
        if ([regex]::Matches($git, "`r").Count -eq 0)
        {
            $git = [regex]::Replace($git, "`n", "`r`n")
        }

        if ([IO.File]::Exists($destinationFile))
        {
            $file = [IO.File]::ReadAllText($destinationFile)
        }

        if (([string]::Compare($git, $file) -ne 0))
        {
            log-info "copying script $($destinationFile)"
            [IO.File]::WriteAllText($destinationFile, $git)
            return $true
        }
        else
        {
            log-info "script is up to date"
        }
        
        return $false
    }
    catch [System.Exception] 
    {
        log-info "get-update:exception: $($error | out-string)"
        $error.Clear()
        return $false    
    }
}

# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    $dataWritten = $false
    $counter = 0
    $foregroundColor = "white"

    if ($data -imatch "error:|fail")
    {
        $foregroundColor = "red"
    }
    elseif ($data -imatch "warning")
    {
        $foregroundColor = "yellow"
    }
    elseif ($data -imatch "running")
    {
        $foregroundColor = "green"
    }
    elseif ($data -imatch "deallocated|stopped")
    {
        $foregroundColor = "gray"
    }
    elseif ($data -imatch "unknown")
    {
        $foregroundColor = "cyan"
    }

    while (!$noLog -and !$dataWritten -and $counter -lt 1000)
    {
        try
        {
            out-file -Append -InputObject "$([System.DateTime]::Now):$($data)`n" -FilePath $logFile
            $dataWritten = $true
        }
        catch
        {
            Start-Sleep -Milliseconds 10
            $counter++
        }
    }

    if ($data -imatch "verbose:")
    {
        if ($VerbosePreference -ine "SilentlyContinue")
        {
            write-host $data -ForegroundColor $foregroundColor
        }
    }
    else
    {
        write-host $data -ForegroundColor $foregroundcolor
    }
}

# ----------------------------------------------------------------------------------------------------------------
function monitor-backgroundJobs()
{
    $updateCounter = 1

    while ((check-backgroundJobs -writeStatus ($updateCounter % 300 -eq 0)))
    {
        $updateCounter++
        Start-Sleep -Seconds 1
    }
}

# ----------------------------------------------------------------------------------------------------------------
function perform-action($currentAction)
{
    switch ($currentAction)
    {
        "deallocate" 
        { 
            start-backgroundJobs -jobInfos ($global:jobInfos) -throttle $throttle 
        }

        "list" 
        { 
            log-info "resourcegroupname   `t| vm name             `t| provisioning   `t| power"
            log-info "---------------------------------------------------------------------------------"

            foreach ($jobInfo in $global:jobInfos)
            {
                log-info "$($jobInfo.vm.resourceGroupName.PadRight(20))`t| $($jobInfo.vm.name.PadRight(20))`t| $($jobInfo.provisioningState.PadRight(15))`t| $($jobInfo.powerState.PadRight(15))"
            }
        }

        "listRunning" 
        { 
            foreach ($jobInfo in $global:jobInfos | where-object vmRunning -imatch $true)
            {
                log-info "$($jobInfo.vm.resourceGroupName):$($jobInfo.vm.name):running"
            }
        }
            
        "listDeallocated" 
        { 
            foreach ($jobInfo in $global:jobInfos | where-object vmRunning -imatch $false)
            {
                log-info "$($jobInfo.vm.resourceGroupName):$($jobInfo.vm.name):deallocated"
            }
        }

        "restart" 
        { 
            start-backgroundJobs -jobInfos ($global:jobInfos | where-object vmRunning -imatch $true) -throttle $throttle 
        }

        "start" 
        { 
            start-backgroundJobs -jobInfos ($global:jobInfos | where-object vmRunning -imatch $false) -throttle $throttle 
        }

        "stop" 
        { 
            start-backgroundJobs -jobInfos ($global:jobInfos | where-object vmRunning -imatch $true) -throttle $throttle 
        }

        default: {}
    }
}

# ----------------------------------------------------------------------------------------------------------------
function remove-backgroundJobs()
{
    foreach ($job in get-job)
    {
        log-info "verbose:removing job"
        log-info "verbose: $(Receive-Job -Job $Job | fl * | out-string)"
        log-info "verbose: $(Remove-Job -Job $job -Force)"
    }
}

#-------------------------------------------------------------------
function start-backgroundJob($jobInfo)
{
    log-info "verbose:starting background job $($jobInfo.jobName)"
        
    $job = Start-Job -ScriptBlock `
    { 
        param($jobInfo)
        $ctx = $null

        . $($jobInfo.invocation.scriptname)
        $ctx = Import-AzureRmContext -Path $jobInfo.profileContext
        # bug to be fixed 8/2017
        # From <https://github.com/Azure/azure-powershell/issues/3954> 
        [void]$ctx.Context.TokenCache.Deserialize($ctx.Context.TokenCache.CacheData)

        & $jobInfo.backgroundJobFunction $jobInfo

    } -Name $jobInfo.jobName -ArgumentList $jobInfo

    if ($DebugPreference -ine "SilentlyContinue")
    {
        ### debug job
        Start-Sleep -Seconds 5
        debug-job -Job $job
        pause
    }

    return $job
}

# ----------------------------------------------------------------------------------------------------------------
function start-backgroundJobs($jobInfos, $throttle)
{
    if (!$jobInfos)
    {
        log-info "no vm's need action: '$($action)' performed"
        return
    }

    $count = 1
    $global:jobsCount = @($jobInfos).Count
    log-info "starting $($global:jobsCount) background jobs:"
    $activity = "starting $($global:jobsCount) '$($action) vms' jobs. throttle: $($throttle). Ctrl-C to stop script."

    foreach ($jobInfo in $jobInfos)
    {
        while ((check-backgroundJobs) -gt $throttle)
        {
            log-info "verbose:throttled"
            Start-Sleep -Seconds 1
        }
        
        [void]$global:jobs.Add((start-backgroundJob -jobInfo $jobInfo))
        $status = "$($count) / $($global:jobsCount) jobs started. " `
            + "time elapsed:  $(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes"
        $percentComplete = ($count / $global:jobsCount * 100)
        Write-Progress -Activity $activity -Status $status -PercentComplete $percentComplete -id 1
        $count++
    }
}

# ----------------------------------------------------------------------------------------------------------------
function update-progress()
{
    $globalJobsCount = $global:jobsCount

    if ($globalJobsCount -gt 0)
    {
        $finishedJobsCount = $globalJobsCount - @(get-job).Count
        $status = "$($finishedJobsCount) / $($globalJobsCount) vm jobs completed. " `
            + "time elapsed:  $(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes"
        $percentComplete = ($finishedJobsCount / $globaljobsCount * 100)

        Write-Progress -Activity "$($action) $($globalJobsCount) vms jobs completion status:" -Status $status -PercentComplete $percentComplete -ParentId 1
    }
}

# ----------------------------------------------------------------------------------------------------------------
if ($host.Name -ine "ServerRemoteHost")
{
    main
}
