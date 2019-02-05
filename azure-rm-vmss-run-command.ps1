<#
    script to invoke powershell script with output through rest to azure vm scaleset vms

    Invoke-AzureRmVmssVMRunCommand -ResourceGroupName {{resourceGroupName}} -VMScaleSetName{{scalesetName}} -InstanceId {{instanceId}} -ScriptPath c:\temp\test1.ps1 -Parameter @{'name' = 'patterns';'value' = "{{certthumb1}},{{certthumb2}}"} -Verbose -Debug -CommandId RunPowerShellScript
    example run command with parameters
    DEBUG: ============================ HTTP REQUEST ============================

    HTTP Method:
    POST

    Absolute Uri:
    https://management.azure.com/subscriptions/{{subscriptionId}}/resourceGroups/{{resourceGroupName}}/providers/Microsoft.Compute/virtualMachineScaleSets/{{scalesetName}}/virtualmachines/{{instanceId}}/runCommand?api-version=2018-10-01

    Headers:
    x-ms-client-request-id        : ed0ad00a-fc6c-40f3-9015-8d92665f8362
    accept-language               : en-US

    Body:
    {
    "commandId": "RunPowerShellScript",
    "script": [
        "param($patterns)",
        "$certInfo = Get-ChildItem -Path cert: -Recurse | Out-String;",
        "$retval = $true;",
        "foreach($pattern in $patterns.split(","))",
        "{ ",
        "    if(!$pattern)",
        "    {",
        "        continue ",
        "    };",
        "    $retval = $retval -and [regex]::IsMatch($certInfo,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::SingleLine) ",
        "};",
        "return $retval;"
    ],
    "parameters": [
        {
        "name": "patterns",
        "value": "{{certthumb1}},{{certthumb2}}"
        }
    ]
    }
#>
param(
    [object]$token = $global:token,
    [string]$SubscriptionID = (Get-AzureRmContext).Subscription.Id,
    [string]$baseURI = "https://management.azure.com" ,
    [string]$nodeTypeApiVersion = "?api-version=2018-06-01",
    [string]$location = "eastus",
    [string]$resourceGroup,
    [string]$vmssName = "nt0",
    [int]$instanceId = -1,
    [string]$script,
    [collections.arraylist]$parameters = [collections.arraylist]@() # list of hashtables @{"name" = "%parameter name%"; "value" = "%parameter value%"}
)

$ErrorActionPreference = "silentlycontinue"

function main()
{
    if (!(get-azurermresource))
    {
        add-azurermaccount
    }

    if (!$script)
    {
        $script = (node-psTestNetScript)
        [void]$parameters.Add(@{"name" = "remoteHost"; "value" = "time.windows.com"})
        [void]$parameters.Add(@{"name" = "port"; "value" = "80"})
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
        
        foreach ($ss in $scalesets)
        {
            write-host "$($count). $($ss.Name)"
            $count++
        }
        
        if (($number = read-host "enter number of the cluster to query or ctrl-c to exit:") -le $count)
        {
            $vmss = $scalesets[$number - 1].Name
            write-host $vmss
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


    if ($error)
    {
        return 1
    }
}

function invoke-web($uri, $method, $body = "")
{
    $headers = @{
        'authorization' = "Bearer $($token.access_token)" 
        'ContentType'   = "application/json"
    }

    $params = @{ 
        ContentType = "application/json"
        Headers     = $headers
        Method      = $method
        uri         = $uri
        timeoutsec  = 600
    }

    if ($method -imatch "post")
    {
        [void]$params.Add('body', $body)
    }

    write-verbose ($params | out-string)
    $error.Clear()
    $response = Invoke-WebRequest @params -Verbose -Debug
    write-verbose "response: $response"
    write-host $error

    $error.Clear()
    $json = convertto-json -InputObject $response -ErrorAction SilentlyContinue 
    write-host $json -ForegroundColor Green 

    if ($error)
    {
        write-host ($response) -ForegroundColor DarkGreen
        $error.Clear()
    }

    $global:response = $response
    return $response
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
    # first run can take 15 minutes! has to install run extension?
    # simple subsequent commands can take minimum 30 sec

    if (!$script)
    {
        return $false
    }

    if ((test-path $script))
    {
        write-host "reading file $script"
        $scriptList = [collections.arraylist]@([io.file]::readAllLines($script))
    }
    else
    {
        $scriptList = [collections.arraylist]@($script.split("`r`n", [stringsplitoptions]::removeEmptyEntries))
    }
    
    write-host $scriptList 
    
    $body = @{
        'commandId' = 'RunPowerShellScript'
        'script'    = $scriptList
    } 

    if ($parameters)
    {
        [void]$body.Add('parameters', $parameters)
    }

    write-host ($body | convertto-json)

    $responses = [collections.arraylist]@()
    $statusUris = [collections.arraylist]@()
    
    for ($i = $instanceId; $i -lt $maxInstanceId; $i++)
    {
        $posturl = "$($baseUri)/subscriptions/$($subscriptionId)/resourceGroups/$($resourceGroup)/providers/Microsoft.Compute/virtualMachineScaleSets/$($vmssName)/virtualmachines/$($i)/runCommand$($nodeTypeApiVersion)"
        $response = invoke-web -uri $posturl -method "post" -body ($body | convertto-json)
        write-verbose $response
        [void]$responses.Add($response)

        $statusUri = ($response.Headers.'Azure-AsyncOperation')
        write-host $statusUri
        [void]$statusUris.Add($statusUri)
    }

    
    foreach ($statusUri in [collections.arraylist]@($statusUris))
    {
        Write-Host "checking statusuri $statusuri" -ForegroundColor Magenta
        while (!$error)
        {
            $response = (invoke-web -uri $statusUri -method "get")
            write-verbose ($response | out-string)
            $result = $response.Content | convertfrom-json

            if ($result.status -imatch "inprogress")
            {
                start-sleep -seconds 1
                continue
            }
            elseif ($result.status -imatch "succeeded")
            {
                write-host ($result.properties.output.value.message)
            }
            elseif ($result.status -imatch "canceled")
            {
                write-warning "action canceled"
            }
            else
            {
                write-warning "unknown status $($result.status)"
            }

            write-host ($response | out-string)
            $result = $response.content | convertfrom-json
            write-host ($result.properties.output.value.message)
            $statusUris.Remove($statusUri)
            break
        }
    }
}

main
