<#
    script to invoke powershell script with output to azure vm scaleset vms

    Invoke-AzureRmVmssVMRunCommand -ResourceGroupName {{resourceGroupName}} -VMScaleSetName{{scalesetName}} -InstanceId {{instanceId}} -ScriptPath c:\temp\test1.ps1 -Parameter @{'name' = 'patterns';'value' = "{{certthumb1}},{{certthumb2}}"} -Verbose -Debug -CommandId RunPowerShellScript
#>
param(
    [string]$resourceGroup,
    [string]$vmssName,
    [int]$instanceId = -1,
    [string]$script, # script string content or file path to script
    [hashtable]$parameters = @{} # hashtable @{"name" = "value";}
)

$ErrorActionPreference = "silentlycontinue"

function main()
{
    get-job | remove-job -Force

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
        $script = (node-psTestNetScript)
        [void]$parameters.Add(@{"remoteHost" = "time.windows.com"})
        [void]$parameters.Add(@{"port" = "80"})
    }

    if (!$resourceGroup -or !$vmssName)
    {
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

    if ($instanceId -lt 0)
    {
        $scaleset = get-azurermvmss -ResourceGroupName $resourceGroup -VMScaleSetName $vmss
        $maxInstanceId = $scaleset.Sku.Capacity
        $instanceId = 0
    }
    else
    {
        $maxInstanceId = $instanceId + 1
    }

    $result = run-vmssPsCommand -resourceGroup $resourceGroup -vmssName $vmssName -instanceId $instanceId -maxInstanceId $maxInstanceId -script $script -parameters $parameters
    write-host $result
    $count = 0
    $global:jobs = [collections.arraylist]@()

    while (get-job)
    {
        foreach ($job in get-job)
        {
            if ($job.State -ine "Running")
            {
                write-host ($job | fl * | out-string)
                $global:jobs.Add(($job.output | ConvertTo-Json))
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

        if($count -gt 80)
        {
            write-host "."
            $count = 0    
        }
        else 
        {
            write-host "." -NoNewline    
        }
        
        Start-Sleep -Seconds 1
 
    }

    if ($error)
    {
        return 1
    }

    write-host "finished. output stored in `$global:jobs"
}

function node-psTestNetScript()
{
    return @'
        param($remoteHost, $port)
        test-netconnection $remoteHost -port $port
'@
}

function run-vmssPsCommand ($resourceGroup, $vmssName, $instanceId, $maxInstanceId, [string]$script, [collections.arraylist]$parameters)
{
    if (!$script)
    {
        return $false
    }

    if ((test-path $script))
    {
        write-host "reading file $script"
        $scriptList = Get-Content -Raw -Path $script
    }
    else
    {
        $tempScriptName = ".\script.ps1"
        $scriptList = [collections.arraylist]@($script.split("`r`n", [stringsplitoptions]::removeEmptyEntries))
        [io.file]::WriteAllText($tempScriptName, $script)
        $script = $tempScriptName
    }
    
    for ($i = $instanceId; $i -lt $maxInstanceId; $i++)
    {
        if ($parameters)
        {
            write-host "Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
            -VMScaleSetName $vmssName `
            -InstanceId $i `
            -ScriptPath $script `
            -Parameter $parameters `
            -CommandId RunPowerShellScript `
            -AsJob"
    
            $response = Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $i `
                -ScriptPath $script `
                -Parameter $parameters `
                -CommandId RunPowerShellScript `
                -AsJob
        }
        else 
        {
            write-host "Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
            -VMScaleSetName $vmssName `
            -InstanceId $i `
            -ScriptPath $script `
            -CommandId RunPowerShellScript `
            -AsJob"
    
            $response = Invoke-AzureRmVmssVMRunCommand -ResourceGroupName $resourceGroup `
                -VMScaleSetName $vmssName `
                -InstanceId $i `
                -ScriptPath $script `
                -CommandId RunPowerShellScript `
                -AsJob
        }
        
        write-host ($response | fl * | out-string)
    }

}

main
