<#
    script to invoke powershell script with output to azure vm scaleset vms

    Invoke-AzureRmVmssVMRunCommand -ResourceGroupName {{resourceGroupName}} -VMScaleSetName{{scalesetName}} -InstanceId {{instanceId}} -ScriptPath c:\temp\test1.ps1 -Parameter @{'name' = 'patterns';'value' = "{{certthumb1}},{{certthumb2}}"} -Verbose -Debug -CommandId RunPowerShellScript
#>
param(
    [string]$resourceGroup,
    [string]$vmssName,
    [object]$instanceId,
    [string]$script, # script string content or file path to script
    [hashtable]$parameters = @{}, # hashtable @{"name" = "value";}
    [string]$jsonOutputFile
)

$ErrorActionPreference = "silentlycontinue"
$global:jobs = @{}
$global:joboutputs = @{}
$tempScript = ".\tempscript.ps1"

function main()
{
    $error.Clear()
    get-job | remove-job -Force

    get-command Invoke-AzureRmVmssVMRunCommand -ErrorAction SilentlyContinue
    
    if($error)
    {
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
            return
        }

        if($error)
        {
            return
        }
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
        out-file -InputObject ($global:joboutputs | ConvertTo-Json) -filepath $jsonOutputFile -force
    }

    write-host "finished. output stored in `$global:joboutputs"
    $global:joboutputs | fl *

    if ($error)
    {
        return 1
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
    while (get-job)
    {
        foreach ($job in get-job)
        {
            write-verbose ($job | fl * | out-string)

            if ($job.State -ine "Running")
            {
                write-host ($job | fl * | out-string)
                $global:joboutputs.Add(($global:jobs[$job.id]),($job.output | ConvertTo-Json))
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
            write-host
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
        if ($parameters)
        {
            write-host "Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
            -VMScaleSetName $vmssName `
            -InstanceId $instanceId `
            -ScriptPath $script `
            -Parameter $parameters `
            -CommandId RunPowerShellScript `
            -AsJob"
    
            $response = Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $instanceId `
                -ScriptPath $script `
                -Parameter $parameters `
                -CommandId RunPowerShellScript `
                -AsJob
        }
        else 
        {
            write-host "Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
            -VMScaleSetName $vmssName `
            -InstanceId $instanceId `
            -ScriptPath $script `
            -CommandId RunPowerShellScript `
            -AsJob"
    
            $response = Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $instanceId `
                -ScriptPath $script `
                -CommandId RunPowerShellScript `
                -AsJob
        }

        if($response)
        {
            $global:jobs.Add($response.Id,"$resourceGroup`:$vmssName`:$i")
            write-host ($response | fl * | out-string)
        }
        else
        {
            write-warning "no response from command!"
        }
    }
}

main
