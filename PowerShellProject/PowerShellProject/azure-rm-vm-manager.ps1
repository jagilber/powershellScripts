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
   Version    : 170626 original
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

.PARAMETER exclusionList
    string array list of vm's to exclude from command

#>  

param(
    [string]$action = 'listRunning',
    [string[]]$resourceGroupNames = @(),
    [string[]]$exclusionList = @(),
    [int]$throttle = 20
)

$logFile = "azure-rm-vm-manager.log.txt"
$profileContext = "$($env:TEMP)\ProfileContext.ctx"
$global:jobs = New-Object Collections.ArrayList

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $error.Clear()
    $allVms = @()
    $filteredVms = New-Object Collections.ArrayList

    log-info "starting script"
    remove-backgroundJobs

    # cant check on command line cause of calling on background job
    #[string][ValidateSet('start', 'stop', 'restart', 'listRunning')] 
    if(!$action -or ($action -ine 'start' -and $action -ine 'stop' -and $action -ine 'listRunning'-and $action -ine 'restart'))
    {
        Write-Warning "-action [start|stop|listRunning|restart] is a mandatory argument. exiting"
        exit 1
    }

    try
    {
        # see if we need to auth
        authenticate-azureRm

        $allVms = @(Find-AzureRmResource -ResourceType Microsoft.Compute/virtualMachines)

        if($resourceGroupNames)
        {
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
        }
        else
        {
            $filteredVms = $allVms
        }

        log-info "checking $($filteredVms.Count) vms"
        $jobInfos = New-Object Collections.ArrayList
    
        foreach ($vm in $filteredVms)
        {
            write-verbose "adding job $($vm.resourceGroupName)\$($vm.name)"
            $jobInfo = @{}
            $jobInfo.vm = ""
            $jobInfo.profileContext = $profileContext
            $jobInfo.exclusionList = $exclusionList
            $jobInfo.action = $action
            $jobInfo.invocation = $MyInvocation
            $JobInfo.backgroundJobFunction = (get-item function:do-backgroundJob)
            $jobInfo.jobName = $action
            $jobInfo.result = $null
            $jobInfo.vm = $vm
            $jobInfo.jobName = "$($action):$($vm.Name)"
            [void]$jobInfos.Add($jobInfo)
   
        } # end foreach

        start-backgroundJobs -jobInfos $jobInfos -throttle $throttle
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

        log-info "finished"
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
    log-info "doing background job $($jobInfo.action)"
    log-info "================"

    if ($jobinfo.action -ine 'listRunning')
    {
        log-info "$(get-date) checking vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
    }

    if($jobInfo.action -ieq "stop" -or $jobInfo.action -ieq "restart" -or $jobInfo.action -ieq "listRunning")
    {
        foreach ($status in (get-azurermvm -resourceGroupName $jobInfo.vm.resourceGroupName -Name $jobInfo.vm.Name -status).Statuses)
        {
            #log-info $status.Code
            if ($status.Code -eq "PowerState/running")
            {
                if ($jobInfo.action -ieq 'listRunning')
                {
                    log-info "$($jobInfo.vm.resourceGroupName):$($jobInfo.vm.name):running"
                    break
                }

                if ($jobInfo.exclusionList.Contains($jobInfo.vm.name))
                {
                    log-info "`t$(get-date) skipping vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    
                }
                else
                {
                    log-info "`t$(get-date) stopping vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    Stop-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName -Force
                    log-info "`t$(get-date) vm stopped $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                }
            }
        }
    }

    if($jobInfo.action -ieq "start" -or $jobInfo.action -ieq "restart")
    {
        foreach ($status in (get-azurermvm -resourceGroupName $jobInfo.vm.resourceGroupName -Name $jobInfo.vm.Name -status).Statuses)
        {
            if ($status.Code -eq "PowerState/running")
            {
                break
            }
            elseif ($status.Code -ieq "PowerState/deallocated")
            {
                if ($jobInfo.exclusionList.Contains($vm.name))
                {
                    write-host "`t$(get-date) skipping vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    
                }
                else
                {
                    write-host "`t$(get-date) starting vm $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                    Start-AzureRmvm -Name $jobInfo.vm.Name -ResourceGroupName $jobInfo.vm.resourceGroupName
                    write-host "`t$(get-date) vm started $($jobInfo.vm.resourceGroupName)\$($jobInfo.vm.name)"
                }

                break
            }
        }

    }
    
    #$jobInfo.result = $count
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
            Remove-Job -Id $job.Id -Force  
        }
        else
        {
            $jobInfo = (Receive-Job -Job $job | fl * | out-string)
        }            

        if($jobInfo)
        {
            log-info $jobInfo                
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
        Write-verbose (Remove-Job -Job $job -Force)
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
