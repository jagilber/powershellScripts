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
   Version    : 170627 added -vms
   History    : 

.EXAMPLE  
    .\azure-rm-vm-manager.ps1 -action stop
    will stop all vm's in subscription!

.EXAMPLE  
    .\azure-rm-vm-manager.ps1 -resourceGroupName existingResourceGroup -action start
    will start all vm's in resource group existingResoureGroup

.EXAMPLE  
    .\azure-rm-vm-manager.ps1 -resourceGroupName existingResourceGroup -action listRunning
    will list all running vm's in resource group existingResourceGroup

.PARAMETER action
    required. action to perform. start, stop, restart, listRunning

.PARAMETER resourceGroupName
    string array of resource group names of the resource groups containg the vm's to manage
    if NOT specified, all resource groups will be managed

.PARAMETER vms
    string array list of vm's to include for command

.PARAMETER excludeVms
    string array list of vm's to exclude from command

#>  

[CmdletBinding()]
param(
    #[ValidateSet('start','stop','restart','listRunning','listStopped')]
    [string]$action = 'listRunning',
    [string[]]$resourceGroupNames = @(),
    [string[]]$excludeVms = @(),
    [int]$throttle = 20,
    [string[]]$vms = @()
)

$logFile = "azure-rm-vm-manager.log.txt"
$profileContext = "$($env:TEMP)\ProfileContext.ctx"
$global:jobs = New-Object Collections.ArrayList
$action = $action.ToLower()

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $error.Clear()
    $allVms = @()
    $filteredVms = New-Object Collections.ArrayList
    $startTime = get-date
    $jobInfos = New-Object Collections.ArrayList

    log-info "$((get-date).ToString("o")) starting script"
    remove-backgroundJobs

    try
    {
        # see if we need to auth
        authenticate-azureRm

        $allVms = @(Find-AzureRmResource -ResourceType Microsoft.Compute/virtualMachines)

        # check passed in resource group names
        foreach($resourceGroupName in $resourceGroupNames)
        {
            foreach($vm in $allVms)
            {
                if($resourceGroupName -imatch $vm.ResourceGroupName)
                {
                    [void]$filteredVms.Add($vm)
                }
            }
        }

        # check passed in vm names
        foreach($vm in $vms)
        {
            if(!($filteredVms.Name -imatch $vm) -and ($allVms.Name -imatch $vm))
            {
                [void]$filteredVms.AddRange(@($allVms |? Name -imatch $vm))
            }
        }

        # check for excludeVms names
        foreach($excludeVm in $excludeVms)
        {
            if(($filteredVms.Name -imatch $excludeVm) -and ($allVms.Name -imatch $excludeVm))
            {
                [void]$filteredVms.RemoveRange(@($allVms |? Name -imatch $excludeVm))
            }
        }


        # if neither passed in use all
        if(!$vms -and !$resourceGroupNames)
        {
           Write-Warning "warning: querying / managing all vm's in subscription! use -resourcegroupnames or -vms to filter. if this is wrong, press ctrl-c to exit..."
           $filteredVms = $allVms
        }
        else
        {
            foreach($filteredVm in $filteredVms)
            {
                log-info "$($filteredVm.resourceGroupName)\$($filteredVm.Name)"
            }
        }

        log-info "checking $($filteredVms.Count) vms. use -verbose switch to see more detail..."
        
    
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
            $jobInfo.poweredon = $null
            $jobInfo.vm = $vm
            $jobInfo.jobName = "$($action):$($vm.resourceGroupName)\$($vm.name)"
            $jobInfo.verbosePreference = $VerbosePreference
            $jobInfo.debugPreference = $DebugPreference
            # quicker to not use jobs for checking power state
            $jobInfo.poweredon = check-vmPoweredOn -jobInfo $jobInfo
            [void]$jobInfos.Add($jobInfo)
        } 

        # perform action
        switch($action)
        {
            "listRunning" { 
                foreach ($jobInfo in $jobInfos |? poweredon -imatch $true)
                {
                    log-info "$($jobInfo.vm.resourceGroupName):$($jobInfo.vm.name):running"
                }
            }
            
            "listStopped" { 
                foreach ($jobInfo in $jobInfos |? poweredon -imatch $false)
                {
                    log-info "$($jobInfo.vm.resourceGroupName):$($jobInfo.vm.name):stopped"
                }
            }

            "restart" { start-backgroundJobs -jobInfos ($jobInfos |? poweredon -imatch $true) -throttle $throttle }

            "start" { start-backgroundJobs -jobInfos ($jobInfos |? poweredon -imatch $false) -throttle $throttle }

            "stop" { start-backgroundJobs -jobInfos ($jobInfos |? poweredon -imatch $true) -throttle $throttle }

            default: {}
        }

        monitor-backgroundJobs 
    }
    catch
    {
        log-info "main:exception:$($error)"
    }
    finally
    {
        remove-backgroundJobs

        if(test-path $profileContext)
        {
            Remove-Item -Path $profileContext -Force
        }

        log-info "$((get-date).ToString("o")) finished script. total minutes: $(((get-date) - $startTime).totalminutes)"
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
        if ($allModules -inotcontains "AzureRM.network")
        {
            log-info "installing AzureRm.network powershell module..."
            install-module AzureRM.network -force

        }
            
        Import-Module azurerm.profile        
        Import-Module azurerm.resources        
        Import-Module azurerm.compute            
        Import-Module azurerm.network
		#log-info "installing AzureRm powershell module..."
		#install-module AzureRM -force
        
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
            log-info "exception authenticating. exiting $($error)" -ForegroundColor Yellow
            exit 1
        }
    }

    Save-AzureRmContext -Path $profileContext -Force
}

