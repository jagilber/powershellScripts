# SCRIPT TO GET ALL AZURERM-VM AND STOP
# 170609
# https://azure.microsoft.com/en-us/documentation/articles/resource-group-authenticate-service-principal/

param(
    [string[]]$resourceGroupNames = @(),
    [string[]]$exclusionList = @(),
    [switch]$listRunning
)

$logFile = "azure-vm-shutdown.log.txt"
#$subscriptionId = ""
#Select-AzureRmSubscription -SubscriptionId $subscriptionId 
$profileContext = "$($env:TEMP)\ProfileContext.ctx"

# to stop only specific resource groups. Remove entries to run on all groups
#$resourceGroupNames = @()
#$exclusionList = @() #@("rds-dc-1","ara-rds-1","ara-rds-2")

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $ctx = $null
    $allVms = @()
    $filteredVms = New-Object Collections.ArrayList

    log-info "starting script"
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

    $jobs = @()

    # save context for jobs
    Save-AzureRmContext -Path $profileContext -Force 

    log-info "checking $($filteredVms.Count) vms"

    foreach ($vm in $filteredVms)
    {
        write-verbose "starting job $($vm.resourceGroupName)\$($vm.name)"
       
        $job = Start-Job -Name "vm" -ScriptBlock {
            param($resourceGroupName, $exclusionList, $profileContext, $listRunning, $vm)

            $ctx = Import-AzureRmContext -Path $profileContext
            # bug to be fixed 8/2017
            # From <https://github.com/Azure/azure-powershell/issues/3954> 
            $ctx.Context.TokenCache.Deserialize($ctx.Context.TokenCache.CacheData)

            if (!$listRunning)
            {
                write-host "$(get-date) checking vm $($resourceGroupName)\$($vm.name)"
            }

            foreach ($status in (get-azurermvm -resourceGroupName $resourceGroupName -Name $vm.Name -status).Statuses)
            {
                #write-host $status.Code
                if ($status.Code -eq "PowerState/running")
                {
                    if ($listRunning)
                    {
                        write-host "$($resourceGroupName):$($vm.name):running"
                        break
                    }

                    if ($exclusionList.Contains($vm.name))
                    {
                        write-host "`t$(get-date) skipping vm $($resourceGroupName)\$($vm.name)"
                    
                    }
                    else
                    {
                        write-host "`t$(get-date) stopping vm $($resourceGroupName)\$($vm.name)"
                        Stop-AzureRmvm -Name $vm.Name -ResourceGroupName $resourceGroupName -Force
                        write-host "`t$(get-date) vm stopped $($resourceGroupName)\$($vm.name)"
                    }
                }
            }
        } -ArgumentList ($vm.resourceGroupName, $exclusionList, $profileContext, $listRunning, $vm)

        $jobs = $jobs + $job
    } # end foreach

    # Wait for all jobs to complete
    if ($jobs -ne @())
    {
        while ((get-job | where { $_.Name -eq "vm" }))
        {

            foreach ($job in get-job)
            {
                Receive-Job -Job $job #| log-info

                if ($job.State -ieq 'Completed')
                {
     
                    Remove-Job -Job $job
                }
            }

            start-sleep -seconds 1
        }
    }

    if(test-path $profileContext)
    {
        Remove-Item -Path $profileContext -Force
    }

    log-info "finished"
}

# ----------------------------------------------------------------------------------------------------------------
function authenticate-azureRm()
{
    # make sure at least wmf 5.0 installed

    if ($PSVersionTable.PSVersion -lt [version]"5.0.0.0")
    {
        write-host "update version of powershell to at least wmf 5.0. exiting..." -ForegroundColor Yellow
        start-process "https://www.bing.com/search?q=download+windows+management+framework+5.0"
        # start-process "https://www.microsoft.com/en-us/download/details.aspx?id=50395"
        exit
    }

    #  verify NuGet package
	$nuget = get-packageprovider nuget -Force

	if (-not $nuget -or ($nuget.Version -lt [version]::New("2.8.5.22")))
	{
		write-host "installing nuget package..."
		install-packageprovider -name NuGet -minimumversion ([version]::New("2.8.5.201")) -force
	}

    $allModules = (get-module azure* -ListAvailable).Name
	#  install AzureRM module
	if ($allModules -inotcontains "AzureRM")
	{
        # at least need profile, resources, compute, network
        if ($allModules -inotcontains "AzureRM.profile")
        {
            write-host "installing AzureRm.profile powershell module..."
            install-module AzureRM.profile -force
        }
        if ($allModules -inotcontains "AzureRM.resources")
        {
            write-host "installing AzureRm.resources powershell module..."
            install-module AzureRM.resources -force
        }
        if ($allModules -inotcontains "AzureRM.compute")
        {
            write-host "installing AzureRm.compute powershell module..."
            install-module AzureRM.compute -force
        }
        if ($allModules -inotcontains "AzureRM.network")
        {
            write-host "installing AzureRm.network powershell module..."
            install-module AzureRM.network -force

        }
            
        Import-Module azurerm.profile        
        Import-Module azurerm.resources        
        Import-Module azurerm.compute            
        Import-Module azurerm.network
		#write-host "installing AzureRm powershell module..."
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
            write-host "exception authenticating. exiting $($error)" -ForegroundColor Yellow
            exit 1
        }
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

main