<#
.SYNOPSIS
    powershell script to export existing azure arm template resource settings similar for portal deployed service fabric cluster
    works with cloudshell https://shell.azure.com/
    >help .\azure-az-sf-export-arm-template.ps1 -full

.LINK
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-export-arm-template.ps1" -outFile "$pwd\azure-az-sf-export-arm-template.ps1";
    .\azure-az-sf-export-arm-template.ps1 -resourceGroupName <resource group name>

.DESCRIPTION  
    powershell script to export existing azure arm template resource settings similar for portal deployed service fabric cluster
    this assumes all resources in same resource group as that is the only way to deploy from portal.
    uses az cmdlet export-azresourcegroup -includecomments -includeparameterdefaults to generate raw export

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
    Version    : 210316
    History    : 

.EXAMPLE 
    .\azure-az-sf-export-arm-template.ps1 -resourceGroupName clusterresourcegroup
    export sf resources in resource group 'clusteresourcegroup' and generate template.json

.EXAMPLE 
    .\azure-az-sf-export-arm-template.ps1 -resourceGroupName clusterresourcegroup -useExportedJsonFile .\template.export.json
    export sf resources in resource group 'clusteresourcegroup' and generate template.json using existing raw export file .\template.export.json

#>

[cmdletbinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName = '',
    [string]$templatePath = "$psscriptroot/templates-$resourceGroupName", # for cloudshell
    [string]$useExportedJsonFile = '',
    [string]$adminPassword = '', #'GEN_PASSWORD',
    [switch]$detail,
    [string]$logFile = "$templatePath/azure-az-sf-export-arm-template.log",
    [switch]$compress,
    [switch]$updateScript
)

# todo unused params need cleanup
[string[]]$resourceNames = ''
[string[]]$excludeResourceNames = ''
[bool]$patch = $false # [switch]
[string]$templateParameterFile = ''
[string]$apiVersion = '' 
[int]$sleepSeconds = 1 
#[ValidateSet('Incremental', 'Complete')]
[string]$mode = 'Incremental'
[bool]$useLatestApiVersion = $false # [swtich]
# end todo unused params need cleanup

set-strictMode -Version 3.0
$schema = 'http://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json'
$parametersSchema = 'http://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json'
$updateUrl = 'https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-export-arm-template.ps1'

$global:templateJsonFile = "$templatePath/template.json"
$global:resourceTemplateObj = @{ }
$global:resourceErrors = 0
$global:resourceWarnings = 0
$global:configuredRGResources = [collections.arraylist]::new()
$global:sflogs = $null
$global:sfdiags = $null
$global:startTime = get-date
$global:storageKeyApi = '2015-05-01-preview'
$global:defaultSflogsValue = "[toLower(concat('sflogs',uniqueString(resourceGroup().id),'2'))]"
$global:defaultSfdiagsValue = "[toLower(concat(uniqueString(resourceGroup().id),'3'))]"
$env:SuppressAzurePowerShellBreakingChangeWarnings = $true
$PSModuleAutoLoadingPreference = 2
$currentErrorActionPreference = $ErrorActionPreference
$currentVerbosePreference = $VerbosePreference
$debugLevel = 'none'

function main () {
    if (!(test-path $templatePath)) {
        # test local and for cloudshell
        mkdir $templatePath
        write-log "making directory $templatePath"
    }

    write-log "starting"

    if ($detail) {
        $ErrorActionPreference = 'continue'
        $VerbosePreference = 'continue'
        $debugLevel = 'all'
    }

    if (!(check-module)) {
        return
    }

    if ($updateScript -and (get-update -updateUrl $updateUrl)) {
        return
    }
    
    if (!(@(Get-AzResourceGroup).Count)) {
        write-log "connecting to azure"
        Connect-AzAccount
    }

    if ($resourceNames) {
        foreach ($resourceName in $resourceNames) {
            write-log "getting resource $resourceName"
            $global:configuredRGResources.AddRange(@((get-azresource -ResourceGroupName $resourceGroupName -resourceName $resourceName)))
        }
    }
    else {
        $resourceIds = enum-allResources
        foreach ($resourceId in $resourceIds) {
            $resource = get-azresource -resourceId "$resourceId" -ExpandProperties
            if ($resource.ResourceGroupName -ieq $resourceGroupName) {
                write-log "adding resource id to configured resources: $($resource.resourceId)" -ForegroundColor Cyan
                [void]$global:configuredRGResources.Add($resource)
            }
            else {
                write-log "skipping resource $($resource.resourceid) as it is out of resource group scope $($resource.ResourceGroupName)" -isWarning
            }
        }
    }

    display-settings -resources $global:configuredRGResources

    if ($global:configuredRGResources.count -lt 1) {
        write-log "error enumerating resource $($error | format-list * | out-string)" -isWarning
        return
    }

    $deploymentName = "$resourceGroupName-$((get-date).ToString("yyyyMMdd-HHmms"))"

    if ($patch) {
        #remove-jobs
        #if (!(deploy-template -configuredResources $global:configuredRGResources)) { return }
        #wait-jobs
    }
    else {
        $currentConfig = create-exportTemplate
        create-currentTemplate $currentConfig
        create-redeployTemplate $currentConfig
        create-addNodeTypeTemplate $currentConfig
        create-newTemplate $currentConfig

        if ($compress) {
            $zipFile = "$templatePath.zip"
            compress-archive $templatePath $zipFile -Force
            # only works in ps5.6
            set-clipboard -path $zipFile 
        }

        $global:resourceTemplateObj = $currentConfig
        $error.clear()

        write-host "finished. files stored in $templatePath" -ForegroundColor Green
        code $templatePath # for cloudshell and local
        
        if ($error) {
            . $templateJsonFile.Replace(".json", ".current.json")
        }
    }

    if ($global:resourceErrors -or $global:resourceWarnings) {
        write-log "deployment may not have been successful: errors: $global:resourceErrors warnings: $global:resourceWarnings" -isWarning

        if ($DebugPreference -ieq 'continue') {
            write-log "errors: $($error | sort-object -Descending | out-string)"
        }
    }

    $deployment = Get-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name $deploymentName -ErrorAction silentlycontinue

    write-log "deployment:`r`n$($deployment | format-list * | out-string)"
    Write-Progress -Completed -Activity "complete"
    write-log "time elapsed:  $(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes`r`n"
    write-log 'finished. template stored in $global:resourceTemplateObj' -ForegroundColor Cyan
    if ($logFile) {
        write-log "log file saved to $logFile"
    }
}

function add-outputs($currentConfig, $name, $value, $type = 'string') {
    $outputs = $currentConfig.psobject.Properties | where-object name -ieq 'outputs'
    $outputItem = @{
        value = $value
        type  = $type
    }

    if (!$outputs) {
        # create pscustomobject
        $currentConfig | Add-Member -TypeName System.Management.Automation.PSCustomObject -NotePropertyMembers @{
            outputs = @{
                $name = $outputItem
            }
        }
    }
    else {
        $currentConfig.outputs.add($name, $outputItem)
    }
}

