<#
.SYNOPSIS
    powershell script to export existing azure arm template resource settings similar for portal deployed service fabric cluster


.LINK
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/temp/azure-az-sf-export-arm-template.ps1" -outFile "$pwd\azure-az-sf-export-arm-template.ps1";
    .\azure-az-sf-export-arm-template.ps1 -resourceGroupName {{ resource group name }} -resourceName {{ resource name }} [-patch]

.DESCRIPTION  
    powershell script to export existing azure arm template resource settings similar for portal deployed service fabric cluster
    this assumes all resources in same resource group as that is the only way to deploy from portal
    
    PRECAUTION: when script queries the arm resources, if unable to determine configured api version, 
     the latest api version for that resource will be written to the template.json.

.NOTES  
    File Name  : azure-az-sf-export-arm-template.ps1
    Author     : jagilber
    Version    : 210307
    History    : 

.EXAMPLE 
    .\azure-az-sf-export-arm-template.ps1 -resourceGroupName clusterresourcegroup
    export sf resources in resource group 'clusteresourcegroup' and generate template.json

#>

[cmdletbinding()]
param (
    [string]$resourceGroupName = '',
    [string[]]$resourceNames = '',
    [string[]]$excludeResourceNames = '',
    [switch]$patch,
    [string]$templateJsonFile = "$psscriptroot/template.json", 
    [string]$templateParameterFile = '', 
    [string]$apiVersion = '' ,
    [string]$schema = 'http://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json',
    [int]$sleepSeconds = 1, 
    [ValidateSet('Incremental', 'Complete')]
    [string]$mode = 'Incremental',
    [switch]$useLatestApiVersion,
    [switch]$detail
)

set-strictMode -Version 3.0
$global:resourceTemplateObj = @{ }
$global:resourceErrors = 0
$global:resourceWarnings = 0
$global:configuredRGResources = [collections.arraylist]::new()
$env:SuppressAzurePowerShellBreakingChangeWarnings = $true
$PSModuleAutoLoadingPreference = 2
$currentErrorActionPreference = $ErrorActionPreference
$currentVerbosePreference = $VerbosePreference
$debugLevel = 'none'

function main () {
    write-host "starting"
    if ($detail) {
        $ErrorActionPreference = 'continue'
        $VerbosePreference = 'continue'
        $debugLevel = 'all'
    }

    if (!(check-module)) {
        return
    }
    
    Enable-AzureRmAlias
    if (!(Get-AzContext)) {
        write-host "connecting to azure"
        Connect-AzAccount
    }

    $global:startTime = get-date

    if (!$resourceGroupName -or !$templateJsonFile) {
        write-error 'specify resourceGroupName'
        return
    }

    if ($resourceNames) {
        foreach ($resourceName in $resourceNames) {
            write-host "getting resource $resourceName"
            $global:configuredRGResources.AddRange(@((get-azresource -ResourceGroupName $resourceGroupName -resourceName $resourceName)))
        }
    }
    else {
        $resourceIds = enum-resources
        foreach ($resourceId in $resourceIds) {
            $resource = get-azresource -resourceId "$resourceId" -ExpandProperties
            $global:configuredRGResources.Add($resource)
        }
    }

    display-settings -resources $global:configuredRGResources

    if ($global:configuredRGResources.count -lt 1) {
        Write-Warning "error enumerating resource $($error | format-list * | out-string)"
        return
    }

    $deploymentName = "$resourceGroupName-$((get-date).ToString("yyyyMMdd-HHmms"))"

    if ($patch) {
        remove-jobs
        if (!(deploy-template -configuredResources $global:configuredRGResources)) { return }
        wait-jobs
    }
    else {
        export-template -configuredResources $global:configuredRGResources
        write-host "template exported to $templateJsonFile" -ForegroundColor Yellow
        write-host "to update arm resource, modify $templateJsonFile.  when finished, execute script with -patch to update resource" -ForegroundColor Yellow

        $error.clear()
        code $templateJsonFile
        if ($error) {
            . $templateJsonFile
        }
    }

    if ($global:resourceErrors -or $global:resourceWarnings) {
        write-warning "deployment may not have been successful: errors: $global:resourceErrors warnings: $global:resourceWarnings"

        if ($DebugPreference -ieq 'continue') {
            write-host "errors: $($error | sort-object -Descending | out-string)"
        }
    }

    $deployment = Get-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name $deploymentName -ErrorAction silentlycontinue

    write-host "deployment:`r`n$($deployment | format-list * | out-string)"
    Write-Progress -Completed -Activity "complete"
    write-host "time elapsed:  $(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes`r`n"
    write-host 'finished. template stored in $global:resourceTemplateObj' -ForegroundColor Cyan
}

