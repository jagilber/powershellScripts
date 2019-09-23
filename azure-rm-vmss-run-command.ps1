<#  
.SYNOPSIS  
    powershell script to invoke azure rm invoke-azurermvmssvmruncommand command with output on azure vm scaleset vms
    
.DESCRIPTION  
    powershell script to invoke azure rm invoke-azurermvmssvmruncommand command with output on azure vm scaleset vms
    Invoke-AzureRmVmssVMRunCommand -ResourceGroupName {{resourceGroupName}} -VMScaleSetName{{scalesetName}} -InstanceId {{instanceId}} -ScriptPath c:\temp\test1.ps1 -Parameter @{'name' = 'patterns';'value' = "{{certthumb1}},{{certthumb2}}"} -Verbose -Debug -CommandId $commandId
    Get-AzureRmVMRunCommandDocument -Location westus | select ID, OSType, Label

.NOTES  
   File Name  : azure-rm-vmss-run-command.ps1
   Author     : jagilber
   Version    : 190403
   History    : 

.EXAMPLE  
    .\azure-rm-vmss-run-command.ps1 -script c:\temp\test.ps1
    will prompt for resource group, vm scaleset name, and instance ids to run powershell script c:\temp\test.ps1 on

.EXAMPLE  
    .\azure-rm-vmss-run-command.ps1 -script c:\temp\test.ps1 -resourceGroup testrg
    will prompt for vm scaleset name, and instance ids to run powershell script c:\temp\test.ps1 on

.EXAMPLE  
    .\azure-rm-vmss-run-command.ps1 -script c:\temp\test.ps1 -resourceGroup testrg -vmssname nt0
    will prompt for instance ids to run powershell script c:\temp\test.ps1 on

.EXAMPLE  
    .\azure-rm-vmss-run-command.ps1 -script c:\temp\test.ps1 -resourceGroup testrg -vmssname nt0 -instanceid 0
    will run powershell script c:\temp\test.ps1 on instance id 0

.EXAMPLE  
    .\azure-rm-vmss-run-command.ps1 -resourceGroup testrg -vmssname nt0 -instanceid 0
    will run test powershell script on instance id 0

.EXAMPLE  
    .\azure-rm-vmss-run-command.ps1 -listCommandIds
    will list all possible commandIds available for command

.EXAMPLE  
    .\azure-rm-vmss-run-command.ps1 -removeExtension
    will remove the invoke run command extension that is required for running commands.
    it is *not* required to remove extension

.PARAMETER resourceGroup
    name of reource group containing vm scale set. if not provided, script will prompt for input.

.PARAMETER vmssName
    name of vm scale set. if not provided, script will prompt for input.

.PARAMETER instanceId
    string array of instance id(s). if not provided, script will prompt for input. 
    examples: 0 or 0-2 or 0,1,2

.PARAMETER script
    path and file name to script to invoke on vm scale set nodes

.PARAMETER parameters
    hashtable of script arguments in format of @{"name" = "value"}
    exmaple: @{"adminUserName" = "cloudadmin"}

.PARAMETER jsonOutputFile
    path and file name of json output file to populate with results.

.PARAMETER commandId
    optional commandId to invoke other than the default of RunCommand. use -listCommandIds argument for list of commandIds available.

.PARAMETER removeExtension
    switch to invoke run command, an extension is dynamically installed. this may or may not be already present and causes no harm.
    after completing all commands, the extension can be removed with -removeExtension switch

.PARAMETER listCommandIds
    swtich to list optional commandIds and return

.PARAMETER force
    switch to force invocation of command on vm scaleset node regardless of provisioningstate. Any state other than 'successful' may fail.

.LINK
    https://github.com/jagilber/powershellScripts/blob/master/azure-rm-vmss-run-command.ps1
#>  

[CmdletBinding()]
param(
    [string]$resourceGroup,
    [string]$vmssName,
    [string]$instanceId,
    [string]$script, # script string content or file path to script
    [hashtable]$parameters = @{}, # hashtable @{"name" = "value";}
    [string]$jsonOutputFile,
    [string]$commandId = "RunPowerShellScript",
    [switch]$removeExtension,
    [switch]$listCommandIds,
    [switch]$force
)

$ErrorActionPreference = "silentlycontinue"
$global:jobs = @{}
$global:joboutputs = @{}
$tempScript = ".\tempscript.ps1"
$removeCommandId = "RemoveRunCommandWindowsExtension"
$global:startTime = get-date
$global:success = 0
$global:fail = 0
$global:extensionInstalled = 0
$global:extensionNotInstalled = 0