function add-parameterNameByResourceType($currentConfig, $type, $name, $metadataDescription = '') {
    
    $resources = @($currentConfig.resources | where-object 'type' -eq $type)
    $parameterNames = @{}

    foreach ($resource in $resources) {
        $parameterName = create-parametersName -resource $resource -name $name
        $parameterizedName = create-parameterizedName -parameterName $name -resource $resource -withbrackets
        $parameterNameValue = get-resourceParameterValue -resource $resource -name $name
        set-resourceParameterValue -resource $resource -name $name -newValue $parameterizedName

        if ($parameterNameValue -ne $null) {
            [void]$parameterNames.Add($parameterName, $parameterNameValue)
        }
    }

    write-log "parameter names $parameterNames"
    foreach ($parameterName in $parameterNames.GetEnumerator()) {
        if (!(get-fromParametersSection -currentConfig $currentConfig -parameterName $parameterName.key)) {
            add-toParametersSection -currentConfig $currentConfig `
                -parameterName $parameterName.key `
                -parameterValue $parameterName.value `
                -metadataDescription $metadataDescription
        }
    }
}

function add-parameter($currentConfig, $resource, $name, $aliasName = $name, $resourceObject = $resource, $value = $null, $type = 'string', $metadataDescription = '') {
    $parameterName = create-parametersName -resource $resource -name $aliasName
    $parameterizedName = create-parameterizedName -parameterName $aliasName -resource $resource -withbrackets
    $parameterNameValue = $value

    if (!$parameterNameValue) {
        $parameterNameValue = get-resourceParameterValue -resource $resourceObject -name $name
    }

    set-resourceParameterValue -resource $resourceObject -name $name -newValue $parameterizedName

    if ($parameterNameValue -ne $null) {
        write-log "parameter name $parameterName"
        if (!(get-fromParametersSection -currentConfig $currentConfig -parameterName $parameterName)) {
            add-toParametersSection -currentConfig $currentConfig `
                -parameterName $parameterName `
                -parameterValue $parameterNameValue `
                -type $type `
                -metadataDescription $metadataDescription
        }
    }
}

function add-toParametersSection ($currentConfig, $parameterName, $parameterValue, $type = "string", $metadataDescription = "") {
    $parameterObject = @{
        type         = $type
        defaultValue = $parameterValue 
        metadata     = @{description = $metadataDescription }
    }

    foreach ($psObjectProperty in $currentConfig.parameters.psobject.Properties) {
        if (($psObjectProperty.Name -imatch $parameterName)) {
            $psObjectProperty.Value = $parameterObject
            return
        }
    }

    $currentConfig.parameters | Add-Member -MemberType NoteProperty -Name $parameterName -Value $parameterObject
}

function add-vmssProtectedSettings($vmssResource) {
    $sflogsParameter = create-parameterizedName -parameterName 'name' -resource $global:sflogs

    foreach ($extension in $vmssResource.properties.virtualMachineProfile.extensionPRofile.extensions) {
        if ($extension.properties.type -ieq 'ServiceFabricNode') {
            $extension.properties | Add-Member -MemberType NoteProperty -Name protectedSettings -Value @{
                StorageAccountKey1 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', $sflogsParameter),'$storageKeyApi').key1]"
                StorageAccountKey2 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', $sflogsParameter),'$storageKeyApi').key2]"
            }
            write-log "added $($extension.properties.type) protectedsettings $($extension.properties.protectedSettings | create-json)" -ForegroundColor Magenta
        }

        if ($extension.properties.type -ieq 'IaaSDiagnostics') {
            $saname = $extension.properties.settings.storageAccount
            $sfdiagsParameter = create-parameterizedName -parameterName 'name' -resource ($global:sfdiags | where-object name -imatch $saname)
            $extension.properties.settings.storageAccount = "[$sfdiagsParameter]"

            $extension.properties | Add-Member -MemberType NoteProperty -Name protectedSettings -Value @{
                storageAccountName     = "$sfdiagsParameter"
                storageAccountKey      = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', $sfdiagsParameter),'$storageKeyApi').key1]"
                storageAccountEndPoint = "https://core.windows.net/"                  
            }
            write-log "added $($extension.properties.type) protectedsettings $($extension.properties.protectedSettings | create-json)" -ForegroundColor Magenta
        }
    }
}

function check-module() {
    $error.clear()
    get-command Connect-AzAccount -ErrorAction SilentlyContinue
    
    if ($error) {
        $error.clear()
        write-log "azure module for Connect-AzAccount not installed." -isWarning

        get-command Connect-AzureRmAccount -ErrorAction SilentlyContinue
        if (!$error) {
            write-log "azure module for Connect-AzureRmAccount is installed. use cloud shell to run script instead https://shell.azure.com/" -isWarning
            return $false
        }
        
        if ((read-host "is it ok to install latest azure az module?[y|n]") -imatch "y") {
            $error.clear()
            install-module az.accounts -AllowClobber -Force
            install-module az.resources -AllowClobber -Force

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

function create-addNodeTypeTemplate($currentConfig) {
    # create add node type templates for primary os / hardware sku change
    # create secondary for additional secondary nodetypes
    $templateFile = $templateJsonFile.Replace(".json", ".addnodetype.json")
    $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")

    # addprimarynodetype from primarynodetype
    # addsecondarynodetype from secondarynodetype
    parameterize-nodeTypes $currentConfig

    create-parameterFile $currentConfig  $templateParameterFile
    verify-config $currentConfig $templateParameterFile

    # save base / current json
    $currentConfig | create-json | out-file $templateFile

    # save current readme
    $readme = "addnodetype modifications:
            - additional parameters have been added
            - microsoft monitoring agent extension has been removed (provisions automatically on deployment)
            - adminPassword required parameter added (needs to be set)
            - if upgradeMode for cluster resource is set to 'Automatic', clusterCodeVersion is removed
            - protectedSettings for vmss extensions cluster and diagnostic extensions are added and set to storage account settings
            - dnsSettings for public Ip Address needs to be unique
            - storageAccountNames required parameters (needs to be unique or will be generated)
            - if adding new vmss, each vmss resource needs a cluster nodetype resource added
            - if adding new vmss, only one nodetype should be isprimary unless upgrading primary nodetype
            - if adding new vmss, verify isprimary nodetype durability matches durability in cluster resource
            - primarydurability is a parameter
            - isPrimary is a parameter
            - additional nodetype resource has been added to cluster resource
            "
    $readme | out-file $templateJsonFile.Replace(".json", ".addnodetype.readme.txt")

}

function create-currentTemplate($currentConfig) {
    # create base /current template
    $templateFile = $templateJsonFile.Replace(".json", ".current.json")
    $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")

    remove-duplicateResources $currentConfig
    remove-unusedParameters $currentConfig
    modify-lbResources $currentConfig
    modify-vmssResources $currentConfig
    
    create-parameterFile $currentConfig  $templateParameterFile
    verify-config $currentConfig $templateParameterFile

    # save base / current json
    $currentConfig | create-json | out-file $templateFile

    # save current readme
    $readme = "current modifications:
            - additional parameters have been added
            - extra / duplicate child resources removed from root
            - dependsOn modified to remove conflicting / unneeded resources
            - protectedSettings for vmss extensions cluster and diagnostic extensions are added and set to storage account settings
            "
    $readme | out-file $templateJsonFile.Replace(".json", ".current.readme.txt")
}

function create-exportTemplate() {
    # create base /current template
    $templateFile = $templateJsonFile.Replace(".json", ".export.json")

    if ($useExportedJsonFile -and (test-path $useExportedJsonFile)) {
        write-log "using existing export file $useExportedJsonFile" -ForegroundColor Green
        $templateFile = $useExportedJsonFile
    }
    else {
        $exportResult = export-template -configuredResources $global:configuredRGResources -jsonFile $templateFile
        write-log "template exported to $templateFile" -ForegroundColor Yellow
        write-log "template export result $($exportResult|out-string)" -ForegroundColor Yellow
    }

    # save base / current json
    $currentConfig = Get-Content -raw $templateFile | convertfrom-json
    $currentConfig | create-json | out-file $templateFile

    # save current readme
    $readme = "export:
            - this is raw export from ps cmdlet export-azresourcegroup -includecomments -includeparameterdefaults
            - $templateFile will not be usable to recreate / create new cluster in this state
            - use 'current' to modify existing cluster
            - use 'redeploy' or 'new' to recreate / create cluster
            "
    $readme | out-file $templateJsonFile.Replace(".json", ".export.readme.txt")
    return $currentConfig
}

function create-json(
    [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [object]$inputObject,
    [int]$depth = 99
) {
    
    $currentWarningPreference = $WarningPreference
    $WarningPreference = 'SilentlyContinue'
    
    # to fix \u0027 single quote issue
    $result = $inputObject | convertto-json -depth $depth | foreach-object { [regex]::unescape($_) }
    $WarningPreference = $currentWarningPreference

    return $result
}

function create-jsonTemplate([collections.arraylist]$resources, 
    [string]$jsonFile, 
    [hashtable]$parameters = @{},
    [hashtable]$variables = @{},
    [hashtable]$outputs = @{}) {
    try {
        $resourceTemplate = @{ 
            resources      = $resources
            '$schema'      = $schema
            contentVersion = "1.0.0.0"
            outputs        = $outputs
            parameters     = $parameters
            variables      = $variables
        } | create-json

        $resourceTemplate | out-file $jsonFile
        write-log $resourceTemplate -ForegroundColor Cyan
        $global:resourceTemplateObj = $resourceTemplate | convertfrom-json
        return $true
    }
    catch { 
        write-log "$($_)`r`n$($error | out-string)" -isError
        return $false
    }
}

function create-newTemplate($currentConfig) {
    # create deploy / new / add template
    $templateFile = $templateJsonFile.Replace(".json", ".new.json")
    $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")
    # nodetype info, isPrimary
    # modify-clusterResourcesDeploy $currentConfig
    # os, sku, capacity, durability?
    # modify-vmssResourcesDeploy $currentConfig
    # GEN_UNIQUE dns, fqdn
    # modify-ipResourcesDeploy $currentConfig
    # GEN_UNIQUE name
    $parameterExclusions = modify-storageResourcesDeploy $currentConfig
    modify-vmssResourcesDeploy $currentConfig

    create-parameterFile -currentConfig $currentConfig -parameterFileName $templateParameterFile -ignoreParameters $parameterExclusions
    verify-config $currentConfig $templateParameterFile

    # # save add json
    $currentConfig | create-json | out-file $templateFile

    # save add readme
    $readme = "new / add modifications:
            - microsoft monitoring agent extension has been removed (provisions automatically on deployment)
            - adminPassword required parameter added (needs to be set)
            - if upgradeMode for cluster resource is set to 'Automatic', clusterCodeVersion is removed
            - protectedSettings for vmss extensions cluster and diagnostic extensions are added and set to storage account settings
            - dnsSettings for public Ip Address needs to be unique
            - storageAccountNames required parameters (needs to be unique or will be generated)
            - if adding new vmss, each vmss resource needs a cluster nodetype resource added
            - if adding new vmss, only one nodetype should be isprimary unless upgrading primary nodetype
            - if adding new vmss, verify isprimary nodetype durability matches durability in cluster resource
            "
    $readme | out-file $templateJsonFile.Replace(".json", ".new.readme.txt")
}

function create-parameterFile($currentConfig, $parameterFileName, $ignoreParameters = @()) {
    $parameterTemplate = [ordered]@{ 
        '$schema'      = $parametersSchema
        contentVersion = "1.0.0.0"
    } 

    # create pscustomobject
    $parameterTemplate | Add-Member -TypeName System.Management.Automation.PSCustomObject -NotePropertyMembers @{ parameters = @{} }
    
    foreach ($psObjectProperty in $currentConfig.parameters.psobject.Properties.GetEnumerator()) {
        $metadata = $null

        if ($ignoreParameters.Contains($psObjectProperty.name)) {
            write-log "skipping parameter $($psobjectProperty.name)"
            continue
        }

        write-log "value properties:$($psObjectProperty.Value.psobject.Properties.Name)" -verbose
        $parameterItem = @{
            value = $psObjectProperty.Value.defaultValue
        }

        if ($psObjectProperty.Value.GetType().name -ieq 'hashtable' -and $psObjectProperty.Value['metadata']) {
            if ($psObjectProperty.value.metadata.description) {
                $parameterItem.metadata = @{description = $psObjectProperty.value.metadata.description }
            }
        }
        $parameterTemplate.parameters.Add($psObjectProperty.name, $parameterItem)
    }

    if (!($parameterFileName.tolower().contains('parameters'))) {
        $parameterFileName = $parameterFileName.tolower().replace('.json', '.parameters.json')
    }

    write-log "creating parameterfile $parameterFileName" -ForegroundColor Green
    $parameterTemplate | create-json | out-file -FilePath $parameterFileName
}

function create-parameterizedName($parameterName, $resource, [switch]$withbrackets) {
    if ($withbrackets) {
        return "[parameters('$(create-parametersName -resource $resource -name $parameterName)')]"
    }

    return "parameters('$(create-parametersName -resource $resource -name $parameterName)')"
}

function create-parametersName($resource, $name = 'name') {
    $resourceSubType = [regex]::replace($resource.type, '^.+?/', '')
    if ($resource.name.contains('[')) {
        $resourceName = [regex]::Match($resource.comments, ".+/([^/]+)'.$").Groups[1].Value
    }
    else {
        $resourceName = $resource.name
    }
    
    $parametersName = "$($resourceSubType)_$($resourceName)_$($name)"
    write-log "returning $parametersName"
    return $parametersName
}

function create-redeployTemplate($currentConfig) {
    # create redeploy template
    $templateFile = $templateJsonFile.Replace(".json", ".redeploy.json")
    $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")

    modify-clusterResourceRedeploy $currentConfig
    modify-lbResourcesRedeploy $currentConfig
    modify-vmssResourcesRedeploy $currentConfig
    modify-ipAddressesRedeploy $currentConfig

    create-parameterFile $currentConfig  $templateParameterFile
    verify-config $currentConfig $templateParameterFile

    # # save redeploy json
    $currentConfig | create-json | out-file $templateFile

    # save redeploy readme
    $readme = "redeploy modifications:
            - microsoft monitoring agent extension has been removed (provisions automatically on deployment)
            - adminPassword required parameter added (needs to be set)
            - if upgradeMode for cluster resource is set to 'Automatic', clusterCodeVersion is removed
            - protectedSettings for vmss extensions cluster and diagnostic extensions are added and set to storage account settings
            - clusterendpoint is parameterized
            "
    $readme | out-file $templateJsonFile.Replace(".json", ".redeploy.readme.txt")
}

function deploy-template($configuredResources) {
    $templateParameters = @{}
    $parameters = @{}
    $variables = @{}
    $outputs = @{}
    
    $json = get-content -raw $templateJsonFile | convertfrom-json
    
    if (!$json -or !$json.resources) {
        write-log "invalid template file $templateJsonFile" -isError
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
    write-log "validating template: Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
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
        write-log "patching resource with $tempJsonFile" -ForegroundColor Yellow
        start-job -ScriptBlock {
            param ($resourceGroupName, $tempJsonFile, $deploymentName, $mode, $debugLevel, $detail, $templateParameters)
            if ($detail) {
                $VerbosePreference = 'continue'
            }

            write-log "using file: $tempJsonFile"
            write-log "deploying template: New-AzResourceGroupDeployment -Name $deploymentName `
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
        write-log "template validation failed: $($error |out-string) $($result | out-string)"
        write-log "template validation failed`r`n$($error | create-json)`r`n$($result | create-json)" -isError
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
        $settings += $resource | create-json
    }
    write-log "current settings: `r`n $settings" -ForegroundColor Green
}

function export-template($configuredResources, $jsonFile) {
    write-log "exporting template to $jsonFile" -ForegroundColor Yellow
    $resources = [collections.arraylist]@()
    $azResourceGroupLocation = @($configuredResources)[0].Location
    $resourceIds = @($configuredResources.ResourceId)

    # todo issue
    new-item -ItemType File -path $jsonFile -ErrorAction SilentlyContinue
    write-log "file exists:$((test-path $jsonFile))"
    write-log "resource ids: $resourceIds" -ForegroundColor green

    write-log "Export-AzResourceGroup -ResourceGroupName $resourceGroupName `
            -Path $jsonFile `
            -Force `
            -IncludeComments `
            -IncludeParameterDefaultValue `
            -Resource $resourceIds
    " -foregroundcolor Blue
    Export-AzResourceGroup -ResourceGroupName $resourceGroupName `
        -Path $jsonFile `
        -Force `
        -IncludeComments `
        -IncludeParameterDefaultValue `
        -Resource $resourceIds
    
    return

    # todo cleanup if not implementing latest api
    write-log "getting latest api versions" -ForegroundColor yellow
    $resourceProviders = Get-AzResourceProvider -Location $azResourceGroupLocation

    write-log "getting configured api versions" -ForegroundColor green

    $currentConfig = Get-Content -raw $jsonFile | convertfrom-json
    $currentApiVersions = $currentConfig.resources | select-object type, apiversion | sort-object -Unique type
    write-log ($currentApiVersions | format-list * | out-string)
    remove-item $jsonFile -Force
    
    foreach ($azResource in $configuredResources) {
        write-log "azresource by id: $($azResource | format-list * | out-string)" -verbose
        $resourceApiVersion = $null

        if (!$useLatestApiVersion -and $currentApiVersions.type.contains($azResource.ResourceType)) {
            $rpType = $currentApiVersions | where-object type -ieq $azResource.ResourceType | select-object apiversion
            $resourceApiVersion = $rpType.ApiVersion
            write-log "using configured resource schema api version: $resourceApiVersion to enumerate and save resource: `r`n`t$($azResource.ResourceId)" -ForegroundColor green
        }

        if ($useLatestApiVersion -or !$resourceApiVersion) {
            $resourceProvider = $resourceProviders | where-object ProviderNamespace -ieq $azResource.ResourceType.split('/')[0]
            $rpType = $resourceProvider.ResourceTypes | where-object ResourceTypeName -ieq $azResource.ResourceType.split('/')[1]
            $resourceApiVersion = $rpType.ApiVersions[0]
            write-log "using latest schema api version: $resourceApiVersion to enumerate and save resource: `r`n`t$($azResource.ResourceId)" -ForegroundColor yellow
        }

        $azResource = get-azresource -Id $azResource.ResourceId -ExpandProperties -ApiVersion $resourceApiVersion
        write-log "azresource by id and version: $($azResource | format-list * | out-string)" -verbose

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

    if (!(create-jsonTemplate -resources $resources -jsonFile $jsonFile)) { return }
    return
    # end todo cleanup
}

