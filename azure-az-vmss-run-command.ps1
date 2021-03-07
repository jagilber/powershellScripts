<#  
.SYNOPSIS  
    powershell script to invoke azure rm invoke-azvmssvmruncommand command with output on azure vm scaleset vms
    
.DESCRIPTION  
    powershell script to invoke azure rm invoke-azvmssvmruncommand command with output on azure vm scaleset vms
    Invoke-azVmssVMRunCommand -ResourceGroupName {{resourceGroupName}} -VMScaleSetName{{scalesetName}} -InstanceId {{instanceId}} -ScriptPath c:\temp\test1.ps1 -Parameter @{'name' = 'patterns';'value' = "{{certthumb1}},{{certthumb2}}"} -Verbose -Debug -CommandId $commandId
    Get-azVMRunCommandDocument -Location westus | select ID, OSType, Label

    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-vmss-run-command.ps1" -outFile "$pwd\azure-az-vmss-run-command.ps1"

.NOTES  
   File Name  : azure-az-vmss-run-command.ps1
   Author     : jagilber
   Version    : 191012
   History    : 

.EXAMPLE 
    .\azure-az-vmss-run-command.ps1 -script 'reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\CrashControl' -concurrent
    query memory dump settings concurrently

.EXAMPLE 
    .\azure-az-vmss-run-command.ps1 -script 'reg add HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\CrashControl /v CrashDumpEnabled /t REG_DWORD /d 1 /f'
    
    set memory dump settings to complete memory dump (requires reboot) on specified nodes

.EXAMPLE 
    .\azure-az-vmss-run-command.ps1 -script 'shutdown /r /t 0'

    restart specified nodes

.EXAMPLE
    .\azure-az-vmss-run-command.ps1 -script '& {
        if(((get-itemproperty HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl CrashDumpEnabled).CrashDumpEnabled) -ne 1) {
            write-host "set to complete dump. restarting"
            set-itemproperty HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl CrashDumpEnabled 1
            shutdown /d p:4:2 /c "enable complete dump" /r /t 1
        }
        else {
            write-host "already set to complete dump. returning"
        }
    }'

    set memory dump settings to complete memory dump and reboot nodes specified if required. do not run concurrently.