function main()
{
    $error.Clear()
    get-job | remove-job -Force

    if (!(check-module))
    {
        return
    }

    if (!(Get-AzureRmResourceGroup))
    {
        connect-azurermaccount

        if ($error)
        {
            return
        }
    }

    if($listCommandIds)
    {
        Get-AzureRmVMRunCommandDocument -Location westus | Select-Object ID, OSType, Label
        return
    }

    if (!$script)
    {
        Write-Warning "using test script. use -script and -parameters arguments to supply script and parameters"
        $script = node-psTestScript
    }

    if (!$resourceGroup -or !$vmssName)
    {
        $nodePrompt = $true
        $count = 1
        $resourceGroups = Get-AzureRmResourceGroup
        
        foreach ($rg in $resourceGroups)
        {
            write-host "$($count). $($rg.ResourceGroupName)"
            $count++
        }
        
        if (($number = read-host "enter number of the resource group to query or ctrl-c to exit:") -le $count)
        {
            $resourceGroup = $resourceGroups[$number - 1].ResourceGroupName
            write-host $resourceGroup
        }

        $count = 1
        $scalesets = Get-AzureRmVmss -ResourceGroupName $resourceGroup
        
        foreach ($scaleset in $scalesets)
        {
            write-host "$($count). $($scaleset.Name)"
            $count++
        }
        
        if (($number = read-host "enter number of the cluster to query or ctrl-c to exit:") -le $count)
        {
            $vmssName = $scalesets[$number - 1].Name
            write-host $vmssName
        }
    }

    $scaleset = get-azurermvmss -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName
    $maxInstanceId = $scaleset.Sku.Capacity
    write-host "$vmssName capacity: $maxInstanceId (0 - $($maxInstanceId - 1))"

    if (!$instanceId)
    {
        $instanceIds = generate-list "0-$($maxInstanceId - 1)"

        if ($nodePrompt)
        {
            $numbers = read-host "enter 0 based, comma separated list of number(s), or number range of the nodes to invoke script:"

            if ($numbers)
            {
                $instanceIds = generate-list $numbers
            }
        }
    }
    else
    {
        $instanceIds = generate-list $instanceId
    }

    write-host $instanceIds

    write-host "checking provisioning states"
    $instances = Get-AzureRmVmssVM -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName -InstanceView
    write-host "$($instances | out-string)"

    if($instances.ProvisioningState -inotmatch "succeeded" -and !$force)
    {
        Write-Warning "not all nodes are in 'succeeded' provisioning state so command may fail. returning. use -force to attempt command regardless of provisioning state."
        return
    }

    if (!(test-path $script))
    {
        out-file -InputObject $script -filepath $tempscript -Force
        $script = $tempScript
    }

    if ($removeExtension)
    {
        $commandId = $removeCommandId
    }

    $result = run-vmssPsCommand -resourceGroup $resourceGroup `
        -vmssName $vmssName `
        -instanceIds $instanceIds `
        -script $script `
        -parameters $parameters

    write-host $result
    $count = 0

    monitor-jobs

    if ((test-path $tempScript))
    {
        remove-item $tempScript -Force
    }

    if ($jsonOutputFile)
    {
        write-host "saving json to file $jsonOutputFile"
        #out-file -InputObject ($global:joboutputs | ConvertTo-Json) -filepath $jsonOutputFile -force
        ($global:joboutputs | convertto-json).replace("\r\n", "").replace("\`"", "`"").replace("`"{", "{").replace("}`"", "}") | out-file $jsonOutputFile -Force
    }

    $global:joboutputs | fl *
    write-host "finished. output stored in `$global:joboutputs"
    write-host "total fail:$($global:fail) total success:$($global:success)"

    if ($error)
    {
        return 1
    }
}

function check-module()
{
    get-command Invoke-AzureRmVmssVMRunCommand -ErrorAction SilentlyContinue
    
    if ($error)
    {
        $error.clear()
        write-warning "Invoke-AzureRmVmssVMRunCommand not installed."

        if ((read-host "is it ok to install latest azurerm?[y|n]") -imatch "y")
        {
            $error.clear()
            remove-module azurerm
            install-module azurerm -AllowClobber -force
            import-module azurerm
        }
        else
        {
            return $false
        }

        if ($error)
        {
            return $false
        }
    }
}

