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
    log-info "starting script"
    # see if we need to auth
    try
    {
        $ret = Get-AzureRmTenant
    }
    catch 
    {
        try
        {
            Import-AzureRmContext -Path $profileContext
            $ret = Get-AzureRmTenant
        }
        catch
        {
            Login-AzureRmAccount
        }
    }

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
        foreach ($vm in (get-azureRmvm -ResourceGroupName $resourceGroupName | select-object Name))
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