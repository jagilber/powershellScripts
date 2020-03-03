<#
# script to update azure arm template resource settings
download:
(new-object net.webclient).DownloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-patch-resource.ps1","$pwd\azure-az-patch-resource.ps1")
.\azure-az-patch-resource.ps1 -resourceGroupName {{ resource group name }} -resourceName {{ resource name }} [-patch]

.EXAMPLE
#>

param (
    [string]$resourceGroupName = '',
    [string]$resourceName = '',
    [string]$templateJsonFile = '.\template.json', 
    [string]$apiVersion = '' ,#'2019-06-01-preview' sf, # '2019-07-01' vmss
    [string]$schema = 'http://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json',
    [switch]$patch
)

function main () {
    if (!$resourceGroupName -or !$resourceName -or !$templateJsonFile) {
        write-error 'pass arguments'
        return
    }

    if (!(Get-AzContext)) {
        Connect-AzAccount
    }

    $error.Clear()
    display-settings

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
        $result = Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $templateJsonFile -Verbose

        if(!$error -and !$result) {
            write-host "patching cluster with $templateJsonFile" -ForegroundColor Yellow
            New-AzResourceGroupDeployment -Name "$resourceGroupName-$((get-date).ToString("yyyyMMdd-HHmmss"))" `
                -ResourceGroupName $resourceGroupName `
                -DeploymentDebugLogLevel All `
                -TemplateFile $templateJsonFile `
                -Verbose
        }
        else {
            write-error "template validation failed`r`n$($error | out-string)`r`n$result"
            return
        }
    }
    else {
        write-host "exporting template to $templateJsonFile" -ForegroundColor Yellow
        # convert az resource to arm template
        $azResource = get-azresource -Name $resourceName -ResourceGroupName $resourceGroupName -ExpandProperties

        if(!$apiVersion) {
            $apiVersion = "[providers('$($azResource.ResourceType.split('/')[0])','$($azResource.ResourceType.split('/')[1])').apiVersions[0]]"
        }

        $resourceTemplate = @{ 
            '$schema' = $schema
            contentVersion = "1.0.0.0"
            resources = @(
                @{
                    apiVersion = $apiVersion
                    dependsOn = @()
                    type = $azResource.Type
                    location = $azResource.Location
                    id = $azResource.Id
                    name = $azResource.Name
                    tags = $azResource.Tags
                    properties = $azResource.properties
                })
        } | convertto-json -depth 99

        $resourceTemplate | out-file $templateJsonFile
        write-host $resourceTemplate -ForegroundColor Cyan
        write-host "template exported to $templateJsonFile" -ForegroundColor Yellow
        write-host "to update cluster, modify $templateJsonFile.  when finished, execute script with -patch to update cluster" -ForegroundColor Yellow
        . $templateJsonFile

        return
    }

    display-settings
    write-host 'finished'
}

function display-settings() {
    $settings = Get-AzResource -ResourceGroupName $resourceGroupName `
        -Name $resourceName `
        -ExpandProperties | convertto-json -depth 99
    write-host "current settings: `r`n $settings" -ForegroundColor Green
}

main
