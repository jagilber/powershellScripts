<#
    script to invoke powershell script with output on azure vm scaleset vms
    Invoke-AzureRmVmssVMRunCommand -ResourceGroupName {{resourceGroupName}} -VMScaleSetName{{scalesetName}} -InstanceId {{instanceId}} -ScriptPath c:\temp\test1.ps1 -Parameter @{'name' = 'patterns';'value' = "{{certthumb1}},{{certthumb2}}"} -Verbose -Debug -CommandId $commandId
    Get-AzureRmVMRunCommandDocument -Location westus | select ID, OSType, Label

    .\azure-rm-vmss-run-command.ps1
    .\azure-rm-vmss-run-command.ps1 -resourcegroup testrg
    .\azure-rm-vmss-run-command.ps1 -resourcegroup testrg -vmssname nt0
    .\azure-rm-vmss-run-command.ps1 -resourcegroup testrg -vmssname nt0 -instanceId 0
    .\azure-rm-vmss-run-command.ps1 -resourcegroup testrg -vmssname nt0 -instanceId 0-3
    .\azure-rm-vmss-run-command.ps1 -resourcegroup testrg -vmssname nt0 -instanceId "0-3,5"
    .\azure-rm-vmss-run-command.ps1 -resourcegroup testrg -vmssname nt0 -script "ipconfig"
    .\azure-rm-vmss-run-command.ps1 -resourcegroup testrg -vmssname nt0 -script "ipconfig;hostname"
    .\azure-rm-vmss-run-command.ps1 -resourcegroup testrg -vmssname nt0 -script c:\temp\somescript.ps1
    
    .\azure-rm-vmss-run-command.ps1 -resourcegroup testrg -vmssname nt0 -removeExtension
    .\azure-rm-vmss-run-command.ps1 -removeExtension
#>
param(
    [string]$resourceGroup,
    [string]$vmssName,
    [string]$instanceId,
    [string]$script, # script string content or file path to script
    [hashtable]$parameters = @{}, # hashtable @{"name" = "value";}
    [string]$jsonOutputFile,
    [string]$commandId = "RunPowerShellScript",
    [switch]$removeExtension
)

$ErrorActionPreference = "silentlycontinue"
$global:jobs = @{}
$global:joboutputs = @{}
$tempScript = ".\tempscript.ps1"
$removeCommandId = "RemoveRunCommandWindowsExtension"

function main()
{
    $error.Clear()
    get-job | remove-job -Force

    if(!(check-module))
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

        if($nodePrompt)
        {
            $numbers = read-host "enter 0 based, comma separated list of number(s), or number range of the nodes to invoke script:"

            if($numbers)
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

    if (!(test-path $script))
    {
        out-file -InputObject $script -filepath $tempscript -Force
        $script = $tempScript
    }

    $result = run-vmssPsCommand -resourceGroup $resourceGroup `
        -vmssName $vmssName `
        -instanceIds $instanceIds `
        -script $script `
        -parameters $parameters

    write-host $result
    $count = 0

    monitor-jobs

    if((test-path $tempScript))
    {
        remove-item $tempScript -Force
    }

    if($jsonOutputFile)
    {
        write-host "saving json to file $jsonOutputFile"
        #out-file -InputObject ($global:joboutputs | ConvertTo-Json) -filepath $jsonOutputFile -force
        ($global:joboutputs | convertto-json).replace("\r\n","").replace("\`"","`"").replace("`"{","{").replace("}`"","}") | out-file $jsonOutputFile -Force
    }

    write-host "finished. output stored in `$global:joboutputs"
    $global:joboutputs | fl *

    if ($error)
    {
        return 1
    }
}

function check-module()
{
    get-command Invoke-AzureRmVmssVMRunCommand -ErrorAction SilentlyContinue
    
    if($error)
    {
        $error.clear()
        write-warning "Invoke-AzureRmVmssVMRunCommand not installed."

        if((read-host "is it ok to install latest azurerm?[y|n]") -imatch "y")
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

        if($error)
        {
            return $false
        }
    }
}

function generate-list([string]$strList)
{
    $list = [collections.arraylist]@()

    foreach($split in $strList.Replace(" ","").Split(","))
    {
        if($split.contains("-"))
        {
            [int]$lbound = [int][regex]::match($split,".+?-").value.trimend("-")
            [int]$ubound = [int][regex]::match($split,"-.+").value.trimstart("-")

            while($lbound -le $ubound)
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
        subsequent executions take around a minute but can take up to 30..." -foregroundcolor yellow
    write-host "use -removeExtension to remove extension or reset"

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
                [void]$global:joboutputs.add(($global:jobs[$job.id]),($job.output | ConvertTo-Json))
                write-host ($job.output | ConvertTo-Json)
                $job.output
                Remove-Job -Id $job.Id -Force  
            }
            else
            {
                $jobInfo = Receive-Job -Job $job
                
                if($jobInfo)
                {
                    write-host ($jobInfo | fl * | out-string)
                }
            }
        }

        if($count -ge 60)
        {
            write-host $minCount
            $minCount++
            $count = 0
        }

        write-host "." -NoNewline    
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
        
        if(!($instance.VmAgent.ExtensionHandlers.Type -imatch "RunCommandWindows"))
        {
            Write-Warning "run command extension not installed. this will install extension automatically but will be slow..."
        }

        if($removeExtension)
        {
            $commandId = $removeCommandId
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

        if($response)
        {
            $global:jobs.Add($response.Id,"$resourceGroup`:$vmssName`:$instanceId")
            write-host ($response | fl * | out-string)
        }
        else
        {
            write-warning "no response from command!"
        }
    }
}

main
