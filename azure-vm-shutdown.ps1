#SCRIPT TO GET ALL AZURE-VM AND STOP
# 160330

#download azure powershell module
# http://azure.microsoft.com/en-us/documentation/articles/powershell-install-configure/#Install
# http://go.microsoft.com/fwlink/p/?linkid=320376&clcid=0x409
# Import-Module Azure

$logFile = "azure-vm-shutdown.log"
$subscriptionId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
Select-AzureSubscription -SubscriptionId $subscriptionId 


# to stop only specific cloud services. Remove entries to run on all services
$requestedServices = @()
$exclusionList = @() #@("rds-dc-1","ara-rds-1","ara-rds-2")

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    # see if we need to auth
    try
    {
        #get-azuresubscription
        $ret = Get-AzureService
    }
    catch 
    {
        Add-AzureAccount
    }

    if([string]::IsNullOrEmpty($requestedServices))
    {
        $services = (Get-AzureService).ServiceName
    }
    else
    {
        $services = $requestedServices
    }

    $jobs = @()

    foreach($service in $services)
    {
       
        $job = Start-Job -Name "vm" -ScriptBlock {
            param($ServiceName,$exclusionList)
            foreach($vm in get-azurevm -ServiceName $ServiceName)
            {
                write-host "$(get-date) checking vm $($vm.name):$($vm.PowerState)"
                if($vm.PowerState -ieq "Started")
                {
                    if($exclusionList.Contains($vm.name))
                    {
                        write-host "`t$(get-date) skipping vm $($vm.name)"
                    
                    }
                    else
                    {
                        write-host "`t$(get-date) stopping vm $($vm.name)"
                        Stop-Azurevm -Name $vm.Name -ServiceName $ServiceName -Force
                    }
                }
            }
        } -ArgumentList ($service,$exclusionList)

        $jobs = $jobs + $job
    }

    # Wait for all jobs to complete
    if($jobs -ne @())
    {
        while((get-job | where { $_.Name -eq "vm" }))
        {

            foreach($job in get-job)
            {
                Receive-Job -Job $job #| log-info

                if($job.State -ieq 'Completed')
                {
     
                    Remove-Job -Job $job
                }
            }
        }

        foreach($service in $services)
        {
            foreach($vm in get-azurevm -ServiceName $service)
            {
                log-info "$(get-date) final vm powerstate $($vm.name):$($vm.PowerState)"
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
    while(!$dataWritten -and $counter -lt 1000)
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