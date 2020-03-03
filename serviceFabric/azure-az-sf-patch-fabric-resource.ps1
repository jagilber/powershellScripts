<#
# script to update azure service fabric arm template resource settings
# https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-fabric-settings

download:
(new-object net.webclient).DownloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-patch-fabric-resource.ps1","$pwd\azure-az-sf-patch-fabric-resource.ps1")
.\azure-az-sf-patch-fabric-resource.ps1 -resourceGroup {{cluster resource group}} -clusterName {{cluster name}} [-patch]

.EXAMPLE
#>

param (
    [string]$resourceGroup = '',
    [string]$clusterName = '',
    [string]$templateJsonFile = '.\template.json', 
    [string]$sfApiVersion = '2019-06-01-preview',
    [string]$schema = 'http://schema.management.azure.com/schemas/2019-03-01/deploymentTemplate.json'
    [switch]$patch
)

function main () {
    if (!$resourceGroup -or !$clusterName -or !$templateJsonFile) {
        write-error 'pass arguments'
        return
    }

    if (!(Get-AzContext)) {
        Connect-AzAccount
    }

    $error.Clear()
    $global:currentSettings = Get-AzResource -ResourceGroupName $resourceGroup -Name $clusterName -ExpandProperties | convertto-json -depth 99
    write-host "current settings: `r`n $global:currentSettings" -ForegroundColor Green
    write-host "current fabric settings"
    $currentSettings.FabricSettings
    
    if ($error) {
        Write-Warning "error enumerating cluster"
        return
    }

    if ($patch) {
        if(!(get-content -raw $templateJsonFile | convertfrom-json)) {
            write-error "invalid template file $templateJsonFile"
            return
        }

        $error.Clear()
        $result = Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroup -TemplateFile $templateJsonFile -Verbose

        if(!$error -and !$result) {
            write-host "patching cluster with $templateJsonFile" -ForegroundColor Yellow
            New-AzResourceGroupDeployment -Name "$resourceGroup-$((get-date).ToString("yyyyMMdd-HHmmss"))" `
                -ResourceGroupName $resourceGroup `
                -DeploymentDebugLogLevel All `
                -TemplateFile $templateJsonFile `
                -Verbose
        }
        else {
            write-error "template validation failed`r`n$error`r`n$result"
            return
        }
    }
    else {
        write-host "exporting template to $templateJsonFile" -ForegroundColor Yellow
        # convert sf cluster az resource to sf arm template
        $cluster = get-azresource -Name $clusterName -ResourceGroupName $resourceGroup -ExpandProperties # -ResourceType Microsoft.ServiceFabric/clusters

        $clusterTemplate = @{ 
            '$schema' = $schema
            contentVersion = "1.0.0.0"
            resources = @(
                @{
                    apiVersion = $sfApiVersion
                    dependsOn = @()
                    type = $cluster.Type
                    location = $cluster.Location
                    id = $cluster.Id
                    name = $cluster.Name
                    tags = $cluster.Tags
                    properties = $cluster.properties
                })
        } | convertto-json -depth 99

        $clusterTemplate | out-file $templateJsonFile
        write-host $clusterTemplate -ForegroundColor Cyan

        write-host "template exported to $templateJsonFile" -ForegroundColor Yellow
        write-host "to update cluster, modify $templateJsonFile.  when finished, execute script with -patch to update cluster" -ForegroundColor Yellow
        . $templateJsonFile

        return
    }

    $global:newSettings = Get-AzResource -ResourceGroupName $resourceGroup -Name $clusterName -ExpandProperties | convertto-json -depth 99
    write-host "new settings: `r`n $global:newSettings" -ForegroundColor Cyan
    write-host "new fabric settings"

    $currentSettings.FabricSettings
    write-host 'finished'
}

main