# ----------------------------------------------------------------------------------------------------------------
function check-backgroundJobs()
{
    foreach ($job in get-job)
    {
        $jobInfo = $Null

        if ($job.State -ine "Running")
        {
            $jobInfo = "$($job.Name) $($job.JobStateInfo)"
            log-info "verbose $(Remove-Job -Id $job.Id -Force)"
        }
        else
        {
            $jobInfo = (Receive-Job -Job $job | fl * | out-string)
        }            

        if($jobInfo)
        {
            log-info "verbose:jobresult:$($jobInfo)"
        }

        Start-Sleep -Seconds 1
    }

    return @(get-job).Count
}

# ----------------------------------------------------------------------------------------------------------------
function check-vmPoweredOn($jobInfo)
{
    log-info "verbose:checking vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"

    foreach ($status in (get-azurermvm -resourceGroupName $jobInfo.vm.resourceGroupName -Name $jobInfo.vm.Name -status).Statuses)
    {
        if ($status.Code -eq "PowerState/running")
        {
            log-info "verbose:`tvm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name):running"
            return $true
        }
        elseif ($status.Code -ieq "PowerState/deallocated")
        {
            log-info "verbose:`tvm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name):deallocated"
            return $false
        }
    }    

    log-info "verbose:`twarning:vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name):unknown"
    return $null
}

# ----------------------------------------------------------------------------------------------------------------
function do-backgroundJob($jobInfo)
{
    $powerState = $null
    $VerbosePreference = $jobInfo.verbosePreference
    log-info "verbose:doing background job $($jobInfo.action)"
   
    # for job debugging
    # when attached with -debug switch, set $debugPreference to SilentlyContinue to debug
    while($jobInfo.debugPreference -ieq "Inquire")
    {
		log-info "verbose:waiting to debug background job $($jobInfo.action) : $($jobInfo.debugPreference)"
        start-sleep -Seconds 1
    }
    
    switch((check-vmPoweredOn -jobInfo $jobInfo))
    {
        $true {
            switch($jobInfo.action)
            {
                "stop" {
                    log-info "verbose:`tstopping vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    Stop-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName -Force
                    log-info "verbose:`tvm stopped $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                }
                "restart" {
                    log-info "verbose:`trestarting vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    Restart-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName
                    log-info "verbose:`tvm restarted $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                }
                default: {}
            }
        }

        $false {
            switch($jobInfo.action)
            {
                "start" {
                    log-info "verbose:`tstarting vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    Start-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName
                    log-info "verbose:`tvm started $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                }
                default: {}
            }
        }

        default: {
            log-info "error:vm power state unknown $($jobInfo.vm.name)"
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    $dataWritten = $false
    $counter = 0
    $foregroundColor = "white"

    if($data.ToString().ToLower().StartsWith("error"))
    {
        $foregroundColor = "red"
    }

    while (!$dataWritten -and $counter -lt 1000)
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

    if($data.ToLower().StartsWith("verbose:"))
    {
        if($VerbosePreference -ine "SilentlyContinue")
        {
            write-host $data -ForegroundColor $foregroundcolor
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
        log-info "verbose:removing job"
        log-info "verbose $(Receive-Job -Job $Job | fl * | out-string)"
        log-info "verbose $(Remove-Job -Job $job -Force)"
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

        log-info ($jobInfo.action)
        #do-backgroundJob -jobInfo $jobInfo
        & $jobInfo.backgroundJobFunction $jobInfo

    } -Name $jobInfo.jobName -ArgumentList $jobInfo

    if($DebugPreference -ine "SilentlyContinue")
    {
        ### debug job
        Start-Sleep -Seconds 5
        debug-job -Job $job
        pause
        ### end test
    }

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
            log-info "verbose:throttled"
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
