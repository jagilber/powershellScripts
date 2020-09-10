<#
.SYNOPSIS
    powershell script to update (patch) existing azure arm template resource settings similar to resources.azure.com

.LINK
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-patch-resource.ps1" -outFile "$pwd\azure-az-patch-resource.ps1";
    .\azure-az-patch-resource.ps1 -resourceGroupName {{ resource group name }} -resourceName {{ resource name }} [-patch]

.DESCRIPTION  
    powershell script to update (patch) existing azure arm template resource settings similar to resources.azure.com.
    useful for environments where resources.azure.com is not an option.
    PRECAUTION: there is no method to query current api versions being used. when script queries the arm resources, 
        the latest api version for that resource will be written to the template.json for each resource.

.NOTES  
    File Name  : azure-az-patch-resource.ps1
    Author     : jagilber
    Version    : 200725
    History    : 

.EXAMPLE 
    .\azure-az-patch-resource.ps1 -resourceGroupName clusterresourcegroup
    enumerate all resources in resource group 'clusteresourcegroup' and generate template.json

.EXAMPLE 
    .\azure-az-patch-resource.ps1 -resourceGroupName clusterresourcegroup -patch
    patch all resources in resource group 'clusteresourcegroup' using existing template.json

.EXAMPLE 
    .\azure-az-patch-resource.ps1 -resourceGroupName clusterresourcegroup -resource nt0
    enumerate resource named 'nt0' in resource group 'clusteresourcegroup' and generate template.json

.EXAMPLE 
    .\azure-az-patch-resource.ps1 -resourceGroupName clusterresourcegroup -resource nt0 -patch
    patch all resource named 'nt0' in resource group 'clusteresourcegroup' using existing template.json

.EXAMPLE 
    .\azure-az-patch-resource.ps1 -resourceGroupName clusterresourcegroup -templatejsonfile clusterresourcegroup.json
    enumerate all resources in resource group 'clusteresourcegroup' and generate clusterresourcegroup.json

.EXAMPLE 
    .\azure-az-patch-resource.ps1 -resourceGroupName clusterresourcegroup -patch -templatejsonfile clusterresourcegroup.json
    patch all resources in resource group 'clusteresourcegroup' using existing clusterresourcegroup.json
#>

[cmdletbinding()]
param (
    [string]$resourceGroupName = '',
    [string[]]$resourceNames = '',
    [switch]$patch,
    [string]$templateJsonFile = '.\template.json', 
    [string]$apiVersion = '' ,
    [string]$schema = 'http://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json',
    [int]$sleepSeconds = 1, 
    [ValidateSet('Incremental', 'Complete')]
    [string]$mode = 'Incremental',
    [switch]$useLatestApiVersion
)

set-strictMode -Version 3.0
$global:resourceTemplateObj = @{ }
$global:resourceErrors = 0
$global:resourceWarnings = 0

$PSModuleAutoLoadingPreference = 2
$currentErrorActionPreference = $ErrorActionPreference
$currentVerbosePreference = $VerbosePreference