function enum-allResources() {
    $resources = [collections.arraylist]::new()

    write-log "getting resource group cluster $resourceGroupName"
    $clusterResource = enum-clusterResource
    if (!$clusterResource) {
        write-log "unable to enumerate cluster. exiting" -isError
        return $null
    }
    [void]$resources.Add($clusterResource.Id)

    write-log "getting scalesets $resourceGroupName"
    $vmssResources = @(enum-vmssResources $clusterResource)
    if ($vmssResources.Count -lt 1) {
        write-log "unable to enumerate vmss. exiting" -isError
        return $null
    }
    else {
        [void]$resources.AddRange(@($vmssResources.Id))
    }

    write-log "getting storage $resourceGroupName"
    $storageResources = @(enum-storageResources $clusterResource)
    if ($storageResources.count -lt 1) {
        write-log "unable to enumerate storage. exiting" -isError
        return $null
    }
    else {
        [void]$resources.AddRange(@($storageResources.Id))
    }
    
    write-log "getting virtualnetworks $resourceGroupName"
    $vnetResources = @(enum-vnetResourceIds $vmssResources)
    if ($vnetResources.count -lt 1) {
        write-log "unable to enumerate vnets. exiting" -isError
        return $null
    }
    else {
        [void]$resources.AddRange($vnetResources)
    }

    write-log "getting loadbalancers $resourceGroupName"
    $lbResources = @(enum-lbResourceIds $vmssResources)
    if ($lbResources.count -lt 1) {
        write-log "unable to enumerate loadbalancers. exiting" -isError
        return $null
    }
    else {
        [void]$resources.AddRange($lbResources)
    }

    write-log "getting ip addresses $resourceGroupName"
    $ipResources = @(enum-ipResourceIds $lbResources)
    if ($ipResources.count -lt 1) {
        write-log "unable to enumerate ips." -isWarning
        #return $null
    }
    else {
        [void]$resources.AddRange($ipResources)
    }

    write-log "getting key vaults $resourceGroupName"
    $kvResources = @(enum-kvResourceIds $vmssResources)
    if ($kvResources.count -lt 1) {
        write-log "unable to enumerate key vaults." -isWarning
        #return $null
    }
    else {
        [void]$resources.AddRange($kvResources)
    }

    write-log "getting nsgs $resourceGroupName"
    $nsgResources = @(enum-nsgResourceIds $vmssResources)
    if ($nsgResources.count -lt 1) {
        write-log "unable to enumerate nsgs." -isWarning
        #return $null
    }
    else {
        [void]$resources.AddRange($nsgResources)
    }

    if ($excludeResourceNames) {
        $resources = $resources | where-object Name -NotMatch "$($excludeResourceNames -join "|")"
    }

    return $resources | sort-object -Unique
}
function enum-clusterResource() {
    $clusters = @(get-azresource -ResourceGroupName $resourceGroupName `
            -ResourceType 'Microsoft.ServiceFabric/clusters' `
            -ExpandProperties)
    $clusterResource = $null
    $count = 1
    $number = 0

    write-log "all clusters $clusters" -verbose
    if ($clusters.count -gt 1) {
        foreach ($cluster in $clusters) {
            write-log "$($count). $($cluster.name)"
            $count++
        }
        
        $number = [convert]::ToInt32((read-host "enter number of the cluster to query or ctrl-c to exit:"))
        if ($number -le $count) {
            $clusterResource = $cluster[$number - 1].Name
            write-log $clusterResource
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

    write-log "using cluster resource $clusterResource" -ForegroundColor Green
    return $clusterResource
}

function enum-ipResourceIds($lbResources) {
    $resources = [collections.arraylist]::new()

    foreach ($lbResource in $lbResources) {
        write-log "checking lbResource for ip config $lbResource"
        $lb = get-azresource -ResourceId $lbResource -ExpandProperties
        foreach ($fec in $lb.Properties.frontendIPConfigurations) {
            if ($fec.properties.publicIpAddress) {
                $id = $fec.properties.publicIpAddress.id
                write-log "adding public ip: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }
    }

    write-log "ip resources $resources)" -verbose
    return $resources.ToArray() | sort-object -Unique
}

function enum-kvResourceIds($vmssResources) {
    $resources = [collections.arraylist]::new()

    foreach ($vmssResource in $vmssResources) {
        write-log "checking vmssResource for key vaults $($vmssResource.Name)"
        foreach ($id in $vmssResource.Properties.virtualMachineProfile.osProfile.secrets.sourceVault.id) {
            write-log "adding kv id: $id" -ForegroundColor green
            [void]$resources.Add($id)
        }
    }

    write-log "kv resources $resources)" -verbose
    return $resources.ToArray() | sort-object -Unique
}

function enum-lbResourceIds($vmssResources) {
    $resources = [collections.arraylist]::new()

    foreach ($vmssResource in $vmssResources) {
        # get nic for vnet/subnet and lb
        write-log "checking vmssResource for network config $($vmssResource.Name)"
        foreach ($nic in $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations) {
            foreach ($ipconfig in $nic.properties.ipConfigurations) {
                $id = [regex]::replace($ipconfig.properties.loadBalancerBackendAddressPools.id, '/backendAddressPools/.+$', '')
                write-log "adding lb id: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }
    }

    write-log "lb resources $resources)" -verbose
    return $resources.ToArray() | sort-object -Unique
}

function enum-nsgResourceIds($vmssResources) {
    $resources = [collections.arraylist]::new()

    foreach ($vnetId in $vnetResources) {
        $vnetresource = @(get-azresource -ResourceId $vnetId -ExpandProperties)
        write-log "checking vnet resource for nsg config $($vnetresource.Name)"
        foreach ($subnet in $vnetResource.Properties.subnets) {
            if ($subnet.properties.networkSecurityGroup.id) {
                $id = $subnet.properties.networkSecurityGroup.id
                write-log "adding nsg id: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }

    }

    write-log "nsg resources $resources" -verbose
    return $resources.ToArray() | sort-object -Unique
}

function enum-storageResources($clusterResource) {
    $resources = [collections.arraylist]::new()
    
    $sflogs = $clusterResource.Properties.diagnosticsStorageAccountConfig.storageAccountName
    write-log "cluster sflogs storage account $sflogs"

    $scalesets = enum-vmssResources($clusterResource)
    $sfdiags = @(($scalesets.Properties.virtualMachineProfile.extensionProfile.extensions.properties | where-object type -eq 'IaaSDiagnostics').settings.storageAccount) | Sort-Object -Unique
    write-log "cluster sfdiags storage account $sfdiags"
  
    $storageResources = @(get-azresource -ResourceGroupName $resourceGroupName `
            -ResourceType 'Microsoft.Storage/storageAccounts' `
            -ExpandProperties)

    $global:sflogs = $storageResources | where-object name -ieq $sflogs
    $global:sfdiags = @($storageResources | where-object name -ieq $sfdiags)
    
    [void]$resources.add($global:sflogs)
    foreach ($sfdiag in $global:sfdiags) {
        [void]$resources.add($sfdiag)
    }
    
    write-log "storage resources $resources" -verbose
    return $resources.ToArray() | sort-object name -Unique
}

function enum-vmssResources($clusterResource) {
    $nodeTypes = $clusterResource.Properties.nodeTypes
    write-log "cluster nodetypes $($nodeTypes| create-json)"
    $vmssResources = [collections.arraylist]::new()

    $clusterEndpoint = $clusterResource.Properties.clusterEndpoint
    write-log "cluster id $clusterEndpoint" -ForegroundColor Green
    
    if (!$nodeTypes -or !$clusterEndpoint) {
        return $null
    }

    $resources = @(get-azresource -ResourceGroupName $resourceGroupName `
            -ResourceType 'Microsoft.Compute/virtualMachineScaleSets' `
            -ExpandProperties)

    write-log "vmss resources $resources" -verbose

    foreach ($resource in $resources) {
        $vmsscep = ($resource.Properties.virtualMachineProfile.extensionprofile.extensions.properties.settings | Select-Object clusterEndpoint).clusterEndpoint
        if ($vmsscep -ieq $clusterEndpoint) {
            write-log "adding vmss resource $($resource | create-json)" -ForegroundColor Cyan
            [void]$vmssResources.Add($resource)
        }
        else {
            write-log "vmss assigned to different cluster $vmsscep" -isWarning
        }
    }

    return $vmssResources.ToArray() | sort-object name -Unique
}

function enum-vnetResourceIds($vmssResources) {
    $resources = [collections.arraylist]::new()

    foreach ($vmssResource in $vmssResources) {
        # get nic for vnet/subnet and lb
        write-log "checking vmssResource for network config $($vmssResource.Name)"
        foreach ($nic in $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations) {
            foreach ($ipconfig in $nic.properties.ipConfigurations) {
                $id = [regex]::replace($ipconfig.properties.subnet.id, '/subnets/.+$', '')
                write-log "adding vnet id: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }
    }

    write-log "vnet resources $resources" -verbose
    return $resources.ToArray() | sort-object -Unique
}

function get-clusterResource($currentConfig) {
    $resources = @($currentConfig.resources | Where-Object type -ieq 'Microsoft.ServiceFabric/clusters')
    
    if ($resources.count -ne 1) {
        write-log "unable to find cluster resource" -isError
    }

    write-log "returning cluster resource $resources" -verbose
    return $resources[0]
}

function get-lbResources($currentConfig) {
    $resources = @($currentConfig.resources | Where-Object type -ieq 'Microsoft.Network/loadBalancers')
    
    if ($resources.count -eq 0) {
        write-log "unable to find lb resource" -isError
    }

    write-log "returning lb resource $resources" -verbose
    return $resources
}

function get-fromParametersSection($currentConfig, $parameterName) {
    $parameters = @($currentConfig.parameters)
    $currentErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'silentlycontinue'

    $results = @($parameters.$parameterName.defaultValue)
    $ErrorActionPreference = $currentErrorPreference
    
    if(!$results){
        write-warning "no matching values found in parameters section for $parameterName"
    }
    if(@($results).count -gt 1){
        write-warning "multiple matching values found in parameters section for $parameterName `r`n $($results |create-json)"
    }

    write-host "get-fromParametersSection: returning: $($results | create-json)" -ForegroundColor Magenta
    return $results
}

function get-parameterizedNameFromValue($resourceObject) {
    if ([regex]::IsMatch($resourceobject, "\[parameters\('(.+?)'\)\]", [text.regularExpressions.regexOptions]::ignorecase)) {
        return [regex]::match($resourceobject, "\[parameters\('(.+?)'\)\]", [text.regularExpressions.regexOptions]::ignorecase).groups[1].Value
    }
    return $null
}

function get-resourceParameterValue($resource, $name) {
    $retval = $null
    foreach ($psObjectProperty in $resource.psobject.Properties) {
        write-log "checking parameter name $psobjectProperty" -verbose

        if (($psObjectProperty.Name -imatch $name)) {
            $parameterValues = @($psObjectProperty.Name)
            if ($parameterValues.Count -eq 1) {
                $parameterValue = $psObjectProperty.Value
                if (!($parameterValue)) {
                    return [string]::Empty
                }
                return $parameterValue
            }
            else {
                write-log "multiple parameter names found in resource. returning" -isError
                return $null
            }
        }
        elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Management.Automation.PSCustomObject') {
            $retval = get-resourceParameterValue -resource $psObjectProperty.Value -name $name
        }
        else {
            write-log "get-resourceParameterValue: skipping. property name:$($psObjectProperty.Name) name:$name type:$($psObjectProperty.TypeNameOfValue)" -verbose
        }
    }

    write-log "get-resourceParameterValue: returning $retval" -verbose
    return $retval
}
function get-resourceParameterValueObject($resource, $name) {
    $retval = $null
    foreach ($psObjectProperty in $resource.psobject.Properties) {
        write-log "checking parameter object $psobjectProperty" -verbose

        if (($psObjectProperty.Name -imatch $name)) {
            $parameterValues = @($psObjectProperty.Name)
            if ($parameterValues.Count -eq 1) {
                write-log "returning parameter object $psobjectProperty" -verbose
                $retval = $resource.psobject.Properties[$psObjectProperty.name]
                break
            }
            else {
                write-log "multiple parameter names found in resource. returning" -isError
                $retval = $null
                break
            }
        }
        elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Management.Automation.PSCustomObject') {
            $retval = get-resourceParameterValueObject -resource $psObjectProperty.Value -name $name
        }
        else {
            write-log "get-resourceParameterValueObject: skipping. property name:$($psObjectProperty.Name) name:$name type:$($psObjectProperty.TypeNameOfValue)" -verbose
        }
    }

    write-log "get-resourceParameterValueObject: returning $retval" -verbose
    return $retval
}

function get-vmssExtensions($vmssResource, $extensionType = $null) {
    $extensions = @($vmssResource.properties.virtualMachineProfile.extensionProfile.extensions)
    $results = [collections.arraylist]::new()

    if ($extensionType) {
        foreach ($extension in $extensions) {
            if ($extension.properties.type -ieq $extensionType) {
                [void]$results.Add($extension)
            }
        }
    }
    else {
        $results = $extensions
    }

    if ($results.Count -lt 1) {
        write-log "unable to find extension in vmss resource $($vmssResource.name) $extensionType" -isError
    }

    return $results.ToArray()
}

function get-vmssResources($currentConfig) {
    $resources = @($currentConfig.resources | Where-Object type -ieq 'Microsoft.Compute/virtualMachineScaleSets')
    if ($resources.count -eq 0) {
        write-log "unable to find vmss resource" -isError
    }
    write-log "returning vmss resource $resources" -verbose
    return $resources
}

function get-vmssResourcesByNodeType($currentConfig, $nodetypeResource) {
    $vmssResources = get-vmssResources -currentConfig $currentConfig
    $vmssByNodeType = [collections.arraylist]::new()

    foreach ($vmssResource in $vmssResources) {
        $extension = get-vmssExtensions -vmssResource $vmssResource -extensionType 'ServiceFabricNode'
        $parameterizedName = get-parameterizedNameFromValue $extension.properties.settings.nodetyperef

        if ($parameterizedName) {
            $nodetypeName = get-fromParametersSection $currentConfig -parameterName $parameterizedName
        }
        else {
            $nodetypeName = $extension.properties.settings.nodetyperef
        }

        if ($nodetypeName -ieq $nodetypeResource.name) {
            write-log "found scaleset by nodetyperef $nodetypeName" -foregroundcolor Cyan
            [void]$vmssByNodeType.add($vmssResource)
        }
    }

    return $vmssByNodeType.ToArray()
}

function modify-clusterResourceAddNodeType($currentConfig) {
    $clusterResource = get-clusterResource $currentConfig
    
    write-log "setting `$clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter"
    $clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter
    
    write-log "setting `$clusterResource.properties.upgradeMode = Manual"
    $clusterResource.properties.upgradeMode = "Manual"
    $reference = "[reference($(create-parameterizedName -parameterName 'name' -resource $clusterResource))]"
    add-outputs -currentConfig $currentConfig -name 'clusterProperties' -value $reference -type 'object'
}


function modify-clusterResourceRedeploy($currentConfig) {
    $sflogsParameter = create-parameterizedName -parameterName 'name' -resource $global:sflogs -withbrackets
    $clusterResource = get-clusterResource $currentConfig
    
    write-log "setting `$clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter"
    $clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter
    
    if ($clusterResource.properties.upgradeMode -ieq 'Automatic') {
        write-log "removing value cluster code version $($clusterResource.properties.clusterCodeVersion)" -ForegroundColor Yellow
        $clusterResource.properties.psobject.Properties.remove('clusterCodeVersion')
    }
    
    $reference = "[reference($(create-parameterizedName -parameterName 'name' -resource $clusterResource))]"
    add-outputs -currentConfig $currentConfig -name 'clusterProperties' -value $reference -type 'object'
}

function modify-ipAddressesRedeploy($currentConfig) {
    # add ip address dns parameter
    $metadataDescription = 'this name must be unique in deployment region.'
    $dnsSettings = add-parameterNameByResourceType -currentConfig $currentConfig -type "Microsoft.Network/publicIPAddresses" -name 'domainNameLabel' -metadataDescription $metadataDescription
    $fqdn = add-parameterNameByResourceType -currentConfig $currentConfig -type "Microsoft.Network/publicIPAddresses" -name 'fqdn' -metadataDescription $metadataDescription
}

function modify-lbResources($currenConfig) {
    $lbResources = get-lbResources $currentConfig
    foreach ($lbResource in $lbResources) {
        # fix backend pool
        write-log "fixing exported lb resource $($lbresource | create-json)"
        $parameterName = get-parameterizedNameFromValue $lbresource.name
        if ($parameterName) {
            $name = $currentConfig.parameters.$parametername.defaultValue
        }

        if (!$name) {
            $name = $lbResource.name
        }

        $lb = get-azresource -ResourceGroupName $resourceGroupName -Name $name -ExpandProperties -ResourceType 'Microsoft.Network/loadBalancers'
        $dependsOn = [collections.arraylist]::new()

        write-log "removing backendpool from lb dependson"
        foreach ($depends in $lbresource.dependsOn) {
            if ($depends -inotmatch $lb.Properties.backendAddressPools.Name) {
                [void]$dependsOn.Add($depends)
            }
        }
        $lbResource.dependsOn = $dependsOn.ToArray()
        write-log "lbResource modified dependson: $($lbResource.dependson | create-json)" -ForegroundColor Yellow
        
    }
}

function modify-lbResourcesRedeploy($currenConfig) {
    $lbResources = get-lbResources $currentConfig
    foreach ($lbResource in $lbResources) {
        # fix dupe pools and rules
        if ($lbResource.properties.inboundNatPools) {
            write-log "removing natrules: $($lbResource.properties.inboundNatRules | create-json)" -ForegroundColor Yellow
            [void]$lbResource.properties.psobject.Properties.Remove('inboundNatRules')
        }
    }
}

function modify-storageResourcesDeploy($currentConfig) {
    $metadataDescription = 'this name must be unique in deployment region.'
    $parameterExclusions = [collections.arraylist]::new()
    $sflogsParameter = create-parametersName -resource $global:sflogs
    [void]$parameterExclusions.Add($sflogsParameter)

    add-toParametersSection -currentConfig $currentConfig `
        -parameterName $sflogsParameter `
        -parameterValue $global:defaultSflogsValue `
        -metadataDescription $metadataDescription

    foreach ($sfdiag in $global:sfdiags) {
        $sfdiagParameter = create-parametersName -resource $sfdiag
        [void]$parameterExclusions.Add($sfdiagParameter)
        add-toParametersSection -currentConfig $currentConfig `
            -parameterName $sfdiagParameter `
            -parameterValue $global:defaultSfdiagsValue `
            -metadataDescription $metadataDescription
    }

    return $parameterExclusions.ToArray()
}

function modify-vmssResources($currenConfig) {
    $vmssResources = get-vmssResources $currentConfig
   
    foreach ($vmssResource in $vmssResources) {

        write-log "modifying dependson"
        $dependsOn = [collections.arraylist]::new()
        $subnetIds = @($vmssResource.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.ipconfigurations.properties.subnet.id)

        foreach ($depends in $vmssResource.dependsOn) {
            if ($depends -imatch 'backendAddressPools') { continue }

            if ($depends -imatch 'Microsoft.Network/loadBalancers') {
                [void]$dependsOn.Add($depends)
            }
            # example depends "[resourceId('Microsoft.Network/virtualNetworks/subnets', parameters('virtualNetworks_VNet_name'), 'Subnet-0')]"
            if ($subnetIds.contains($depends)) {
                write-log 'cleaning subnet dependson' -ForegroundColor Yellow
                $depends = $depends.replace("/subnets'", "/'")
                $depends = [regex]::replace($depends, "\), '.+?'\)\]", "))]")
                [void]$dependsOn.Add($depends)
            }
        }
        $vmssResource.dependsOn = $dependsOn.ToArray()
        write-log "vmssResource modified dependson: $($vmssResource.dependson | create-json)" -ForegroundColor Yellow
    }
}

function modify-vmssResourcesDeploy($currenConfig) {
    $vmssResources = get-vmssResources $currentConfig
    foreach ($vmssResource in $vmssResources) {
        $extension = get-vmssExtensions -vmssResource $vmssResource -extensionType 'ServiceFabricNode'
        $clusterResource = get-clusterResource $currentConfig

        $parameterizedName = create-parameterizedName -parameterName 'name' -resource $clusterResource
        $newName = "[reference($parameterizedName).clusterEndpoint]"

        write-log "setting cluster endpoint to $newName"
        set-resourceParameterValue -resource $extension.properties.settings -name 'clusterEndpoint' -newValue $newName
        # remove clusterendpoint parameter
        remove-unusedParameters -currentConfig $currentConfig
    }
}

function modify-vmssResourcesRedeploy($currenConfig) {
    $vmssResources = get-vmssResources $currentConfig
   
    foreach ($vmssResource in $vmssResources) {
        # add protected settings
        add-vmssProtectedSettings($vmssResource)

        # remove mma
        $extensions = [collections.arraylist]::new()
        foreach ($extension in $vmssResource.properties.virtualMachineProfile.extensionProfile.extensions) {
            if ($extension.properties.type -ieq 'MicrosoftMonitoringAgent') {
                continue
            }
            if ($extension.properties.type -ieq 'ServiceFabricNode') {
                write-log "parameterizing cluster endpoint"
                add-parameter -currentConfig $currentConfig -resource $vmssResource -name 'clusterEndpoint' -resourceObject $extension.properties.settings
            }
            [void]$extensions.Add($extension)
        }    
        $vmssResource.properties.virtualMachineProfile.extensionProfile.extensions = $extensions

        write-log "modifying dependson"
        $dependsOn = [collections.arraylist]::new()
        $subnetIds = @($vmssResource.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.ipconfigurations.properties.subnet.id)

        foreach ($depends in $vmssResource.dependsOn) {
            if ($depends -imatch 'backendAddressPools') { continue }

            if ($depends -imatch 'Microsoft.Network/loadBalancers') {
                [void]$dependsOn.Add($depends)
            }
            # example depends "[resourceId('Microsoft.Network/virtualNetworks/subnets', parameters('virtualNetworks_VNet_name'), 'Subnet-0')]"
            if ($subnetIds.contains($depends)) {
                write-log 'cleaning subnet dependson' -ForegroundColor Yellow
                $depends = $depends.replace("/subnets'", "/'")
                $depends = [regex]::replace($depends, "\), '.+?'\)\]", "))]")
                [void]$dependsOn.Add($depends)
            }
        }
        $vmssResource.dependsOn = $dependsOn.ToArray()
        write-log "vmssResource modified dependson: $($vmssResource.dependson | create-json)" -ForegroundColor Yellow
            
        write-log "parameterizing hardware sku"
        add-parameter -currentConfig $currentConfig -resource $vmssResource -name 'name' -aliasName 'hardwareSku' -resourceObject $vmssResources.sku
            
        write-log "parameterizing hardware capacity"
        add-parameter -currentConfig $currentConfig -resource $vmssResource -name 'capacity' -resourceObject $vmssResources.sku -type 'int'

        write-log "parameterizing os sku"
        add-parameter -currentConfig $currentConfig -resource $vmssResource -name 'sku' -aliasName 'osSku' -resourceObject $vmssResource.properties.virtualMachineProfile.storageProfile.imageReference

        if (!($vmssResource.properties.virtualMachineProfile.osProfile.psobject.Properties | where-object name -ieq 'adminPassword')) {
            write-log "adding admin password"
            $vmssResource.properties.virtualMachineProfile.osProfile | Add-Member -MemberType NoteProperty -Name 'adminPassword' -Value $adminPassword
            add-parameter -currentConfig $currentConfig `
                -resource $vmssResource `
                -name 'adminPassword' `
                -resourceObject $vmssResource.properties.virtualMachineProfile.osProfile `
                -metadataDescription 'password must be set before deploying template.'
            $parameterizedName = create-parameterizedName -parameterName 'adminPassword' -resource $vmssResource -withbrackets
            # add-outputs -currentConfig $currentConfig -name 'adminPassword' -value $parameterizedName -type 'string'
        }
    }
}

function parameterize-nodetype($currentConfig, $nodetype, $parameterName, $parameterValue = $null, $type = 'string') {
    $clusterResource = get-clusterResource $currentConfig
    #$vmssResources = get-vmssResources $currentConfig
    write-host "parameterize-nodetype($currentConfig, $nodetype, $parameterName, $parameterValue, $type)"

    if (!$parameterValue) {
        $parameterValue = get-resourceParameterValue -resource $nodetype -name $parameterName
        #$parameterValueObject = get-resourceParameterValueObject -resource $nodetype -name $parameterName
        #$parameterValue = $parameterValueObject.Value
        #$type = $parameterValueObject.TypeNameOfValue
    }
    
    write-log "setting $parameterName to $parameterValue for $($nodetype.name)" -foregroundcolor Magenta

    # add-parameter -currentConfig $currentConfig `
    #     -resource $clusterResource `
    #     -name $parameterName `
    #     -resourceObject $nodetype `
    #     -type $type

    $vmssResources = get-vmssResourcesByNodeType -currentConfig $currentConfig -nodetypeResource $nodetype

    foreach ($vmssResource in $vmssResources) {
        write-log "add-parameter -currentConfig $currentConfig `
            -resource $vmssResource `
            -name $parameterName `
            -resourceObject $nodetype `
            -value $parameterValue `
            -type $type
        "
        add-parameter -currentConfig $currentConfig `
            -resource $vmssResource `
            -name $parameterName `
            -resourceObject $nodetype `
            -value $parameterValue `
            -type $type

        $extension = get-vmssExtensions -vmssResource $vmssResource -extensionType 'ServiceFabricNode'

        write-log "add-parameter -currentConfig $currentConfig `
            -resource $clusterResource `
            -name $parameterName `
            -resourceObject $($extension.properties.settings) `
            -value $parameterValue `
            -type $type
        "
        add-parameter -currentConfig $currentConfig `
            -resource $clusterResource `
            -name $parameterName `
            -resourceObject $extension.properties.settings `
            -value $parameterValue `
            -type $type
    }
}

function parameterize-nodeTypes($currentConfig) {
    # todo. should validation be here? how many nodetypes
    $clusterResource = get-clusterResource $currentConfig
    $nodetypes = [collections.arraylist]::new()
    $nodetypes.AddRange(@($clusterResource.properties.nodetypes))

    if ($nodetypes.Count -lt 1) {
        write-log "no nodetypes detected!" -isError
        return
    }

    write-log "current nodetypes $($nodetypes.name)" -ForegroundColor Green
    $primarynodetypes = @($nodetypes | Where-Object isPrimary -eq $true)

    if ($primarynodetypes.count -eq 0) {
        write-log "unable to find primary nodetype" -isError
    }
    elseif ($primarynodetypes.count -gt 1) {
        write-log "more than one primary node type detected!" -isError
    }
    
    foreach ($nodetype in $nodetypes) {
        parameterize-nodetype -currentConfig $currentConfig -nodetype $nodetype -parameterName 'durabilityLevel'
        parameterize-nodetype -currentConfig $currentConfig -nodetype $nodetype -parameterName 'isPrimary' -type 'bool'
        # todo parameterize name? only the new nodetype name should be parameterized
        # this will be a copy of existing nodetype that will be used with new associated scaleset by nodetyperef
        # existing nodetypes / scalesets should *not* have nodetype.name parameterized
        #parameterize-nodetype -currentConfig $currentConfig -nodetype $nodetype -parameterName 'name'
    } 

    write-log "adding new nodetype" -foregroundcolor Cyan
    $newPrimaryNodeType = $primarynodetypes.clone()[0]
    $existingVmssNodeTypeRef = @(get-vmssResourcesByNodeType -currentConfig $currentConfig -nodetypeResource $newPrimaryNodeType)

    if($existingVmssNodeTypeRef.count -lt 1){
        write-log "unable to find existing nodetypes by nodetyperef" -isError
        return
    }

    #$newSecondaryNodeType = $nodetypes.clone()[0]
    $parameterizedName = get-parameterizedNameFromValue -resourceObject $newPrimaryNodeType.name

    if (!$parameterizedName) {
        $newNodeTypeExistingName = get-resourceParameterValue -resource $newPrimaryNodeType -name 'name'
        $parameterizedName = create-parameterizedName -parameterName $newNodeTypeExistingName -resource $existingVmssNodeTypeRef[0]
        add-toParametersSection -currentConfig $currentConfig -parameterName $parameterizedName -parameterValue $newNodeTypeExistingName

        write-log "parameterizing new nodetype name" -foregroundcolor Cyan
        parameterize-nodetype -currentConfig $currentConfig -nodetype $newPrimaryNodeType -parameterName 'name' -parameterValue $parameterizedName
    }
    
    $nodetypes.Add($newPrimaryNodeType)
    $clusterResource.properties.nodetypes = $nodetypes
}

function remove-duplicateResources($currentConfig) {
    # fix up deploy errors by removing duplicated sub resources on root like lb rules by
    # removing any 'type' added by export-azresourcegroup that was not in the $global:configuredRGResources
    $currentResources = [collections.arraylist]::new() #$currentConfig.resources | create-json | convertfrom-json

    $resourceTypes = $global:configuredRGResources.resourceType
    foreach ($resource in $currentConfig.resources.GetEnumerator()) {
        write-log "checking exported resource $($resource.name)" -ForegroundColor Magenta
        write-log "checking exported resource $($resource | create-json)" -verbose
        if ($resourceTypes.Contains($resource.type)) {
            write-log "adding exported resource $($resource.name)" -ForegroundColor Cyan
            write-log "adding exported resource $($resource | create-json)" -verbose
            [void]$currentResources.Add($resource)
        }
    }
    $currentConfig.resources = $currentResources

}

function remove-jobs() {
    try {
        foreach ($job in get-job) {
            write-log "removing job $($job.Name)" -report $global:scriptName
            write-log $job -report $global:scriptName
            $job.StopJob()
            Remove-Job $job -Force
        }
    }
    catch {
        write-log "error:$($Error | out-string)"
        $error.Clear()
    }
}

function remove-unusedParameters($currentConfig) {
    $parametersRemoveList = [collections.arraylist]::new()
    #serialize and copy
    $currentConfigResourcejson = $currentConfig | create-json
    $currentConfigJson = $currentConfigResourcejson | convertfrom-json

    # remove parameters section but keep everything else like variables, resources, outputs
    $currentConfigJson.psobject.properties.remove('Parameters')
    $currentConfigResourcejson = $currentConfigJson | create-json

    foreach ($psObjectProperty in $currentConfig.parameters.psobject.Properties) {
        $parameterizedName = "parameters\('$($psObjectProperty.name)'\)"
        write-log "checking to see if $parameterizedName is being used"
        if ([regex]::IsMatch($currentConfigResourcejson, $parameterizedName, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            write-log "$parameterizedName is being used" -verbose
            continue
        }
        write-log "removing $parameterizedName" -verbose
        [void]$parametersRemoveList.Add($psObjectProperty)
    }

    foreach ($parameter in $parametersRemoveList) {
        write-log "removing $($parameter.name)" -isWarning
        $currentConfig.parameters.psobject.Properties.Remove($parameter.name)
    }
}

function set-resourceParameterValue($resource, $name, $newValue) {
    $retval = $false
    foreach ($psObjectProperty in $resource.psobject.Properties) {
        write-log "checking parameter name $psobjectProperty" -verbose

        if (($psObjectProperty.Name -imatch $name)) {
            $parameterValues = @($psObjectProperty.Name)
            if ($parameterValues.Count -eq 1) {
                $parameterValue = $psObjectProperty.Value
                $psObjectProperty.Value = $newValue
                return $true
            }
            else {
                write-log "multiple parameter names found in resource. returning" -isError
                return $false
            }
        }
        elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Management.Automation.PSCustomObject') {
            $retval = set-resourceParameterValue -resource $psObjectProperty.Value -name $name -newValue $newValue
        }
    }

    return $retval
}

function get-update($updateUrl) {
    write-log "get-update:checking for updated script: $($updateUrl)"
    $gitScript = $null
    $scriptFile = $MyInvocation.ScriptName

    $error.Clear()
    $gitScript = Invoke-RestMethod -Uri $updateUrl 

    if (!$error -and $gitScript) {
        write-log "reading $scriptFile"
        $currentScript = get-content -raw $scriptFile
    
        write-log "comparing export and current functions" -verbose
        if ([string]::Compare([regex]::replace($gitScript, "\s", ""), [regex]::replace($currentScript, "\s", "")) -eq 0) {
            write-log "no change to $scriptFile. skipping update." -ForegroundColor Cyan
            $error.Clear()
            return $false
        }

        $error.clear()
        out-file -inputObject $gitScript -FilePath $scriptFile -Force

        if (!$error) {
            write-log "$scriptFile has been updated. restart script." -ForegroundColor yellow
            return $true
        }

        write-log "$scriptFile has not been updated." -isWarning
    }
    else {
        write-log "error checking for updated script $error" -isWarning
        $error.Clear()
        return $false
    }
}

function verify-config($currentConfig, $templateParameterFile) {
    $json = '.\verify-config.json'
    $currentConfig | create-json | out-file -FilePath $json -Force

    write-log "Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
        -Mode Incremental `
        -Templatefile $json `
        -TemplateParameterFile $templateParameterFile `
        -Verbose
    " -ForegroundColor Green

    Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
        -Mode Incremental `
        -TemplateFile $json `
        -TemplateParameterFile $templateParameterFile `
        -Verbose

    remove-item $json
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

function write-log([object]$data, [ConsoleColor]$foregroundcolor = [ConsoleColor]::Gray, [switch]$isError, [switch]$isWarning, [switch]$verbose) {
    if (!$data) { return }
    $stringData = [text.stringbuilder]::new()
    $verboseTag = ''
    if ($verbose) { $verboseTag = 'verbose:' }
    
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
                write-log (@($job.Warning.ReadAll()) -join "`r`n") -isWarning
                $stringData.appendline(@($job.Warning.ReadAll()) -join "`r`n")
                $stringData.appendline(($job | format-list * | out-string))
                $global:resourceWarnings++
            }
            if ($job.Error) {
                write-log (@($job.Error.ReadAll()) -join "`r`n") -isError
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
        $stringData = ("$((get-date).tostring('HH:mm:ss.fff')):$verboseTag$($data | format-list * | out-string)").trim()
    }

    if ($isError) {
        write-error $stringData
    }
    elseif ($isWarning) {
        Write-Warning $stringData
    }
    elseif ($verbose) {
        write-verbose $stringData
    }
    else {
        write-host $stringData -ForegroundColor $foregroundcolor
    }

    if ($logFile) {
        out-file -Append -inputobject $stringData.ToString() -filepath $logFile
    }
}

function write-progressInfo() {
    $ErrorActionPreference = $VerbosePreference = 'silentlycontinue'
    $errorCount = $error.Count
    write-log "Get-AzResourceGroupDeploymentOperation -ResourceGroupName $resourceGroupName -DeploymentName $deploymentName -ErrorAction silentlycontinue" -verbose
    $deploymentOperations = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $resourceGroupName -DeploymentName $deploymentName -ErrorAction silentlycontinue
    $status = "time elapsed:  $(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes" #`r`n"
    write-log $status -verbose

    $count = 0
    Write-Progress -Activity "deployment: $deploymentName resource patching: $resourceGroupName" -Status $status -id ($count++)

    if ($deploymentOperations) {
        write-log ("deployment operations: `r`n`t$($deploymentOperations | out-string)") -verbose
        
        foreach ($operation in $deploymentOperations) {
            write-log ($operation | create-json) -verbose
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
