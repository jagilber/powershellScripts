# SCRIPT TO GET ALL AZURERM-VM AND START
# 170609
# https://azure.microsoft.com/en-us/documentation/articles/resource-group-authenticate-service-principal/

param(
    [string[]]$resourceGroupNames = @(),
    [string[]]$exclusionList = @(),
    [switch]$listRunning
)

$erroractionpreference = "SilentlyContinue"
$logFile = "azure-vm-startup.log.txt"
#$subscriptionId = ""
#Select-AzureRmSubscription -SubscriptionId $subscriptionId 
$profileContext = "$($env:TEMP)\ProfileContext.ctx"

# to start only specific resource groups. Remove entries to run on all groups
#$resourceGroupNames = @("rdsdepjag1")
#$exclusionList = @() #@("rds-dc-1","ara-rds-1","ara-rds-2")

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    log-info "starting script"
    # see if we need to auth
    authenticate-azureRm
    
    if ([string]::IsNullOrEmpty($resourceGroupNames))
    {
        $resourceGroups = (Get-AzureRmResourceGroup).ResourceGroupName
    }
    else
    {
        $resourceGroups = $resourceGroupNames
    }

    $jobs = @()

    # save context for jobs
    Save-AzureRmContext -Path $profileContext -Force 

    ForEach ($resourceGroupName in $resourceGroups)
    {
        foreach ($vm in get-azureRmvm -ResourceGroupName $resourceGroupName | Select-Object Name)
        {
            log-info "starting job $($resourceGroupName)\$($vm.name)"
            $job = Start-Job -Name "vm" -ScriptBlock {
                param($resourceGroupName, $exclusionList, $profileContext, $listRunning, $vm)

                $ret = Import-AzureRmContext -Path $profileContext

                if (!$listRunning)
                {
                    write-host "$(get-date) checking vm $($resourceGroupName)\$($vm.name)"
                }

                foreach ($status in (get-azurermvm -resourceGroupName $resourceGroupName -Name $vm.Name -status).Statuses)
                {
                    if ($status.Code -eq "PowerState/running")
                    {
                        if ($listRunning)
                        {
                            write-host "$($resourceGroupName):$($vm.name):running"
                            break
                        }

                        break
                    }
                    elseif ($status.Code -ieq "PowerState/deallocated")
                    {
                        if ($listRunning)
                        {
                            break
                        }
                        elseif ($exclusionList.Contains($vm.name))
                        {
                            write-host "`t$(get-date) skipping vm $($resourceGroupName)\$($vm.name)"
                    
                        }
                        else
                        {
                            write-host "`t$(get-date) starting vm $($resourceGroupName)\$($vm.name)"
                            Start-AzureRmvm -Name $vm.Name -ResourceGroupName $resourceGroupName
                            write-host "`t$(get-date) vm started $($resourceGroupName)\$($vm.name)"
                        }

                        break
                    }
                }
            } -ArgumentList ($resourceGroupName, $exclusionList, $profileContext, $listRunning, $vm)

            $jobs = $jobs + $job
        }
    }

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
        }
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