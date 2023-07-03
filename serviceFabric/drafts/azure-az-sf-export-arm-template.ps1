<#
.SYNOPSIS
    powershell script to export existing azure arm template resource settings using export-azresourcegroup and modifying necessary settings for redeploy
    works with cloudshell https://shell.azure.com/
    >help .\azure-az-sf-export-arm-template.ps1 -full

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-export-arm-template.ps1" -outFile "$pwd/azure-az-sf-export-arm-template.ps1";
    ./azure-az-sf-export-arm-template.ps1 -resourceGroupName <resource group name>

.DESCRIPTION
    powershell script to export existing azure arm template resource settings using export-azresourcegroup and modifying necessary settings for redeploy
    this assumes all resources in same resource group as that is the only way to deploy from portal.

    base cluster dependencies:
        loadbalancer depends on public ip
        vmss depends on
            vnet
            loadbalancer
            storage account sflogs
            storage account diag
        cluster depends on storage account sflogs

.NOTES
    File Name  : azure-az-sf-export-arm-template.ps1
    Author     : jagilber
    Version    : 0

.EXAMPLE
    .\azure-az-sf-export-arm-template.ps1 -resourceGroupName clusterresourcegroup
    export sf resources in resource group 'clusteresourcegroup' and generate template.json

.EXAMPLE
    .\azure-az-sf-export-arm-template.ps1 -resourceGroupName clusterresourcegroup -useExportedJsonFile .\template.export.json
    export sf resources in resource group 'clusteresourcegroup' and generate template.json using existing raw export file .\template.export.json
#>

[cmdletbinding()]
param (
    #[Parameter(Mandatory = $true)]
    [string]$resourceGroupName = '',
    [string]$templateFile = "$psscriptroot/templates-$resourceGroupName", # for cloudshell
    [string]$useExportedJsonFile = '',
    [string]$adminPassword = '', #'GEN_PASSWORD',
    [string]$logFile = "$templateFile/azure-az-sf-export-arm-template.log",
    [switch]$compress,
    [switch]$updateScript,
    [switch]$deploy
)

set-strictMode -Version 3.0
$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'continue'
#$VerbosePreference = 'continue'

$resourceTypes = @{
    cluster              = 'Microsoft.ServiceFabric/clusters'
    vmss                 = 'Microsoft.Compute/virtualMachineScaleSets'
    loadBalancer         = 'Microsoft.Network/loadBalancers'
    publicIp             = 'Microsoft.Network/publicIPAddresses'
    vnet                 = 'Microsoft.Network/virtualNetworks'
    storageAccount       = 'Microsoft.Storage/storageAccounts'
    networkInterface     = 'Microsoft.Network/networkInterfaces'
    networkSecurityGroup = 'Microsoft.Network/networkSecurityGroups'
    networkSecurityRule  = 'Microsoft.Network/networkSecurityGroups/securityRules'
    subnet               = 'Microsoft.Network/virtualNetworks/subnets'
    #extension            = 'Microsoft.Compute/virtualMachineScaleSets/extensions'
}

function main() {
    $jsonExport = ''
    $rgModel = @{}

    try {
        write-console "main() started"
        $error.Clear()

        if (!(Get-Module az)) {
            Import-Module az
        }

        if (!(get-azresourceGroup)) {
            Connect-AzAccount
        }

        if (!$resourceGroupName) {
            write-console "resourceGroupName is required"
            return
        }

        if ($useExportedJsonFile -and (Test-Path $templateFile)) {
            $jsonExport = read-json $templateFile
        }
        else {
            $jsonExport = export-resourceGroup
        }

        $rgModel = convert-fromJson $jsonExport
        #$rgModel = update-serviceFabricModel $rgModel
        #$rgModel = update-vmssModel $rgModel
        $rgModel = update-lbModel $rgModel

        $result = deploy-rgModel $rgModel

        return $result
    }
    catch [Exception] {
        $errorString = "exception: $($psitem.Exception)
        exception:`r`n$($psitem.Exception.Message)
        innerException:`r`n$($psitem.Exception.InnerException)
        ($error | out-string)
        $($psitem.ScriptStackTrace)"
        Write-Host $errorString -foregroundColor Red
    }
    finally {
        write-console "finished"
    }
}

