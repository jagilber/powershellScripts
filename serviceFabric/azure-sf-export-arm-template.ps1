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
    [string[]]$resourceNames = '',
    [string[]]$excludeResourceNames = '',
    [switch]$detail,
    [string]$logFile = "$templatePath/azure-az-sf-export-arm-template.log",
    [switch]$compress,
    [switch]$updateScript
)

set-strictMode -Version 3.0
$PSModuleAutoLoadingPreference = 2
$currentErrorActionPreference = $ErrorActionPreference
$currentVerbosePreference = $VerbosePreference
$env:SuppressAzurePowerShellBreakingChangeWarnings = $true

class SFTemplate {
    [string]$parametersSchema = 'http://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json'
    [string]$updateUrl = 'https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-export-arm-template.ps1'

    [collections.arraylist]$global:errors = [collections.arraylist]::new()
    [collections.arraylist]$global:warnings = [collections.arraylist]::new()
    [int]$global:functionDepth = 0
    [string]$global:templateJsonFile = "$templatePath/template.json"
    [int]$global:resourceErrors = 0
    [int]$global:resourceWarnings = 0
    [hashtable]$global:clusterTree = @{}
    [collections.arraylist]$global:configuredRGResources = [collections.arraylist]::new()
    [object]$global:currentConfig = $null
    [object]$global:sflogs = $null
    [object]$global:sfdiags = $null
    [datetime]$global:startTime = (get-date)
    [string]$global:storageKeyApi = '2015-05-01-preview'
    [string]$global:defaultSflogsValue = "[toLower(concat('sflogs',uniqueString(resourceGroup().id),'2'))]"
    [string]$global:defaultSfdiagsValue = "[toLower(concat(uniqueString(resourceGroup().id),'3'))]"
    [text.regularExpressions.regexOptions]$global:ignoreCase = [text.regularExpressions.regexOptions]::IgnoreCase

    SFTemplate() {}
    static SFTemplate() {}

    [void] Export() {
        if (!(test-path $templatePath)) {
            # test local and for cloudshell
            mkdir $templatePath
            WriteLog "making directory $templatePath"
        }

        WriteLog "starting"
        if ($updateScript -and (GetUpdate -updateUrl $updateUrl)) {
            return
        }

        if (!$resourceGroupName) {
            WriteLog "resource group name is required." -isError
            return
        }

        if ($detail) {
            $ErrorActionPreference = 'continue'
            $VerbosePreference = 'continue'
            $debugLevel = 'all'
        }

        if (!(CheckModule)) {
            return
        }

        if (!(@(Get-AzResourceGroup).Count)) {
            WriteLog "connecting to azure"
            Connect-AzAccount
        }

        if ($resourceNames) {
            foreach ($resourceName in $resourceNames) {
                WriteLog "getting resource $resourceName"
                [void]$global:configuredRGResources.AddRange(@((get-azresource -ResourceGroupName $resourceGroupName -resourceName $resourceName)))
            }
        }
        else {
            $resourceIds = EnumAllResources
            foreach ($resourceId in $resourceIds) {
                $resource = get-azresource -resourceId "$resourceId" -ExpandProperties
                if ($resource.ResourceGroupName -ieq $resourceGroupName) {
                    WriteLog "adding resource id to configured resources: $($resource.resourceId)" -ForegroundColor Cyan
                    [void]$global:configuredRGResources.Add($resource)
                }
                else {
                    WriteLog "skipping resource $($resource.resourceid) as it is out of resource group scope $($resource.ResourceGroupName)" -isWarning
                }
            }
        }

        DisplaySettings -resources $global:configuredRGResources

        if ($global:configuredRGResources.count -lt 1) {
            WriteLog "error enumerating resource $($error | format-list * | out-string)" -isWarning
            return
        }

        $deploymentName = "$resourceGroupName-$((get-date).ToString("yyyyMMdd-HHmms"))"

        # create $global:currentConfig
        CreateExportTemplate

        # use $global:currentConfig
        CreateCurrentTemplate
        CreateRedeployTemplate
        CreateAddPrimaryNodeTypeTemplate
        CreateAddSecondaryNodeTypeTemplate
        CreateNewTemplate

        if ($compress) {
            $zipFile = "$templatePath.zip"
            compress-archive $templatePath $zipFile -Force
            WriteLog "zip file located here:$zipFile" -ForegroundColor Cyan
        }

        $error.clear()

        write-host "finished. files stored in $templatePath" -ForegroundColor Green
        code $templatePath # for cloudshell and local
        
        if ($error) {
            . $templateJsonFile.Replace(".json", ".current.json")
        }

        if ($global:resourceErrors -or $global:resourceWarnings) {
            WriteLog "deployment may not have been successful: errors: $global:resourceErrors warnings: $global:resourceWarnings" -isWarning

            if ($DebugPreference -ieq 'continue') {
                WriteLog "errors: $($error | sort-object -Descending | out-string)"
            }
        }

        $deployment = Get-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name $deploymentName -ErrorAction silentlycontinue

        WriteLog "deployment:`r`n$($deployment | format-list * | out-string)"
        Write-Progress -Completed -Activity "complete"

        if ($global:warnings) {
            WriteLog "global warnings:" -foregroundcolor Yellow
            WriteLog ($global:warnings | CreateJson) -isWarning
        }

        if ($global:errors) {
            WriteLog "global errors:" -foregroundcolor Red
            WriteLog ($global:errors | CreateJson) -isError
        }

        WriteLog "time elapsed:  $(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes`r`n"
        WriteLog 'finished. template stored in $global:currentConfig' -ForegroundColor Cyan

        if ($logFile) {
            WriteLog "log file saved to $logFile"
        }
    }

    [void] AddOutputs( [string]$name, [string]$value, [string]$type = 'string') {
    <#
    .SYNOPSIS
        add element to outputs section of template
        outputs: null
    .OUTPUTS
        [null]
    #>
        WriteLog "enter:AddOutputs( $name, $value, $type = 'string'"
        $outputs = $global:currentConfig.psobject.Properties | where-object name -ieq 'outputs'
        $outputItem = @{
            value = $value
            type = $type
        }

        if (!$outputs) {
            # create pscustomobject
            $global:currentConfig | Add-Member -TypeName System.Management.Automation.PSCustomObject -NotePropertyMembers @{
                outputs = @{
                    $name = $outputItem
                }
            }
        }
        else {
            [void]$global:currentConfig.outputs.add($name, $outputItem)
        }
        WriteLog "exit:AddOutputs:added"
    }

