<#
## TESTING ##
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
    [string]$instanceId = -1,
    [string]$script,
    [hashtable]$parameters = @{}
)

function main()
{
    if(!$script)
    {
        $script = (node-psTestNetScript)
        $parameters.Add(@{"name" = "remoteHost";"value" = "time.windows.com"})
        $parameters.Add(@{"name" = "port";"value" = "80"})
    }

    if(!$resourceGroup -or !$vmssName)
    {

    }

    $result = run-vmssPsCommand -resourceGroup $resourceGroup -vmssName $vmssName -instanceId $instanceId -script $script -parameters $parameters
    write-host $result

    if($error)
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
        ContentType = $contentType
        Headers     = $headers
        Method      = $method
        uri         = $uri
        timeoutsec  = 600
    }

    if($method -imatch "post")
    {
        $params.Add('body', $body)
    }

    write-host ($params | out-string)
    $error.Clear()
    $response = Invoke-WebRequest @params -Verbose -Debug
    write-verbose "response: $response"
    write-host $error

    $error.Clear()
    write-host ($response | convertto-json) -ForegroundColor Green -ErrorAction SilentlyContinue

    if($error)
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
function run-vmssPsCommand ($resourceGroup, $vmssName, $instanceId, [string]$script, [collections.arraylist]$parameters)
{
    # first run can take 15 minutes! has to install run extension?
    # simple subsequent commands can take minimum 30 sec

    if(!$script)
    {
        return $false
    }

    if((test-path $script))
    {
        write-host "reading file $script"
        $scriptList = [collections.arraylist]@([io.file]::readAllLines($script))
    }
    else
    {
        $scriptList = [collections.arraylist]@($script.split("`r`n",[stringsplitoptions]::removeEmptyEntries))
    }
    
    write-host $scriptList 
    
    $posturl = "$($baseUri)/subscriptions/$($subscriptionId)/resourceGroups/$($resourceGroup)/providers/Microsoft.Compute/virtualMachineScaleSets/$($vmssName)/virtualmachines/$($instanceId)/runCommand$($nodeTypeApiVersion)"
    $body = @{
        'commandId' = 'RunPowerShellScript'
        'script' = $scriptList
    } 

    if($parameters)
    {
        $body.Add('parameters',$parameters)
    }

    write-host ($body | convertto-json)
    $response = invoke-web -uri $posturl -method "post" -body ($body | convertto-json)

    $statusUri = ($response.Headers.'Azure-AsyncOperation')

    while(!$error)
    {
        $response = (invoke-web -uri $statusUri -method "get")
        write-host ($response | out-string)
        
        if(!($response.StatusCode -eq 200))
        {
            break
        }
        
        $result = $response.Content | convertfrom-json

        if($result.status -imatch "inprogress")
        {
            start-sleep -seconds 10
        }
        elseif($result.status -imatch "succeeded")
        {
            write-host ($result.properties.output.value.message)
            break
        }
        elseif($result.status -imatch "canceled")
        {
            write-warning "action canceled"
            break
        }
        else
        {
            write-warning "unknown status $($result.status)"
            break
        }
    }

    write-host ($response | out-string)
    $result = $response.content | convertfrom-json
    write-host ($result.properties.output.value.message)

    return ($result.properties.output.value.message)
}

main
