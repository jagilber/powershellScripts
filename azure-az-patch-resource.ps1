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
    [string]$apiVersion = '' , #'2019-06-01-preview' sf, # '2019-07-01' vms
    [string]$schema = 'http://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json',
    [switch]$patch
)

function main () {
    #if (!$resourceGroupName -or !$resourceNames -or !$templateJsonFile) {
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
        Write-Warning "error enumerating cluster"
        return
    }

    if ($patch) {
        if (!(get-content -raw $templateJsonFile | convertfrom-json)) {
            write-error "invalid template file $templateJsonFile"
            return
        }

        $error.Clear()
        $result = Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $templateJsonFile -Verbose

        if (!$error -and !$result) {
            write-host "patching cluster with $templateJsonFile" -ForegroundColor Yellow
            New-AzResourceGroupDeployment -Name "$resourceGroupName-$((get-date).ToString("yyyyMMdd-HHmms"))" `
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
        $resources = [collections.arraylist]@()
        $azResourceGroupLocation = @(get-azresource -ResourceGroupName $resourceGroupName)[0].Location
        $resourceProviders = Get-AzResourceProvider -Location $azResourceGroupLocation

        foreach ($name in $resourceNames) {
            # convert az resource to arm template
            $azResource = get-azresource -Name $name -ResourceGroupName $resourceGroupName -ExpandProperties
            $resourceProvider = $resourceProviders | where-object ProviderNamespace -ieq ($azResource.ResourceType.split('/')[0])
            $rpType = $resourceProvider.ResourceTypes | Where-Object ResourceTypeName -ieq $azResource.ResourceType.split('/')[1]
            $resourceApiVersion = $apiVersion

            if(!$apiVersion) {
                $resourceApiVersion = $rpType.ApiVersions[0]
            }

            $resources.Add(@{
                    apiVersion = $resourceApiVersion
                    dependsOn  = @()
                    type       = $azResource.ResourceType
                    location   = $azResource.Location
                    id         = $azResource.ResourceId
                    name       = $azResource.Name
                    tags       = $azResource.Tags
                    properties = $azResource.properties
                })
        }
        
        $resourceTemplate = @{ 
            '$schema'      = $schema
            contentVersion = "1.0.0.0"
            resources      = $resources
        } | convertto-json -depth 99

        $resourceTemplate | out-file $templateJsonFile
        write-host $resourceTemplate -ForegroundColor Cyan
        write-host "template exported to $templateJsonFile" -ForegroundColor Yellow
        write-host "to update arm resource, modify $templateJsonFile.  when finished, execute script with -patch to update resource" -ForegroundColor Yellow
        . $templateJsonFile

        return
    }

    display-settings
    write-host 'finished'
}

function display-settings() {
    foreach ($name in $resourceNames) {
        $settings += Get-AzResource -ResourceGroupName $resourceGroupName `
            -Name $name `
            -ExpandProperties | convertto-json -depth 99
    }
    write-host "current settings: `r`n $settings" -ForegroundColor Green
}

main