.EXAMPLE
    .\azure-az-vmss-run-command.ps1 -script '& {
        $file = "dotnet-runtime-3.0.0-win-x64.exe"
        $downloadUrl = "https://download.visualstudio.microsoft.com/download/pr/b3b81103-619a-48d8-ac1b-e03bbe153b7c/566b0f50872164abd1478a5b3ec38ffa/$file"
        invoke-webRequest $downloadUrl -outFile "$pwd/$file"
        # /install /repair /uninstall /layout /passive /quiet /norestart /log
        start-process -wait -filePath ".\dotnet-runtime-3.0.0-win-x64.exe" -argumentList "/norestart /quiet /install /log `"$pwd/$file.log`""
        type "$pwd/$file.log"
    }' -resourceGroup sfcluster -vmssName nt0 -instanceId 0-4 -concurrent

    install .net core 3.0 without restart concurrently to nodes 0-4

.EXAMPLE  
    .\azure-az-vmss-run-command.ps1 -script c:\temp\test.ps1

    prompt for resource group, vm scaleset name, and instance ids to run powershell script c:\temp\test.ps1 on

.EXAMPLE  
    .\azure-az-vmss-run-command.ps1 -script c:\temp\test.ps1 -resourceGroup testrg

    prompt for vm scaleset name, and instance ids to run powershell script c:\temp\test.ps1 on

.EXAMPLE  
    .\azure-az-vmss-run-command.ps1 -script c:\temp\test.ps1 -resourceGroup testrg -vmssname nt0

    prompt for instance ids to run powershell script c:\temp\test.ps1 on

.EXAMPLE  
    .\azure-az-vmss-run-command.ps1 -script c:\temp\test.ps1 -resourceGroup testrg -vmssname nt0 -instanceid 0

    run powershell script c:\temp\test.ps1 on instance id 0

.EXAMPLE  
    .\azure-az-vmss-run-command.ps1 -resourceGroup testrg -vmssname nt0 -instanceid 0

    run test powershell script on instance id 0

.EXAMPLE  
    .\azure-az-vmss-run-command.ps1 -listCommandIds

    list all possible commandIds available for command

.EXAMPLE  
    .\azure-az-vmss-run-command.ps1 -removeExtension
    
    remove the invoke run command extension that is required for running commands.
    it is *not* required to remove extension

.PARAMETER resourceGroup
    name of resource group containing vm scale set. if not provided, script prompt for input.

.PARAMETER vmssName
    name of vm scale set. if not provided, script prompt for input.

.PARAMETER instanceId
    string array of instance id(s). if not provided, script prompt for input. 
    examples: 0 or 0-2 or 0,1,2

.PARAMETER script
    path and file name to script to invoke on vm scale set nodes

.PARAMETER parameters
    hashtable of script arguments in format of @{"name" = "value"}
    example: @{"adminUserName" = "cloudadmin"}

.PARAMETER jsonOutputFile
    path and file name of json output file to populate with results.

.PARAMETER commandId
    optional commandId to invoke other than the default of RunCommand. use -listCommandIds argument for list of commandIds available.

.PARAMETER removeExtension
    switch to invoke run command, an extension is dynamically installed. this may or may not be already present and causes no harm.
    after completing all commands, the extension can be removed with -removeExtension switch

.PARAMETER listCommandIds
    switch to list optional commandIds and return

.PARAMETER force
    switch to force invocation of command on vm scaleset node regardless of provisioningstate. Any state other than 'successful' may fail.

.PARAMETER concurrent
    switch to run command against multiple nodes concurrently. default is single node at a time.
    WARNING: running jobs concurrently on scalesets such as service fabric where there are minimum node requirements can cause an outage if the node is restarted.

.LINK
    https://github.com/jagilber/powershellScripts/blob/master/azure-az-vmss-run-command.ps1
#>  

[CmdletBinding()]
param(
    [string]$resourceGroup,
    [string]$vmssName,
    [string]$instanceId,
    [string]$script, # script string content or file path to script
    [hashtable]$parameters = @{ }, # hashtable @{"name" = "value";}
    [string]$jsonOutputFile,
    [string]$commandId = "RunPowerShellScript",
    [switch]$removeExtension,
    [switch]$listCommandIds,
    [string]$location = "westus",
    [switch]$force,
    [switch]$concurrent
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = "silentlycontinue"
$global:jobs = @{ }
$global:joboutputs = @{ }
$tempScript = ".\tempscript.ps1"
$removeCommandId = "RemoveRunCommandWindowsExtension"
$global:startTime = get-date
$global:success = 0
$global:fail = 0
$global:extensionInstalled = 0
$global:extensionNotInstalled = 0
$global:pscommand = $commandId -ieq "RunPowerShellScript"

function main() {
    $error.Clear()
    get-job | remove-job -Force

    if (!(check-module)) {
        return
    }

    if (!(Get-azResourceGroup)) {
        connect-azaccount

        if ($error) {
            return
        }
    }

    if ($concurrent) {
        write-warning "running jobs concurrently on scalesets with minimum node requirements such as service fabric, can cause an outage if the node is restarted from command being run!"
        write-warning "ctrl-c now if this is incorrect"
    }

    if ($listCommandIds) {
        Get-azVMRunCommandDocument -Location $location | Select-Object ID, OSType, Label
        return
    }

    if ($pscommand -and !$script) {
        Write-Warning "using test script. use -script and -parameters arguments to supply script and parameters"
        $script = node-psTestScript
    }

    if (!$resourceGroup) {
        $nodePrompt = $true
        $count = 1
        $number = 0
        $resourceGroups = Get-azResourceGroup
        
        foreach ($rg in @($resourceGroups)) {
            write-host "$($count). $($rg.ResourceGroupName)"
            $count++
        }
        
        $number = [convert]::ToInt32((read-host "enter number of the resource group to query or ctrl-c to exit:"))

        if ($number -le $count) {
            $resourceGroup = $resourceGroups[$number - 1].ResourceGroupName
            write-host $resourceGroup
        }
    }

    $scalesets = Get-azVmss -ResourceGroupName $resourceGroup

    if (!$vmssName) {
        $nodePrompt = $true
        $number = 0
        $count = 1
        
        foreach ($scaleset in @($scalesets)) {
            write-host "$($count). $($scaleset.Name)"
            $count++
        }
        
        $number = [convert]::ToInt32((read-host "enter number of the scaleset to query or ctrl-c to exit:"))

        if ($number -le $count) {
            $vmssName = $scalesets[$number - 1].Name
            write-host $vmssName
        }
    }

    $scaleset = get-azvmss -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName
    $maxInstanceId = $scaleset.Sku.Capacity
    write-host "$vmssName capacity: $maxInstanceId (0 - $($maxInstanceId - 1))"

    if (!$instanceId) {
        $instanceIds = generate-list "0-$($maxInstanceId - 1)"

        if ($nodePrompt) {
            $numbers = read-host "enter 0 based, comma separated list of number(s), or number range of the nodes to invoke script:"

            if ($numbers) {
                $instanceIds = generate-list $numbers
            }
        }
    }
    else {
        $instanceIds = generate-list $instanceId
    }

    write-host $instanceIds

    write-host "checking provisioning states"
    $instances = @(Get-azVmssVM -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName -InstanceView)
    write-host "$($instances.InstanceView.Statuses | fl * | out-string)"

    foreach ($instance in $instances) {
        if (($instance.InstanceView.Statuses.DisplayStatus -inotcontains "provisioning succeeded" `
                    -or $instance.InstanceView.Statuses.DisplayStatus -inotcontains "vm running") `
                -and !$force) {
            Write-Warning "not all nodes are in 'succeeded' provisioning state or 'vm running' so command may fail. returning. use -force to attempt command regardless of provisioning state."
            return
        }
    }

    if ($pscommand -and !(test-path $script)) {
        out-file -InputObject $script -filepath $tempscript -Force
        $script = $tempScript
    }

    if ($removeExtension) {
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

    if ((test-path $tempScript)) {
        remove-item $tempScript -Force
    }

    if ($jsonOutputFile) {
        write-host "saving json to file $jsonOutputFile"
        #out-file -InputObject ($global:joboutputs | ConvertTo-Json) -filepath $jsonOutputFile -force
        ($global:joboutputs | convertto-json).replace("\r\n", "").replace("\`"", "`"").replace("`"{", "{").replace("}`"", "}") | out-file $jsonOutputFile -Force
    }

    $global:joboutputs | fl *
    write-host "finished. output stored in `$global:joboutputs"
    write-host "total fail:$($global:fail) total success:$($global:success)"
    write-host "total time elapsed:$(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes"
    write-host "optionally use -removeExtension to remove runcommand extension or reset."

    if ($error) {
        return 1
    }
}

function check-module() {
    $error.clear()
    get-command Invoke-azVmssVMRunCommand -ErrorAction SilentlyContinue
    
    if ($error) {
        $error.clear()
        write-warning "Invoke-azVmssVMRunCommand not installed."

        if ((read-host "is it ok to install latest az?[y|n]") -imatch "y") {
            $error.clear()
            install-module az.accounts
            install-module az.resources
            install-module az.compute

            import-module az.accounts
            import-module az.resources
            import-module az.compute
        }
        else {
            return $false
        }

        if ($error) {
            return $false
        }
    }

    return $true
}

function generate-list([string]$strList) {
    $list = [collections.arraylist]@()

    foreach ($split in $strList.Replace(" ", "").Split(",")) {
        if ($split.contains("-")) {
            [int]$lbound = [int][regex]::match($split, ".+?-").value.trimend("-")
            [int]$ubound = [int][regex]::match($split, "-.+").value.trimstart("-")

            while ($lbound -le $ubound) {
                [void]$list.add($lbound)
                $lbound++
            }
        }
        else {
            [void]$list.add($split)
        }
    }

    return $list
}

function monitor-jobs() {
    $originalJobsCount = (get-job).count
    $minCount = 1
    $count = 0

    while (get-job) {
        foreach ($job in get-job) {
            write-verbose ($job | fl * | out-string)

            if ($job.state -ine "running") {
                write-host ($job | fl * | out-string)
                if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job | ConvertTo-Json))
                    $global:fail++
                }
                else {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job.output | ConvertTo-Json))
                    $global:success++
                }
                write-host ($job.output | ConvertTo-Json)
                $job.output
                Remove-Job -Id $job.Id -Force  
            }
            else {
                $jobInfo = Receive-Job -Job $job
                
                if ($jobInfo) {
                    write-host ($jobInfo | fl * | out-string)
                }
            }
        }

        if ($count -ge 60) {
            write-host $minCount
            $minCount++
            $count = 0
        }

        write-host "." -NoNewline    
        $instances = Get-azVmssVM -ResourceGroupName $resourceGroup -vmscalesetname $vmssName -InstanceView
        write-verbose "$($instances | convertto-json -WarningAction SilentlyContinue)"

        $currentJobsCount = (get-job).count
        $activity = "$($commandId) $($originalJobsCount - $currentJobsCount) / $($originalJobsCount) vm jobs completed:"
        $status = "extension installed:$($global:extensionInstalled)    not installed:$($global:extensionNotInstalled)    fail results:$($global:fail)" `
            + "    success results:$($global:success)    time elapsed:$(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes"
        $percentComplete = ((($originalJobsCount - $currentJobsCount) / $originalJobsCount) * 100)

        Write-Progress -Activity $activity -Status $status -PercentComplete $percentComplete
        Start-Sleep -Seconds 1
        $count++ 
    }
}

function node-psTestScript() {
    return "# $(get-date)
        wmic qfe;
        ipconfig;
        hostname;"
}

function run-vmssPsCommand ($resourceGroup, $vmssName, $instanceIds, [string]$script, $parameters) {
    write-host "first time only can take up to 45 minutes if the run command extension is not installed. 
        subsequent executions take between a 2 and 30 minutes..." -foregroundcolor yellow

    foreach ($instanceId in $instanceIds) {
        $instance = get-azvmssvm -ResourceGroupName $resourceGroup -VMScaleSetName $vmssName -InstanceId $instanceId -InstanceView
        write-host "instance id: $($instanceId)`r`n$($instance.VmAgent.ExtensionHandlers | convertto-json)" -ForegroundColor Cyan
        
        if (!($instance.VmAgent.ExtensionHandlers.Type -imatch "RunCommandWindows")) {
            Write-Warning "run command extension not installed."
            $global:extensionNotInstalled++

            if ($removeExtension) {
                continue
            }

            Write-Warning "this install extension automatically which take additional time."
        }
        else {
            $global:extensionInstalled++
        }

        if ($removeExtension) {
            $script = $null
            $parameters = $null

            write-host "Invoke-azVmssVMRunCommand -ResourceGroupName $resourceGroup `
            -VMScaleSetName $vmssName `
            -InstanceId $instanceId `
            -CommandId $commandId `
            -AsJob"
    
            $response = Invoke-azVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $instanceId `
                -CommandId $commandId `
                -AsJob
        }
        elseif($pscommand) {
            if ($parameters.Count -gt 0) {
                write-host "Invoke-azVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $instanceId `
                -ScriptPath $script `
                -Parameter $parameters `
                -CommandId $commandId `
                -AsJob"
        
                $response = Invoke-azVmssVMRunCommand -ResourceGroupName $resourceGroup `
                    -VMScaleSetName $vmssName `
                    -InstanceId $instanceId `
                    -ScriptPath $script `
                    -Parameter $parameters `
                    -CommandId $commandId `
                    -AsJob
            }
            else {
                write-host "Invoke-azVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $instanceId `
                -ScriptPath $script `
                -CommandId $commandId `
                -AsJob"
        
                $response = Invoke-azVmssVMRunCommand -ResourceGroupName $resourceGroup `
                    -VMScaleSetName $vmssName `
                    -InstanceId $instanceId `
                    -ScriptPath $script `
                    -CommandId $commandId `
                    -AsJob
            }
        }
        elseif ($parameters.Count -gt 0) {
            write-host "Invoke-azVmssVMRunCommand -ResourceGroupName $resourceGroup `
            -VMScaleSetName $vmssName `
            -InstanceId $instanceId `
            -Parameter $parameters `
            -CommandId $commandId `
            -AsJob"
    
            $response = Invoke-azVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $instanceId `
                -Parameter $parameters `
                -CommandId $commandId `
                -AsJob
        }
        else {
            write-host "Invoke-azVmssVMRunCommand -ResourceGroupName $resourceGroup `
            -VMScaleSetName $vmssName `
            -InstanceId $instanceId `
            -CommandId $commandId `
            -AsJob"
    
            $response = Invoke-azVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $instanceId `
                -CommandId $commandId `
                -AsJob
        }

        if (!$concurrent) {
            monitor-jobs
        }

        if ($response) {
            $global:jobs.Add($response.Id, "$resourceGroup`:$vmssName`:$instanceId")
            write-host ($response | fl * | out-string)
        }
        else {
            write-warning "no response from command!"
            $global:fail++
        }
    }
}

main