function check-module() {
    $error.clear()
    get-command Connect-AzAccount -ErrorAction SilentlyContinue
    
    if ($error) {
        $error.clear()
        write-warning "azure module for Connect-AzAccount not installed."

        if ((read-host "is it ok to install latest azure az module?[y|n]") -imatch "y") {
            $error.clear()
            install-module az.accounts
            install-module az.resources

            import-module az.accounts
            import-module az.resources
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

function create-jsonTemplate([collections.arraylist]$resources, 
    [string]$jsonFile, 
    [hashtable]$parameters = @{},
    [hashtable]$variables = @{},
    [hashtable]$outputs = @{}
) {
    try {
        $resourceTemplate = @{ 
            resources      = $resources
            '$schema'      = $schema
            contentVersion = "1.0.0.0"
            outputs        = $outputs
            parameters     = $parameters
            variables      = $variables
        } | convertto-json -depth 99

        $resourceTemplate | out-file $jsonFile
        write-host $resourceTemplate -ForegroundColor Cyan
        $global:resourceTemplateObj = $resourceTemplate | convertfrom-json
        return $true
    }
    catch { 
        write-error "$($_)`r`n$($error | out-string)"
        return $false
    }
}

function deploy-template($configuredResources) {
    $templateParameters = @{}
    $parameters = @{}
    $variables = @{}
    $outputs = @{}
    
    $json = get-content -raw $templateJsonFile | convertfrom-json
    
    if (!$json -or !$json.resources) {
        write-error "invalid template file $templateJsonFile"
        return
    }

    if ((test-path $templateParameterFile)) {
        $jsonParameters = get-content -raw $templateParameterFile | convertfrom-json
        # convert pscustom object to hashtable
        foreach ($jsonParameter in $jsonParameters.parameters.psobject.properties) {
            $templateParameters.Add($jsonParameter.name, $jsonParameter.value.value)
        }
    }

    $templateJsonFile = Resolve-Path $templateJsonFile
    $tempJsonFile = "$([io.path]::GetDirectoryName($templateJsonFile))\$([io.path]::GetFileNameWithoutExtension($templateJsonFile)).temp.json"
    $resources = @($json.resources | where-object Id -imatch ($configuredResources.ResourceId -join '|'))

    foreach ($jsonParameter in $json.parameters.psobject.properties) {
        $parameters.Add($jsonParameter.name, $jsonParameter.value)
    }
    
    foreach ($jsonParameter in $json.variables.psobject.properties) {
        $variables.Add($jsonParameter.name, $jsonParameter.value)
    }

    foreach ($jsonParameter in $json.outputs.psobject.properties) {
        $outputs.Add($jsonParameter.name, $jsonParameter.value)
    }

    create-jsonTemplate -resources $resources -jsonFile $tempJsonFile -parameters $parameters -variables $variables -outputs $outputs | Out-Null

    $error.Clear()
    write-host "validating template: Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
        -TemplateFile $tempJsonFile `
        -Verbose:$detail `
        -TemplateParameterObject $templateParameters `
        -Debug:$detail `
        -Mode $mode" -ForegroundColor Cyan

    $result = Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
        -TemplateFile $tempJsonFile `
        -Verbose:$detail `
        -TemplateParameterObject $templateParameters `
        -Debug:$detail `
        -Mode $mode

    if (!$error -and !$result) {
        write-host "patching resource with $tempJsonFile" -ForegroundColor Yellow
        start-job -ScriptBlock {
            param ($resourceGroupName, $tempJsonFile, $deploymentName, $mode, $debugLevel, $detail, $templateParameters)
            if ($detail) {
                $VerbosePreference = 'continue'
            }

            write-host "using file: $tempJsonFile"
            write-host "deploying template: New-AzResourceGroupDeployment -Name $deploymentName `
                -ResourceGroupName $resourceGroupName `
                -DeploymentDebugLogLevel $debuglevel `
                -TemplateFile $tempJsonFile `
                -TemplateParameterObject $templateParameters `
                -Verbose:$detail `
                -Mode $mode" -ForegroundColor Cyan

            New-AzResourceGroupDeployment -Name $deploymentName `
                -ResourceGroupName $resourceGroupName `
                -DeploymentDebugLogLevel $debugLevel `
                -TemplateFile $tempJsonFile `
                -TemplateParameterObject $templateParameters `
                -Verbose:$detail `
                -Mode $mode
        } -ArgumentList $resourceGroupName, $tempJsonFile, $deploymentName, $mode, $debugLevel, $detail, $templateParameters
    }
    else {
        write-host "template validation failed: $($error |out-string) $($result | out-string)"
        write-error "template validation failed`r`n$($error | convertto-json)`r`n$($result | convertto-json)"
        return $false
    }

    if ($error) {
        return $false
    }
    else {
        return $true
    }
}

function display-settings($resources) {
    $settings = @()
    foreach ($resource in $resources) {
        $settings += $resource | convertto-json -depth 99
    }
    write-host "current settings: `r`n $settings" -ForegroundColor Green
}

function export-template($configuredResources) {
    write-host "exporting template to $templateJsonFile" -ForegroundColor Yellow
    $resources = [collections.arraylist]@()
    $azResourceGroupLocation = @($configuredResources)[0].Location
    
    write-host "getting latest api versions" -ForegroundColor yellow
    $resourceProviders = Get-AzResourceProvider -Location $azResourceGroupLocation

    write-host "getting configured api versions" -ForegroundColor green

    $resourceIds = @($configuredResources.ResourceId)
    write-host "resource ids: $resourceIds" -ForegroundColor green

    write-host "
        Export-AzResourceGroup -ResourceGroupName $resourceGroupName `
            -Path $templateJsonFile `
            -Force `
            -IncludeParameterDefaultValue `
            -Resource $resourceIds
    "
    Export-AzResourceGroup -ResourceGroupName $resourceGroupName `
        -Path $templateJsonFile `
        -Force `
        -IncludeParameterDefaultValue `
        -Resource $resourceIds
    
    return

    $currentConfig = Get-Content -raw $templateJsonFile | convertfrom-json
    $currentApiVersions = $currentConfig.resources | select-object type, apiversion | sort-object -Unique type
    write-host ($currentApiVersions | format-list * | out-string)
    remove-item $templateJsonFile -Force
    
    foreach ($azResource in $configuredResources) {
        write-verbose "azresource by id: $($azResource | format-list * | out-string)"
        $resourceApiVersion = $null

        if (!$useLatestApiVersion -and $currentApiVersions.type.contains($azResource.ResourceType)) {
            $rpType = $currentApiVersions | where-object type -ieq $azResource.ResourceType | select-object apiversion
            $resourceApiVersion = $rpType.ApiVersion
            write-host "using configured resource schema api version: $resourceApiVersion to enumerate and save resource: `r`n`t$($azResource.ResourceId)" -ForegroundColor green
        }

        if ($useLatestApiVersion -or !$resourceApiVersion) {
            $resourceProvider = $resourceProviders | where-object ProviderNamespace -ieq $azResource.ResourceType.split('/')[0]
            $rpType = $resourceProvider.ResourceTypes | where-object ResourceTypeName -ieq $azResource.ResourceType.split('/')[1]
            $resourceApiVersion = $rpType.ApiVersions[0]
            write-host "using latest schema api version: $resourceApiVersion to enumerate and save resource: `r`n`t$($azResource.ResourceId)" -ForegroundColor yellow
        }

        $azResource = get-azresource -Id $azResource.ResourceId -ExpandProperties -ApiVersion $resourceApiVersion
        write-verbose "azresource by id and version: $($azResource | format-list * | out-string)"

        [void]$resources.Add(@{
                apiVersion = $resourceApiVersion
                #dependsOn  = @()
                type       = $azResource.ResourceType
                location   = $azResource.Location
                id         = $azResource.ResourceId
                name       = $azResource.Name 
                tags       = $azResource.Tags
                properties = $azResource.properties
            })
    }

    if (!(create-jsonTemplate -resources $resources -jsonFile $templateJsonFile)) { return }
    return
}

function enum-clusterResource() {
    $clusters = @(get-azresource -ResourceGroupName $resourceGroupName `
            -ResourceType 'Microsoft.ServiceFabric/clusters' `
            -ExpandProperties)
    $clusterResource = $null
    $count = 1
    $number = 0

    write-verbose "all clusters $clusters"
    if ($clusters.count -gt 1) {
        foreach ($cluster in $clusters) {
            write-host "$($count). $($rg.ResourceGroupName)"
            $count++
        }
        
        $number = [convert]::ToInt32((read-host "enter number of the cluster to query or ctrl-c to exit:"))
        if ($number -le $count) {
            $clusterResource = $resourceGroups[$number - 1].ResourceGroupName
            write-host $clusterResource
        }
        else {
            return $null
        }
    }
    elseif ($clusters.count -lt 1) {
        return $null
    }
    else {
        $clusterResource = $clusters[0]
    }

    write-host "using cluster resource $clusterResource" -ForegroundColor Green
    return $clusterResource
}

function enum-ipResources($lbResources) {
    $resources = [collections.arraylist]::new()

    foreach ($lbResource in $lbResources) {
        write-host "checking lbResource for ip config $lbResource"
        $lb = get-azresource -ResourceId $lbResource -ExpandProperties
        foreach ($fec in $lb.Properties.frontendIPConfigurations) {
            if ($fec.properties.publicIpAddress) {
                $id = $fec.properties.publicIpAddress.id
                write-host "adding public ip: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }
    }

    write-verbose "ip resources $resources)"
    return $resources.ToArray() | sort-object -Unique
}

function enum-kvResources($vmssResources) {
    $resources = [collections.arraylist]::new()

    foreach ($vmssResource in $vmssResources) {
        write-host "checking vmssResource for key vaults $($vmssResource.Name)"
        foreach ($id in $vmssResource.Properties.virtualMachineProfile.osProfile.secrets.sourceVault.id) {
            write-host "adding kv id: $id" -ForegroundColor green
            [void]$resources.Add($id)
        }
    }

    write-verbose "kv resources $resources)"
    return $resources.ToArray() | sort-object -Unique
}

function enum-lbResources($vmssResources) {
    $resources = [collections.arraylist]::new()

    foreach ($vmssResource in $vmssResources) {
        # get nic for vnet/subnet and lb
        write-host "checking vmssResource for network config $($vmssResource.Name)"
        foreach ($nic in $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations) {
            foreach ($ipconfig in $nic.properties.ipConfigurations) {
                $id = [regex]::replace($ipconfig.properties.loadBalancerBackendAddressPools.id, '/backendAddressPools/.+$', '')
                write-host "adding lb id: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }
    }

    write-verbose "lb resources $resources)"
    return $resources.ToArray() | sort-object -Unique
}

function enum-nsgResources($vmssResources) {
    $nsgResources = [collections.arraylist]::new()

    foreach ($vnetId in $vnetResources) {
        $vnetresource = @(get-azresource -ResourceId $vnetId -ExpandProperties)
        write-host "checking vnet resource for nsg config $($vnetresource.Name)"
        foreach ($subnet in $vnetResource.Properties.subnets) {
            if ($subnet.properties.networkSecurityGroup.id) {
                $id = $subnet.properties.networkSecurityGroup.id
                write-host "adding nsg id: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }

    }

    write-verbose "nsg resources $resources"
    return $resources.ToArray() | sort-object -Unique
}

function enum-resources() {
    $resources = [collections.arraylist]::new()

    write-host "getting resource group cluster $resourceGroupName"
    $clusterResource = @(enum-clusterResource)
    if (!$clusterResource) {
        write-error "unable to enumerate cluster. exiting"
        return $null
    }
    [void]$resources.Add($clusterResource.Id)

    write-host "getting scalesets $resourceGroupName"
    $vmssResources = @(enum-vmssResources $clusterResource)
    if (!$vmssResources) {
        write-error "unable to enumerate vmss. exiting"
        return $null
    }
    if ($vmssResources.count -gt 1) {
        [void]$resources.AddRange($vmssResources.Id)
    }
    else {
        [void]$resources.Add($vmssResources.Id)
    }
    

    write-host "getting virtualnetworks $resourceGroupName"
    $vnetResources = @(enum-vnetResources $vmssResources)
    if (!$vnetResources) {
        write-error "unable to enumerate vnets. exiting"
        return $null
    }
    if ($vnetResources.count -gt 1) {
        [void]$resources.AddRange($vnetResources)
    }
    else {
        [void]$resources.Add($vnetResources)
    }

    write-host "getting loadbalancers $resourceGroupName"
    $lbResources = @(enum-lbResources $vmssResources)
    if (!$lbResources) {
        write-error "unable to enumerate loadbalancers. exiting"
        return $null
    }
    if ($lbResources.count -gt 1) {
        [void]$resources.AddRange($lbResources)
    }
    else {
        [void]$resources.Add($lbResources)
    }

    write-host "getting ip addresses $resourceGroupName"
    $ipResources = @(enum-ipResources $lbResources)
    if (!$ipResources) {
        write-warning "unable to enumerate ips."
        #return $null
    }
    if ($ipResources.count -gt 1) {
        [void]$resources.AddRange($ipResources)
    }
    else {
        [void]$resources.Add($ipResources)
    }

    write-host "getting key vaults $resourceGroupName"
    $kvResources = @(enum-kvResources $vmssResources)
    if (!$kvResources) {
        write-warning "unable to enumerate key vaults."
        #return $null
    }

    if ($kvResources.count -gt 1) {
        [void]$resources.AddRange($kvResources)
    }
    elseif ($kvResources.count -eq 1) {
        [void]$resources.Add($kvResources)
    }

    write-host "getting nsgs $resourceGroupName"
    $nsgResources = @(enum-nsgResources $vmssResources)
    if (!$nsgResources) {
        write-warning "unable to enumerate nsgs."
        #return $null
    }

    if ($nsgResources.count -gt 1) {
        [void]$resources.AddRange($nsgResources)
    }
    elseif ($nsgResources.count -eq 1) {
        [void]$resources.Add($nsgResources)
    }

    if ($excludeResourceNames) {
        $resources = $resources | where-object Name -NotMatch "$($excludeResourceNames -join "|")"
    }

    return $resources | sort-object -Unique
}

function enum-vmssResources($clusterResource) {
    $nodeTypes = $clusterResource.Properties.nodeTypes
    write-host "cluster nodetypes $($nodeTypes| convertto-json)"
    $vmssResources = [collections.arraylist]::new()

    $clusterEndpoint = $clusterResource.Properties.clusterEndpoint
    write-host "cluster id $clusterEndpoint" -ForegroundColor Green
    
    if (!$nodeTypes -or !$clusterEndpoint) {
        return $null
    }

    $resources = @(get-azresource -ResourceGroupName $resourceGroupName `
            -ResourceType 'Microsoft.Compute/virtualMachineScaleSets' `
            -ExpandProperties)

    write-verbose "vmss resources $resources"

    foreach ($resource in $resources) {
        if (($resource.Properties.virtualMachineProfile.extensionprofile.extensions.properties.settings 
                | Select-Object clusterEndpoint).clusterEndpoint -ieq $clusterEndpoint) {
            write-host "adding vmss resource $($resource | convertto-json)"
            [void]$vmssResources.Add($resource)
        }
    }

    return $vmssResources.ToArray() | sort-object -Unique
}

function enum-vnetResources($vmssResources) {
    $resources = [collections.arraylist]::new()

    foreach ($vmssResource in $vmssResources) {
        # get nic for vnet/subnet and lb
        write-host "checking vmssResource for network config $($vmssResource.Name)"
        foreach ($nic in $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations) {
            foreach ($ipconfig in $nic.properties.ipConfigurations) {
                $id = [regex]::replace($ipconfig.properties.subnet.id, '/subnets/.+$', '')
                write-host "adding vnet id: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }
    }

    write-verbose "vnet resources $resources"
    return $resources.ToArray() | sort-object -Unique
}

function remove-jobs() {
    try {
        foreach ($job in get-job) {
            write-host "removing job $($job.Name)" -report $global:scriptName
            write-host $job -report $global:scriptName
            $job.StopJob()
            Remove-Job $job -Force
        }
    }
    catch {
        write-host "error:$($Error | out-string)"
        $error.Clear()
    }
}

function wait-jobs() {
    write-log "monitoring jobs"
    while (get-job) {
        foreach ($job in get-job) {
            $jobInfo = (receive-job -Id $job.id)
            if ($jobInfo) {
                write-log -data $jobInfo
            }
            else {
                write-log -data $job
            }

            if ($job.state -ine "running") {
                write-log -data $job

                if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                    write-log -data $job
                }

                write-log -data $job
                remove-job -Id $job.Id -Force  
            }

            write-progressInfo
            start-sleep -Seconds $sleepSeconds
        }
    }

    write-log "finished jobs"
}

function write-log($data) {
    if (!$data) { return }
    [text.stringbuilder]$stringData = New-Object text.stringbuilder
    
    if ($data.GetType().Name -eq "PSRemotingJob") {
        foreach ($job in $data.childjobs) {
            if ($job.Information) {
                $stringData.appendline(@($job.Information.ReadAll()) -join "`r`n")
            }
            if ($job.Verbose) {
                $stringData.appendline(@($job.Verbose.ReadAll()) -join "`r`n")
            }
            if ($job.Debug) {
                $stringData.appendline(@($job.Debug.ReadAll()) -join "`r`n")
            }
            if ($job.Output) {
                $stringData.appendline(@($job.Output.ReadAll()) -join "`r`n")
            }
            if ($job.Warning) {
                write-warning (@($job.Warning.ReadAll()) -join "`r`n")
                $stringData.appendline(@($job.Warning.ReadAll()) -join "`r`n")
                $stringData.appendline(($job | format-list * | out-string))
                $global:resourceWarnings++
            }
            if ($job.Error) {
                write-error (@($job.Error.ReadAll()) -join "`r`n")
                $stringData.appendline(@($job.Error.ReadAll()) -join "`r`n")
                $stringData.appendline(($job | format-list * | out-string))
                $global:resourceErrors++
            }
            if ($stringData.tostring().Trim().Length -lt 1) {
                return
            }
        }
    }
    else {
        $stringData = "$(get-date):$($data | format-list * | out-string)"
    }

    write-host $stringData
}

function write-progressInfo() {
    $ErrorActionPreference = $VerbosePreference = 'silentlycontinue'
    $errorCount = $error.Count
    write-verbose "Get-AzResourceGroupDeploymentOperation -ResourceGroupName $resourceGroupName -DeploymentName $deploymentName -ErrorAction silentlycontinue"
    $deploymentOperations = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $resourceGroupName -DeploymentName $deploymentName -ErrorAction silentlycontinue
    $status = "time elapsed:  $(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes" #`r`n"
    write-verbose $status

    $count = 0
    Write-Progress -Activity "deployment: $deploymentName resource patching: $resourceGroupName" -Status $status -id ($count++)

    if ($deploymentOperations) {
        write-verbose ("deployment operations: `r`n`t$($deploymentOperations | out-string)")
        
        foreach ($operation in $deploymentOperations) {
            write-verbose ($operation | convertto-json)
            $currentOperation = "$($operation.Properties.targetResource.resourceType) $($operation.Properties.targetResource.resourceName)"
            $status = "$($operation.Properties.provisioningState) $($operation.Properties.statusCode) $($operation.Properties.timestamp) $($operation.Properties.duration)"
            
            if ($operation.Properties.statusMessage) {
                $status = "$status $($operation.Properties.statusMessage)"
            }
            
            $activity = "$($operation.Properties.provisioningOperation):$($currentOperation)"
            Write-Progress -Activity $activity -id ($count++) -Status $status
        }
    }

    if ($errorCount -ne $error.Count) {
        $error.RemoveRange($errorCount - 1, $error.Count - $errorCount)
    }

    if ($detail) {
        $ErrorActionPreference = $VerbosePreference = 'continue'
    }
}

main
$ErrorActionPreference = $currentErrorActionPreference
$VerbosePreference = $currentVerbosePreference