function add-property($resource, $name, $value = $null, $overwrite = $false) {
    write-console "checking property '$name' = '$value' to $resource"
    if (!$resource) { return $resource }
    if ($name -match '\.') {
        foreach ($object in $name.split('.')) {
            $childName = $name.replace("$object.", '')
            $resource.$object = add-property -resource $resource.$object -name $childName -value $value
            return $resource
        }
    }
    else {
        foreach ($property in $resource.PSObject.Properties) {
            if ($property.Name -ieq $name) {
                write-console "property '$name' already exists" -foregroundColor 'Yellow'
                if (!$overwrite) { return $resource }
            }
        }

    }

    write-console "add-member -MemberType NoteProperty -Name $name -Value $value"
    $resource | add-member -MemberType NoteProperty -Name $name -Value $value
    write-console "added property '$name' = '$value' to resource" -foregroundColor 'Green'
    return $resource
}

function convert-fromJson($json, $display = $false) {
    write-console "convert-fromJson:$json" -verbose:$display
    $object = $json | convertfrom-json -asHashTable

    return $object
}

function convert-toJson($object, $display = $false) {
    $json = $object | convertto-json -Depth 99
    write-console $json -verbose:$display

    return $json
}

function deploy-rgModel($rgModel) {

    $templateJson = convert-toJson $rgModel
    write-json $templateJson $templateFile
    write-console $templateJson -foregroundColor 'Cyan'

    write-console "test-azResourceGroupDeployment -templateFile $templateFile -resourceGroupName $resourceGroupName -Verbose" -foregroundColor 'Cyan'
    $result = test-azResourceGroupDeployment -templateFile $templateFile -resourceGroupName $resourceGroupName -Verbose

    if ($result) {
        write-console "error: test-azResourceGroupDeployment failed:$($result | out-string)" -err
        return $result
    }
  
    $deploymentName = "$($MyInvocation.MyCommand.Name)-$(get-date -Format 'yyMMddHHmmss')"
    write-console "new-azResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -Verbose -DeploymentDebugLogLevel All" -foregroundColor 'Cyan'
  
    if ($deploy) {
        $result = new-azResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -Verbose -DeploymentDebugLogLevel All
    }
    else {
        write-console "after verifying / modifying $templateFile, run the above 'new-azresourcegroupdeployment' command to deploy the template" -foregroundColor 'Yellow'
    }

    return $result
}

function export-resourceGroup() {
    $error.Clear()
    write-console "export-azResourceGroup -ResourceGroupName $resourceGroupName -IncludeParameterDefaultValue -IncludeComments -Path $templateFile -Force" -foregroundColor 'Cyan'
    $result = Export-AzResourceGroup -ResourceGroupName $resourceGroupName -IncludeParameterDefaultValue -IncludeComments -Path $templateFile -Force
    if (!$result -or $error) {
        write-console "export-azResourceGroup failed. result: $result, error: $($error | out-string)" -err
    }

    $jsonExport = read-json $templateFile
    return $jsonExport
}

function get-resourceTypes($model, $typeName) {
    $typeResources = @($model.resources | where-object type -ieq $typeName)
    write-console "get-resourceTypes:returning $($typeResources.count) resources of type '$typeName'"
    return $typeResources
}

function get-sfProtectedSettings($storageAccountName, $templateJson) {
    $storageAccountKey1 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('supportLogStorageAccountName')),'2015-05-01-preview').key1]"
    $storageAccountKey2 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('supportLogStorageAccountName')),'2015-05-01-preview').key2]"
    write-console "get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName"
    $storageAccountKeys = get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName

    if (!$storageAccountKeys) {
        write-console "storage account key not found" -err
        $error.Clear()
        $templateJson = add-property -resource $templateJson -name 'variables.supportLogStorageAccountName' -value $storageAccountName
    }
    else {
        $storageAccountKey1 = $storageAccountKeys[0].Value
        $storageAccountKey2 = $storageAccountKeys[1].Value
    }

    $storageAccountProtectedSettings = @{
        "storageAccountKey1" = $storageAccountKey1
        "storageAccountKey2" = $storageAccountKey2
    }

    write-console $storageAccountProtectedSettings
    return $storageAccountProtectedSettings
}

