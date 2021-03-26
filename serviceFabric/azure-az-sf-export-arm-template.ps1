<#
.SYNOPSIS
    powershell script to export existing azure arm template resource settings similar for portal deployed service fabric cluster
    works with cloudshell https://shell.azure.com/
    >help .\azure-az-sf-export-arm-template.ps1 -full

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-export-arm-template.ps1" -outFile "$pwd/azure-az-sf-export-arm-template.ps1";
    ./azure-az-sf-export-arm-template.ps1 -resourceGroupName <resource group name>

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
    Version    : 210322.1
    todo       : merge capacity and instance count
                 rename and hide unused parameters for addnodetype
                 update readmes
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
    #[Parameter(Mandatory = $true)]
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

$global:errors = [collections.arraylist]::new()
$global:warnings = [collections.arraylist]::new()
$global:functionDepth = 0
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
    if ($updateScript -and (get-update -updateUrl $updateUrl)) {
        return
    }

    if (!$resourceGroupName) {
        write-log "resource group name is required." -isError
        return
    }

    if ($detail) {
        $ErrorActionPreference = 'continue'
        $VerbosePreference = 'continue'
        $debugLevel = 'all'
    }

    if (!(check-module)) {
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
            write-log "zip file located here:$zipFile" -ForegroundColor Cyan
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

    if ($global:warnings) {
        write-log "global warnings:" -foregroundcolor Yellow
        write-log ($global:warnings | create-json) -isWarning
    }

    if ($global:errors) {
        write-log "global errors:" -foregroundcolor Red
        write-log ($global:errors | create-json) -isError
    }

    write-log "time elapsed:  $(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes`r`n"
    write-log 'finished. template stored in $global:resourceTemplateObj' -ForegroundColor Cyan
    if ($logFile) {
        write-log "log file saved to $logFile"
    }
}

function add-outputs($currentConfig, [string]$name, [string]$value, [string]$type = 'string') {
<#
.SYNOPSIS
    add element to outputs section of template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:add-outputs($currentConfig, $name, $value, $type = 'string'"
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
        [void]$currentConfig.outputs.add($name, $outputItem)
    }
    write-log "exit:add-outputs:added"
}