    [void] AddParameterNameByResourceType( [string]$type, [string]$name, [string]$metadataDescription = '') {
        <#
        .SYNOPSIS
            add parameter name by resource type
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:AddParameterNameByResourceType( $type, $name, $metadataDescription = '')"
        $resources = @($global:currentConfig.resources | where-object 'type' -eq $type)
        $parameterNames = @{}

        foreach ($resource in $resources) {
            $parameterName = CreateParametersName -resource $resource -name $name
            $parameterizedName = CreateParameterizedName -parameterName $name -resource $resource -withbrackets
            $parameterNameValue = GetResourceParameterValue -resource $resource -name $name
            SetResourceParameterValue -resource $resource -name $name -newValue $parameterizedName

            if ($parameterNameValue -ne $null) {
                [void]$parameterNames.Add($parameterName, $parameterNameValue)
                WriteLog "AddParameterNameByResourceType:parametername added $parameterName : $parameterNameValue"
            }
        }

        WriteLog "AddParameterNameByResourceType:parameter names $parameterNames"
        foreach ($parameterName in $parameterNames.GetEnumerator()) {
            if (!(GetFromParametersSection -parameterName $parameterName.key)) {
                AddToParametersSection `
                    -parameterName $parameterName.key `
                    -parameterValue $parameterName.value `
                    -metadataDescription $metadataDescription
            }
        }
        WriteLog "exit:AddParameterNameByResourceType"
    }

    [void] AddParameter( [object]$resource, [string]$name, [string]$aliasName = $name, [object]$resourceObject = $resource, [object]$value = $null, [string]$type = 'string', [string]$metadataDescription = '') {
        <#
        .SYNOPSIS
            add a new parameter based on $resource $name/$aliasName $resourceObject
            outputs: null
        .OUTPUTS
            [null]
        #>
        $parameterName = CreateParametersName -resource $resource -name $aliasName
        $parameterizedName = CreateParameterizedName -parameterName $aliasName -resource $resource -withbrackets
        $parameterNameValue = $value

        if (!$parameterNameValue) {
            $parameterNameValue = GetResourceParameterValue -resource $resourceObject -name $name
        }
        WriteLog "enter:AddParameter( $resource, $name, $aliasName = $name, $resourceObject = $resource, $value = $null, $type = 'string', $metadataDescription = '')"
        $null = SetResourceParameterValue -resource $resourceObject -name $name -newValue $parameterizedName

        if ($parameterNameValue -ne $null) {
            WriteLog "AddParameter:adding parameter name:$parameterName parameter value:$parameterNameValue"
            if ((GetFromParametersSection -parameterName $parameterName) -eq $null) {
                WriteLog "AddParameter:$parameterName not found in parameters sections. adding."
                AddToParametersSection `
                    -parameterName $parameterName `
                    -parameterValue $parameterNameValue `
                    -type $type `
                    -metadataDescription $metadataDescription
            }
        }
        WriteLog "exit:AddParameter"
    }

    [void] AddToParametersSection( [string]$parameterName, [object]$parameterValue, [string]$type = 'string', [string]$metadataDescription = '') {
        <#
        .SYNOPSIS
            add a new parameter based on $parameterName and $parameterValue to parameters Setion
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:AddToParametersSection:parameterName:$parameterName, parameterValue:$parameterValue, $type = 'string', $metadataDescription"
        $parameterObject = @{
            type         = $type
            defaultValue = $parameterValue 
            metadata     = @{description = $metadataDescription }
        }

        foreach ($psObjectProperty in $global:currentConfig.parameters.psobject.Properties) {
            if (($psObjectProperty.Name -ieq $parameterName)) {
                $psObjectProperty.Value = $parameterObject
                WriteLog "exit:AddToParametersSection:parameterObject value added to existing parameter:$($parameterValue|CreateJson)"
                return
            }
        }

        $global:currentConfig.parameters | Add-Member -MemberType NoteProperty -Name $parameterName -Value $parameterObject
        WriteLog "exit:AddToParametersSection:new parameter name:$parameterName added $($parameterObject |CreateJson)"
    }

    [void] AddVmssProtectedSettings([object]$vmssResource) {
        <#
        .SYNOPSIS
            add wellknown protectedSettings section to vmss resource for storageAccounts
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:AddVmssProtectedSettings$($vmssResource.name)"
        $sflogsParameter = CreateParameterizedName -parameterName 'name' -resource $global:sflogs

        foreach ($extension in $vmssResource.properties.virtualMachineProfile.extensionPRofile.extensions) {
            if ($extension.properties.type -ieq 'ServiceFabricNode') {
                $extension.properties | Add-Member -MemberType NoteProperty -Name protectedSettings -Value @{
                    StorageAccountKey1 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', $sflogsParameter),'$storageKeyApi').key1]"
                    StorageAccountKey2 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', $sflogsParameter),'$storageKeyApi').key2]"
                }
                WriteLog "AddVmssProtectedSettings:added $($extension.properties.type) protectedsettings $($extension.properties.protectedSettings | CreateJson)" -ForegroundColor Magenta
            }

            if ($extension.properties.type -ieq 'IaaSDiagnostics') {
                $saname = $extension.properties.settings.storageAccount
                $sfdiagsParameter = CreateParameterizedName -parameterName 'name' -resource ($global:sfdiags | where-object name -imatch $saname)
                $extension.properties.settings.storageAccount = "[$sfdiagsParameter]"

                $extension.properties | Add-Member -MemberType NoteProperty -Name protectedSettings -Value @{
                    storageAccountName     = "$sfdiagsParameter"
                    storageAccountKey      = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', $sfdiagsParameter),'$storageKeyApi').key1]"
                    storageAccountEndPoint = "https://core.windows.net/"                  
                }
                WriteLog "AddVmssProtectedSettings:added $($extension.properties.type) protectedsettings $($extension.properties.protectedSettings | CreateJson)" -ForegroundColor Magenta
            }
        }
        WriteLog "exit:AddVmssProtectedSettings"
    }

    [bool] CheckModule() {
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
            WriteLog "azure module for Connect-AzAccount not installed." -isWarning

            get-command Connect-AzureRmAccount -ErrorAction SilentlyContinue
            if (!$error) {
                WriteLog "azure module for Connect-AzureRmAccount is installed. use cloud shell to run script instead https://shell.azure.com/" -isWarning
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

    [void] CreateAddPrimaryNodeTypeTemplate() {
        <#
        .SYNOPSIS
            creates new addprimarynodetype template with modifications based on redeploy template
            based off of first nodetype found where isPrimary = true
            isPrimary will be set to true
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:CreateAddPrimaryNodeTypeTemplate"
        # create add node type templates for primary os / hardware sku change
        # create secondary for additional secondary nodetypes
        $templateFile = $templateJsonFile.Replace(".json", ".addprimarynodetype.json")
        $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")

        if (!(ParameterizeNodetypes -isPrimaryFilter $true)) {
            WriteLog "exit:CreateAddPrimaryNodeTypeTemplate:no nodetype found" -isError
            return
        }

        CreateParameterFile  $templateParameterFile
        VerifyConfig $templateParameterFile

        # save base / current json
        $global:currentConfig | CreateJson | out-file $templateFile

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
        $readme | out-file $templateJsonFile.Replace(".json", ".addprimarynodetype.readme.txt")
        WriteLog "exit:create-addNodePrimaryTypeTemplate"
    }

    [void] CreateAddSecondaryNodeTypeTemplate() {
        <#
        .SYNOPSIS
            creates new addsecondarynodetype template with modifications based on redeploy template
            based off of first nodetype found where isPrimary = false
            isPrimary will be set to false
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:CreateAddSecondaryNodeTypeTemplate"
        # create add node type templates for primary os / hardware sku change
        # create secondary for additional secondary nodetypes
        $templateFile = $templateJsonFile.Replace(".json", ".addsecondarynodetype.json")
        $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")

        if (!(ParameterizeNodetypes)) {
            WriteLog "CreateAddSecondaryNodeTypeTemplate:no secondary nodetype found" -foregroundcolor Yellow

            if (!(ParameterizeNodetypes -isPrimaryFilter $true -isPrimaryValue $false)) {
                WriteLog "exit:CreateAddSecondaryNodeTypeTemplate:no primary nodetype found" -isError
                return
            }
        }


        CreateParameterFile  $templateParameterFile
        VerifyConfig $templateParameterFile

        # save base / current json
        $global:currentConfig | CreateJson | out-file $templateFile

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
        $readme | out-file $templateJsonFile.Replace(".json", ".addsecondarynodetype.readme.txt")
        WriteLog "exit:CreateAddSecondaryNodeTypeTemplate"
    }

    [void] CreateCurrentTemplate() {
        <#
        .SYNOPSIS
            creates new current template with modifications based on raw export template
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:CreateCurrentTemplate"
        # create base /current template
        $templateFile = $templateJsonFile.Replace(".json", ".current.json")
        $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")

        RemoveDuplicateResources
        RemoveUnusedParameters
        ModifyLbResources
        ModifyVmssResources
    
        CreateParameterFile  $templateParameterFile
        VerifyConfig $templateParameterFile

        # save base / current json
        $global:currentConfig | CreateJson | out-file $templateFile

        # save current readme
        $readme = "current modifications:
            - additional parameters have been added
            - extra / duplicate child resources removed from root
            - dependsOn modified to remove conflicting / unneeded resources
            - protectedSettings for vmss extensions cluster and diagnostic extensions are added and set to storage account settings
            "
        $readme | out-file $templateJsonFile.Replace(".json", ".current.readme.txt")
        WriteLog "exit:CreateCurrentTemplate"
    }

    [void] CreateExportTemplate() {
        <#
        .SYNOPSIS
            creates new export template from resource group and sets $global:currentConfig
            must be called before any modification functions
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:CreateExportTemplate"
        # create base /current template
        $templateFile = $templateJsonFile.Replace(".json", ".export.json")

        if ($useExportedJsonFile -and (test-path $useExportedJsonFile)) {
            WriteLog "using existing export file $useExportedJsonFile" -ForegroundColor Green
            $templateFile = $useExportedJsonFile
        }
        else {
            $exportResult = ExportTemplate -configuredResources $global:configuredRGResources -jsonFile $templateFile
            WriteLog "template exported to $templateFile" -ForegroundColor Yellow
            WriteLog "template export result $($exportResult|out-string)" -ForegroundColor Yellow
        }

        # save base / current json
        $global:currentConfig = Get-Content -raw $templateFile | convertfrom-json
        $global:currentConfig | CreateJson | out-file $templateFile

        # save current readme
        $readme = "export:
            - this is raw export from ps cmdlet export-azresourcegroup -includecomments -includeparameterdefaults
            - $templateFile will not be usable to recreate / create new cluster in this state
            - use 'current' to modify existing cluster
            - use 'redeploy' or 'new' to recreate / create cluster
            "
        $readme | out-file $templateJsonFile.Replace(".json", ".export.readme.txt")
        WriteLog "exit:CreateExportTemplate"
    }

    [string] CreateJson(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [object]$inputObject,
        [int]$depth = 99) {
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

    [void] CreateNewTemplate() {
        <#
        .SYNOPSIS
            creates new new template from based on addnodetype template
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:CreateNewTemplate"
        # create deploy / new / add template
        $templateFile = $templateJsonFile.Replace(".json", ".new.json")
        $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")
        $parameterExclusions = ModifyStorageResourcesDeploy
        ModifyVmssResourcesDeploy
        ModifyClusterResourceDeploy

        CreateParameterFile -parameterFileName $templateParameterFile -ignoreParameters $parameterExclusions
        VerifyConfig $templateParameterFile

        # # save add json
        $global:currentConfig | CreateJson | out-file $templateFile

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
        WriteLog "exit:CreateNewTemplate"
    }

    [void] CreateParameterFile( [string]$parameterFileName, [string[]]$ignoreParameters = @()) {
        <#
        .SYNOPSIS
            creates new template parameters files based on $global:currentConfig
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:CreateParameterFile( [string]$parameterFileName, [string[]]$ignoreParameters = @())"
 
        $parameterTemplate = [ordered]@{ 
            '$schema'      = $parametersSchema
            contentVersion = "1.0.0.0"
        } 

        # create pscustomobject
        $parameterTemplate | Add-Member -TypeName System.Management.Automation.PSCustomObject -NotePropertyMembers @{ parameters = @{} }
    
        foreach ($psObjectProperty in $global:currentConfig.parameters.psobject.Properties.GetEnumerator()) {
            if ($ignoreParameters.Contains($psObjectProperty.name)) {
                WriteLog "CreateParameterFile:skipping parameter $($psobjectProperty.name)"
                continue
            }

            WriteLog "CreateParameterFile:value properties:$($psObjectProperty.Value.psobject.Properties.Name)" -verbose
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

        WriteLog "CreateParameterFile:creating parameterfile $parameterFileName" -ForegroundColor Green
        $parameterTemplate | CreateJson | out-file -FilePath $parameterFileName
        WriteLog "exit:CreateParameterFile"
    }

    [string] CreateParameterizedName($parameterName, $resource = $null, [switch]$withbrackets) {
        <#
        .SYNOPSIS
            creates parameterized name for variables, resources, and outputs section based on $paramterName and $resource
            outputs: string
        .OUTPUTS
            [string]
        #>
        WriteLog "enter:CreateParameterizedName $parameterName, $resource = $null, [switch]$withbrackets"
        $retval = ""

        if ($resource) {
            $retval = CreateParametersName -resource $resource -name $parameterName
            $retval = "parameters('$retval')"
        }
        else {
            $retval = "parameters('$parameterName')"
        }

        if ($withbrackets) {
            $retval = "[$retval]"
        }

        WriteLog "exit:CreateParameterizedName:$retval"
        return $retval
    }

    [string] CreateParametersName([object]$resource, [string]$name = 'name') {
        <#
        .SYNOPSIS
            creates parameter name for parameters, variables, resources, and outputs section based on $resource and $name
            outputs: string
        .OUTPUTS
            [string]
        #>
        WriteLog "enter:CreateParametersName($resource, $name = 'name')"
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
        $parametersName = [regex]::replace($name, '^' + [regex]::Escape($parametersNamePrefix), '', $global:ignoreCase)
        $parametersName = "$($resourceSubType)_$($resourceName)_$($name)"

        WriteLog "exit:CreateParametersName returning:$parametersName"
        return $parametersName
    }

    [void] CreateRedeployTemplate() {
        <#
        .SYNOPSIS
            creates new redeploy template from current template
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:CreateRedeployTemplate"
        # create redeploy template
        $templateFile = $templateJsonFile.Replace(".json", ".redeploy.json")
        $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")

        ModifyClusterResourceRedeploy
        ModifyLbResourcesRedeploy
        ModifyVmssResourcesRedeploy
        ModifyIpAddressesRedeploy

        CreateParameterFile  $templateParameterFile
        VerifyConfig $templateParameterFile

        # # save redeploy json
        $global:currentConfig | CreateJson | out-file $templateFile

        # save redeploy readme
        $readme = "redeploy modifications:
            - microsoft monitoring agent extension has been removed (provisions automatically on deployment)
            - adminPassword required parameter added (needs to be set)
            - if upgradeMode for cluster resource is set to 'Automatic', clusterCodeVersion is removed
            - protectedSettings for vmss extensions cluster and diagnostic extensions are added and set to storage account settings
            - clusterendpoint is parameterized
            "
        $readme | out-file $templateJsonFile.Replace(".json", ".redeploy.readme.txt")
        WriteLog "exit:CreateRedeployTemplate"
    }

    [void] DisplaySettings([object[]]$resources) {
        <#
        .SYNOPSIS
            displays current resource settings
            outputs: null
        .OUTPUTS
            [null]
        #>
        $settings = @()
        foreach ($resource in $resources) {
            $settings += $resource | CreateJson
        }
        WriteLog "current settings: `r`n $settings" -ForegroundColor Green
    }

    [void] ExportTemplate($configuredResources, $jsonFile) {
        <#
        .SYNOPSIS
            exports raw teamplate from azure using export-azresourcegroup cmdlet
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:ExportTemplate:exporting template to $jsonFile" -ForegroundColor Yellow
        $resources = [collections.arraylist]@()
        $azResourceGroupLocation = @($configuredResources)[0].Location
        $resourceIds = @($configuredResources.ResourceId)

        # todo issue
        new-item -ItemType File -path $jsonFile -ErrorAction SilentlyContinue
        WriteLog "ExportTemplate:file exists:$((test-path $jsonFile))"
        WriteLog "ExportTemplate:resource ids: $resourceIds" -ForegroundColor green

        WriteLog "Export-AzResourceGroup -ResourceGroupName $resourceGroupName `
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
    
        WriteLog "exit:ExportTemplate:template exported to $jsonFile" -ForegroundColor Yellow
    }

    [object[]] EnumAllResources() {
        <#
        .SYNOPSIS
            enumerate all resources in resource group
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        WriteLog "enter:EnumAllResources"
        $resources = [collections.arraylist]::new()

        WriteLog "EnumAllResources:getting resource group cluster $resourceGroupName"
        $clusterResource = EnumClusterResource
        if (!$clusterResource) {
            WriteLog "EnumAllResources:unable to enumerate cluster. exiting" -isError
            return $null
        }
        [void]$resources.Add($clusterResource.Id)

        WriteLog "EnumAllResources:getting scalesets $resourceGroupName"
        $vmssResources = @(EnumVmssResources $clusterResource)
        if ($vmssResources.Count -lt 1) {
            WriteLog "EnumAllResources:unable to enumerate vmss. exiting" -isError
            return $null
        }
        else {
            [void]$resources.AddRange(@($vmssResources.Id))
        }

        WriteLog "EnumAllResources:getting storage $resourceGroupName"
        $storageResources = @(EnumStorageResources $clusterResource)
        if ($storageResources.count -lt 1) {
            WriteLog "EnumAllResources:unable to enumerate storage. exiting" -isError
            return $null
        }
        else {
            [void]$resources.AddRange(@($storageResources.Id))
        }
    
        WriteLog "EnumAllResources:getting virtualnetworks $resourceGroupName"
        $vnetResources = @(EnumVnetResourceIds $vmssResources)
        if ($vnetResources.count -lt 1) {
            WriteLog "EnumAllResources:unable to enumerate vnets. exiting" -isError
            return $null
        }
        else {
            [void]$resources.AddRange($vnetResources)
        }

        WriteLog "EnumAllResources:getting loadbalancers $resourceGroupName"
        $lbResources = @(EnumLbResourceIds $vmssResources)
        if ($lbResources.count -lt 1) {
            WriteLog "EnumAllResources:unable to enumerate loadbalancers. exiting" -isError
            return $null
        }
        else {
            [void]$resources.AddRange($lbResources)
        }

        WriteLog "EnumAllResources:getting ip addresses $resourceGroupName"
        $ipResources = @(EnumIpResourceIds $lbResources)
        if ($ipResources.count -lt 1) {
            WriteLog "EnumAllResources:unable to enumerate ips." -isWarning
        }
        else {
            [void]$resources.AddRange($ipResources)
        }

        WriteLog "EnumAllResources:getting key vaults $resourceGroupName"
        $kvResources = @(EnumKvResourceIds $vmssResources)
        if ($kvResources.count -lt 1) {
            WriteLog "EnumAllResources:unable to enumerate key vaults." -isWarning
        }
        else {
            [void]$resources.AddRange($kvResources)
        }

        WriteLog "EnumAllResources:getting nsgs $resourceGroupName"
        $nsgResources = @(EnumNsgResourceIds $vmssResources)
        if ($nsgResources.count -lt 1) {
            WriteLog "EnumAllResources:unable to enumerate nsgs." -isWarning
        }
        else {
            [void]$resources.AddRange($nsgResources)
        }

        if ($excludeResourceNames) {
            $resources = $resources | where-object Name -NotMatch "$($excludeResourceNames -join "|")"
        }

        WriteLog "exit:EnumAllResources"
        return $resources | sort-object -Unique
    }

    [object] EnumClusterResource() {
        <#
        .SYNOPSIS
            enumerate cluster resource using get-azresource.
            will prompt if multiple cluster resources found.
            outputs: object
        .OUTPUTS
            [object]
        #>
        WriteLog "enter:EnumClusterResource"
        $clusters = @(get-azresource -ResourceGroupName $resourceGroupName `
                -ResourceType 'Microsoft.ServiceFabric/clusters' `
                -ExpandProperties)
        $clusterResource = $null
        $count = 1
        $number = 0

        WriteLog "all clusters $clusters" -verbose
        if ($clusters.count -gt 1) {
            foreach ($cluster in $clusters) {
                WriteLog "$($count). $($cluster.name)"
                $count++
            }
        
            $number = [convert]::ToInt32((read-host "enter number of the cluster to query or ctrl-c to exit:"))
            if ($number -le $count) {
                $clusterResource = $cluster[$number - 1].Name
                WriteLog $clusterResource
            }
            else {
                return $null
            }
        }
        elseif ($clusters.count -lt 1) {
            WriteLog "error:EnumClusterResource: no cluster found" -isError
            return $null
        }
        else {
            $clusterResource = $clusters[0]
        }

        WriteLog "using cluster resource $clusterResource" -ForegroundColor Green
        WriteLog "exit:EnumClusterResource"
        $global:clusterTree.cluster.resource = $clusterResource
        return $clusterResource
    }

    [string[]] EnumIpResourceIds([object[]]$lbResources) {
        <#
        .SYNOPSIS
            enumerate ip resource id's from lb resources
            outputs: string[]
        .OUTPUTS
            [string[]]
        #>
        WriteLog "enter:EnumIpResourceIds"
        $resources = [collections.arraylist]::new()

        foreach ($lbResource in $lbResources) {
            WriteLog "checking lbResource for ip config $lbResource"
            $lb = get-azresource -ResourceId $lbResource -ExpandProperties
            foreach ($fec in $lb.Properties.frontendIPConfigurations) {
                if ($fec.properties.publicIpAddress) {
                    $id = $fec.properties.publicIpAddress.id
                    WriteLog "adding public ip: $id" -ForegroundColor green
                    [void]$resources.Add($id)
                }
            }
        }

        WriteLog "EnumIpResourceIds:ip resources $resources" -verbose
        WriteLog "exit:EnumIpResourceIds"
        return $resources.ToArray() | sort-object -Unique
    }

    [string[]] EnumKvResourceIds([object[]]$vmssResources) {
        <#
        .SYNOPSIS
            enumerate keyvault resource id's from vmss resources
            outputs: string[]
        .OUTPUTS
            [string[]]
        #>
        WriteLog "enter:EnumKvResourceIds"
        $resources = [collections.arraylist]::new()

        foreach ($vmssResource in $vmssResources) {
            WriteLog "EnumKvResourceIds:checking vmssResource for key vaults $($vmssResource.Name)"
            foreach ($id in $vmssResource.Properties.virtualMachineProfile.osProfile.secrets.sourceVault.id) {
                WriteLog "EnumKvResourceIds:adding kv id: $id" -ForegroundColor green
                [void]$resources.Add($id)
            }
        }

        WriteLog "kv resources $resources" -verbose
        WriteLog "exit:EnumKvResourceIds"
        return $resources.ToArray() | sort-object -Unique
    }

    [string[]] EnumLbResourceIds([object[]]$vmssResources) {
        <#
        .SYNOPSIS
            enumerate loadbalancer resource id's from vmss resources
            outputs: string[]
        .OUTPUTS
            [string[]]
        #>
        WriteLog "enter:EnumLbResourceIds"
        $resources = [collections.arraylist]::new()

        foreach ($vmssResource in $vmssResources) {
            # get nic for vnet/subnet and lb
            WriteLog "EnumLbResourceIds:checking vmssResource for network config $($vmssResource.Name)"
            foreach ($nic in $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations) {
                foreach ($ipconfig in $nic.properties.ipConfigurations) {
                    $id = [regex]::replace($ipconfig.properties.loadBalancerBackendAddressPools.id, '/backendAddressPools/.+$', '')
                    WriteLog "EnumLbResourceIds:adding lb id: $id" -ForegroundColor green
                    [void]$resources.Add($id)
                }
            }
        }

        WriteLog "lb resources $resources" -verbose
        WriteLog "exit:EnumLbResourceIds"
        return $resources.ToArray() | sort-object -Unique
    }

    [string[]] EnumNsgResourceIds([object[]]$vmssResources) {
        <#
        .SYNOPSIS
            enumerate network security group resource id's from vmss resources
            outputs: string[]
        .OUTPUTS
            [string[]]
        #>
        WriteLog "enter:EnumNsgResourceIds"
        $resources = [collections.arraylist]::new()

        foreach ($vnetId in $vnetResources) {
            $vnetresource = @(get-azresource -ResourceId $vnetId -ExpandProperties)
            WriteLog "EnumNsgResourceIds:checking vnet resource for nsg config $($vnetresource.Name)"
            foreach ($subnet in $vnetResource.Properties.subnets) {
                if ($subnet.properties.networkSecurityGroup.id) {
                    $id = $subnet.properties.networkSecurityGroup.id
                    WriteLog "EnumNsgResourceIds:adding nsg id: $id" -ForegroundColor green
                    [void]$resources.Add($id)
                }
            }

        }

        WriteLog "nsg resources $resources" -verbose
        WriteLog "exit:EnumNsgResourceIds"
        return $resources.ToArray() | sort-object -Unique
    }

    [object[]] EnumStorageResources([object]$clusterResource) {
        <#
        .SYNOPSIS
            enumerate storage resources from cluster resource
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        WriteLog "enter:EnumStorageResources"
        $resources = [collections.arraylist]::new()
    
        $sflogs = $clusterResource.Properties.diagnosticsStorageAccountConfig.storageAccountName
        WriteLog "EnumStorageResources:cluster sflogs storage account $sflogs"

        $scalesets = EnumVmssResources($clusterResource)
        $sfdiags = @(($scalesets.Properties.virtualMachineProfile.extensionProfile.extensions.properties | where-object type -eq 'IaaSDiagnostics').settings.storageAccount) | Sort-Object -Unique
        WriteLog "EnumStorageResources:cluster sfdiags storage account $sfdiags"
  
        $storageResources = @(get-azresource -ResourceGroupName $resourceGroupName `
                -ResourceType 'Microsoft.Storage/storageAccounts' `
                -ExpandProperties)

        $global:sflogs = $storageResources | where-object name -ieq $sflogs
        $global:sfdiags = @($storageResources | where-object name -ieq $sfdiags)
    
        [void]$resources.add($global:sflogs)
        foreach ($sfdiag in $global:sfdiags) {
            WriteLog "EnumStorageResources: adding $sfdiag"
            [void]$resources.add($sfdiag)
        }
    
        WriteLog "storage resources $resources" -verbose
        WriteLog "exit:EnumStorageResources"
        return $resources.ToArray() | sort-object name -Unique
    }

    [object[]] EnumVmssResources([object]$clusterResource) {
        <#
        .SYNOPSIS
            enumerate virtual machine scaleset resources from cluster resource
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        WriteLog "enter:EnumVmssResources"
        $nodeTypes = $clusterResource.Properties.nodeTypes
        WriteLog "EnumVmssResources:cluster nodetypes $($nodeTypes| CreateJson)"
        $vmssResources = [collections.arraylist]::new()

        $clusterEndpoint = $clusterResource.Properties.clusterEndpoint
        WriteLog "EnumVmssResources:cluster id $clusterEndpoint" -ForegroundColor Green
    
        if (!$nodeTypes -or !$clusterEndpoint) {
            WriteLog "exit:EnumVmssResources:nodetypes:$nodeTypes clusterEndpoint:$clusterEndpoint" -isError
            return $null
        }

        $resources = @(get-azresource -ResourceGroupName $resourceGroupName `
                -ResourceType 'Microsoft.Compute/virtualMachineScaleSets' `
                -ExpandProperties)

        WriteLog "EnumVmssResources:vmss resources $resources" -verbose

        foreach ($resource in $resources) {
            $vmsscep = ($resource.Properties.virtualMachineProfile.extensionprofile.extensions.properties.settings | Select-Object clusterEndpoint).clusterEndpoint
            if ($vmsscep -ieq $clusterEndpoint) {
                WriteLog "EnumVmssResources:adding vmss resource $($resource | CreateJson)" -ForegroundColor Cyan
                [void]$vmssResources.Add($resource)
            }
            else {
                WriteLog "EnumVmssResources:vmss assigned to different cluster $vmsscep" -isWarning
            }
        }

        WriteLog "exit:EnumVmssResources"
        $global:clusterTree.cluster.resource = $clusterResource
        return $vmssResources.ToArray() | sort-object name -Unique
    }

    [string[]] EnumVnetResourceIds([object[]]$vmssResources) {
        <#
        .SYNOPSIS
            enumerate virtual network resource Ids from vmss resources
            outputs: string[]
        .OUTPUTS
            [string[]]
        #>
        WriteLog "enter:EnumVnetResourceIds"
        $resources = [collections.arraylist]::new()

        foreach ($vmssResource in $vmssResources) {
            # get nic for vnet/subnet and lb
            WriteLog "EnumVnetResourceIds:checking vmssResource for network config $($vmssResource.Name)"
            foreach ($nic in $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations) {
                foreach ($ipconfig in $nic.properties.ipConfigurations) {
                    $id = [regex]::replace($ipconfig.properties.subnet.id, '/subnets/.+$', '')
                    WriteLog "EnumVnetResourceIds:adding vnet id: $id" -ForegroundColor green
                    [void]$resources.Add($id)
                }
            }
        }

        WriteLog "vnet resources $resources" -verbose
        WriteLog "exit:EnumVnetResourceIds"
        return $resources.ToArray() | sort-object -Unique
    }

    [object] GetClusterResource() {
        <#
        .SYNOPSIS
            enumerate cluster resources[0] from $global:currentConfig
            outputs: object
        .OUTPUTS
            [object]
        #>
        WriteLog "enter:GetClusterResource"
        $resources = @($global:currentConfig.resources | Where-Object type -ieq 'Microsoft.ServiceFabric/clusters')
    
        if ($resources.count -ne 1) {
            WriteLog "unable to find cluster resource" -isError
        }

        WriteLog "returning cluster resource $resources" -verbose
        WriteLog "exit:GetClusterResource:$($resources[0])"
        return $resources[0]
    }

    [object[]] GetLbResources() {
        <#
        .SYNOPSIS
            enumerate loadbalancer resources from $global:currentConfig
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        WriteLog "enter:GetLbResources"
        $resources = @($global:currentConfig.resources | Where-Object type -ieq 'Microsoft.Network/loadBalancers')
    
        if ($resources.count -eq 0) {
            WriteLog "unable to find lb resource" -isError
        }

        WriteLog "returning lb resource $resources" -verbose
        WriteLog "exit:GetLbResources:$($resources.count)"
        return $resources
    }

    [object[]] GetFromParametersSection( [string]$parameterName) {
        <#
        .SYNOPSIS
            enumerate defaultValue[] from parameters section by $parameterName
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        WriteLog "enter:GetFromParametersSection parameterName=$parameterName"
        $results = $null
        $parameters = @($global:currentConfig.parameters)
        $currentErrorPreference = $ErrorActionPreference
        $ErrorActionPreference = 'silentlycontinue'

        $results = @($parameters.$parameterName.defaultValue)
        $ErrorActionPreference = $currentErrorPreference
    
        if (@($results).Count -lt 1) {
            WriteLog "GetFromParametersSection:no matching values found in parameters section for $parameterName"
        }
        if (@($results).count -gt 1) {
            WriteLog "GetFromParametersSection:multiple matching values found in parameters section for $parameterName" -isWarning
        }

        WriteLog "exit:GetFromParametersSection: returning: $($results | CreateJson)" -ForegroundColor Magenta
        return $results
    }

    [string] GetParameterizedNameFromValue([object]$resourceObject) {
        <#
        .SYNOPSIS
            enumerate parameter name from parameter value that is parameterized
            [regex]::match($resourceobject, "\[parameters\('(.+?)'\)\]")
            outputs: string
        .OUTPUTS
            [string]
        #>
        WriteLog "enter:GetParameterizedNameFromValue($resourceObject)"
        $retval = $null
        if ([regex]::IsMatch($resourceobject, "\[parameters\('(.+?)'\)\]", $global:ignoreCase)) {
            $retval = [regex]::match($resourceobject, "\[parameters\('(.+?)'\)\]", $global:ignoreCase).groups[1].Value
        }

        WriteLog "exit:GetParameterizedNameFromValue:returning $retval"
        return $retval
    }

    [object] GetResourceParameterValue([object]$resource, [string]$name) {
        <#
        .SYNOPSIS
            gets resource parameter value from $resource object by $name
            outputs: object
        .OUTPUTS
            [object]
        #>
        WriteLog "enter:GetResourceParameterValue:resource:$($resource|CreateJson) name:$name"
        $retval = $null
        $values = [collections.arraylist]::new()
        [void]$values.AddRange(@(GetResourceParameterValues -resource $resource -name $name))
    
        if ($values.Count -eq 1) {
            WriteLog "GetResourceParameterValue:parameter name found in resource. returning first value" -foregroundcolor Magenta
            $retval = @($values)[0]
        }
        elseif ($values.Count -gt 1) {
            WriteLog "GetResourceParameterValue:multiple parameter names found in resource. returning first value" -isError
            $retval = @($values)[0]
        }
        elseif ($values.Count -lt 1) {
            WriteLog "GetResourceParameterValue:no parameter name found in resource. returning $null" -isError
        }
        WriteLog "exit:GetResourceParameterValue:returning:$retval" -foregroundcolor Magenta
        return $retval
    }

    [object[]] GetResourceParameterValues([object]$resource, [string]$name) {
        <#
        .SYNOPSIS
            gets resource parameter values from $resource object by regex ^$name$
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        WriteLog "enter:GetResourceParameterValues:resource:$($resource|CreateJson) name:$name"
        $retval = [collections.arraylist]::new()

        if ($resource.psobject.members.name -imatch 'ToArray') {
            foreach ($resourceObject in $resource.ToArray()) {
                [void]$retval.AddRange(@(GetResourceParameterValues -resource $resourceObject -name $name))
            }
        }
        elseif ($resource.psobject.members.name -imatch 'GetEnumerator') {
            foreach ($resourceObject in $resource.GetEnumerator()) {
                [void]$retval.AddRange(@(GetResourceParameterValues -resource $resourceObject -name $name))
            }
        }

        foreach ($psObjectProperty in $resource.psobject.Properties.GetEnumerator()) {
        
            WriteLog "GetResourceParameterValues:checking parameter name:$($psobjectProperty.name)`r`n`tparameter type:$($psObjectProperty.TypeNameOfValue)`r`n`tfilter:$name" -verbose

            if (($psObjectProperty.Name -imatch "^$name$")) {
                $parameterValues = @($psObjectProperty | Where-Object Name -imatch "^$name$")
                if ($parameterValues.Count -eq 1) {
                    $parameterValue = $psObjectProperty.Value
                    if (!($parameterValue)) {
                        WriteLog "GetResourceParameterValues:returning:string::empty" -foregroundcolor green
                        [void]$retval.Add([string]::Empty)
                    }
                    else {
                        WriteLog "GetResourceParameterValues:returning:$parameterValue" -foregroundcolor green
                        [void]$retval.Add($parameterValue)
                    }
                }
                else {
                    WriteLog "GetResourceParameterValues:multiple parameter names found in resource"
                    [void]$retval.AddRange($parameterValues)
                }
            }
            elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Management.Automation.PSCustomObject') {
                [void]$retval.AddRange(@(GetResourceParameterValues -resource $psObjectProperty.Value -name $name))
            }
            elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Collections.Hashtable') {
                [void]$retval.AddRange(@(GetResourceParameterValues -resource $psObjectProperty.Value -name $name))
            }
            elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Collections.ArrayList') {
                [void]$retval.AddRange(@(GetResourceParameterValues -resource $psObjectProperty.Value -name $name))
            }
            else {
                WriteLog "GetResourceParameterValues:skipping property name:$($psObjectProperty.Name) type:$($psObjectProperty.TypeNameOfValue) filter:$name"
                #WriteLog "GetResourceParameterValue:skipping property name:$($psObjectProperty|CreateJson) type:$($psObjectProperty.TypeNameOfValue) filter:$name" -verbose
            }
        }
        WriteLog "exit:GetResourceParameterValues:returning:$retval" -foregroundcolor Magenta
        return $retval.ToArray()
    }

    [object] GetResourceParameterValueObject($resource, $name) {
        <#
        .SYNOPSIS
            get resource parameter value object
            outputs: object
        .OUTPUTS
            [object]
        #>
        WriteLog "enter:GetResourceParameterValueObjet:name $name"
        $retval = $null
        foreach ($psObjectProperty in $resource.psobject.Properties) {
            WriteLog "GetResourceParameterValueObject:checking parameter object $psobjectProperty" -verbose

            if (($psObjectProperty.Name -ieq $name)) {
                $parameterValues = @($psObjectProperty.Name)
                if ($parameterValues.Count -eq 1) {
                    WriteLog "GetResourceParameterValueObject:returning parameter object $psobjectProperty" -verbose
                    $retval = $resource.psobject.Properties[$psObjectProperty.name]
                    break
                }
                else {
                    WriteLog "GetResourceParameterValueObject:multiple parameter names found in resource. returning" -isError
                    $retval = $null
                    break
                }
            }
            elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Management.Automation.PSCustomObject') {
                $retval = GetResourceParameterValueObject -resource $psObjectProperty.Value -name $name
            }
            else {
                WriteLog "GetResourceParameterValueObject: skipping. property name:$($psObjectProperty.Name) name:$name type:$($psObjectProperty.TypeNameOfValue)" -verbose
            }
        }

        WriteLog "exit:GetResourceParameterValueObject: returning $retval"
        return $retval
    }

    [bool] GetUpdate($updateUrl) {
        <#
        .SYNOPSIS
            checks for script update
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        WriteLog "GetUpdate:checking for updated script: $($updateUrl)"
        $gitScript = $null
        $scriptFile = $MyInvocation.ScriptName

        $error.Clear()
        $gitScript = Invoke-RestMethod -Uri $updateUrl 

        if (!$error -and $gitScript) {
            WriteLog "reading $scriptFile"
            $currentScript = get-content -raw $scriptFile
    
            WriteLog "comparing export and current functions" -verbose
            if ([string]::Compare([regex]::replace($gitScript, "\s", ""), [regex]::replace($currentScript, "\s", "")) -eq 0) {
                WriteLog "no change to $scriptFile. skipping update." -ForegroundColor Cyan
                $error.Clear()
                return $false
            }

            $error.clear()
            out-file -inputObject $gitScript -FilePath $scriptFile -Force

            if (!$error) {
                WriteLog "$scriptFile has been updated. restart script." -ForegroundColor yellow
                return $true
            }

            WriteLog "$scriptFile has not been updated." -isWarning
        }
        else {
            WriteLog "error checking for updated script $error" -isWarning
            $error.Clear()
            return $false
        }
    }

    [object[]] GetVmssExtensions([object]$vmssResource, [string]$extensionType = $null) {
        <#
        .SYNOPSIS
            returns vmss extension resources from $vmssResource
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        WriteLog "enter:GetVmssExtensions:vmssname: $($vmssResource.name)"
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
            WriteLog "GetVmssExtensions:unable to find extension in vmss resource $($vmssResource.name) $extensionType" -isError
        }

        WriteLog "exit:GetVmssExtensions:results count: $($results.count)"
        return $results.ToArray()
    }

    [object[]] GetVmssResources() {
        <#
        .SYNOPSIS
            returns vmss resources from $global:currentConfig
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        WriteLog "enter:GetVmssResources"
        $resources = @($global:currentConfig.resources | Where-Object type -ieq 'Microsoft.Compute/virtualMachineScaleSets')
        if ($resources.count -eq 0) {
            WriteLog "GetVmssResources:unable to find vmss resource" -isError
        }
        WriteLog "GetVmssResources:returning vmss resource $resources" -verbose
        WriteLog "exit:GetVmssResources"
        return $resources
    }

    [object[]] GetVmssResourcesByNodeType( [object]$nodetypeResource) {
        <#
        .SYNOPSIS
            returns vmss resources from $global:currentConfig by $nodetypeResource
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        WriteLog "enter:GetVmssResourcesByNodeType"
        $vmssResources = GetVmssResources
        $vmssByNodeType = [collections.arraylist]::new()

        foreach ($vmssResource in $vmssResources) {
            $extension = GetVmssExtensions -vmssResource $vmssResource -extensionType 'ServiceFabricNode'
            $parameterizedName = GetParameterizedNameFromValue $extension.properties.settings.nodetyperef

            if ($parameterizedName) {
                $nodetypeName = GetFromParametersSection -parameterName $parameterizedName
            }
            else {
                $nodetypeName = $extension.properties.settings.nodetyperef
            }

            if ($nodetypeName -ieq $nodetypeResource.name) {
                WriteLog "found scaleset by nodetyperef $nodetypeName" -foregroundcolor Cyan
                [void]$vmssByNodeType.add($vmssResource)
            }
        }

        WriteLog "exit:GetVmssResourcesByNodeType:result count:$($vmssByNodeType.count)"
        return $vmssByNodeType.ToArray()
    }

    [void] ModifyClusterResourceDeploy() {
        <#
        .SYNOPSIS
            modifies cluster resource for deploy template from addnodetype
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:ModifyClusterResourceDeploy"
        # clean previous entries
        #$null = RemoveParameterizedNodeTypes
    
        # reparameterize all
        ParameterizeNodetypes -all
    
        # remove unparameterized nodetypes
        #$null = RemoveUnparameterizedNodeTypes
        WriteLog "exit:ModifyClusterResourceDeploy"
    }


    [void] ModifyClusterResourceRedeploy() {
        <#
        .SYNOPSIS
            modifies cluster resource for redeploy template from current
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:ModifyClusterResourceRedeploy"
        $sflogsParameter = CreateParameterizedName -parameterName 'name' -resource $global:sflogs -withbrackets
        $clusterResource = GetClusterResource
    
        WriteLog "ModifyClusterResourceRedeploy:setting `$clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter"
        $clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter
    
        if ($clusterResource.properties.upgradeMode -ieq 'Automatic') {
            WriteLog "ModifyClusterResourceRedeploy:removing value cluster code version $($clusterResource.properties.clusterCodeVersion)" -ForegroundColor Yellow
            [void]$clusterResource.properties.psobject.Properties.remove('clusterCodeVersion')
        }
    
        $reference = "[reference($(CreateParameterizedName -parameterName 'name' -resource $clusterResource))]"
        AddOutputs -name 'clusterProperties' -value $reference -type 'object'
        WriteLog "exit:ModifyClusterResourceDeploy"
    }

    [void] ModifyIpAddressesRedeploy() {
        <#
        .SYNOPSIS
            modifies ip resources for redeploy template
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:ModifyIpAddressesRedeploy"
        # add ip address dns parameter
        $metadataDescription = 'this name must be unique in deployment region.'
        $dnsSettings = AddParameterNameByResourceType -type "Microsoft.Network/publicIPAddresses" -name 'domainNameLabel' -metadataDescription $metadataDescription
        $fqdn = AddParameterNameByResourceType -type "Microsoft.Network/publicIPAddresses" -name 'fqdn' -metadataDescription $metadataDescription
        WriteLog "exit:ModifyIpAddressesRedeploy"
    }

    [void] ModifyLbResources($currenConfig) {
        <#
        .SYNOPSIS
            modifies loadbalancer resources for current
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:ModifyLbResources"
        $lbResources = GetLbResources
        foreach ($lbResource in $lbResources) {
            # fix backend pool
            WriteLog "ModifyLbResources:fixing exported lb resource $($lbresource | CreateJson)"
            $parameterName = GetParameterizedNameFromValue $lbresource.name
            if ($parameterName) {
                $name = $global:currentConfig.parameters.$parametername.defaultValue
            }

            if (!$name) {
                $name = $lbResource.name
            }

            $lb = get-azresource -ResourceGroupName $resourceGroupName -Name $name -ExpandProperties -ResourceType 'Microsoft.Network/loadBalancers'
            $dependsOn = [collections.arraylist]::new()

            WriteLog "ModifyLbResources:removing backendpool from lb dependson"
            foreach ($depends in $lbresource.dependsOn) {
                if ($depends -inotmatch $lb.Properties.backendAddressPools.Name) {
                    [void]$dependsOn.Add($depends)
                }
            }
            $lbResource.dependsOn = $dependsOn.ToArray()
            WriteLog "ModifyLbResources:lbResource modified dependson: $($lbResource.dependson | CreateJson)" -ForegroundColor Yellow
        }
        WriteLog "exit:ModifyLbResources"
    }

    [void] ModifyLbResourcesRedeploy($currenConfig) {
        <#
        .SYNOPSIS
            modifies loadbalancer resources for redeploy template
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:ModifyLbResourcesRedeploy"
        $lbResources = GetLbResources
        foreach ($lbResource in $lbResources) {
            # fix dupe pools and rules
            if ($lbResource.properties.inboundNatPools) {
                WriteLog "ModifyLbResourcesRedeploy:removing natrules: $($lbResource.properties.inboundNatRules | CreateJson)" -ForegroundColor Yellow
                [void]$lbResource.properties.psobject.Properties.Remove('inboundNatRules')
            }
        }
        WriteLog "exit:ModifyLbResourcesRedeploy"
    }

    [void] ModifyStorageResourcesDeploy() {
        <#
        .SYNOPSIS
            modifies storage resources for deploy template
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:ModifyStorageResourcesDeploy"
        $metadataDescription = 'this name must be unique in deployment region.'
        $parameterExclusions = [collections.arraylist]::new()
        $sflogsParameter = CreateParametersName -resource $global:sflogs
        [void]$parameterExclusions.Add($sflogsParameter)

        AddToParametersSection `
            -parameterName $sflogsParameter `
            -parameterValue $global:defaultSflogsValue `
            -metadataDescription $metadataDescription

        foreach ($sfdiag in $global:sfdiags) {
            $sfdiagParameter = CreateParametersName -resource $sfdiag
            [void]$parameterExclusions.Add($sfdiagParameter)
            AddToParametersSection `
                -parameterName $sfdiagParameter `
                -parameterValue $global:defaultSfdiagsValue `
                -metadataDescription $metadataDescription
        }

        WriteLog "exit:ModifyStorageResourcesDeploy"
        return $parameterExclusions.ToArray()
    }

    [void] ModifyVmssResources($currenConfig) {
        <#
        .SYNOPSIS
            modifies vmss resources for current template
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:ModifyVmssResources"
        $vmssResources = GetVmssResources
   
        foreach ($vmssResource in $vmssResources) {

            WriteLog "modifying dependson"
            $dependsOn = [collections.arraylist]::new()
            $subnetIds = @($vmssResource.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.ipconfigurations.properties.subnet.id)

            foreach ($depends in $vmssResource.dependsOn) {
                if ($depends -imatch 'backendAddressPools') { continue }

                if ($depends -imatch 'Microsoft.Network/loadBalancers') {
                    [void]$dependsOn.Add($depends)
                }
                # example depends "[resourceId('Microsoft.Network/virtualNetworks/subnets', parameters('virtualNetworks_VNet_name'), 'Subnet-0')]"
                if ($subnetIds.contains($depends)) {
                    WriteLog 'cleaning subnet dependson' -ForegroundColor Yellow
                    $depends = $depends.replace("/subnets'", "/'")
                    $depends = [regex]::replace($depends, "\), '.+?'\)\]", "))]")
                    [void]$dependsOn.Add($depends)
                }
            }
            $vmssResource.dependsOn = $dependsOn.ToArray()
            WriteLog "vmssResource modified dependson: $($vmssResource.dependson | CreateJson)" -ForegroundColor Yellow
        }
        WriteLog "exit:ModifyVmssResources"
    }

    [void] ModifyVmssResourcesDeploy($currenConfig) {
        <#
        .SYNOPSIS
            modifies storage vmss for deploy template
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:ModifyVmssResourcesDeploy"
        $vmssResources = GetVmssResources
        foreach ($vmssResource in $vmssResources) {
            $extension = GetVmssExtensions -vmssResource $vmssResource -extensionType 'ServiceFabricNode'
            $clusterResource = GetClusterResource

            $parameterizedName = CreateParameterizedName -parameterName 'name' -resource $clusterResource
            $newName = "[reference($parameterizedName).clusterEndpoint]"

            WriteLog "setting cluster endpoint to $newName"
            SetResourceParameterValue -resource $extension.properties.settings -name 'clusterEndpoint' -newValue $newName
            # remove clusterendpoint parameter
            RemoveUnusedParameters
        }
        WriteLog "exit:ModifyVmssResourcesDeploy"
    }

    [void] ModifyVmssResourcesRedeploy($currenConfig) {
        <#
        .SYNOPSIS
            modifies vmss resources for redeploy template
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:ModifyVmssResourcesReDeploy"
        $vmssResources = GetVmssResources
   
        foreach ($vmssResource in $vmssResources) {
            # add protected settings
            AddVmssProtectedSettings($vmssResource)

            # remove mma
            $extensions = [collections.arraylist]::new()
            foreach ($extension in $vmssResource.properties.virtualMachineProfile.extensionProfile.extensions) {
                if ($extension.properties.type -ieq 'MicrosoftMonitoringAgent') {
                    continue
                }
                if ($extension.properties.type -ieq 'ServiceFabricNode') {
                    WriteLog "ModifyVmssResourcesReDeploy:parameterizing cluster endpoint"
                    AddParameter -resource $vmssResource -name 'clusterEndpoint' -resourceObject $extension.properties.settings
                }
                [void]$extensions.Add($extension)
            }    
            $vmssResource.properties.virtualMachineProfile.extensionProfile.extensions = $extensions

            WriteLog "ModifyVmssResourcesReDeploy:modifying dependson"
            $dependsOn = [collections.arraylist]::new()
            $subnetIds = @($vmssResource.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.ipconfigurations.properties.subnet.id)

            foreach ($depends in $vmssResource.dependsOn) {
                if ($depends -imatch 'backendAddressPools') { continue }

                if ($depends -imatch 'Microsoft.Network/loadBalancers') {
                    [void]$dependsOn.Add($depends)
                }
                # example depends "[resourceId('Microsoft.Network/virtualNetworks/subnets', parameters('virtualNetworks_VNet_name'), 'Subnet-0')]"
                if ($subnetIds.contains($depends)) {
                    WriteLog 'ModifyVmssResourcesReDeploy:cleaning subnet dependson' -ForegroundColor Yellow
                    $depends = $depends.replace("/subnets'", "/'")
                    $depends = [regex]::replace($depends, "\), '.+?'\)\]", "))]")
                    [void]$dependsOn.Add($depends)
                }
            }

            $vmssResource.dependsOn = $dependsOn.ToArray()
            WriteLog "ModifyVmssResourcesReDeploy:vmssResource modified dependson: $($vmssResource.dependson | CreateJson)" -ForegroundColor Yellow
            
            WriteLog "ModifyVmssResourcesReDeploy:parameterizing hardware sku"
            AddParameter -resource $vmssResource -name 'name' -aliasName 'hardwareSku' -resourceObject $vmssResource.sku
            
            WriteLog "ModifyVmssResourcesReDeploy:parameterizing hardware capacity"
            AddParameter -resource $vmssResource -name 'capacity' -resourceObject $vmssResource.sku -type 'int'

            WriteLog "ModifyVmssResourcesReDeploy:parameterizing os sku"
            AddParameter -resource $vmssResource -name 'sku' -aliasName 'osSku' -resourceObject $vmssResource.properties.virtualMachineProfile.storageProfile.imageReference

            if (!($vmssResource.properties.virtualMachineProfile.osProfile.psobject.Properties | where-object name -ieq 'adminPassword')) {
                WriteLog "ModifyVmssResourcesReDeploy:adding admin password"
                $vmssResource.properties.virtualMachineProfile.osProfile | Add-Member -MemberType NoteProperty -Name 'adminPassword' -Value $adminPassword
            
                AddParameter `
                    -resource $vmssResource `
                    -name 'adminPassword' `
                    -resourceObject $vmssResource.properties.virtualMachineProfile.osProfile `
                    -metadataDescription 'password must be set before deploying template.'
            }
        }
        WriteLog "exit:ModifyVmssResourcesReDeploy"
    }

    [void] ParameterizeNodetype( [object]$nodetype, [string]$parameterName, [object]$parameterValue = $null, [string]$type = 'string') {
        <#
        .SYNOPSIS
            parameterizes nodetype for addnodetype template
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:ParameterizeNodetype:nodetype:$($nodetype |CreateJson) parameterName:$parameterName parameterValue:$parameterValue type:$type"
        $vmssResources = @(GetVmssResourcesByNodeType -nodetypeResource $nodetype)
        $parameterizedName = $null

        if ($parameterValue -eq $null) {
            $parameterValue = GetResourceParameterValue -resource $nodetype -name $parameterName
        }
        foreach ($vmssResource in $vmssResources) {
            $parametersName = CreateParametersName -resource $vmssResource -name $parameterName

            $parameterizedName = GetParameterizedNameFromValue -resourceObject (GetResourceParameterValue -resource $nodetype -name $parameterName)
            if (!$parameterizedName) {
                $parameterizedName = CreateParameterizedName -resource $vmssResource -parameterName $parameterName
            }

            $null = AddToParametersSection -parameterName $parametersName -parameterValue $parameterValue -type $type
            WriteLog "ParameterizeNodetype:setting $parametersName to $parameterValue for $($nodetype.name)" -foregroundcolor Magenta

            WriteLog "ParameterizeNodetype:AddParameter `
            -resource $vmssResource `
            -name $parameterName `
            -resourceObject $nodetype `
            -value $parameterizedName `
            -type $type
        "

            AddParameter `
                -resource $vmssResource `
                -name $parameterName `
                -resourceObject $nodetype `
                -value $parameterizedName `
                -type $type

            $extension = GetVmssExtensions -vmssResource $vmssResource -extensionType 'ServiceFabricNode'
            
            WriteLog "ParameterizeNodetype:AddParameter `
                -resource $vmssResource `
                -name $parameterName `
                -resourceObject $($extension.properties.settings) `
                -value $parameterizedName `
                -type $type
            "

            AddParameter `
                -resource $vmssResource `
                -name $parameterName `
                -resourceObject $extension.properties.settings `
                -value $parameterizedName `
                -type $type
        }
        WriteLog "exit:ParameterizeNodetype"
    }

    [bool] ParameterizeNodetypes([bool]$isPrimaryFilter = $false, [bool]$isPrimaryValue = $isPrimaryFilter, [switch]$all) {
        <#
        .SYNOPSIS
            parameterizes nodetypes for addnodetype template filtered by $isPrimaryFilter and isPrimary value set to $isPrimaryValue
            there will always be at least one primary nodetype unparameterized except for 'new' template
            there will only be one parameterized nodetype
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        WriteLog "enter:ParameterizeNodetypes([bool]$isPrimaryFilter, [bool]$isPrimaryValue)"
        # todo. should validation be here? how many nodetypes
        $null = RemoveParameterizedNodeTypes

        $clusterResource = GetClusterResource
        $nodetypes = [collections.arraylist]::new()
        [void]$nodetypes.AddRange(@($clusterResource.properties.nodetypes))
        $filterednodetypes = $nodetypes.psobject.copy()

        if ($nodetypes.Count -lt 1) {
            WriteLog "exit:ParameterizeNodetypes:no nodetypes detected!" -isError
            return $false
        }

        WriteLog "ParameterizeNodetypes:current nodetypes $($nodetypes.name)" -ForegroundColor Green
    
        if ($all) {
            $nodetypes.Clear()
        }
        else {
            $filterednodetypes = @($nodetypes | Where-Object isPrimary -ieq $isPrimaryFilter)[0]
        }

        if ($filterednodetypes.count -eq 0) {
            WriteLog "exit:ParameterizeNodetypes:unable to find nodetype where isPrimary=$isPrimaryFilter" -isError:$isPrimaryValue
            return $false
        }
        elseif ($filterednodetypes.count -gt 1 -and $isPrimaryFilter) {
            WriteLog "ParameterizeNodetypes:more than one primary node type detected!" -isError
        }
 
        foreach ($filterednodetype in $filterednodetypes) {
            WriteLog "ParameterizeNodetypes:adding new nodetype" -foregroundcolor Cyan
            $newNodeType = $filterednodetype.psobject.copy()
            $existingVmssNodeTypeRef = @(GetVmssResourcesByNodeType -nodetypeResource $newNodeType)

            if ($existingVmssNodeTypeRef.count -lt 1) {
                WriteLog "exit:ParameterizeNodetypes:unable to find existing nodetypes by nodetyperef" -isError
                return $false
            }

            WriteLog "ParameterizeNodetypes:parameterizing new nodetype " -foregroundcolor Cyan

            # setting capacity value should be parametized value to vmInstanceCount value
            $capacity = GetResourceParameterValue -resource $existingVmssNodeTypeRef[0].sku -name 'capacity'
            $null = SetResourceParameterValue -resource $newNodeType -name 'vmInstanceCount' -newValue $capacity

            ParameterizeNodetype -nodetype $newNodeType -parameterName 'durabilityLevel'
        
            if ($all) {
                ParameterizeNodetype -nodetype $newNodeType -parameterName 'isPrimary' -type 'bool'
            }
            else {
                ParameterizeNodetype -nodetype $newNodeType -parameterName 'isPrimary' -type 'bool' -parameterValue $isPrimaryValue
            }
        
            # todo: currently name has to be parameterized last so parameter names above can be found
            ParameterizeNodetype -nodetype $newNodeType -parameterName 'name'
        
            [void]$nodetypes.Add($newNodeType)
        }    

        $clusterResource.properties.nodetypes = $nodetypes
        WriteLog "exit:ParameterizeNodetypes:result:`r`n$($nodetypes | CreateJson)"
        return $true
    }

    [void] RemoveDuplicateResources() {
        <#
        .SYNOPSIS
            removes duplicate resources for current template from export
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:RemoveDuplicateResources"
        # fix up deploy errors by removing duplicated sub resources on root like lb rules by
        # removing any 'type' added by export-azresourcegroup that was not in the $global:configuredRGResources
        $currentResources = [collections.arraylist]::new() #$global:currentConfig.resources | CreateJson | convertfrom-json

        $resourceTypes = $global:configuredRGResources.resourceType
        foreach ($resource in $global:currentConfig.resources.GetEnumerator()) {
            WriteLog "RemoveDuplicateResources:checking exported resource $($resource.name)" -ForegroundColor Magenta
            WriteLog "RemoveDuplicateResources:checking exported resource $($resource | CreateJson)" -verbose
        
            if ($resourceTypes.Contains($resource.type)) {
                WriteLog "RemoveDuplicateResources:adding exported resource $($resource.name)" -ForegroundColor Cyan
                WriteLog "RemoveDuplicateResources:adding exported resource $($resource | CreateJson)" -verbose
                [void]$currentResources.Add($resource)
            }
        }
        $global:currentConfig.resources = $currentResources
        WriteLog "exit:RemoveDuplicateResources"
    }

    [bool] RemoveParameterizedNodeTypes() {
        <#
        .SYNOPSIS
            removes parameterized nodetypes for from cluster resource section in $global:currentConfig
            there will always be at least one primary nodetype unparameterized unless 'new' template
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        WriteLog "enter:RemoveParameterizedNodeTypes"
        $clusterResource = GetClusterResource
        $cleanNodetypes = [collections.arraylist]::new()
        $nodetypes = [collections.arraylist]::new()
        $retval = $false
        [void]$nodetypes.AddRange(@($clusterResource.properties.nodetypes))

        if ($nodetypes.Count -lt 1) {
            WriteLog "exit:RemoveParameterizedNodeTypes:no nodetypes detected!" -isError
            return $false
        }

        foreach ($nodetype in $nodetypes) {
            if (!(GetParameterizedNameFromValue -resourceObject $nodetype.name)) {
                WriteLog "RemoveParameterizedNodeTypes:skipping:$($nodetype.name)"
                [void]$cleanNodetypes.Add($nodetype)
            }
            else {
                WriteLog "RemoveParameterizedNodeTypes:removing:$($nodetype.name)"
            }
        }

        if ($cleanNodetypes.Count -gt 0) {
            $retval = $true
            $clusterResource.properties.nodetypes = $cleanNodetypes
            $null = RemoveUnusedParameters
        }
        else {
            WriteLog "exit:RemoveParameterizedNodeTypes:no clean nodetypes" -isError
        }

        WriteLog "exit:RemoveParameterizedNodeTypes:$retval"
        return $retval
    }

    [bool] RemoveUnparameterizedNodeTypes() {
        <#
        .SYNOPSIS
            removes unparameterized nodetypes for from cluster resource section in $global:currentConfig
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        WriteLog "enter:RemoveUnparameterizedNodeTypes"
        $clusterResource = GetClusterResource
        $cleanNodetypes = [collections.arraylist]::new()
        $nodetypes = [collections.arraylist]::new()
        $retval = $false
        [void]$nodetypes.AddRange(@($clusterResource.properties.nodetypes))

        if ($nodetypes.Count -lt 1) {
            WriteLog "exit:RemoveUnparameterizedNodeTypes:no nodetypes detected!" -isError
            return $false
        }

        foreach ($nodetype in $nodetypes) {
            if ((GetParameterizedNameFromValue -resourceObject $nodetype.name)) {
                WriteLog "RemoveUnparameterizedNodeTypes:removing:$($nodetype.name)"
                [void]$cleanNodetypes.Add($nodetype)
            }
            else {
                WriteLog "RemoveUnparameterizedNodeTypes:skipping:$($nodetype.name)"
            }
        }

        if ($cleanNodetypes.Count -gt 0) {
            $retval = $true
            $clusterResource.properties.nodetypes = $cleanNodetypes
            #$null = RemoveUnusedParameters
        }
        else {
            WriteLog "exit:RemoveUnparameterizedNodeTypes:no parameterized nodetypes" -isError
        }

        WriteLog "exit:RemoveUnparameterizedNodeTypes:$retval"
        return $retval
    }


    [void] RemoveUnusedParameters() {
        <#
        .SYNOPSIS
            removes unused parameters from parameters section
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:RemoveUnusedParameters"
        $parametersRemoveList = [collections.arraylist]::new()
        #serialize and copy
        $global:currentConfigResourcejson = $global:currentConfig | CreateJson
        $global:currentConfigJson = $global:currentConfigResourcejson | convertfrom-json

        # remove parameters section but keep everything else like variables, resources, outputs
        [void]$global:currentConfigJson.psobject.properties.remove('Parameters')
        $global:currentConfigResourcejson = $global:currentConfigJson | CreateJson

        foreach ($psObjectProperty in $global:currentConfig.parameters.psobject.Properties) {
            $parameterizedName = CreateParameterizedName $psObjectProperty.name
            WriteLog "RemoveUnusedParameters:checking to see if $parameterizedName is being used"
            if ([regex]::IsMatch($global:currentConfigResourcejson, [regex]::Escape($parameterizedName), $global:ignoreCase)) {
                WriteLog "RemoveUnusedParameters:$parameterizedName is being used" -verbose
                continue
            }
            WriteLog "RemoveUnusedParameters:removing $parameterizedName" -verbose
            [void]$parametersRemoveList.Add($psObjectProperty)
        }

        foreach ($parameter in $parametersRemoveList) {
            WriteLog "RemoveUnusedParameters:removing $($parameter.name)" -isWarning
            [void]$global:currentConfig.parameters.psobject.Properties.Remove($parameter.name)
        }
        WriteLog "exit:RemoveUnusedParameters"
    }

    [bool] RenameParameter( [string]$oldParameterName, [string]$newParameterName) {
        <#
        .SYNOPSIS
            renames parameter from $oldParameterName to $newParameterName by $oldParameterName in all template sections
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        WriteLog "enter:RenameParameter: $oldParameterName, $newParameterName"

        if (!$oldParameterName -or !$newParameterName) {
            WriteLog "exit:RenameParameter:error:empty parameters:oldParameterName:$oldParameterName newParameterName:$newParameterName" -isError
            return $false
        }

        $oldParameterizedName = CreateParameterizedName -parameterName $oldParameterName
        $newParameterizedName = CreateParameterizedName -parameterName $newParameterName
        $global:currentConfigResourcejson = $null

        if (!$global:currentConfig.parameters) {
            WriteLog "exit:RenameParameter:error:empty parameters section" -isError
            return $false
        }

        #serialize
        $global:currentConfigParametersjson = $global:currentConfig.parameters | CreateJson
        $global:currentConfigResourcejson = $global:currentConfig | CreateJson


        if ([regex]::IsMatch($global:currentConfigResourcejson, [regex]::Escape($newParameterizedName), $global:ignoreCase)) {
            WriteLog "exit:RenameParameter:new parameter already exists in resources section:$newParameterizedName" -isError
            return $false
        }

        if ([regex]::IsMatch($global:currentConfigParametersjson, [regex]::Escape($newParameterName), $global:ignoreCase)) {
            WriteLog "exit:RenameParameter:new parameter already exists in parameters section:$newParameterizedName" -isError
            return $false
        }

        if ([regex]::IsMatch($global:currentConfigParametersjson, [regex]::Escape($oldParameterName), $global:ignoreCase)) {
            WriteLog "RenameParameter:found parameter Name:$oldParameterName" -verbose
            $global:currentConfigParametersjson = [regex]::Replace($global:currentConfigParametersjson, [regex]::Escape($oldParameterName), $newParameterName, $global:ignoreCase)
            WriteLog "RenameParameter:replaced $oldParameterName json:$global:currentConfigParametersJson" -verbose
            $global:currentConfig.parameters = $global:currentConfigParametersjson | convertfrom-json

            # reserialize with modified parameters section
            $global:currentConfigResourcejson = $global:currentConfig | CreateJson
        }
        else {
            WriteLog "RenameParameter:parameter not found:$oldParameterName" -isWarning
        }

        if ($global:currentConfigResourcesjson) {
            if ([regex]::IsMatch($global:currentConfigResourcejson, [regex]::Escape($oldParameterizedName), $global:ignoreCase)) {
                WriteLog "RenameParameter:found parameterizedName:$oldParameterizedName" -verbose
                $global:currentConfigResourceJson = [regex]::Replace($global:currentConfigResourcejson, [regex]::Escape($oldParameterizedName), $newParameterizedName, $global:ignoreCase)
                WriteLog "RenameParameter:replaced $oldParameterizedName json:$global:currentConfigResourceJson" -verbose
                $global:currentConfig = $global:currentConfigResourcejson | convertfrom-json
            }
            else {
                WriteLog "RenameParameter:parameter not found:$oldParameterizedName" -isWarning
            }
        }

        WriteLog "RenameParameter:result:$($global:currentConfig | CreateJson)" -verbose
        WriteLog "exit:RenameParameter"
        return $true
    }

    [bool] RenameParametersByResource( [object]$resource, [string]$oldResourceName, [string]$newResourceName) {
        <#
    .SYNOPSIS
        renames parameter from $oldResourceName to $newResourceName by $resource in all template sections
        outputs: bool
    .OUTPUTS
        [bool]
    #>
        WriteLog "enter:RenameParametersByResource [object]$resource, [string]$oldResourceName, [string]$newResourceName"
        # get resource current name
        $currentParameterizedName = GetParameterizedNameFromValue $resource.name
        if (!$currentParameterizedName) {
            $currentResourceName = $resource.name
            $currentParameterizedName = CreateParameterizedName -resource $resource
        }
        else {
            $currentResourceName = GetFromParametersSection -parameterName $currentParameterizedName
        }
    
        $currentResourceType = $resource.type

        if (!$currentResourceName -or !$currentResourceType) {
            WriteLog "exit:RenameParametersByResource:invalid resource. no name/type:$($resource|CreateJson)" -isError
            return $false
        }
    
    }

    [bool] SetResourceParameterValue([object]$resource, [string]$name, [string]$newValue) {
        <#
        .SYNOPSIS
            sets resource parameter value in resources section
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        WriteLog "enter:SetResourceParameterValue:resource:$($resource|CreateJson) name:$name,newValue:$newValue" -foregroundcolor DarkCyan
        $retval = $false
        foreach ($psObjectProperty in $resource.psobject.Properties) {
            WriteLog "SetResourceParameterValuechecking parameter name $psobjectProperty" -verbose

            if (($psObjectProperty.Name -ieq $name)) {
                $parameterValues = @($psObjectProperty.Name)
                if ($parameterValues.Count -eq 1) {
                    $psObjectProperty.Value = $newValue
                    $retval = $true
                    break
                }
                else {
                    WriteLog "SetResourceParameterValue:multiple parameter names found in resource. returning" -isError
                    $retval = $false
                    break
                }
            }
            elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Management.Automation.PSCustomObject') {
                $retval = SetResourceParameterValue -resource $psObjectProperty.Value -name $name -newValue $newValue
            }
            else {
                WriteLog "SetResourceParameterValue:skipping type:$($psObjectProperty.TypeNameOfValue)" -verbose
            }
        }

        WriteLog "exit:SetResourceParameterValue:returning:$retval"
        return $retval
    }

    [void] VerifyConfig( [string]$templateParameterFile) {
        <#
        .SYNOPSIS
            verifies current configuration $global:currentConfig using test-resourcegroupdeployment
            outputs: null
        .OUTPUTS
            [null]
        #>
        WriteLog "enter:VerifyConfig:templateparameterFile:$templateParameterFile"
        $json = '.\VerifyConfig.json'
        $global:currentConfig | CreateJson | out-file -FilePath $json -Force

        WriteLog "Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
        -Mode Incremental `
        -Templatefile $json `
        -TemplateParameterFile $templateParameterFile `
        -Verbose
    " -ForegroundColor Green

        $error.Clear()
        $result = Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
            -Mode Incremental `
            -TemplateFile $json `
            -TemplateParameterFile $templateParameterFile `
            -Verbose

        if ($error -or $result) {
            WriteLog "exit:VerifyConfig:error:$($result | CreateJson) `r`n$($error | out-string)" -isError
        }
        else {
            WriteLog "exit:VerifyConfig:success" -foregroundcolor Green
        }
    
        remove-item $json
        $error.Clear()
    }

    [void] WriteLog([object]$data, [ConsoleColor]$foregroundcolor = [ConsoleColor]::Gray, [switch]$isError, [switch]$isWarning, [switch]$verbose) {
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
                    [void]$stringData.appendline(@($job.Information.ReadAll()) -join "`r`n")
                }
                if ($job.Verbose) {
                    [void]$stringData.appendline(@($job.Verbose.ReadAll()) -join "`r`n")
                }
                if ($job.Debug) {
                    [void]$stringData.appendline(@($job.Debug.ReadAll()) -join "`r`n")
                }
                if ($job.Output) {
                    [void]$stringData.appendline(@($job.Output.ReadAll()) -join "`r`n")
                }
                if ($job.Warning) {
                    WriteLog (@($job.Warning.ReadAll()) -join "`r`n") -isWarning
                    [void]$stringData.appendline(@($job.Warning.ReadAll()) -join "`r`n")
                    [void]$stringData.appendline(($job | format-list * | out-string))
                    $global:resourceWarnings++
                }
                if ($job.Error) {
                    WriteLog (@($job.Error.ReadAll()) -join "`r`n") -isError
                    [void]$stringData.appendline(@($job.Error.ReadAll()) -join "`r`n")
                    [void]$stringData.appendline(($job | format-list * | out-string))
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
            [void]$global:errors.add($stringData)
        }
        elseif ($isWarning) {
            Write-Warning $stringData
            [void]$global:warnings.add($stringData)
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

    $global:clusterTree = @{
        cluster = @{
            resource      = [object]::new()
            relationships = @{
                vmss            = @()
                storageAccounts = @()
            }
        }
        vmss    = @(
            @{
                resource      = [object]::new()
                relationships = @{
                    loadbalancers = @()
                    ipAddresses   = @()
                    vnets         = @()
                    keyvaults     = @()
                }
            }
        )
    }
}

[SFTemplate]$sftemplate = [SFTemplate]::new()
$sftemplate.Export();

$ErrorActionPreference = $currentErrorActionPreference
$VerbosePreference = $currentVerbosePreference