function get-wadProtectedSettings($storageAccountName, $templateJson) {
    $storageAccountTemplate = "[variables('applicationDiagnosticsStorageAccountName')]"
    $storageAccountKey = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('applicationDiagnosticsStorageAccountName')),'2015-05-01-preview').key1]"
    $storageAccountEndPoint = "https://core.windows.net/"

    write-console "get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName"
    $storageAccountKeys = get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName

    if (!$storageAccountKeys) {
        write-console "storage account key not found"
        $storageAccountName = $storageAccountTemplate
        $templateJson = add-property -resource $templateJson -name 'variables.applicationDiagnosticsStorageAccountName' -value $storageAccountName
    }
    else {
        $storageAccountName = $storageAccountName
        $storageAccountKey = $storageAccountKeys[0].Value
    }

    $storageAccountProtectedSettings = @{
        "storageAccountName"     = $storageAccountName
        "storageAccountKey"      = $storageAccountKey
        "storageAccountEndPoint" = $storageAccountEndPoint
    }
    write-console $storageAccountProtectedSettings
    return $storageAccountProtectedSettings
}

function read-json($file) {
    write-console "get-content $file -raw"
    $json = Get-Content $file -raw
    write-console $json -verbose
    
    return $json
}

function update-lbModel($rgModel) {
    $lbResources = get-resourceTypes $rgModel $resourceTypes.loadBalancer

    return $rgModel
}

function update-serviceFabricModel($rgModel) {
    $sfResource = get-resourceTypes $rgModel $resourceTypes.cluster
    if ($sfResource.gettype().Name -ine 'OrderedHashtable') {
        write-console "error: found $($sfResource.count) service fabric clusters in resource group '$resourceGroupName'" -err
        return
    }

    # remove cluster properties that are not needed for redeploy
    if ($sfResource.properties.upgradeMode -ieq 'Automatic') {
        write-console "removing cluster clusterCodeVersion property as upgradeMode is 'Automatic'"
        $sfResource.properties.clusterCodeVersion = ''
    }

    return $rgModel
}

function update-vmssModel($rgModel) {
    $vmssResources = get-resourceTypes $rgModel $resourceTypes.vmss
    $sfResource = get-resourceTypes $rgModel $resourceTypes.cluster
    foreach ($vmssResource in $vmssResources) {
        $extensions = $vmssResource.virtualMachineProfile.extensionProfile.extensions
        foreach ($extension in $extensions) {
            if ($extension.properties.publisher -ieq 'Microsoft.Azure.ServiceFabric') {
                $protectedSettings = get-sfProtectedSettings $sfResource. $rgModel
                $extension = add-property -resource $extension.properties -name 'protectedSettings' -value $protectedSettings
            }
            elseif ($extension.properties.publisher -ieq 'Microsoft.Azure.Diagnostics') {
                $protectedSettings = get-wadProtectedSettings $extension.properties.storageAccountName $rgModel
                $extension = add-property -resource $extension.properties -name 'protectedSettings' -value $protectedSettings
            }
        }
    }
    return $rgModel
}

function write-console($message, $foregroundColor = 'White', [switch]$verbose, [switch]$err) {
    if (!$message) { return }
    if ($message.gettype().name -ine 'string') {
        $message = $message | convertto-json -Depth 10
    }

    if ($verbose) {
        write-verbose($message)
    }
    else {
        write-host($message) -ForegroundColor $foregroundColor
    }

    if ($err) {
        write-error($message)
        throw
    }
}

function write-json($json, $file) {
    write-console "out-file -InputObject $json -FilePath $file -Force"
    out-file -InputObject $json -FilePath $file -Force
    write-console "json saved to $file" -foregroundColor 'Green'
}

main