function add-parameterNameByResourceType($currentConfig, [string]$type, [string]$name, [string]$metadataDescription = '') {
<#
.SYNOPSIS
    add parameter name by resource type
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:add-parameterNameByResourceType($currentConfig, $type, $name, $metadataDescription = '')"
    $resources = @($currentConfig.resources | where-object 'type' -eq $type)
    $parameterNames = @{}

    foreach ($resource in $resources) {
        $parameterName = create-parametersName -resource $resource -name $name
        $parameterizedName = create-parameterizedName -parameterName $name -resource $resource -withbrackets
        $parameterNameValue = get-resourceParameterValue -resource $resource -name $name
        set-resourceParameterValue -resource $resource -name $name -newValue $parameterizedName

        if ($parameterNameValue -ne $null) {
            [void]$parameterNames.Add($parameterName, $parameterNameValue)
            write-log "add-parameterNameByResourceType:parametername added $parameterName : $parameterNameValue"
        }
    }

    write-log "add-parameterNameByResourceType:parameter names $parameterNames"
    foreach ($parameterName in $parameterNames.GetEnumerator()) {
        if (!(get-fromParametersSection -currentConfig $currentConfig -parameterName $parameterName.key)) {
            add-toParametersSection -currentConfig $currentConfig `
                -parameterName $parameterName.key `
                -parameterValue $parameterName.value `
                -metadataDescription $metadataDescription
        }
    }
    write-log "exit:add-parameterNameByResourceType"
}

function add-parameter($currentConfig, [object]$resource, [string]$name, [string]$aliasName = $name, [object]$resourceObject = $resource, [object]$value = $null, [string]$type = 'string', [string]$metadataDescription = '') {
<#
.SYNOPSIS
    add a new parameter based on $resource $name/$aliasName $resourceObject
    outputs: null
.OUTPUTS
    [null]
#>
    $parameterName = create-parametersName -resource $resource -name $aliasName
    $parameterizedName = create-parameterizedName -parameterName $aliasName -resource $resource -withbrackets
    $parameterNameValue = $value

    if (!$parameterNameValue) {
        $parameterNameValue = get-resourceParameterValue -resource $resourceObject -name $name
    }
    write-log "enter:add-parameter($currentConfig, $resource, $name, $aliasName = $name, $resourceObject = $resource, $value = $null, $type = 'string', $metadataDescription = '')"
    $null = set-resourceParameterValue -resource $resourceObject -name $name -newValue $parameterizedName

    if ($parameterNameValue -ne $null) {
        write-log "add-parameter:parameter name $parameterName"
        if (!(get-fromParametersSection -currentConfig $currentConfig -parameterName $parameterName)) {
            add-toParametersSection -currentConfig $currentConfig `
                -parameterName $parameterName `
                -parameterValue $parameterNameValue `
                -type $type `
                -metadataDescription $metadataDescription
        }
    }
    write-log "exit:add-parameter"
}

function add-toParametersSection ($currentConfig, [string]$parameterName, [string]$parameterValue, [string]$type = 'string', [string]$metadataDescription = '') {
<#
.SYNOPSIS
    add a new parameter based on $parameterName and $parameterValue to parameters Setion
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:add-toParametersSection:parameterName:$parameterName, parameterValue:$parameterValue, $type = 'string', $metadataDescription"
    $parameterObject = @{
        type         = $type
        defaultValue = $parameterValue 
        metadata     = @{description = $metadataDescription }
    }

    foreach ($psObjectProperty in $currentConfig.parameters.psobject.Properties) {
        if (($psObjectProperty.Name -ieq $parameterName)) {
            $psObjectProperty.Value = $parameterObject
            write-log "exit:add-toParametersSection:parameterObject value added to existing parameter:$parameterObject"
            return
        }
    }

    $currentConfig.parameters | Add-Member -MemberType NoteProperty -Name $parameterName -Value $parameterObject
    write-log "exit:add-toParametersSection:new parameter name:$parameterName added"
}

function add-vmssProtectedSettings([object]$vmssResource) {
<#
.SYNOPSIS
    add wellknown protectedSettings section to vmss resource for storageAccounts
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:add-vmssProtectedSettings$($vmssResource.name)"
    $sflogsParameter = create-parameterizedName -parameterName 'name' -resource $global:sflogs

    foreach ($extension in $vmssResource.properties.virtualMachineProfile.extensionPRofile.extensions) {
        if ($extension.properties.type -ieq 'ServiceFabricNode') {
            $extension.properties | Add-Member -MemberType NoteProperty -Name protectedSettings -Value @{
                StorageAccountKey1 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', $sflogsParameter),'$storageKeyApi').key1]"
                StorageAccountKey2 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', $sflogsParameter),'$storageKeyApi').key2]"
            }
            write-log "add-vmssProtectedSettings:added $($extension.properties.type) protectedsettings $($extension.properties.protectedSettings | create-json)" -ForegroundColor Magenta
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
            write-log "add-vmssProtectedSettings:added $($extension.properties.type) protectedsettings $($extension.properties.protectedSettings | create-json)" -ForegroundColor Magenta
        }
    }
    write-log "exit:add-vmssProtectedSettings"
}

function check-module() {
<#
.SYNOPSIS
    checks for proper azure az modules
    outputs: bool
.OUTPUTS
    [bool]
#>
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
<#
.SYNOPSIS
    creates new addnodetype template with modifications based on redeploy template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:create-addNodeTypeTemplate"
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
    write-log "exit:create-addNodeTypeTemplate"
}

function create-currentTemplate($currentConfig) {
<#
.SYNOPSIS
    creates new current template with modifications based on raw export template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:create-currentTemplate"
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
    write-log "exit:create-currentTemplate"
}

function create-exportTemplate() {
<#
.SYNOPSIS
    creates new export template from resource group
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:create-exportTemplate"
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
    write-log "exit:create-exportTemplate"
    return $currentConfig
}

function create-json(
    [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [object]$inputObject,
    [int]$depth = 99
) {
<#
.SYNOPSIS
    creates json string compatible with ps 5.6 - 7.x '\u0027' issue
    inputs: object
    outputs: string
.INPUTS
    [object]
.OUTPUTS
    [string]
#>   
    $currentWarningPreference = $WarningPreference
    $WarningPreference = 'SilentlyContinue'
    
    # to fix \u0027 single quote issue
    $result = $inputObject | convertto-json -depth $depth | foreach-object { $_.replace("\u0027", "'"); } #{ [regex]::unescape($_); }
    $WarningPreference = $currentWarningPreference

    return $result
}

function create-newTemplate($currentConfig) {
<#
.SYNOPSIS
    creates new new template from based on addnodetype template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:create-newTemplate"
    # create deploy / new / add template
    $templateFile = $templateJsonFile.Replace(".json", ".new.json")
    $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")
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
    write-log "exit:create-newTemplate"
}

function create-parameterFile($currentConfig, [string]$parameterFileName, [string[]]$ignoreParameters = @()) {
    write-log "enter:create-parameterFile"
    $parameterTemplate = [ordered]@{ 
        '$schema'      = $parametersSchema
        contentVersion = "1.0.0.0"
    } 
<#
.SYNOPSIS
    creates new template parameters files based on $currentConfig
    outputs: null
.OUTPUTS
    [null]
#>
    # create pscustomobject
    $parameterTemplate | Add-Member -TypeName System.Management.Automation.PSCustomObject -NotePropertyMembers @{ parameters = @{} }
    
    foreach ($psObjectProperty in $currentConfig.parameters.psobject.Properties.GetEnumerator()) {
        if ($ignoreParameters.Contains($psObjectProperty.name)) {
            write-log "create-parameterFile:skipping parameter $($psobjectProperty.name)"
            continue
        }

        write-log "create-parameterFile:value properties:$($psObjectProperty.Value.psobject.Properties.Name)" -verbose
        $parameterItem = @{
            value = $psObjectProperty.Value.defaultValue
        }

        if ($psObjectProperty.Value.GetType().name -ieq 'hashtable' -and $psObjectProperty.Value['metadata']) {
            if ($psObjectProperty.value.metadata.description) {
                $parameterItem.metadata = @{description = $psObjectProperty.value.metadata.description }
            }
        }
        [void]$parameterTemplate.parameters.Add($psObjectProperty.name, $parameterItem)
    }

    if (!($parameterFileName.tolower().contains('parameters'))) {
        $parameterFileName = $parameterFileName.tolower().replace('.json', '.parameters.json')
    }

    write-log "create-parameterFile:creating parameterfile $parameterFileName" -ForegroundColor Green
    $parameterTemplate | create-json | out-file -FilePath $parameterFileName
    write-log "exit:create-parameterFile"
}

function create-parameterizedName([string]$parameterName, [object]$resource, [switch]$withbrackets) {
<#
.SYNOPSIS
    creates parameterized name for variables, resources, and outputs section based on $paramterName and $resource
    outputs: string
.OUTPUTS
    [string]
#>
    if ($withbrackets) {
        return "[parameters('$(create-parametersName -resource $resource -name $parameterName)')]"
    }

    return "parameters('$(create-parametersName -resource $resource -name $parameterName)')"
}

function create-parametersName([object]$resource, [string]$name = 'name') {
<#
.SYNOPSIS
    creates parameter name for parameters, variables, resources, and outputs section based on $resource and $name
    outputs: string
.OUTPUTS
    [string]
#>
    write-log "enter:create-parametersName($resource, $name = 'name')"
    $resourceSubType = [regex]::replace($resource.type, '^.+?/', '')
    if ($resource.name.contains('[')) {
        $resourceName = [regex]::Match($resource.comments, ".+/([^/]+)'.$").Groups[1].Value
    }
    else {
        $resourceName = $resource.name
    }
    
    $resourceName = $resourceName.replace("-", "_")

    # prevent dupes
    $parametersNamePrefix = "$($resourceSubType)_$($resourceName)_"
    $parametersName = [regex]::replace($name, '^' + [regex]::Escape($parametersNamePrefix), '', [text.regularExpressions.regexoptions]::IgnoreCase)
    $parametersName = "$($resourceSubType)_$($resourceName)_$($name)"

    write-log "exit:create-parametersName returning:$parametersName"
    return $parametersName
}

function create-redeployTemplate($currentConfig) {
<#
.SYNOPSIS
    creates new redeploy template from current template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:create-redeployTemplate"
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
    write-log "exit:create-redeployTemplate"
}

function display-settings([object[]]$resources) {
<#
.SYNOPSIS
    displays current resource settings
    outputs: null
.OUTPUTS
    [null]
#>
    $settings = @()
    foreach ($resource in $resources) {
        $settings += $resource | create-json
    }
    write-log "current settings: `r`n $settings" -ForegroundColor Green
}

function export-template($configuredResources, $jsonFile) {
<#
.SYNOPSIS
    exports raw teamplate from azure using export-azresourcegroup cmdlet
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:export-template:exporting template to $jsonFile" -ForegroundColor Yellow
    $resources = [collections.arraylist]@()
    $azResourceGroupLocation = @($configuredResources)[0].Location
    $resourceIds = @($configuredResources.ResourceId)

    # todo issue
    new-item -ItemType File -path $jsonFile -ErrorAction SilentlyContinue
    write-log "export-template:file exists:$((test-path $jsonFile))"
    write-log "export-template:resource ids: $resourceIds" -ForegroundColor green

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
    
    write-log "exit:export-template:template exported to $jsonFile" -ForegroundColor Yellow
}

function enum-allResources() {
<#
.SYNOPSIS
    enumerate all resources in resource group
    outputs: object[]
.OUTPUTS
    [object[]]
#>
    write-log "enter:enum-allResources"
    $resources = [collections.arraylist]::new()

    write-log "enum-allResources:getting resource group cluster $resourceGroupName"
    $clusterResource = enum-clusterResource
    if (!$clusterResource) {
        write-log "enum-allResources:unable to enumerate cluster. exiting" -isError
        return $null
    }
    [void]$resources.Add($clusterResource.Id)

    write-log "enum-allResources:getting scalesets $resourceGroupName"
    $vmssResources = @(enum-vmssResources $clusterResource)
    if ($vmssResources.Count -lt 1) {
        write-log "enum-allResources:unable to enumerate vmss. exiting" -isError
        return $null
    }
    else {
        [void]$resources.AddRange(@($vmssResources.Id))
    }

    write-log "enum-allResources:getting storage $resourceGroupName"
    $storageResources = @(enum-storageResources $clusterResource)
    if ($storageResources.count -lt 1) {
        write-log "enum-allResources:unable to enumerate storage. exiting" -isError
        return $null
    }
    else {
        [void]$resources.AddRange(@($storageResources.Id))
    }
    
    write-log "enum-allResources:getting virtualnetworks $resourceGroupName"
    $vnetResources = @(enum-vnetResourceIds $vmssResources)
    if ($vnetResources.count -lt 1) {
        write-log "enum-allResources:unable to enumerate vnets. exiting" -isError
        return $null
    }
    else {
        [void]$resources.AddRange($vnetResources)
    }

    write-log "enum-allResources:getting loadbalancers $resourceGroupName"
    $lbResources = @(enum-lbResourceIds $vmssResources)
    if ($lbResources.count -lt 1) {
        write-log "enum-allResources:unable to enumerate loadbalancers. exiting" -isError
        return $null
    }
    else {
        [void]$resources.AddRange($lbResources)
    }

    write-log "enum-allResources:getting ip addresses $resourceGroupName"
    $ipResources = @(enum-ipResourceIds $lbResources)
    if ($ipResources.count -lt 1) {
        write-log "enum-allResources:unable to enumerate ips." -isWarning
    }
    else {
        [void]$resources.AddRange($ipResources)
    }

    write-log "enum-allResources:getting key vaults $resourceGroupName"
    $kvResources = @(enum-kvResourceIds $vmssResources)
    if ($kvResources.count -lt 1) {
        write-log "enum-allResources:unable to enumerate key vaults." -isWarning
    }
    else {
        [void]$resources.AddRange($kvResources)
    }

    write-log "enum-allResources:getting nsgs $resourceGroupName"
    $nsgResources = @(enum-nsgResourceIds $vmssResources)
    if ($nsgResources.count -lt 1) {
        write-log "enum-allResources:unable to enumerate nsgs." -isWarning
    }
    else {
        [void]$resources.AddRange($nsgResources)
    }

    if ($excludeResourceNames) {
        $resources = $resources | where-object Name -NotMatch "$($excludeResourceNames -join "|")"
    }

    write-log "exit:enum-allResources"
    return $resources | sort-object -Unique
}

function enum-clusterResource() {
<#
.SYNOPSIS
    enumerate cluster resource using get-azresource.
    will prompt if multiple cluster resources found.
    outputs: object
.OUTPUTS
    [object]
#>
    write-log "enter:enum-clusterResource"
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
        write-log "error:enum-clusterResource: no cluster found" -isError
        return $null
    }
    else {
        $clusterResource = $clusters[0]
    }

    write-log "using cluster resource $clusterResource" -ForegroundColor Green
    write-log "exit:enum-clusterResource"
    return $clusterResource
}

function enum-ipResourceIds([object[]]$lbResources) {
<#
.SYNOPSIS
    enumerate ip resource id's from lb resources
    outputs: string[]
.OUTPUTS
    [string[]]
#>
    write-log "enter:enum-ipResourceIds"
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

    write-log "enum-ipResourceIds:ip resources $resources" -verbose
    write-log "exit:enum-ipResourceIds"
    return $resources.ToArray() | sort-object -Unique
}

function enum-kvResourceIds([object[]]$vmssResources) {
<#
.SYNOPSIS
    enumerate keyvault resource id's from vmss resources
    outputs: string[]
.OUTPUTS
    [string[]]
#>
    write-log "enter:enum-kvResourceIds"
    $resources = [collections.arraylist]::new()

    foreach ($vmssResource in $vmssResources) {
        write-log "enum-kvResourceIds:checking vmssResource for key vaults $($vmssResource.Name)"
        foreach ($id in $vmssResource.Properties.virtualMachineProfile.osProfile.secrets.sourceVault.id) {
            write-log "enum-kvResourceIds:adding kv id: $id" -ForegroundColor green
            [void]$resources.Add($id)
        }
    }

    write-log "kv resources $resources" -verbose
    write-log "exit:enum-kvResourceIds"
    return $resources.ToArray() | sort-object -Unique
}

function enum-lbResourceIds([object[]]$vmssResources) {
<#
.SYNOPSIS
    enumerate loadbalancer resource id's from vmss resources
    outputs: string[]
.OUTPUTS
    [string[]]
#>
    write-log "enter:enum-lbResourceIds"
    $resources = [collections.arraylist]::new()

    foreach ($vmssResource in $vmssResources) {
        # get nic for vnet/subnet and lb
        write-log "enum-lbResourceIds:checking vmssResource for network config $($vmssResource.Name)"
        foreach ($nic in $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations) {
            foreach ($ipconfig in $nic.properties.ipConfigurations) {
                $id = [regex]::replace($ipconfig.properties.loadBalancerBackendAddressPools.id, '/backendAddressPools/.+$', '')
                write-log "enum-lbResourceIds:adding lb id: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }
    }

    write-log "lb resources $resources" -verbose
    write-log "exit:enum-lbResourceIds"
    return $resources.ToArray() | sort-object -Unique
}

function enum-nsgResourceIds([object[]]$vmssResources) {
<#
.SYNOPSIS
    enumerate network security group resource id's from vmss resources
    outputs: string[]
.OUTPUTS
    [string[]]
#>
    write-log "enter:enum-nsgResourceIds"
    $resources = [collections.arraylist]::new()

    foreach ($vnetId in $vnetResources) {
        $vnetresource = @(get-azresource -ResourceId $vnetId -ExpandProperties)
        write-log "enum-nsgResourceIds:checking vnet resource for nsg config $($vnetresource.Name)"
        foreach ($subnet in $vnetResource.Properties.subnets) {
            if ($subnet.properties.networkSecurityGroup.id) {
                $id = $subnet.properties.networkSecurityGroup.id
                write-log "enum-nsgResourceIds:adding nsg id: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }

    }

    write-log "nsg resources $resources" -verbose
    write-log "exit:enum-nsgResourceIds"
    return $resources.ToArray() | sort-object -Unique
}

function enum-storageResources([object]$clusterResource) {
<#
.SYNOPSIS
    enumerate storage resources from cluster resource
    outputs: object[]
.OUTPUTS
    [object[]]
#>
    write-log "enter:enum-storageResources"
    $resources = [collections.arraylist]::new()
    
    $sflogs = $clusterResource.Properties.diagnosticsStorageAccountConfig.storageAccountName
    write-log "enum-storageResources:cluster sflogs storage account $sflogs"

    $scalesets = enum-vmssResources($clusterResource)
    $sfdiags = @(($scalesets.Properties.virtualMachineProfile.extensionProfile.extensions.properties | where-object type -eq 'IaaSDiagnostics').settings.storageAccount) | Sort-Object -Unique
    write-log "enum-storageResources:cluster sfdiags storage account $sfdiags"
  
    $storageResources = @(get-azresource -ResourceGroupName $resourceGroupName `
            -ResourceType 'Microsoft.Storage/storageAccounts' `
            -ExpandProperties)

    $global:sflogs = $storageResources | where-object name -ieq $sflogs
    $global:sfdiags = @($storageResources | where-object name -ieq $sfdiags)
    
    [void]$resources.add($global:sflogs)
    foreach ($sfdiag in $global:sfdiags) {
        write-log "enum-storageResources: adding $sfdiag"
        [void]$resources.add($sfdiag)
    }
    
    write-log "storage resources $resources" -verbose
    write-log "exit:enum-storageResources"
    return $resources.ToArray() | sort-object name -Unique
}

function enum-vmssResources([object]$clusterResource) {
<#
.SYNOPSIS
    enumerate virtual machine scaleset resources from cluster resource
    outputs: object[]
.OUTPUTS
    [object[]]
#>
    write-log "enter:enum-vmssResources"
    $nodeTypes = $clusterResource.Properties.nodeTypes
    write-log "enum-vmssResources:cluster nodetypes $($nodeTypes| create-json)"
    $vmssResources = [collections.arraylist]::new()

    $clusterEndpoint = $clusterResource.Properties.clusterEndpoint
    write-log "enum-vmssResources:cluster id $clusterEndpoint" -ForegroundColor Green
    
    if (!$nodeTypes -or !$clusterEndpoint) {
        write-log "exit:enum-vmssResources:nodetypes:$nodeTypes clusterEndpoint:$clusterEndpoint" -isError
        return $null
    }

    $resources = @(get-azresource -ResourceGroupName $resourceGroupName `
            -ResourceType 'Microsoft.Compute/virtualMachineScaleSets' `
            -ExpandProperties)

    write-log "enum-vmssResources:vmss resources $resources" -verbose

    foreach ($resource in $resources) {
        $vmsscep = ($resource.Properties.virtualMachineProfile.extensionprofile.extensions.properties.settings | Select-Object clusterEndpoint).clusterEndpoint
        if ($vmsscep -ieq $clusterEndpoint) {
            write-log "enum-vmssResources:adding vmss resource $($resource | create-json)" -ForegroundColor Cyan
            [void]$vmssResources.Add($resource)
        }
        else {
            write-log "enum-vmssResources:vmss assigned to different cluster $vmsscep" -isWarning
        }
    }

    write-log "exit:enum-vmssResources"
    return $vmssResources.ToArray() | sort-object name -Unique
}

function enum-vnetResourceIds([object[]]$vmssResources) {
<#
.SYNOPSIS
    enumerate virtual network resource Ids from vmss resources
    outputs: string[]
.OUTPUTS
    [string[]]
#>
    write-log "enter:enum-vnetResourceIds"
    $resources = [collections.arraylist]::new()

    foreach ($vmssResource in $vmssResources) {
        # get nic for vnet/subnet and lb
        write-log "enum-vnetResourceIds:checking vmssResource for network config $($vmssResource.Name)"
        foreach ($nic in $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations) {
            foreach ($ipconfig in $nic.properties.ipConfigurations) {
                $id = [regex]::replace($ipconfig.properties.subnet.id, '/subnets/.+$', '')
                write-log "enum-vnetResourceIds:adding vnet id: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }
    }

    write-log "vnet resources $resources" -verbose
    write-log "exit:enum-vnetResourceIds"
    return $resources.ToArray() | sort-object -Unique
}

function get-clusterResource($currentConfig) {
<#
.SYNOPSIS
    enumerate cluster resources[0] from $currentConfig
    outputs: object
.OUTPUTS
    [object]
#>
    write-log "enter:get-clusterResource"
    $resources = @($currentConfig.resources | Where-Object type -ieq 'Microsoft.ServiceFabric/clusters')
    
    if ($resources.count -ne 1) {
        write-log "unable to find cluster resource" -isError
    }

    write-log "returning cluster resource $resources" -verbose
    write-log "exit:get-clusterResource:$($resources[0])"
    return $resources[0]
}

function get-lbResources($currentConfig) {
<#
.SYNOPSIS
    enumerate loadbalancer resources from $currentConfig
    outputs: object[]
.OUTPUTS
    [object[]]
#>
    write-log "enter:get-lbResources"
    $resources = @($currentConfig.resources | Where-Object type -ieq 'Microsoft.Network/loadBalancers')
    
    if ($resources.count -eq 0) {
        write-log "unable to find lb resource" -isError
    }

    write-log "returning lb resource $resources" -verbose
    write-log "exit:get-lbResources:$($resources.count)"
    return $resources
}

function get-fromParametersSection($currentConfig, [string]$parameterName) {
<#
.SYNOPSIS
    enumerate defaultValue[] from parameters section by $parameterName
    outputs: object[]
.OUTPUTS
    [object[]]
#>
    write-log "enter:get-fromParametersSection parameterName=$parameterName"
    $results = $null
    $parameters = @($currentConfig.parameters)
    $currentErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'silentlycontinue'

    $results = @($parameters.$parameterName.defaultValue)
    $ErrorActionPreference = $currentErrorPreference
    
    if (!$results) {
        write-log "get-fromParametersSection:no matching values found in parameters section for $parameterName"
    }
    if (@($results).count -gt 1) {
        write-log "get-fromParametersSection:multiple matching values found in parameters section for $parameterName `r`n $($results |create-json)"
    }

    write-log "exit:get-fromParametersSection: returning: $($results | create-json)" -ForegroundColor Magenta
    return $results
}

function get-parameterizedNameFromValue([object]$resourceObject) {
<#
.SYNOPSIS
    enumerate parameter name from parameter value that is parameterized
    [regex]::match($resourceobject, "\[parameters\('(.+?)'\)\]")
    outputs: string
.OUTPUTS
    [string]
#>
    write-log "enter:get-parameterizedNameFromValue($resourceObject)"
    $retval = $null
    if ([regex]::IsMatch($resourceobject, "\[parameters\('(.+?)'\)\]", [text.regularExpressions.regexOptions]::ignorecase)) {
        $retval = [regex]::match($resourceobject, "\[parameters\('(.+?)'\)\]", [text.regularExpressions.regexOptions]::ignorecase).groups[1].Value
    }

    write-log "exit:get-parameterizedNameFromValue:returning $retval"
    return $retval
}

function get-resourceParameterValue([object]$resource, [string]$name) {
<#
.SYNOPSIS
    gets resource parameter value
    outputs: string
.OUTPUTS
    [string]
#>
    write-log "enter:get-resourceParameterValue:resource:$($resource|create-json) name:$name"
    $retval = $null
    foreach ($psObjectProperty in $resource.psobject.Properties) {
        write-log "get-resourceParameterValue:checking parameter name:$psobjectProperty" -verbose

        if (($psObjectProperty.Name -ieq $name)) {
            $parameterValues = @($psObjectProperty.Name)
            if ($parameterValues.Count -eq 1) {
                $parameterValue = $psObjectProperty.Value
                if (!($parameterValue)) {
                    write-log "exit:get-resourceParameterValue:returning:string::empty"
                    return [string]::Empty
                }
                write-log "exit:get-resourceParameterValue:returning:$parameterValue"
                return $parameterValue
            }
            else {
                write-log "exit:get-resourceParameterValue:multiple parameter names found in resource. returning" -isError
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

    write-log "exit:get-resourceParameterValue:returning:$retval"
    return $retval
}

function get-resourceParameterValueObject($resource, $name) {
<#
.SYNOPSIS
    get resource parameter value object
    outputs: object
.OUTPUTS
    [object]
#>
    write-log "enter:get-resourceParameterValueObjet:name $name"
    $retval = $null
    foreach ($psObjectProperty in $resource.psobject.Properties) {
        write-log "get-resourceParameterValueObject:checking parameter object $psobjectProperty" -verbose

        if (($psObjectProperty.Name -ieq $name)) {
            $parameterValues = @($psObjectProperty.Name)
            if ($parameterValues.Count -eq 1) {
                write-log "get-resourceParameterValueObject:returning parameter object $psobjectProperty" -verbose
                $retval = $resource.psobject.Properties[$psObjectProperty.name]
                break
            }
            else {
                write-log "get-resourceParameterValueObject:multiple parameter names found in resource. returning" -isError
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

    write-log "exit:get-resourceParameterValueObject: returning $retval"
    return $retval
}

function get-update($updateUrl) {
<#
.SYNOPSIS
    checks for script update
    outputs: bool
.OUTPUTS
    [bool]
#>
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

function get-vmssExtensions([object]$vmssResource, [string]$extensionType = $null) {
<#
.SYNOPSIS
    returns vmss extension resources from $vmssResource
    outputs: object[]
.OUTPUTS
    [object[]]
#>
    write-log "enter:get-vmssExtensions:vmssname: $($vmssResource.name)"
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
        write-log "get-vmssExtensions:unable to find extension in vmss resource $($vmssResource.name) $extensionType" -isError
    }

    write-log "exit:get-vmssExtensions:results count: $($results.count)"
    return $results.ToArray()
}

function get-vmssResources($currentConfig) {
<#
.SYNOPSIS
    returns vmss resources from $currentConfig
    outputs: object[]
.OUTPUTS
    [object[]]
#>
    write-log "enter:get-vmssResources"
    $resources = @($currentConfig.resources | Where-Object type -ieq 'Microsoft.Compute/virtualMachineScaleSets')
    if ($resources.count -eq 0) {
        write-log "get-vmssResources:unable to find vmss resource" -isError
    }
    write-log "get-vmssResources:returning vmss resource $resources" -verbose
    write-log "exit:get-vmssResources"
    return $resources
}

function get-vmssResourcesByNodeType($currentConfig, [object]$nodetypeResource) {
<#
.SYNOPSIS
    returns vmss resources from $currentConfig by $nodetypeResource
    outputs: object[]
.OUTPUTS
    [object[]]
#>
    write-log "enter:get-vmssResourcesByNodeType"
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

    write-log "exit:get-vmssResourcesByNodeType:result count:$($vmssByNodeType.count)"
    return $vmssByNodeType.ToArray()
}

function modify-clusterResourceAddNodeType($currentConfig) {
<#
.SYNOPSIS
    modifies cluster resource for addNodeType template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:modify-clusterResourceAddNodeType"
    $clusterResource = get-clusterResource $currentConfig
    
    write-log "modify-clusterResourceAddNodeType:setting `$clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter"
    $clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter
    
    write-log "modify-clusterResourceAddNodeType:setting `$clusterResource.properties.upgradeMode = Manual"
    $clusterResource.properties.upgradeMode = "Manual"
    $reference = "[reference($(create-parameterizedName -parameterName 'name' -resource $clusterResource))]"
    add-outputs -currentConfig $currentConfig -name 'clusterProperties' -value $reference -type 'object'
    write-log "exit:modify-clusterResourceAddNodeType"
}


function modify-clusterResourceRedeploy($currentConfig) {
<#
.SYNOPSIS
    modifies cluster resource for redeploy template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:modify-clusterResourceDeploy"
    $sflogsParameter = create-parameterizedName -parameterName 'name' -resource $global:sflogs -withbrackets
    $clusterResource = get-clusterResource $currentConfig
    
    write-log "modify-clusterResourceDeploy:setting `$clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter"
    $clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter
    
    if ($clusterResource.properties.upgradeMode -ieq 'Automatic') {
        write-log "modify-clusterResourceDeploy:removing value cluster code version $($clusterResource.properties.clusterCodeVersion)" -ForegroundColor Yellow
        $clusterResource.properties.psobject.Properties.remove('clusterCodeVersion')
    }
    
    $reference = "[reference($(create-parameterizedName -parameterName 'name' -resource $clusterResource))]"
    add-outputs -currentConfig $currentConfig -name 'clusterProperties' -value $reference -type 'object'
    write-log "exit:modify-clusterResourceDeploy"
}

function modify-ipAddressesRedeploy($currentConfig) {
<#
.SYNOPSIS
    modifies ip resources for redeploy template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:modify-ipAddressesRedeploy"
    # add ip address dns parameter
    $metadataDescription = 'this name must be unique in deployment region.'
    $dnsSettings = add-parameterNameByResourceType -currentConfig $currentConfig -type "Microsoft.Network/publicIPAddresses" -name 'domainNameLabel' -metadataDescription $metadataDescription
    $fqdn = add-parameterNameByResourceType -currentConfig $currentConfig -type "Microsoft.Network/publicIPAddresses" -name 'fqdn' -metadataDescription $metadataDescription
    write-log "exit:modify-ipAddressesRedeploy"
}

function modify-lbResources($currenConfig) {
<#
.SYNOPSIS
    modifies loadbalancer resources for current
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:modify-lbResources"
    $lbResources = get-lbResources $currentConfig
    foreach ($lbResource in $lbResources) {
        # fix backend pool
        write-log "modify-lbResources:fixing exported lb resource $($lbresource | create-json)"
        $parameterName = get-parameterizedNameFromValue $lbresource.name
        if ($parameterName) {
            $name = $currentConfig.parameters.$parametername.defaultValue
        }

        if (!$name) {
            $name = $lbResource.name
        }

        $lb = get-azresource -ResourceGroupName $resourceGroupName -Name $name -ExpandProperties -ResourceType 'Microsoft.Network/loadBalancers'
        $dependsOn = [collections.arraylist]::new()

        write-log "modify-lbResources:removing backendpool from lb dependson"
        foreach ($depends in $lbresource.dependsOn) {
            if ($depends -inotmatch $lb.Properties.backendAddressPools.Name) {
                [void]$dependsOn.Add($depends)
            }
        }
        $lbResource.dependsOn = $dependsOn.ToArray()
        write-log "modify-lbResources:lbResource modified dependson: $($lbResource.dependson | create-json)" -ForegroundColor Yellow
    }
    write-log "exit:modify-lbResources"
}

function modify-lbResourcesRedeploy($currenConfig) {
<#
.SYNOPSIS
    modifies loadbalancer resources for redeploy template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:modify-lbResourcesRedeploy"
    $lbResources = get-lbResources $currentConfig
    foreach ($lbResource in $lbResources) {
        # fix dupe pools and rules
        if ($lbResource.properties.inboundNatPools) {
            write-log "modify-lbResourcesRedeploy:removing natrules: $($lbResource.properties.inboundNatRules | create-json)" -ForegroundColor Yellow
            [void]$lbResource.properties.psobject.Properties.Remove('inboundNatRules')
        }
    }
    write-log "exit:modify-lbResourcesRedeploy"
}

function modify-storageResourcesDeploy($currentConfig) {
<#
.SYNOPSIS
    modifies storage resources for deploy template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:modify-storageResourcesDeploy"
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

    write-log "exit:modify-storageResourcesDeploy"
    return $parameterExclusions.ToArray()
}

function modify-vmssResources($currenConfig) {
<#
.SYNOPSIS
    modifies vmss resources for current template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:modify-vmssResources"
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
    write-log "exit:modify-vmssResources"
}

function modify-vmssResourcesDeploy($currenConfig) {
<#
.SYNOPSIS
    modifies storage vmss for deploy template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:modify-vmssResourcesDeploy"
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
    write-log "exit:modify-vmssResourcesDeploy"
}

function modify-vmssResourcesRedeploy($currenConfig) {
<#
.SYNOPSIS
    modifies vmss resources for redeploy template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:modify-vmssResourcesReDeploy"
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
                write-log "modify-vmssResourcesReDeploy:parameterizing cluster endpoint"
                add-parameter -currentConfig $currentConfig -resource $vmssResource -name 'clusterEndpoint' -resourceObject $extension.properties.settings
            }
            [void]$extensions.Add($extension)
        }    
        $vmssResource.properties.virtualMachineProfile.extensionProfile.extensions = $extensions

        write-log "modify-vmssResourcesReDeploy:modifying dependson"
        $dependsOn = [collections.arraylist]::new()
        $subnetIds = @($vmssResource.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.ipconfigurations.properties.subnet.id)

        foreach ($depends in $vmssResource.dependsOn) {
            if ($depends -imatch 'backendAddressPools') { continue }

            if ($depends -imatch 'Microsoft.Network/loadBalancers') {
                [void]$dependsOn.Add($depends)
            }
            # example depends "[resourceId('Microsoft.Network/virtualNetworks/subnets', parameters('virtualNetworks_VNet_name'), 'Subnet-0')]"
            if ($subnetIds.contains($depends)) {
                write-log 'modify-vmssResourcesReDeploy:cleaning subnet dependson' -ForegroundColor Yellow
                $depends = $depends.replace("/subnets'", "/'")
                $depends = [regex]::replace($depends, "\), '.+?'\)\]", "))]")
                [void]$dependsOn.Add($depends)
            }
        }

        $vmssResource.dependsOn = $dependsOn.ToArray()
        write-log "modify-vmssResourcesReDeploy:vmssResource modified dependson: $($vmssResource.dependson | create-json)" -ForegroundColor Yellow
            
        write-log "modify-vmssResourcesReDeploy:parameterizing hardware sku"
        add-parameter -currentConfig $currentConfig -resource $vmssResource -name 'name' -aliasName 'hardwareSku' -resourceObject $vmssResource.sku
            
        write-log "modify-vmssResourcesReDeploy:parameterizing hardware capacity"
        add-parameter -currentConfig $currentConfig -resource $vmssResource -name 'capacity' -resourceObject $vmssResource.sku -type 'int'

        write-log "modify-vmssResourcesReDeploy:parameterizing os sku"
        add-parameter -currentConfig $currentConfig -resource $vmssResource -name 'sku' -aliasName 'osSku' -resourceObject $vmssResource.properties.virtualMachineProfile.storageProfile.imageReference

        if (!($vmssResource.properties.virtualMachineProfile.osProfile.psobject.Properties | where-object name -ieq 'adminPassword')) {
            write-log "modify-vmssResourcesReDeploy:adding admin password"
            $vmssResource.properties.virtualMachineProfile.osProfile | Add-Member -MemberType NoteProperty -Name 'adminPassword' -Value $adminPassword
            
            add-parameter -currentConfig $currentConfig `
                -resource $vmssResource `
                -name 'adminPassword' `
                -resourceObject $vmssResource.properties.virtualMachineProfile.osProfile `
                -metadataDescription 'password must be set before deploying template.'
        }
    }
    write-log "exit:modify-vmssResourcesReDeploy"
}

