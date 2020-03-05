<#
# script to update azure arm template resource settings
download:
(new-object net.webclient).DownloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-patch-resource.ps1","$pwd\azure-az-patch-resource.ps1")
.\azure-az-patch-resource.ps1 -resourceGroupName {{ resource group name }} -resourceName {{ resource name }} [-patch]

.EXAMPLE
#>
param (
    [string]$resourceGroupName = '',
    [string[]]$resourceNames = '',
    [string]$templateJsonFile = '.\template.json', 
    [string]$apiVersion = '' ,
    [string]$schema = 'http://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json',
    [int]$sleepSeconds = 1, 
    [switch]$patch
)

$ErrorActionPreference = 'stop' #'continue'
$VerbosePreference = 'continue'
function main () {
    if (!$resourceGroupName -or !$templateJsonFile) {
        write-error 'pas arguments'
        return
    }

    if (!$resourceNames) {
        $resourceNames = @((get-azresource -resourceGroupName $resourceGroupName).Name)
    }

    if (!(Get-AzContext)) {
        Connect-AzAccount
    }

    $error.Clear()
    display-settings

    if ($error) {
        Write-Warning "error enumerating resource"
        return
    }

    if ($patch) {
        remove-jobs
        if (!(deploy-template -resourceNames $resourceNames)) { return }
        wait-jobs
    }
    else {
        export-template -resourceNames $resourceNames
    }

    display-settings
    write-host 'finished'
}

function deploy-template($resourceNames) {
    $json = get-content -raw $templateJsonFile | convertfrom-json
    if ($error -or !$json -or !$json.resources) {
        write-error "invalid template file $templateJsonFile"
        return
    }
    $tempJsonFile = "$([io.path]::GetDirectoryName($templateJsonFile))\$([io.path]::GetFileNameWithoutExtension($templateJsonFile)).temp.json"
    $resources = @($json.resources | ? Name -imatch ($resourceNames -join '|'))

    create-jsonTemplate -resources $resources -jsonFile $tempJsonFile | Out-Null
    $error.Clear()
    $result = Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $tempJsonFile -Verbose

    if (!$error -and !$result) {
        write-host "patching resource with $tempJsonFile" -ForegroundColor Yellow
        New-AzResourceGroupDeployment -Name "$resourceGroupName-$((get-date).ToString("yyyyMMdd-HHmms"))" `
            -ResourceGroupName $resourceGroupName `
            -DeploymentDebugLogLevel All `
            -TemplateFile $tempJsonFile `
            -Verbose `
            #-asjob
    }
    else {
        write-error "template validation failed`r`n$($error | out-string)`r`n$result"
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

function export-template($resourceNames) {
    write-host "exporting template to $templateJsonFile" -ForegroundColor Yellow
    $resources = [collections.arraylist]@()
    $azResourceGroupLocation = @(get-azresource -ResourceGroupName $resourceGroupName)[0].Location
    $resourceProviders = Get-AzResourceProvider -Location $azResourceGroupLocation
    
    foreach ($name in $resourceNames) {
        # convert az resource to arm template
        $azResource = get-azresource -Name $name -ResourceGroupName $resourceGroupName -ExpandProperties
        $resourceProvider = $resourceProviders | where-object ProviderNamespace -ieq $azResource.ResourceType.split('/')[0]
        $rpType = $resourceProvider.ResourceTypes | Where-Object ResourceTypeName -ieq $azResource.ResourceType.split('/')[1]
        $resourceApiVersion = $apiVersion

        if (!$apiVersion) {
            $resourceApiVersion = $rpType.ApiVersions[0]
        }

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

    write-host $resourceTemplate -ForegroundColor Cyan
    write-host "template exported to $templateJsonFile" -ForegroundColor Yellow
    write-host "to update arm resource, modify $templateJsonFile.  when finished, execute script with -patch to update resource" -ForegroundColor Yellow
    . $templateJsonFile
    
    return
}

function create-jsonTemplate([collections.arraylist]$resources, [string]$jsonFile) {
    try {
        $resourceTemplate = @{ 
            '$schema'      = $schema
            contentVersion = "1.0.0.0"
            resources      = $resources
        } | convertto-json -depth 99

        $resourceTemplate | out-file $jsonFile
        return $true
    }
    catch { 
        write-error "$($_)`r`n$($error | out-string)"
        return $false
    }
}
function display-settings() {
    foreach ($name in $resourceNames) {
        $settings += Get-AzResource -ResourceGroupName $resourceGroupName `
            -Name $name `
            -ExpandProperties | convertto-json -depth 99
    }
    write-host "current settings: `r`n $settings" -ForegroundColor Green
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
            #            else {
            #                $jobInfo = (receive-job -Id $job.id)
            #                if ($jobInfo) {
            #                    write-log -data $jobInfo
            #                }
            #            }

            start-sleep -Seconds $sleepSeconds
        }
    }

    write-log "finished jobs: $scriptStartDateTimeUtc" -report $global:scriptName
}
function write-log($data) {
    if (!$data) { return }
    [string]$stringData = ""
    
    if ($data.GetType().Name -eq "PSRemotingJob") {
        foreach ($job in $data.childjobs) {
            if ($job.Information) {
                $stringData += (@($job.Information.ReadAll()) -join "`r`n")
            }
            if ($job.Verbose) {
                $stringData += (@($job.Verbose.ReadAll()) -join "`r`n")
            }
            if ($job.Debug) {
                $stringData += (@($job.Debug.ReadAll()) -join "`r`n")
            }
            if ($job.Output) {
                $stringData += (@($job.Output.ReadAll()) -join "`r`n")
            }
            if ($job.Warning) {
                write-warning (@($job.Warning.ReadAll()) -join "`r`n")
                $stringData += (@($job.Warning.ReadAll()) -join "`r`n")
                $stringData += ($job | fl * | out-string)
            }
            if ($job.Error) {
                write-error (@($job.Error.ReadAll()) -join "`r`n")
                $stringData += (@($job.Error.ReadAll()) -join "`r`n")
                $stringData += ($job | fl * | out-string)
            }
    
            if ($stringData.Trim().Length -gt 0) {
                $stringData += "`r`nname: $($data.Name) state: $($job.State) $($job.Status)`r`n"     
            }
            else {
                return
            }
        }
    }
    else {
        $stringData = "$(get-date):$($data | fl * | out-string)"
    }
    
    write-host $stringData
}

main

