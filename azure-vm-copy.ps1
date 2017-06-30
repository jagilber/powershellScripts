#SCRIPT TO GET ALL AZURE-VM AND COPY
# 150913

#download azure powershell module
# http://azure.microsoft.com/en-us/documentation/articles/powershell-install-configure/#Install
# http://go.microsoft.com/fwlink/p/?linkid=320376&clcid=0x409
# Import-Module Azure
# http://blogs.technet.com/b/heyscriptingguy/archive/2014/01/24/create-backups-of-virtual-machines-in-windows-azure-by-using-powershell.aspx

$logFile = "azure-vm-copy.log"
$subscriptionId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
Select-AzureSubscription -SubscriptionId $subscriptionId 


# to stop only specific cloud services. Remove entries to run on all services
$requestedServices = @()
$inclusionList = @()


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
        log-info "checking service $($service)"
       
        $job = Start-Job -ScriptBlock {
            param($ServiceName,$inclusionList)
            foreach($vm in get-azurevm -ServiceName $ServiceName)
            {
                $isStarted = $false
                write-host "$(get-date) checking vm $($vm.name):$($vm.PowerState)"
                if($inclusionList.Length -gt 0 -and !$inclusionList.Contains($vm.name))
                {
                   write-host "`t$(get-date) skipping vm $($vm.name)"                       
                   continue
                }

                if($vm.InstanceStatus -ine "StoppedVM")
                {
                    if($vm.PowerState -ine "Started" -and $vm.PowerState -ine "Starting")
                    {
                        write-host "`t$(get-date) starting vm $($vm.name)"
                        Start-Azurevm -Name $vm.Name -ServiceName $ServiceName
                    }
                    else
                    {
                        $isStarted = $true
                    }

                    # stop vm but leave it provisioned
                    Stop-AzureVM -Name $vm.Name -ServiceName $ServiceName -StayProvisioned -Force
                }

                # get OS Disk
                $vmOSDisks = @($vm | Get-AzureOSDisk)
                $vmOSDisks += @($vm | Get-AzureDataDisk)

                # set storage account
                # not working
                #$storageAccountName = $vmOSDisks[0].MediaLink.Host.Split('.')[0]
                #Get-AzureSubscription | Set-AzureSubscription -CurrentStorageAccountName $storageAccountName

                $backupContainerName = "backup-$([DateTime]::Now.ToString(`"yyyy-MM-dd`"))"

                if(!(Get-AzureStorageContainer -Name $backupContainerName -ErrorAction SilentlyContinue))
                {
                    New-AzureStorageContainer -Name $backupContainerName -Permission Off
                }

                foreach($vmOSDisk in $vmOSDisks)
                {
                    write-host $vmOSDisk.DiskName

                    $vmOSBlobName = $vmOSDisk.MediaLink.Segments[-1]
                    $vmOSContainerName = $vmOSDisk.MediaLink.Segments[-2].Split('/')[0]

                    Start-AzureStorageBlobCopy -SrcContainer $vmOSContainerName -SrcBlob $vmOSBlobName -DestContainer $backupContainerName -Force

                    # wait for async call to complete

                    $state = Get-AzureStorageBlobCopyState -Container $backupContainerName -Blob $vmOSBlobName -WaitForComplete
                    write-host $state
                }

                if($isStarted)
                {
                    write-host "restarting vm $($vm.Name)"
                    Start-AzureVM -Name $vm.name -ServiceName $ServiceName
                }
                else
                {
                    Stop-AzureVM -Name $vm.Name -ServiceName $ServiceName -Force
                }
            }

        } -ArgumentList ($service,$inclusionList)

        $jobs = $jobs + $job
    }

    # Wait for all jobs to complete
    if($jobs -ne @())
    {
        while(get-job)
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