function parameterize-nodetype($currentConfig, [object]$nodetype, [string]$parameterName, [string]$parameterValue = $null, [string]$type = 'string') {
<#
.SYNOPSIS
    parameterizes nodetype for addnodetype template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:parameterize-nodetype:nodetype:$($nodetype |create-json) parameterName:$parameterName parameterValue:$parameterValue type:$type"
    $vmssResources = @(get-vmssResourcesByNodeType -currentConfig $currentConfig -nodetypeResource $nodetype)
    $parameterizedName = $null

    if (!$parameterValue) {
        $parameterValue = get-resourceParameterValue -resource $nodetype -name $parameterName
    }
    foreach ($vmssResource in $vmssResources) {
        $parametersName = create-parametersName -resource $vmssResource -name $parameterName

        $parameterizedName = get-parameterizedNameFromValue -resourceObject (get-resourceParameterValue -resource $nodetype -name $parameterName)
        if (!$parameterizedName) {
            $parameterizedName = create-parameterizedName -resource $vmssResource -parameterName $parameterName
        }

        add-toParametersSection -currentConfig $currentConfig -parameterName $parametersName -parameterValue $parameterValue -type $type
        write-log "parameterize-nodetype:setting $parametersName to $parameterValue for $($nodetype.name)" -foregroundcolor Magenta

        write-log "parameterize-nodetype:add-parameter -currentConfig $currentConfig `
            -resource $vmssResource `
            -name $parameterName `
            -resourceObject $nodetype `
            -value $parameterizedName `
            -type $type
        "

        add-parameter -currentConfig $currentConfig `
            -resource $vmssResource `
            -name $parameterName `
            -resourceObject $nodetype `
            -value $parameterizedName `
            -type $type

        $extension = get-vmssExtensions -vmssResource $vmssResource -extensionType 'ServiceFabricNode'
            
        write-log "parameterize-nodetype:add-parameter -currentConfig $currentConfig `
                -resource $vmssResource `
                -name $parameterName `
                -resourceObject $($extension.properties.settings) `
                -value $parameterizedName `
                -type $type
            "

        add-parameter -currentConfig $currentConfig `
            -resource $vmssResource `
            -name $parameterName `
            -resourceObject $extension.properties.settings `
            -value $parameterizedName `
            -type $type
    }
    write-log "exit:parameterize-nodetype"
}

function parameterize-nodeTypes($currentConfig) {
<#
.SYNOPSIS
    parameterizes nodetypes for addnodetype template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:parameterize-nodetypes"
    # todo. should validation be here? how many nodetypes
    $clusterResource = get-clusterResource $currentConfig
    $nodetypes = [collections.arraylist]::new()
    $nodetypes.AddRange(@($clusterResource.properties.nodetypes))

    if ($nodetypes.Count -lt 1) {
        write-log "exit:parameterize-nodetypes:no nodetypes detected!" -isError
        return
    }

    write-log "parameterize-nodetypes:current nodetypes $($nodetypes.name)" -ForegroundColor Green
    $primarynodetypes = @($nodetypes | Where-Object isPrimary -eq $true)

    if ($primarynodetypes.count -eq 0) {
        write-log "parameterize-nodetypes:unable to find primary nodetype" -isError
    }
    elseif ($primarynodetypes.count -gt 1) {
        write-log "parameterize-nodetypes:more than one primary node type detected!" -isError
    }
    
    write-log "parameterize-nodetypes:adding new nodetype" -foregroundcolor Cyan
    $newPrimaryNodeType = $primarynodetypes[0].psobject.copy()
    $existingVmssNodeTypeRef = @(get-vmssResourcesByNodeType -currentConfig $currentConfig -nodetypeResource $newPrimaryNodeType)

    if ($existingVmssNodeTypeRef.count -lt 1) {
        write-log "exit:parameterize-nodetypes:unable to find existing nodetypes by nodetyperef" -isError
        return
    }

    write-log "parameterize-nodetypes:parameterizing new nodetype " -foregroundcolor Cyan
    ####    $instanceCount = get-resourceParameterValue
    ####    add-parameter -currentConfig $currentConfig -resource $newPrimaryNodeType -name 'capacity' -aliasname 'vmInstanceCount' -resourceObject $existingVmssNodeTypeRef[0].sku -type 'int'

    parameterize-nodetype -currentConfig $currentConfig -nodetype $newPrimaryNodeType -parameterName 'durabilityLevel'
    parameterize-nodetype -currentConfig $currentConfig -nodetype $newPrimaryNodeType -parameterName 'isPrimary' -type 'bool'
    parameterize-nodetype -currentConfig $currentConfig -nodetype $newPrimaryNodeType -parameterName 'vmInstanceCount' -type 'int'
    # todo: currently name has to be parameterized last so parameter names above can be found
    parameterize-nodetype -currentConfig $currentConfig -nodetype $newPrimaryNodeType -parameterName 'name'
    
    $nodetypes.Add($newPrimaryNodeType)
    $clusterResource.properties.nodetypes = $nodetypes
    write-log "exit:parameterize-nodetypes:result:`r`n$($nodetypes | create-json)"
}

function remove-duplicateResources($currentConfig) {
<#
.SYNOPSIS
    removes duplicate resources for current template
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:remove-duplicateResources"
    # fix up deploy errors by removing duplicated sub resources on root like lb rules by
    # removing any 'type' added by export-azresourcegroup that was not in the $global:configuredRGResources
    $currentResources = [collections.arraylist]::new() #$currentConfig.resources | create-json | convertfrom-json

    $resourceTypes = $global:configuredRGResources.resourceType
    foreach ($resource in $currentConfig.resources.GetEnumerator()) {
        write-log "remove-duplicateResources:checking exported resource $($resource.name)" -ForegroundColor Magenta
        write-log "remove-duplicateResources:checking exported resource $($resource | create-json)" -verbose
        
        if ($resourceTypes.Contains($resource.type)) {
            write-log "remove-duplicateResources:adding exported resource $($resource.name)" -ForegroundColor Cyan
            write-log "remove-duplicateResources:adding exported resource $($resource | create-json)" -verbose
            [void]$currentResources.Add($resource)
        }
    }
    $currentConfig.resources = $currentResources
    write-log "exit:remove-duplicateResources"
}

function remove-unusedParameters($currentConfig) {
<#
.SYNOPSIS
    removes unused parameters from parameters section
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:remove-unusedParameters"
    $parametersRemoveList = [collections.arraylist]::new()
    #serialize and copy
    $currentConfigResourcejson = $currentConfig | create-json
    $currentConfigJson = $currentConfigResourcejson | convertfrom-json

    # remove parameters section but keep everything else like variables, resources, outputs
    $currentConfigJson.psobject.properties.remove('Parameters')
    $currentConfigResourcejson = $currentConfigJson | create-json

    foreach ($psObjectProperty in $currentConfig.parameters.psobject.Properties) {
        $parameterizedName = "parameters\('$($psObjectProperty.name)'\)"
        write-log "remove-unusedParameters:checking to see if $parameterizedName is being used"
        if ([regex]::IsMatch($currentConfigResourcejson, $parameterizedName, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            write-log "remove-unusedParameters:$parameterizedName is being used" -verbose
            continue
        }
        write-log "remove-unusedParameters:removing $parameterizedName" -verbose
        [void]$parametersRemoveList.Add($psObjectProperty)
    }

    foreach ($parameter in $parametersRemoveList) {
        write-log "remove-unusedParameters:removing $($parameter.name)" -isWarning
        $currentConfig.parameters.psobject.Properties.Remove($parameter.name)
    }
    write-log "exit:remove-unusedParameters"
}

function set-resourceParameterValue([object]$resource, [string]$name, [string]$newValue) {
<#
.SYNOPSIS
    sets resource parameter value in resources section
    outputs: bool
.OUTPUTS
    [bool]
#>
    write-log "enter:set-resourceParameterValue:resource:$($resource|create-json) name:$name,newValue:$newValue" -foregroundcolor DarkCyan
    $retval = $false
    foreach ($psObjectProperty in $resource.psobject.Properties) {
        write-log "set-resourceParameterValuechecking parameter name $psobjectProperty" -verbose

        if (($psObjectProperty.Name -ieq $name)) {
            $parameterValues = @($psObjectProperty.Name)
            if ($parameterValues.Count -eq 1) {
                $psObjectProperty.Value = $newValue
                $retval = $true
                break
            }
            else {
                write-log "set-resourceParameterValue:multiple parameter names found in resource. returning" -isError
                $retval = $false
                break
            }
        }
        elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Management.Automation.PSCustomObject') {
            $retval = set-resourceParameterValue -resource $psObjectProperty.Value -name $name -newValue $newValue
        }
        else {
            write-log "set-resourceParameterValue:skipping type:$($psObjectProperty.TypeNameOfValue)" -verbose
        }
    }

    write-log "exit:set-resourceParameterValue:returning:$retval"
    return $retval
}

function verify-config($currentConfig, [string]$templateParameterFile) {
<#
.SYNOPSIS
    verifies current configuration $currentConfig using test-resourcegroupdeployment
    outputs: null
.OUTPUTS
    [null]
#>
    write-log "enter:verify-config:templateparameterFile:$templateParameterFile"
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
    write-log "exit:verify-config:templateparameterFile:$templateParameterFile"
}

function write-log([object]$data, [ConsoleColor]$foregroundcolor = [ConsoleColor]::Gray, [switch]$isError, [switch]$isWarning, [switch]$verbose) {
<#
.SYNOPSIS
    writes output to console and logfile
    outputs: null
.OUTPUTS
    [null]
#>
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
        if ($data.startswith('enter:')) {
            $global:functionDepth++
        }
        elseif ($data.startswith('exit:')) {
            $global:functionDepth--
        }

        $stringData = ("$((get-date).tostring('HH:mm:ss.fff')):$([string]::empty.PadLeft($global:functionDepth,'|'))$verboseTag$($data | format-list * | out-string)").trim()
    }

    if ($isError) {
        write-error $stringData
        $global:errors.add($stringData)
    }
    elseif ($isWarning) {
        Write-Warning $stringData
        $global:warnings.add($stringData)
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

main
$ErrorActionPreference = $currentErrorActionPreference
$VerbosePreference = $currentVerbosePreference