function generate-list([string]$strList)
{
    $list = [collections.arraylist]@()

    foreach ($split in $strList.Replace(" ", "").Split(","))
    {
        if ($split.contains("-"))
        {
            [int]$lbound = [int][regex]::match($split, ".+?-").value.trimend("-")
            [int]$ubound = [int][regex]::match($split, "-.+").value.trimstart("-")

            while ($lbound -le $ubound)
            {
                [void]$list.add($lbound)
                $lbound++
            }
        }
        else
        {
            [void]$list.add($split)
        }
    }

    return $list
}

function monitor-jobs()
{
    write-host "first time only can take up to 45 minutes if the run command extension is not installed. 
        subsequent executions take between a 1 and 30 minutes..." -foregroundcolor yellow
    write-host "use -removeExtension to remove extension or reset"
    $originalJobsCount = (get-job).count
    $minCount = 1
    $count = 0

    while (get-job)
    {
        foreach ($job in get-job)
        {
            write-verbose ($job | fl * | out-string)

            if ($job.state -ine "running")
            {
                write-host ($job | fl * | out-string)
                if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail")
                {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job | ConvertTo-Json))
                    $global:fail++
                }
                else 
                {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job.output | ConvertTo-Json))
                    $global:success++
                }
                write-host ($job.output | ConvertTo-Json)
                $job.output
                Remove-Job -Id $job.Id -Force  
            }
            else
            {
                $jobInfo = Receive-Job -Job $job
                
                if ($jobInfo)
                {
                    write-host ($jobInfo | fl * | out-string)
                }
            }
        }

        if ($count -ge 60)
        {
            write-host $minCount
            $minCount++
            $count = 0
        }

        write-host "." -NoNewline    
        $instances = Get-AzureRmVmssVM -ResourceGroupName $resourceGroup -vmscalesetname $vmssName -InstanceView
        write-verbose "$($instances | convertto-json)"

        $currentJobsCount = (get-job).count
        $activity = "$($commandId) $($originalJobsCount - $currentJobsCount) / $($originalJobsCount) vm jobs completed. (use -removeExtension to remove extension):"
        $status = "extension installed:$($global:extensionInstalled)    not installed:$($global:extensionNotInstalled)    fail results:$($global:fail)" `
            + "    success results:$($global:success)    time elapsed:$(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes"
        $percentComplete = ((($originalJobsCount - $currentJobsCount) / $originalJobsCount) * 100)

        Write-Progress -Activity $activity -Status $status -PercentComplete $percentComplete
        Start-Sleep -Seconds 1
        $count++ 
    }
}

function node-psTestScript()
{
    return "# $(get-date)
        wmic qfe;
        ipconfig;
        hostname;"
}

function run-vmssPsCommand ($resourceGroup, $vmssName, $instanceIds, [string]$script, $parameters)
{
    foreach ($instanceId in $instanceIds)
    {
        $instance = get-azurermvmssvm -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName -InstanceId $instanceId -InstanceView
        write-host "instance id: $($instanceId)`r`n$($instance.VmAgent.ExtensionHandlers | convertto-json)" -ForegroundColor Cyan
        
        if (!($instance.VmAgent.ExtensionHandlers.Type -imatch "RunCommandWindows"))
        {
            Write-Warning "run command extension not installed."
            $global:extensionNotInstalled++

            if ($removeExtension)
            {
                continue
            }

            Write-Warning "this will install extension automatically which will take additional time."
        }
        else 
        {
            $global:extensionInstalled++
        }

        if ($removeExtension)
        {
            $script = $null
            $parameters = $null

            write-host "Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
            -VMScaleSetName $vmssName `
            -InstanceId $instanceId `
            -CommandId $commandId `
            -AsJob"
    
            $response = Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $instanceId `
                -CommandId $commandId `
                -AsJob
        }
        elseif ($parameters)
        {
            write-host "Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
            -VMScaleSetName $vmssName `
            -InstanceId $instanceId `
            -ScriptPath $script `
            -Parameter $parameters `
            -CommandId $commandId `
            -AsJob"
    
            $response = Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $instanceId `
                -ScriptPath $script `
                -Parameter $parameters `
                -CommandId $commandId `
                -AsJob
        }
        else 
        {
            write-host "Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
            -VMScaleSetName $vmssName `
            -InstanceId $instanceId `
            -ScriptPath $script `
            -CommandId $commandId `
            -AsJob"
    
            $response = Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $instanceId `
                -ScriptPath $script `
                -CommandId $commandId `
                -AsJob
        }

        if ($response)
        {
            $global:jobs.Add($response.Id, "$resourceGroup`:$vmssName`:$instanceId")
            write-host ($response | fl * | out-string)
        }
        else
        {
            write-warning "no response from command!"
            $global:fail++
        }
    }
}

main