function main () {
    write-host "starting"
    $ErrorActionPreference = 'continue'
    $VerbosePreference = 'continue'

    if (!(check-module)) {
        return
    }

    if (!(Get-AzContext)) {
        write-host "connecting to azure"
        Connect-AzAccount
    }

    $global:startTime = get-date
    $resourceIds = [collections.arraylist]::new()

    if (!$resourceGroupName -or !$templateJsonFile) {
        write-error 'specify resourceGroupName'
        return
    }

    if ($resourceNames) {
        foreach ($resourceName in $resourceNames) {
            write-host "getting resource $resourceName"
            $resourceIds.AddRange(@((get-azresource -resourceName $resourceName).Id))
        }
    }
    else {
        write-host "getting resource group resource ids $resourceGroupName"
        $resourceIds.AddRange(@((get-azresource -resourceGroupName $resourceGroupName).Id))
    }

    $error.Clear()
    display-settings -resourceIds $resourceIds

    if ($error) {
        Write-Warning "error enumerating resource"
        return
    }

    $deploymentName = "$resourceGroupName-$((get-date).ToString("yyyyMMdd-HHmms"))"

    if ($patch) {
        remove-jobs
        if (!(deploy-template -resourceIds $resourceIds)) { return }
        wait-jobs
    }
    else {
        export-template -resourceIds $resourceIds
        write-host "template exported to $templateJsonFile" -ForegroundColor Yellow
        write-host "to update arm resource, modify $templateJsonFile.  when finished, execute script with -patch to update resource" -ForegroundColor Yellow
        . $templateJsonFile

    }

    if ($global:resourceErrors -or $global:resourceWarnings) {
        write-warning "deployment may not have been successful: errors: $global:resourceErrors warnings: $global:resourceWarnings"
        write-host "errors: $($error | sort -Descending | out-string)"
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

function create-jsonTemplate([collections.arraylist]$resources, [string]$jsonFile) {
    try {
        $resourceTemplate = @{ 
            resources      = $resources
            '$schema'      = $schema
            contentVersion = "1.0.0.0"
            outputs        = @{}
            parameters     = @{}
            variables      = @{}
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
function deploy-template($resourceIds) {
    $json = get-content -raw $templateJsonFile | convertfrom-json
    if ($error -or !$json -or !$json.resources) {
        write-error "invalid template file $templateJsonFile"
        return
    }

    $templateJsonFile = Resolve-Path $templateJsonFile
    $tempJsonFile = "$([io.path]::GetDirectoryName($templateJsonFile))\$([io.path]::GetFileNameWithoutExtension($templateJsonFile)).temp.json"
    $resources = @($json.resources | where Id -imatch ($resourceIds -join '|'))

    create-jsonTemplate -resources $resources -jsonFile $tempJsonFile | Out-Null
    $error.Clear()
    write-host "validating template: Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $tempJsonFile -Verbose -Debug -Mode $mode" -ForegroundColor Cyan
    $result = Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
        -TemplateFile $tempJsonFile `
        -Verbose `
        -Debug `
        -Mode $mode

    if (!$error -and !$result) {
        write-host "patching resource with $tempJsonFile" -ForegroundColor Yellow
        start-job -ScriptBlock {
            param ($resourceGroupName, $tempJsonFile, $deploymentName, $mode)
            $VerbosePreference = 'continue'
            write-host "using file: $tempJsonFile"
            write-host "deploying template: New-AzResourceGroupDeployment -Name $deploymentName `
                -ResourceGroupName $resourceGroupName `
                -DeploymentDebugLogLevel All `
                -TemplateFile $tempJsonFile `
                -Verbose `
                -Mode $mode" -ForegroundColor Cyan

            New-AzResourceGroupDeployment -Name $deploymentName `
                -ResourceGroupName $resourceGroupName `
                -DeploymentDebugLogLevel All `
                -TemplateFile $tempJsonFile `
                -Verbose `
                -Mode $mode
        } -ArgumentList $resourceGroupName, $tempJsonFile, $deploymentName, $mode
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
        #Remove-Item $tempJsonFile -Force
        return $true
    }
}

function display-settings($resourceIds) {
    $settings = @()
    foreach ($resourceId in $resourceIds) {
        $settings += Get-AzResource -Id $resourceId `
            -ExpandProperties | convertto-json -depth 99
    }
    write-host "current settings: `r`n $settings" -ForegroundColor Green
}

function export-template($resourceIds) {
    write-host "exporting template to $templateJsonFile" -ForegroundColor Yellow
    $resources = [collections.arraylist]@()
    $azResourceGroupLocation = @(get-azresource -ResourceGroupName $resourceGroupName)[0].Location
    
    write-host "getting latest api versions" -ForegroundColor yellow
    $resourceProviders = Get-AzResourceProvider -Location $azResourceGroupLocation

    write-host "getting configured api versions" -ForegroundColor green
    Export-AzResourceGroup -ResourceGroupName $resourceGroupName -Path $templateJsonFile -Force
    $currentConfig = Get-Content -raw $templateJsonFile | convertfrom-json
    $currentApiVersions = $currentConfig.resources | select type,apiversion | sort -Unique type
    write-host ($currentApiVersions | fl * | out-string)
    remove-item $templateJsonFile -Force
    
    
    foreach ($resourceId in $resourceIds) {
        # convert az resource to arm template
        # bug where depending on arguments sent to get-azresource. using rg name and type will return correct name for extensions vm/extension
        # ex: 2019-dc/AzureNetworkWatcherExtension
        # querying by resource id returns incorrect name
        # ex: AzureNetworkWatcherExtension
        # so query again for just name using type and rg

        # get validation of rg name and type
        $azResource = get-azresource -Id $resourceId
        write-verbose "azresource by id: $($azResource | fl * | out-string)"
        # requery for correct name
        $azResourceName = (get-azresource -ResourceGroupName $azResource.ResourceGroupName -ResourceType $azResource.ResourceType | where ResourceId -eq $resourceId | select Name).Name
        write-verbose ("azresourcename fix: $azResourceName")
        
        $resourceApiVersion = $null

        if(!$useLatestApiVersion -and $currentApiVersions.type.contains($azResource.ResourceType)) {
            $rpType = $currentApiVersions | where type -ieq $azResource.ResourceType | select apiversion
            $resourceApiVersion = $rpType.ApiVersion
            write-host "using configured resource schema api version: $resourceApiVersion to enumerate and save resource: `r`n`t$($azResource.Id)" -ForegroundColor green
        }

        if($useLatestApiVersion -or !$resourceApiVersion) {
            $resourceProvider = $resourceProviders | where ProviderNamespace -ieq $azResource.ResourceType.split('/')[0]
            $rpType = $resourceProvider.ResourceTypes | where ResourceTypeName -ieq $azResource.ResourceType.split('/')[1]
            $resourceApiVersion = $rpType.ApiVersions[0]
            write-host "using latest schema api version: $resourceApiVersion to enumerate and save resource: `r`n`t$($azResource.Id)" -ForegroundColor yellow
        }

        $azResource = get-azresource -Id $resourceId -ExpandProperties -ApiVersion $resourceApiVersion
        write-verbose "azresource by id and version: $($azResource | fl * | out-string)"

        [void]$resources.Add(@{
                apiVersion = $resourceApiVersion
                #dependsOn  = @()
                type       = $azResource.ResourceType
                location   = $azResource.Location
                id         = $azResource.ResourceId
                name       = $azResourceName #$azResource.Name
                tags       = $azResource.Tags
                properties = $azResource.properties
            })
    }

    if (!(create-jsonTemplate -resources $resources -jsonFile $templateJsonFile)) { return }
    return
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
                $stringData.appendline(($job | fl * | out-string))
                $global:resourceWarnings++
            }
            if ($job.Error) {
                write-error (@($job.Error.ReadAll()) -join "`r`n")
                $stringData.appendline(@($job.Error.ReadAll()) -join "`r`n")
                $stringData.appendline(($job | fl * | out-string))
                $global:resourceErrors++
            }
            if ($stringData.tostring().Trim().Length -lt 1) {
                return
            }
        }
    }
    else {
        $stringData = "$(get-date):$($data | fl * | out-string)"
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
        
        foreach($operation in $deploymentOperations) {
            write-verbose ($operation | convertto-json)
            $currentOperation = "$($operation.Properties.targetResource.resourceType) $($operation.Properties.targetResource.resourceName)"
            $status = "$($operation.Properties.provisioningState) $($operation.Properties.statusCode) $($operation.Properties.timestamp) $($operation.Properties.duration)"
            
            if($operation.Properties.statusMessage) {
                $status = "$status $($operation.Properties.statusMessage)"
            }
            
            $activity = "$($operation.Properties.provisioningOperation):$($currentOperation)"
            Write-Progress -Activity $activity -id ($count++) -Status $status
        }
    }

    if($errorCount -ne $error.Count) {
        $error.RemoveRange($errorCount -1,$error.Count - $errorCount)
    }

    $ErrorActionPreference = $VerbosePreference = 'continue'
}

main
$ErrorActionPreference = $currentErrorActionPreference
$VerbosePreference = $currentVerbosePreference

