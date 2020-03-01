<#
# script to update azure service fabric settings
# https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-fabric-settings

download:
(new-object net.webclient).DownloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-patch-fabric-arm-template.ps1","$pwd\azure-az-sf-patch-fabric-arm-template.ps1")
.\azure-az-sf-patch-fabric-arm-template.ps1 -resourceGroup {{cluster resource group}} -clusterName {{cluster name}} -templateJsonFile {{arm template json file}}

.EXAMPLE
#>

param (
    [string]$resourceGroup = '',
    [string]$clusterName = '',
    [string]$templateJsonFile = '.\template.json', 
    [string]$sfApiVersion = '2019-06-01-preview',
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
    $global:currentSettings = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clusterName
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
                -Verbose `
                -Debug
        }
        else {
            write-error "template validation failed`r`n$error`r`n$result"
            return
        }
    }
    else {
        write-host "exporting template to $templateJsonFile" -ForegroundColor Yellow
        # convert sf cluster az resource to sf arm template
        $cluster = get-azresource -Name $clusterName -ResourceGroupName $resourceGroup -ResourceType Microsoft.ServiceFabric/clusters
        $clusterPropertiesJson = $cluster.properties | convertto-json -depth 99

        $clusterResourcesObject = @{ }
        $clusterResourcesObject.'$schema' = "http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json"
        $clusterResourcesObject.contentVersion = "1.0.0.0"

        $clusterObject = @{ }
        $clusterObject.apiVersion = $sfApiVersion
        #$clusterObject.dependsOn = @()
        $clusterObject.type = $cluster.Type
        $clusterObject.location = $cluster.Location
        #$clusterObject.id = $cluster.Id
        $clusterObject.name = $cluster.Name
        $clusterObject.tags = $cluster.Tags
        #$clusterObject.etag = $cluster.ETag
        $clusterObject.properties = $clusterPropertiesJson | convertfrom-json

        $clusterResourcesObject.Add('resources', @($clusterObject))

        $clusterTemplate = $clusterResourcesObject | convertto-json -depth 99
        $clusterTemplate | out-file $templateJsonFile

        #$clusterTemplate
        write-host $clusterTemplate -ForegroundColor Cyan

        write-host "template exported to $templateJsonFile" -ForegroundColor Yellow
        write-host "modify $templateJsonFile then rerun script with -patch to update cluster" -ForegroundColor Yellow
        . $templateJsonFile

        return
    }

    $global:newSettings = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clusterName
    write-host "new settings: `r`n $global:newSettings" -ForegroundColor Cyan
    write-host "new fabric settings"

    $currentSettings.FabricSettings
    write-host 'finished'
}

main