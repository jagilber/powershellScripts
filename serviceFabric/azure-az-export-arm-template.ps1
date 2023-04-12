<#
.SYNOPSIS
    powershell script to export existing azure arm template resource settings similar for portal deployed service fabric cluster
    works with cloudshell https://shell.azure.com/
    >help .\azure-az-export-arm-template.ps1 -full

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-export-arm-template.ps1" -outFile "$pwd/azure-az-export-arm-template.ps1";
    ./azure-az-export-arm-template.ps1 -resourceGroupName <resource group name>

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
    File Name  : azure-az-export-arm-template.ps1
    Author     : jagilber
    Version    : 230327.1
    todo       :

    History    : add support for private ip address and clusters with no diagnostics extension v2

.EXAMPLE
    .\azure-az-export-arm-template.ps1 -resourceGroupName clusterresourcegroup
    export sf resources in resource group 'clusteresourcegroup' and generate template.json

.EXAMPLE
    .\azure-az-export-arm-template.ps1 -resourceGroupName clusterresourcegroup -useExportedJsonFile .\template.export.json
    export sf resources in resource group 'clusteresourcegroup' and generate template.json using existing raw export file .\template.export.json
#>

[cmdletbinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName = '',
    [string]$templatePath = "$psscriptroot/templates-$resourceGroupName", # for cloudshell
    [string]$useExportedJsonFile = '',
    [string]$adminPassword = '', #'GEN_PASSWORD',
    [string[]]$resourceNames = '',
    [string[]]$excludeResourceNames = '',
    [string]$logFile = "$templatePath/azure-az-sf-export-arm-template-$((get-date).tostring('yyyyMMdd-HHmmss')).log",
    [switch]$compress,
    [switch]$updateScript
)

set-strictMode -Version 3.0
$PSModuleAutoLoadingPreference = 2
$currentErrorActionPreference = $ErrorActionPreference
$currentVerbosePreference = $VerbosePreference
$env:SuppressAzurePowerShellBreakingChangeWarnings = $true
$ErrorActionPreference = 'continue'
#$VerbosePreference = 'continue'

class ClusterModel {
    [SFTemplate]$sfTemplate = $null
    [object]$cluster = $null
    [collections.generic.list[vmss]]$vmss = [collections.generic.list[vmss]]::new()
    [collections.generic.list[string]]$storageAccountIds = [collections.generic.list[string]]::new()

    ClusterModel () {}
    ClusterModel($sfTemplate) {
        $this.sfTemplate = $sfTemplate
    }

    [Vmss[]] FindVmssByExpression([string]$expression) {
        $this.WriteLog("enter:FindVmssByExpression searching for resource:$expression")
        $vmssObjects = @($this.vmss.Where( { . ([scriptblock]::Create($expression)) }))

        if (!$vmssObjects -or $vmssObjects.Count -lt 1) {
            $this.WriteWarning("FindVmssByExpression:warning:vmss not found:expression:$expression")
        }

        $this.WriteLog("exit:FindVmssByExpression returning vmss resource objects: count:$($vmssObjects.Count) objects:$vmssObjects)")
        return $vmssObjects
    }

    [Vmss] FindVmssByResource([object]$vmssResource) {
        $this.WriteVerbose("enter:FindVmssByResource searching for resource:$($this.sfTemplate.CreateJson($vmssResource, 1))")
        [Vmss]$vmssObject = $null
        $vmssObjects = @($this.vmss.Where( {
                    # search by resource if resource object provided or by id if arm resource provided
                    ($this.sftemplate.GetPSPropertyValue($psitem, 'resource') -and $psitem.resource -eq $vmssResource) `
                        -or (($this.sftemplate.GetPSPropertyValue($psitem, 'resource.resourceid') `
                                -and $this.sftemplate.GetPSPropertyValue($vmssResource, 'resourceid')) `
                            -and $psitem.resource.resourceid -eq $vmssResource.resourceid) `
                        -or ($this.sfTemplate.GetPSPropertyValue($vmssResource, 'comments') `
                            -and $vmssResource.comments -ieq "Generalized from resource: '$($psitem.resource.id)'.")
                }))

        if ($vmssObjects.Count -gt 1) {
            $this.WriteError("FindVmssByResource multiple objects found $(($vmssObjects.Count)). returning first object:$vmssObjects")
            $vmssObject = $vmssObjects[0]
        }
        elseif ($vmssObjects.Count -lt 1) {
            $this.WriteError("FindVmssByResource unable to find vmss in ClusterModel:resource:$vmssResource")
        }
        else {
            $vmssObject = $vmssObjects[0]
        }

        $this.WriteVerbose("exit:FindVmssByResource returning vmss resource object:$vmssObject")
        return $vmssObject
    }

    [void] WriteError($data) {
        if ($this.sfTemplate) {
            $this.sfTemplate.WriteError($data)
        }
        else {
            write-error $data
        }
    }

    [void] WriteLog($data) {
        if ($this.sfTemplate) {
            $this.sfTemplate.WriteLog($data)
        }
        else {
            Write-host $data
        }
    }

    [void] WriteVerbose($data) {
        if ($this.sfTemplate) {
            $this.sfTemplate.WriteVerbose($data)
        }
        else {
            write-verbose $data
        }
    }

    [void] WriteWarning($data) {
        if ($this.sfTemplate) {
            $this.sfTemplate.WriteWarning($data)
        }
        else {
            write-warning $data
        }
    }
}

class Vmss {
    Vmss() {

    }
    Vmss($resource) {
        $this.resource = $resource
    }

    [object]$resource = $null
    [collections.generic.list[string]]$loadbalancerIds = [collections.generic.list[string]]::new()
    [collections.generic.list[string]]$ipAddressIds = [collections.generic.list[string]]::new()
    [collections.generic.list[string]]$nsgIds = [collections.generic.list[string]]::new()
    [collections.generic.list[string]]$nsgRuleIds = [collections.generic.list[string]]::new()
    [collections.generic.list[string]]$keyVaultIds = [collections.generic.list[string]]::new()
    [collections.generic.list[string]]$subnetIds = [collections.generic.list[string]]::new()
    [collections.generic.list[string]]$vnetIds = [collections.generic.list[string]]::new()

}

class SFTemplate {
    [string]$resourceGroupName = $resourceGroupName
    [string]$templatePath = $templatePath
    [string]$useExportedJsonFile = $useExportedJsonFile
    [string]$adminPassword = $adminPassword
    [string[]]$resourceNames = $resourceNames
    [string[]]$excludeResourceNames = $excludeResourceNames
    [string]$logFile = $logFile
    [switch]$compress = $compress
    [switch]$updateScript = $updateScript

    [string]$parametersSchema = 'http://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json'
    [string]$updateUrl = 'https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-export-arm-template.ps1'

    [ClusterModel]$clusterModel = [ClusterModel]::new($this)
    [collections.arraylist]$errors = [collections.arraylist]::new()
    [collections.arraylist]$warnings = [collections.arraylist]::new()
    [int]$functionDepth = 0
    [string]$templateJsonFile = "$templatePath/template.json"
    [int]$resourceErrors = 0
    [int]$resourceWarnings = 0
    [collections.arraylist]$configuredRGResources = [collections.arraylist]::new()
    [object]$currentConfig = $null
    [object]$sflogs = $null
    [object]$sfdiags = $null
    [datetime]$startTime = (get-date)
    [string]$storageKeyApi = '2015-05-01-preview'
    [string]$defaultSflogsValue = "[toLower(concat('sflogs',uniqueString(resourceGroup().id),'2'))]"
    [string]$defaultSfdiagsValue = "[toLower(concat(uniqueString(resourceGroup().id),'3'))]"
    [string]$descriptionUniqueCluster = 'this name must be unique in cluster deployment.'
    [string]$descriptionAddPrimary = "$($this.descriptionUniqueCluster) To add a new primary nodetype, update this value."
    [string]$descriptionAddSecondary = "$($this.descriptionUniqueCluster) To add a new secondary nodetype, update this value."
    [string]$descriptionPrimaryDoNotModify = "primary nodetype. do not modify."
    [text.regularExpressions.regexOptions]$ignoreCase = [text.regularExpressions.regexOptions]::IgnoreCase

    SFTemplate() {}
    static SFTemplate() { }

    [void] Export() {
        $this.clusterModel = [ClusterModel]::new($this)

        if (!(test-path $this.templatePath)) {
            # test local and for cloudshell
            mkdir $this.templatePath
            $this.WriteLog("making directory $($this.templatePath)")
        }

        $this.WriteLog("starting")
        if ($this.updateScript -and ($this.GetUpdate($this.updateUrl))) {
            return
        }

        if (!$this.resourceGroupName) {
            $this.WriteError("resource group name is required.")
            return
        }

        if (!($this.CheckModule())) {
            return
        }

        if (!(@(Get-AzResourceGroup).Count)) {
            $this.WriteLog("connecting to azure")
            Connect-AzAccount
        }

        if ($this.resourceNames) {
            foreach ($resourceName in $this.resourceNames) {
                $this.WriteLog("getting resource $resourceName")
                [void]$this.configuredRGResources.AddRange(@($this.GetAzResourceByName($this.resourceGroupName, $resourceName)))
            }
        }
        else {
            $resourceIds = $this.EnumAllResources()
            foreach ($resourceId in $resourceIds) {
                $resource = $this.GetAzResourceById($resourceId)
                if ($resource.ResourceGroupName -ieq $this.resourceGroupName) {
                    $this.WriteLog("adding resource id to configured resources: $($resource.resourceId)", [consolecolor]::Cyan)
                    [void]$this.configuredRGResources.Add($resource)
                }
                else {
                    $this.WriteWarning("skipping resource $($resource.resourceid) as it is out of resource group scope $($resource.ResourceGroupName)")
                }
            }
        }

        $this.DisplaySettings($this.configuredRGResources)

        if ($this.configuredRGResources.count -lt 1) {
            $this.WriteWarning("error enumerating resource $($error | format-list * | out-string)")
            return
        }

        $deploymentName = "$($this.resourceGroupName)-$((get-date).ToString("yyyyMMdd-HHmms"))"

        # create $this.currentConfig
        $this.CreateExportTemplate()

        # use $this.currentConfig
        $this.CreateCurrentTemplate()
        $this.CreateRedeployTemplate()
        $this.CreateAddPrimaryNodeTypeTemplate()
        $this.CreateAddSecondaryNodeTypeTemplate()
        $this.CreateNewTemplate()

        if ($this.compress) {
            $zipFile = "$($this.templatePath).zip"
            compress-archive $this.templatePath $zipFile -Force
            $this.WriteLog("zip file located here:$zipFile", [consolecolor]::Cyan)
        }

        $error.clear()

        write-host "finished. files stored in $($this.templatePath)" -ForegroundColor Green
        code $this.templatePath # for cloudshell and local

        if ($error) {
            . $this.templateJsonFile.Replace(".json", ".current.json")
        }

        if ($this.resourceErrors -or $this.resourceWarnings) {
            $this.WriteWarning("deployment may not have been successful: errors: $this.resourceErrors warnings: $this.resourceWarnings")

            if ($this.DebugPreference -ieq 'continue') {
                $this.WriteLog("errors: $($error | sort-object -Descending | out-string)")
            }
        }

        $deployment = Get-AzResourceGroupDeployment -ResourceGroupName $this.resourceGroupName -Name $deploymentName -ErrorAction silentlycontinue

        $this.WriteLog("deployment:`r`n$($deployment | format-list * | out-string)")
        Write-Progress -Completed -Activity "complete"

        if ($this.warnings) {
            $this.WriteLog("global warnings:", [consolecolor]::Yellow)
            $this.WriteWarning(($this.CreateJson($this.warnings)))
        }

        if ($this.errors) {
            $this.WriteLog("global errors:", [consolecolor]::Red)
            $this.WriteError(($this.CreateJson($this.errors)))
        }

        $this.clusterModel.sfTemplate = $null
        $this.WriteLog("time elapsed:  $(((get-date) - $this.startTime).TotalMinutes.ToString("0.0")) minutes`r`n")
        $this.WriteLog('finished. template stored in $global:sftemplate', [consolecolor]::Cyan)

        if ($this.logFile) {
            $this.WriteLog("log file saved to $this.logFile")
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
        $this.WriteLog("enter:AddOutputs( $name, $value, $type = 'string'")
        $outputs = $this.currentConfig.psobject.Properties | where-object name -ieq 'outputs'
        $outputItem = [pscustomobject]@{
            value = $value
            type  = $type
        }

        if (!$outputs) {
            # create pscustomobject
            $this.currentConfig | Add-Member -TypeName System.Management.Automation.PSCustomObject -NotePropertyMembers @{
                outputs = [pscustomobject]@{
                    $name = $outputItem
                }
            }
        }
        else {
            [void]$this.currentConfig.outputs.add($name, $outputItem)
        }
        $this.WriteLog("exit:AddOutputs:added")
    }

    [void] AddParameterNameByResourceType( [string]$type, [string]$name, [string]$metadataDescription = '') {
        <#
        .SYNOPSIS
            add parameter name by resource type
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:AddParameterNameByResourceType( $type, $name, $metadataDescription = '')")
        $resources = @($this.currentConfig.resources | where-object 'type' -eq $type)
        $parameterNames = @{}

        foreach ($resource in $resources) {
            $parameterName = $this.CreateParametersName($resource, $name)
            $parameterizedName = $this.CreateParameterizedName($name, $resource, $true)
            $parameterNameValue = $this.GetResourceParameterValue($resource, $name)
            $null = $this.SetResourceParameterValue($resource, $name, $parameterizedName)

            if ($null -ne $parameterNameValue) {
                [void]$parameterNames.Add($parameterName, $parameterNameValue)
                $this.WriteLog("AddParameterNameByResourceType:parametername added $parameterName : $parameterNameValue")
            }
        }

        $this.WriteLog("AddParameterNameByResourceType:parameter names $parameterNames")
        foreach ($parameterName in $parameterNames.GetEnumerator()) {
            if ($this.GetFromParametersSection($parameterName.key).Count -lt 1) {
                $this.AddToParametersSection($parameterName.key, $parameterName.value, 'string', $metadataDescription)
            }
        }
        $this.WriteLog("exit:AddParameterNameByResourceType")
    }

    [void] AddParameter( [object]$resource, [string]$name) {
        <#
        .SYNOPSIS
            add a new parameter based on $resource $name/$aliasName $resourceObject
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.AddParameter( $resource, $name, $name, $resource, $null, 'string', '')
    }

    [void] AddParameter( [object]$resource, [string]$name, [object]$resourceObject = $null) {
        <#
        .SYNOPSIS
            add a new parameter based on $resource $name/$aliasName $resourceObject
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.AddParameter( $resource, $name, $name, $resourceObject, $null, 'string', '')
    }

    [void] AddParameter( [object]$resource, [string]$name, [object]$resourceObject = $null, [string]$type = 'string') {
        <#
        .SYNOPSIS
            add a new parameter based on $resource $name/$aliasName $resourceObject
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.AddParameter( $resource, $name, $name, $resourceObject, $null, $type, '')
    }

    [void] AddParameter( [object]$resource, [string]$name, [string]$aliasName = $name, [object]$resourceObject = $null) {
        <#
        .SYNOPSIS
            add a new parameter based on $resource $name/$aliasName $resourceObject
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.AddParameter( $resource, $name, $aliasname, $resourceObject, $null, 'string', '')
    }

    [void] AddParameter( [object]$resource, [string]$name, [string]$aliasName = $name, [object]$resourceObject = $resource, [object]$value = $null) {
        <#
        .SYNOPSIS
            add a new parameter based on $resource $name/$aliasName $resourceObject
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.AddParameter( $resource, $name, $aliasName, $resourceObject, $value, 'string', '')
    }

    [void] AddParameter( [object]$resource, [string]$name, [string]$aliasName = $name, [object]$resourceObject = $resource, [object]$value = $null, [string]$type = 'string', [string]$metadataDescription = '') {
        <#
        .SYNOPSIS
            add a new parameter based on $resource $name/$aliasName $resourceObject
            outputs: null
        .OUTPUTS
            [null]
        #>
        $parameterName = $this.CreateParametersName($resource, $aliasName)
        $parameterizedName = $this.CreateParameterizedName($aliasName, $resource, $true)
        $parameterNameValue = $value

        if (!$parameterNameValue) {
            $parameterNameValue = $this.GetResourceParameterValue($resourceObject, $name)
        }
        $this.WriteLog("enter:AddParameter( $resource, $name, $aliasName = $name, $resourceObject = $resource, $value = $null, $type = 'string', $metadataDescription = '')")
        $null = $this.SetResourceParameterValue($resourceObject, $name, $parameterizedName)

        if ($null -ne $parameterNameValue) {
            $this.WriteLog("AddParameter:adding parameter name:$parameterName parameter value:$parameterNameValue")
            if ($this.GetFromParametersSection($parameterName).Count -lt 1) {
                $this.WriteLog("AddParameter:$parameterName not found in parameters sections. adding.")
                $this.AddToParametersSection($parameterName, $parameterNameValue, $type, $metadataDescription)
            }
        }
        $this.WriteLog("exit:AddParameter")
    }

    [void] AddToParametersSection( [string]$parameterName, [object]$parameterValue, [string]$type = 'string') {
        <#
        .SYNOPSIS
            add a new parameter based on $parameterName and $parameterValue to parameters Setion
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.AddToParametersSection( $parameterName, $parameterValue, $type, '')
    }

    [void] AddToParametersSection( [string]$parameterName, [object]$parameterValue) {
        <#
        .SYNOPSIS
            add a new parameter based on $parameterName and $parameterValue to parameters Setion
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.AddToParametersSection( $parameterName, $parameterValue, 'string', '')
    }

    [void] AddToParametersSection( [string]$parameterName, [object]$parameterValue, [string]$type = 'string', [string]$metadataDescription = '') {
        <#
        .SYNOPSIS
            add a new parameter based on $parameterName and $parameterValue to parameters Setion
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:AddToParametersSection:parameterName:$parameterName, parameterValue:$parameterValue, $type = 'string', $metadataDescription")
        $parameterObject = [pscustomobject]@{
            type         = $type
            defaultValue = $parameterValue
            metadata     = [pscustomobject]@{description = $metadataDescription }
        }

        foreach ($psObjectProperty in $this.currentConfig.parameters.psobject.Properties) {
            if (($psObjectProperty.Name -ieq $parameterName)) {
                $psObjectProperty.Value = $parameterObject
                $this.WriteLog("exit:AddToParametersSection:parameterObject value added to existing parameter:$($this.CreateJson($parameterValue))")
                return
            }
        }

        $this.currentConfig.parameters | Add-Member -MemberType NoteProperty -Name $parameterName -Value $parameterObject
        $this.WriteLog("exit:AddToParametersSection:new parameter name:$parameterName added $($this.CreateJson($parameterObject))")
    }

    [void] AddVmssProtectedSettings([object]$vmssResource) {
        <#
        .SYNOPSIS
            add wellknown protectedSettings section to vmss resource for storageAccounts
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:AddVmssProtectedSettings$($vmssResource.name)")
        $sflogsParameter = $this.CreateParameterizedName('name', $this.sflogs)

        foreach ($extension in $vmssResource.properties.virtualMachineProfile.extensionPRofile.extensions) {
            if ($extension.properties.type -ieq 'ServiceFabricNode') {
                $extension.properties | Add-Member -MemberType NoteProperty -Name protectedSettings -Value ([pscustomobject]@{
                        StorageAccountKey1 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', $sflogsParameter),'$($this.storageKeyApi)').key1]"
                        StorageAccountKey2 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', $sflogsParameter),'$($this.storageKeyApi)').key2]"
                    })
                $this.WriteLog("AddVmssProtectedSettings:added $($extension.properties.type) protectedsettings $($this.CreateJson($extension.properties.protectedSettings))", [consolecolor]::Magenta)
            }

            if ($extension.properties.type -ieq 'IaaSDiagnostics' -and ($this.GetPSPropertyValue($extension, 'properties.settings.storageAccount'))) {
                $saname = $extension.properties.settings.storageAccount
                $sfdiagsParameter = $this.CreateParameterizedName('name', ($this.sfdiags | where-object name -imatch $saname))
                $extension.properties.settings.storageAccount = "[$sfdiagsParameter]"

                $extension.properties | Add-Member -MemberType NoteProperty -Name protectedSettings -Value ([pscustomobject]@{
                        storageAccountName     = "$sfdiagsParameter"
                        storageAccountKey      = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', $sfdiagsParameter),'$($this.storageKeyApi)').key1]"
                        storageAccountEndPoint = "https://core.windows.net/"
                    })
                $this.WriteLog("AddVmssProtectedSettings:added $($extension.properties.type) protectedsettings $($this.CreateJson($extension.properties.protectedSettings))", [consolecolor]::Magenta)
            }
        }
        $this.WriteLog("exit:AddVmssProtectedSettings")
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
            $this.WriteWarning("azure module for Connect-AzAccount not installed.")

            get-command Connect-AzureRmAccount -ErrorAction SilentlyContinue
            if (!$error) {
                $this.WriteWarning("azure module for Connect-AzureRmAccount is installed. use cloud shell to run script instead https://shell.azure.com/")
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
        $this.WriteLog("enter:CreateAddPrimaryNodeTypeTemplate")
        # create add node type templates for primary os / hardware sku change
        # create secondary for additional secondary nodetypes
        $templateFile = $this.templateJsonFile.Replace(".json", ".addprimarynodetype.json")
        $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")

        if (!($this.ParameterizeNodetypes($true, $true))) {
            $this.WriteError("exit:CreateAddPrimaryNodeTypeTemplate:no nodetype found")
            return
        }
        $this.ModifyLbResourcesAddPrimary()
        $this.ModifyVmssResourcesAddPrimary()
        $this.ModifyIpResourcesAddPrimary()

        $this.CreateParameterFile($templateParameterFile)
        $this.VerifyConfig($templateParameterFile)

        # save base / current json
        $this.CreateJson($this.currentConfig) | out-file $templateFile

        # save current readme
        $readme = $global:addPrimaryNodeTypeReadme
        $readme | out-file $this.templateJsonFile.Replace(".json", ".addprimarynodetype.readme.txt")
        $this.WriteLog("exit:CreateAddPrimaryNodeTypeTemplate")
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
        $this.WriteLog("enter:CreateAddSecondaryNodeTypeTemplate")
        # create add node type templates for primary os / hardware sku change
        # create secondary for additional secondary nodetypes
        $templateFile = $this.templateJsonFile.Replace(".json", ".addsecondarynodetype.json")
        $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")

        if (!($this.ParameterizeNodetypes())) {
            $this.WriteLog("CreateAddSecondaryNodeTypeTemplate:no secondary nodetype found", [consolecolor]::Yellow)

            if (!($this.ParameterizeNodetypes($true, $false))) {
                $this.WriteError("exit:CreateAddSecondaryNodeTypeTemplate:no primary nodetype found")
                return
            }
        }
        $this.ModifyLbResourcesAddSecondary()
        $this.ModifyVmssResourcesAddSecondary()
        $this.ModifyIpResourcesAddSecondary()

        $this.CreateParameterFile($templateParameterFile)
        $this.VerifyConfig($templateParameterFile)

        # save base / current json
        $this.CreateJson($this.currentConfig) | out-file $templateFile

        # save current readme
        $readme = $global:addSecondaryNodeTypeReadme
        $readme | out-file $this.templateJsonFile.Replace(".json", ".addsecondarynodetype.readme.txt")
        $this.WriteLog("exit:CreateAddSecondaryNodeTypeTemplate")
    }

    [void] CreateCurrentTemplate() {
        <#
        .SYNOPSIS
            creates new current template with modifications based on raw export template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:CreateCurrentTemplate")
        # create base /current template
        $templateFile = $this.templateJsonFile.Replace(".json", ".current.json")
        $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")

        $this.RemoveDuplicateResources()
        $this.RemoveUnusedParameters()
        $this.ModifyLbResources()
        $this.ModifyNsgResources()
        $this.ModifyVnetResources()
        $this.ModifyVmssResources()
        #$this.ModifyClusterResource()

        # temporarily save working config
        $tempConfig = $this.CreateJson($this.currentConfig)

        # run modifyclusterresourcedeploy for current config only else addprimarynodetype and addsecondarynodetype configs
        # that are called later will not generate due to parameterization
        $this.ModifyClusterResourceDeploy()

        $this.CreateParameterFile($templateParameterFile)
        $this.VerifyConfig($templateParameterFile)

        # save base / current json
        $this.CreateJson($this.currentConfig) | out-file $templateFile

        # restore working config
        $this.currentConfig = $tempConfig | convertfrom-json

        # save current readme
        $readme = $global:currentReadme
        $readme | out-file $this.templateJsonFile.Replace(".json", ".current.readme.txt")
        $this.WriteLog("exit:CreateCurrentTemplate")
    }

    [void] CreateExportTemplate() {
        <#
        .SYNOPSIS
            creates new export template from resource group and sets $this.currentConfig
            must be called before any modification functions
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:CreateExportTemplate")
        # create base /current template
        $templateFile = $this.templateJsonFile.Replace(".json", ".export.json")

        if ($this.useExportedJsonFile -and (test-path $this.useExportedJsonFile)) {
            $this.WriteLog("using existing export file $this.useExportedJsonFile", [consolecolor]::Green)
            $templateFile = $this.useExportedJsonFile
        }
        else {
            $exportResult = $this.ExportTemplate($this.configuredRGResources, $templateFile)
            $this.WriteLog("template exported to $templateFile", [consolecolor]::Yellow)
            $this.WriteLog("template export result $($exportResult|out-string)", [consolecolor]::Yellow)
        }

        # save base / current json
        $this.currentConfig = Get-Content -raw $templateFile | convertfrom-json
        $this.CreateJson($this.currentConfig) | out-file $templateFile

        # save current readme
        $readme = $global:exportReadme
        $readme | out-file $this.templateJsonFile.Replace(".json", ".export.readme.txt")
        $this.WriteLog("exit:CreateExportTemplate")
    }

    [string] CreateJson([object]$inputObject) {
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
        return $this.CreateJson($inputObject, 99)
    }

    [string] CreateJson([object]$inputObject, [int]$depth = 99) {
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
        $currentWarningPreference = $global:WarningPreference
        $WarningPreference = 'SilentlyContinue'

        # to fix \u0027 single quote issue
        $result = $inputObject | convertto-json -depth $depth | foreach-object { $_.replace("\u0027", "'"); }
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
        $this.WriteLog("enter:CreateNewTemplate")
        # create deploy / new / add template
        $templateFile = $this.templateJsonFile.Replace(".json", ".new.json")
        $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")
        $parameterExclusions = $this.ModifyStorageResourcesDeploy()

        $this.ModifyClusterResourceDeploy()
        $this.CreateParameterFile($templateParameterFile, $parameterExclusions)
        $this.VerifyConfig($templateParameterFile)

        # # save add json
        $this.CreateJson($this.currentConfig) | out-file $templateFile

        # save add readme
        $readme = $global:newReadme
        $readme | out-file $this.templateJsonFile.Replace(".json", ".new.readme.txt")
        $this.WriteLog("exit:CreateNewTemplate")
    }

    [void] CreateParameterFile( [string]$parameterFileName) {
        <#
        .SYNOPSIS
            creates new template parameters files based on $this.currentConfig
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.CreateParameterFile($parameterFileName, @())
    }

    [void] CreateParameterFile( [string]$parameterFileName, [string[]]$ignoreParameters = @()) {
        <#
        .SYNOPSIS
            creates new template parameters files based on $this.currentConfig
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:CreateParameterFile( [string]$parameterFileName, [string[]]$ignoreParameters = @())")

        $parameterTemplate = [ordered]@{
            '$schema'      = $this.parametersSchema
            contentVersion = "1.0.0.0"
        }

        # create pscustomobject
        $parameterTemplate | Add-Member -TypeName System.Management.Automation.PSCustomObject -NotePropertyMembers @{ parameters = @{} }
        $parameterItem = @{
            metadata = $null
            value    = $null
        }

        foreach ($psObjectProperty in $this.currentConfig.parameters.psobject.Properties.GetEnumerator()) {
            if ($ignoreParameters.Contains($psObjectProperty.name)) {
                $this.WriteLog("CreateParameterFile:skipping parameter $($psobjectProperty.name)")
                continue
            }

            $this.WriteVerbose("CreateParameterFile:value properties:$($psObjectProperty.Value.psobject.Properties)")
            $parameterItem = @{
                value = $this.GetPSPropertyValue($psObjectProperty, 'value.defaultValue')
            }

            if (($this.GetPSPropertyValue($psObjectProperty, 'value.metadata.description'))) {
                $parameterItem.metadata = @{description = $psObjectProperty.value.metadata.description }
            }

            [void]$parameterTemplate.parameters.Add($psObjectProperty.name, $parameterItem)
        }

        if (!($parameterFileName.tolower().contains('parameters'))) {
            $parameterFileName = $parameterFileName.tolower().replace('.json', '.parameters.json')
        }

        $this.WriteLog("CreateParameterFile:creating parameterfile $parameterFileName", [consolecolor]::Green)
        $this.CreateJson($parameterTemplate) | out-file -FilePath $parameterFileName
        $this.WriteLog("exit:CreateParameterFile")
    }

    [string] CreateParameterizedName($parameterName) {
        <#
        .SYNOPSIS
            creates parameterized name for variables, resources, and outputs section based on $paramterName and $resource
            outputs: string
        .OUTPUTS
            [string]
        #>
        return $this.CreateParameterizedName($parameterName, $null, $false)
    }

    [string] CreateParameterizedName($parameterName, $resource) {
        <#
        .SYNOPSIS
            creates parameterized name for variables, resources, and outputs section based on $paramterName and $resource
            outputs: string
        .OUTPUTS
            [string]
        #>
        return $this.CreateParameterizedName($parameterName, $resource, $false)
    }

    [string] CreateParameterizedName($parameterName, $resource, [switch]$withbrackets) {
        <#
        .SYNOPSIS
            creates parameterized name for variables, resources, and outputs section based on $paramterName and $resource
            outputs: string
        .OUTPUTS
            [string]
        #>
        $this.WriteLog("enter:CreateParameterizedName $parameterName, $resource = $null, [switch]$withbrackets")
        $retval = ""

        if ($resource) {
            $retval = $this.CreateParametersName($resource, $parameterName)
            $retval = "parameters('$retval')"
        }
        else {
            $retval = "parameters('$parameterName')"
        }

        if ($withbrackets) {
            $retval = "[$retval]"
        }

        $this.WriteLog("exit:CreateParameterizedName:$retval")
        return $retval
    }

    [string] CreateParametersName([object]$resource) {
        <#
        .SYNOPSIS
            creates parameter name for parameters, variables, resources, and outputs section based on $resource and $name
            outputs: string
        .OUTPUTS
            [string]
        #>

        return $this.CreateParametersName($resource, 'name')
    }

    [string] CreateParametersName([object]$resource, [string]$name = 'name') {
        <#
        .SYNOPSIS
            creates parameter name for parameters, variables, resources, and outputs section based on $resource and $name
            outputs: string
        .OUTPUTS
            [string]
        #>
        $this.WriteLog("enter:CreateParametersName($resource, $name = 'name')")
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
        $parametersName = [regex]::replace($name, '^' + [regex]::Escape($parametersNamePrefix), '', $this.ignoreCase)
        $parametersName = "$($resourceSubType)_$($resourceName)_$($name)"

        $this.WriteLog("exit:CreateParametersName returning:$parametersName")
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
        $this.WriteLog("enter:CreateRedeployTemplate")
        # create redeploy template
        $templateFile = $this.templateJsonFile.Replace(".json", ".redeploy.json")
        $templateParameterFile = $templateFile.Replace(".json", ".parameters.json")

        $this.ModifyClusterResourceRedeploy()
        $this.ModifyLbResourcesRedeploy()
        $this.ModifyVmssResourcesRedeploy()
        $this.ModifyIpAddressesRedeploy()

        $this.CreateParameterFile($templateParameterFile)
        $this.VerifyConfig($templateParameterFile)

        # # save redeploy json
        $this.CreateJson($this.currentConfig) | out-file $templateFile

        # save redeploy readme
        $readme = $global:redeployReadme
        $readme | out-file $this.templateJsonFile.Replace(".json", ".redeploy.readme.txt")
        $this.WriteLog("exit:CreateRedeployTemplate")
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
            $settings += $this.CreateJson($resource)
        }
        $this.WriteLog("current settings: `r`n $settings", [consolecolor]::Green)
    }

    [object[]] EnumAllResources() {
        <#
        .SYNOPSIS
            enumerate all resources in resource group
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:EnumAllResources")
        $resources = [collections.arraylist]::new()

        $this.WriteLog("EnumAllResources:getting resource group cluster $($this.resourceGroupName)")
        $clusterResource = $this.EnumClusterResource()
        if (!$clusterResource) {
            $this.WriteError("exit:EnumAllResources:unable to enumerate cluster. exiting")
            return $null
        }
        [void]$resources.Add($clusterResource.Id)

        $this.WriteLog("EnumAllResources:getting scalesets $($this.resourceGroupName)")
        $vmssResources = @($this.EnumVmssResources())
        if ($vmssResources.Count -lt 1) {
            $this.WriteError("exit:EnumAllResources:unable to enumerate vmss. exiting")
            return $null
        }
        else {
            [void]$resources.AddRange(@($vmssResources.Id))
        }

        $this.WriteLog("EnumAllResources:getting storage $($this.resourceGroupName)")
        $storageResources = @($this.EnumStorageResources())
        if ($storageResources.count -lt 1) {
            $this.WriteError("exit:EnumAllResources:unable to enumerate storage. exiting")
            return $null
        }
        else {
            [void]$resources.AddRange(@($storageResources.Id))
        }

        $this.WriteLog("EnumAllResources:getting virtualnetworks $($this.resourceGroupName)")
        $vnetResources = @($this.EnumVnetResourceIds($vmssResources))
        if ($vnetResources.count -lt 1) {
            $this.WriteError("exit:EnumAllResources:unable to enumerate vnets. exiting")
            return $null
        }
        else {
            [void]$resources.AddRange($vnetResources)
        }

        $this.WriteLog("EnumAllResources:getting subnets $($this.resourceGroupName)")
        $subnetResources = @($this.EnumSubnetResourceIds($vmssResources))
        if ($subnetResources.count -lt 1) {
            $this.WriteError("exit:EnumAllResources:unable to enumerate subnets. exiting")
            return $null
        }
        else {
            [void]$resources.AddRange($subnetResources)
        }

        $this.WriteLog("EnumAllResources:getting loadbalancers $($this.resourceGroupName)")
        $lbResources = @($this.EnumLbResourceIds($vmssResources))
        if ($lbResources.count -lt 1) {
            $this.WriteError("exit:EnumAllResources:unable to enumerate loadbalancers. exiting")
            return $null
        }
        else {
            [void]$resources.AddRange($lbResources)
        }

        $this.WriteLog("EnumAllResources:getting ip addresses $($this.resourceGroupName)")
        $ipResources = @($this.EnumIpResourceIds($lbResources))
        if ($ipResources.count -lt 1) {
            $this.WriteWarning("EnumAllResources:unable to enumerate ips.")
        }
        else {
            [void]$resources.AddRange($ipResources)
        }

        $this.WriteLog("EnumAllResources:getting key vaults $($this.resourceGroupName)")
        $kvResources = @($this.EnumKvResourceIds($vmssResources))
        if ($kvResources.count -lt 1) {
            $this.WriteWarning("EnumAllResources:unable to enumerate key vaults.")
        }
        else {
            [void]$resources.AddRange($kvResources)
        }

        $this.WriteLog("EnumAllResources:getting nsgs $($this.resourceGroupName)")
        $nsgResources = @($this.EnumNsgResourceIds($vnetResources))
        if ($nsgResources.count -lt 1) {
            $this.WriteWarning("EnumAllResources:unable to enumerate nsgs.")
        }
        else {
            [void]$resources.AddRange($nsgResources)
        }

        $this.WriteLog("EnumAllResources:getting nsg rules $($this.resourceGroupName)")
        $nsgRuleResources = @($this.EnumNsgRuleResourceIds($nsgResources))
        if ($nsgRuleResources.count -lt 1) {
            $this.WriteWarning("EnumAllResources:unable to enumerate nsg rules.")
        }
        else {
            [void]$resources.AddRange($nsgRuleResources)
        }

        if ($this.excludeResourceNames) {
            $resources = $resources | where-object Name -NotMatch "$($this.excludeResourceNames -join "|")"
        }

        $this.WriteLog("exit:EnumAllResources:`r`n$($this.CreateJson($resources))")
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
        $this.WriteLog("enter:EnumClusterResource")
        $clusters = @($this.GetAzResourceByType($this.resourceGroupName, 'Microsoft.ServiceFabric/clusters'))
        $clusterResource = $null
        $count = 1
        $number = 0

        $this.WriteVerbose("all clusters $clusters")
        if ($clusters.count -gt 1) {
            foreach ($cluster in $clusters) {
                $this.WriteLog("$($count). $($cluster.name)")
                $count++
            }

            $number = [convert]::ToInt32((read-host "enter number of the cluster to query or ctrl-c to exit:"))
            if ($number -le $count) {
                $clusterResource = $cluster[$number - 1].Name
                $this.WriteLog($clusterResource)
            }
            else {
                $this.WriteLog("exit:EnumClusterResource:null")
                return $null
            }
        }
        elseif ($clusters.count -lt 1) {
            $this.WriteError("exit:error:EnumClusterResource: no cluster found")
            return $null
        }
        else {
            $clusterResource = $clusters[0]
        }

        $this.WriteLog("using cluster resource $clusterResource", [consolecolor]::Green)
        $this.WriteLog("exit:EnumClusterResource")
        $this.clusterModel.cluster = $clusterResource
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
        $this.WriteLog("enter:EnumIpResourceIds")
        $resources = [collections.arraylist]::new()

        foreach ($lbResource in $lbResources) {
            $this.WriteLog("EnumIpResourceIds:checking lbResource for ip config $lbResource")
            $lb = $this.GetAzResourceById($lbResource)
            foreach ($fec in $lb.Properties.frontendIPConfigurations) {
                if ($this.GetPSPropertyValue($fec, 'properties.publicIpAddress')) {
                    $id = $fec.properties.publicIpAddress.id
                    $this.WriteLog("EnumIpResourceIds:adding public ip: $id", [consolecolor]::green)
                    [void]$resources.Add($id)

                    foreach ($vmssTreeResource in $this.clusterModel.FindVmssByExpression("`$psitem.loadbalancerIds.contains('$lbresource')")) {
                        [void]$vmssTreeResource.ipAddressIds.Add($id)
                    }
                }
            }
        }

        $this.WriteVerbose("EnumIpResourceIds:ip resources count:$($resources.Count) ip resources:`n$resources")
        $this.WriteLog("exit:EnumIpResourceIds")
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
        $this.WriteLog("enter:EnumKvResourceIds")
        $resources = [collections.arraylist]::new()

        foreach ($vmssResource in $vmssResources) {
            $this.WriteLog("EnumKvResourceIds:checking vmssResource for key vaults $($vmssResource.Name)")
            foreach ($id in $vmssResource.Properties.virtualMachineProfile.osProfile.secrets.sourceVault.id) {
                $this.WriteLog("EnumKvResourceIds:adding kv id: $id", [consolecolor]::green)
                [void]$resources.Add($id)

                [object]$vmssTreeResource = $this.clusterModel.FindVmssByResource($vmssResource) # .vmss.$vmssResource.keyvaultIds.Add($id)
                [void]$vmssTreeResource.keyvaultIds.Add($id)
            }
        }

        $this.WriteVerbose("kv resources $resources")
        $this.WriteLog("exit:EnumKvResourceIds")
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
        $this.WriteLog("enter:EnumLbResourceIds")
        $resources = [collections.arraylist]::new()

        foreach ($vmssResource in $vmssResources) {
            # get nic for vnet/subnet and lb
            $this.WriteLog("EnumLbResourceIds:checking vmssResource for network config $($vmssResource.Name)")

            if ($null -eq ($this.GetPSPropertyValue($vmssResource, 'Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.ipConfigurations'))) {
                $this.WriteError("unable to enumerate nic configuration from $($this.CreateJson($vmssResource))")
                continue
            }

            foreach ($nic in $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations) {
                foreach ($ipconfig in $nic.properties.ipConfigurations) {
                    $id = [regex]::replace($ipconfig.properties.loadBalancerBackendAddressPools.id, '/backendAddressPools/.+$', '')
                    $this.WriteLog("EnumLbResourceIds:adding lb id: $id", [consolecolor]::green)
                    [void]$resources.Add($id)

                    [object]$vmssTreeResource = $this.clusterModel.FindVmssByResource($vmssResource)
                    [void]$vmssTreeResource.loadbalancerIds.Add($id)
                }
            }
        }

        $this.WriteVerbose("lb resources $resources")
        $this.WriteLog("exit:EnumLbResourceIds")
        return $resources.ToArray() | sort-object -Unique
    }

    [string[]] EnumNsgResourceIds([object[]]$vnetResources) {
        <#
        .SYNOPSIS
            enumerate network security group resource id's from vnet resources
            outputs: string[]
        .OUTPUTS
            [string[]]
        #>
        $this.WriteLog("enter:EnumNsgResourceIds")
        $resources = [collections.arraylist]::new()

        foreach ($vnetId in $vnetResources) {
            $this.WriteLog("EnumNsgResourceIds:checking vnetId $($vnetId)")
            $vnetresource = @($this.GetAzResourceById($vnetId))

            if ($null -eq ($this.GetPSPropertyValue($vnetResource, 'Properties.subnets'))) {
                $this.WriteError("unable to enumerate subnet configuration from $($this.CreateJson($vnetResource))")
                continue
            }

            $this.WriteLog("EnumNsgResourceIds:checking vnet resource for nsg config $($vnetresource.Name)")

            foreach ($subnet in $vnetResource.Properties.subnets) {
                if (($this.GetPSPropertyValue($subnet, 'properties.networkSecurityGroup.id'))) {
                    $id = $subnet.properties.networkSecurityGroup.id
                    $this.WriteLog("EnumNsgResourceIds:adding nsg id: $id", [consolecolor]::green)
                    [void]$resources.Add($id)

                    foreach ($vmssTreeResource in $this.clusterModel.FindVmssByExpression("`$psitem.subnetIds.contains('$($subnet.Id)')")) {
                        [void]$vmssTreeResource.nsgIds.Add($id)
                    }
                }
            }
        }

        $this.WriteVerbose("nsg resources:$resources")
        $this.WriteLog("exit:EnumNsgResourceIds")
        return $resources.ToArray() | sort-object -Unique
    }

    [string[]] EnumNsgRuleResourceIds([object[]]$nsgResourceIds) {
        <#
        .SYNOPSIS
            enumerate network security group resource id's from vnet resources
            outputs: string[]
        .OUTPUTS
            [string[]]
        #>
        $this.WriteLog("enter:EnumNsgRuleResourceIds")
        $resources = [collections.arraylist]::new()

        foreach ($nsgResourceId in $nsgResourceIds) {
            if (!$nsgResourceId) { continue }
            $nsgResource = $this.GetAzResourceById($nsgResourceId)
            $this.WriteLog("EnumNsgRuleResourceIds:checking rules for resource for nsg config $($nsgResource.Name)")

            if ($null -eq ($this.GetPSPropertyValue($nsgResource, 'Properties.subnets'))) {
                $this.WriteError("unable to enumerate subnet configuration from $($this.CreateJson($nsgResource))")
                continue
            }

            foreach ($rule in $nsgResource.Properties.securityRules) {
                $this.WriteLog("EnumNsgRuleResourceIds:adding nsg rule: $($rule.name)", [consolecolor]::green)
                [void]$resources.Add($rule.id)

                foreach ($vmssTreeResource in $this.clusterModel.FindVmssByExpression("`$psitem.nsgIds.contains('$nsgResourceId')")) {
                    [void]$vmssTreeResource.nsgRuleIds.Add($rule.id)
                }
            }
        }

        $this.WriteVerbose("nsg rule resources:$resources")
        $this.WriteLog("exit:EnumNsgRuleResourceIds")
        return $resources.ToArray() | sort-object -Unique
    }

    [object[]] EnumStorageResources() {
        <#
        .SYNOPSIS
            enumerate storage resources from cluster resource
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:EnumStorageResources")
        $clusterResource = $this.EnumClusterResource()
        $resources = [collections.arraylist]::new()

        $this.sflogs = $this.GetPSPropertyValue($clusterResource, 'Properties.diagnosticsStorageAccountConfig.storageAccountName')
        $this.WriteLog("EnumStorageResources:cluster sflogs storage account $($this.sflogs)")

        #$scalesets = $this.EnumVmssResources()
        $scalesets = @($this.clusterModel.vmss.resource)
        if ($this.GetPSPropertyValues($scalesets, 'Properties.virtualMachineProfile.extensionProfile.extensions.properties.settings.storageAccount')) {
            $diagnosticAccount = $scalesets.Properties.virtualMachineProfile.extensionProfile.extensions.properties | where-object type -eq 'IaaSDiagnostics'
            if ($this.GetPSPropertyValues($diagnosticAccount, 'settings.storageAccount')) {
                $this.sfdiags = @($diagnosticAccount.settings.storageAccount) | Sort-Object -Unique
            }
        }

        $this.WriteLog("EnumStorageResources:cluster sfdiags storage account $($this.sfdiags)")
        $storageResources = @($this.GetAzResourceByType($this.resourceGroupName, 'Microsoft.Storage/storageAccounts'))

        $this.sflogs = $storageResources | where-object name -ieq $this.sflogs
        $this.sfdiags = @($storageResources | where-object name -ieq $this.sfdiags)

        [void]$resources.add($this.sflogs)
        [void]$this.clusterModel.storageAccountIds.Add($this.sflogs.id)

        foreach ($sfdiag in $this.sfdiags) {
            $this.WriteLog("EnumStorageResources: adding $sfdiag")
            [void]$resources.add($sfdiag)
            [void]$this.clusterModel.storageAccountIds.Add($sfdiag.id)
        }

        $this.WriteVerbose("storage resources $resources")
        $this.WriteLog("exit:EnumStorageResources")
        return $resources.ToArray() | sort-object name -Unique
    }

    [string[]] EnumSubnetResourceIds([object[]]$vmssResources) {
        <#
        .SYNOPSIS
            enumerate virtual network subnet resource Ids from vmss resources
            outputs: string[]
        .OUTPUTS
            [string[]]
        #>
        $this.WriteLog("enter:EnumSubnetResourceIds")
        $resources = [collections.arraylist]::new()

        foreach ($vmssResource in $vmssResources) {
            # get nic for vnet/subnet and lb
            $this.WriteLog("EnumSubnetResourceIds:checking vmssResource for network config $($vmssResource.Name)")

            if ($null -eq ($this.GetPSPropertyValue($vmssResource, 'Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.ipConfigurations'))) {
                $this.WriteError("unable to enumerate network interface configuration $($this.CreateJson($vmssResource))")
                continue
            }

            foreach ($nic in $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations) {
                foreach ($ipconfig in $nic.properties.ipConfigurations) {
                    $id = $ipconfig.properties.subnet.id
                    $this.WriteLog("EnumVnetResourceIds:adding subnet id: $id", [consolecolor]::green)
                    [void]$resources.Add($id)
                    [object]$vmssTreeResource = $this.clusterModel.FindVmssByResource($vmssResource)

                    if ($vmssTreeResource) {
                        [void]$vmssTreeResource.subnetIds.Add($id)
                    }
                    else {
                        $this.WriteWarning("EnumVnetResourceIds:unable to find vmss for subnet id: $id")
                    }
                }
            }
        }

        $this.WriteVerbose("subnet resources $resources")
        $this.WriteLog("exit:EnumSubnetResourceIds")
        return $resources.ToArray() | sort-object -Unique
    }

    [object[]] EnumVmssResources() {
        <#
        .SYNOPSIS
            enumerate virtual machine scaleset resources from cluster resource
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:EnumVmssResources")
        $clusterResource = $this.EnumClusterResource()
        $vmssResources = [collections.arraylist]::new()

        $clusterEndpoint = $clusterResource.Properties.clusterEndpoint
        $this.WriteLog("EnumVmssResources:cluster id $clusterEndpoint", [consolecolor]::Green)

        if (!$clusterEndpoint) {
            $this.WriteError("exit:EnumVmssResources:clusterEndpoint:$clusterEndpoint")
            return $null
        }

        $resources = @($this.GetAzResourceByType($this.resourceGroupName, 'Microsoft.Compute/virtualMachineScaleSets'))
        $this.WriteVerbose("EnumVmssResources:vmss resources $resources")

        foreach ($resource in $resources) {
            $vmsscep = $this.GetPSPropertyValue($resource, 'properties.virtualMachineProfile.extensionprofile.extensions.properties.settings.clusterendpoint')

            if ($vmsscep -and $vmsscep -ieq $clusterEndpoint) {
                $this.WriteLog("EnumVmssResources:adding vmss resource $($this.CreateJson($resource))", [consolecolor]::Cyan)
                [void]$vmssResources.Add($resource)
                $vmssTreeResource = [vmss]::new($resource)
                if ($this.clusterModel.vmss.count -lt 1 -or !($this.clusterModel.vmss.resource.name -ieq $resource.Name)) {
                    [void]$this.clusterModel.vmss.Add($vmssTreeResource)
                }
            }
            else {
                $this.WriteWarning("EnumVmssResources:vmss assigned to different cluster $vmsscep")
            }
        }

        $this.WriteLog("exit:EnumVmssResources")
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
        $this.WriteLog("enter:EnumVnetResourceIds")
        $resources = [collections.arraylist]::new()

        foreach ($vmssResource in $vmssResources) {
            # get nic for vnet/subnet and lb
            $this.WriteLog("EnumVnetResourceIds:checking vmssResource for network config $($vmssResource.Name)")

            if ($null -eq ($this.GetPSPropertyValue($vmssResource, 'Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.ipConfigurations'))) {
                $this.WriteError("unable to enumerate network interface configuration $($this.CreateJson($vmssResource))")
                continue
            }

            foreach ($nic in $vmssResource.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations) {
                foreach ($ipconfig in $nic.properties.ipConfigurations) {
                    $id = [regex]::replace($ipconfig.properties.subnet.id, '/subnets/.+$', '')
                    $this.WriteLog("EnumVnetResourceIds:adding vnet id: $id", [consolecolor]::green)
                    [void]$resources.Add($id)

                    [object]$vmssTreeResource = $this.clusterModel.FindVmssByResource($vmssResource)
                    [void]$vmssTreeResource.vnetIds.Add($id)
                }
            }
        }

        $this.WriteVerbose("vnet resources $resources")
        $this.WriteLog("exit:EnumVnetResourceIds")
        return $resources.ToArray() | sort-object -Unique
    }

    [void] ExportTemplate($configuredResources, $jsonFile) {
        <#
        .SYNOPSIS
            exports raw teamplate from azure using export-azresourcegroup cmdlet
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ExportTemplate:exporting template to $jsonFile", [consolecolor]::Yellow)
        $resourceIds = @($configuredResources.ResourceId)

        # todo issue
        new-item -ItemType File -path $jsonFile -ErrorAction SilentlyContinue
        $this.WriteLog("ExportTemplate:file exists:$((test-path $jsonFile))")
        $this.WriteLog("ExportTemplate:resource ids: $resourceIds", [consolecolor]::green)

        $this.WriteLog("Export-AzResourceGroup -ResourceGroupName $($this.resourceGroupName) `
            -Path $jsonFile `
            -Force `
            -IncludeComments `
            -IncludeParameterDefaultValue `
            -Resource $($resourceIds | out-string)", [consolecolor]::Blue)

        Export-AzResourceGroup -ResourceGroupName $this.resourceGroupName `
            -Path $jsonFile `
            -Force `
            -IncludeComments `
            -IncludeParameterDefaultValue `
            -Resource $resourceIds

        $this.WriteLog("exit:ExportTemplate:template exported to $jsonFile", [consolecolor]::Yellow)
    }

    [object] GetAzResourceById([string]$resourceId) {
        <#
        .SYNOPSIS
            enumerate azure resource by azure resource id using get-azresource with expanded properties
            outputs: object
        .OUTPUTS
            [object]
        #>

        $result = $null
        $this.WriteLog("enter:GetAzResourceById([string]$resourceId)", [ConsoleColor]::Magenta)
        if ($resourceId) {
            $this.WriteLog("get-azResource -resourceId $resourceId -ExpandProperties")
            $error.Clear()
            try {
                $result = get-azResource -resourceId $resourceId -ExpandProperties
                if ($error) { throw $error }
            }
            catch [Exception] {
                $this.WriteError("GetAzResourceById:exception:`r`n$psitem`r`n$($error | out-string)")
                $result = $null
                $error.Clear()
            }
        }
        else {
            $this.WriteError("GetAzResourceById:resourceId null/empty")
        }

        $this.WriteLog("exit:GetAzResourceById:get-azResource result:$($this.CreateJson($result))", [ConsoleColor]::DarkMagenta)
        return $result
    }

    [object] GetAzResourceByName([string]$resourceGroupName, [string]$resourceName) {
        <#
        .SYNOPSIS
            enumerate azure resource by azure resource group name and resource name using get-azresource
            outputs: object
        .OUTPUTS
            [object]
        #>

        $result = $null
        $this.WriteLog("enter:GetAzResourceByName([string]$resourceGroupName, [string]$resourceName)", [ConsoleColor]::Magenta)
        if ($resourceGroupName -and $resourceName) {
            $this.WriteLog("get-azResource -ResourceGroupName $resourceGroupName -Name $resourceName")
            $error.Clear()
            try {
                $result = get-azResource -ResourceGroupName $resourceGroupName -Name $resourceName
                if ($error) { throw $error }
            }
            catch [Exception] {
                $this.WriteError("GetAzResourceByName:exception:`r`n$psitem`r`n$($error | out-string)")
                $result = $null
                $error.Clear()
            }
        }
        else {
            $this.WriteError("GetAzResourceByName:resourceGroupName and/or resourceName null/empty")
        }

        $this.WriteLog("exit:GetAzResourceByName:get-azResource result:$($this.CreateJson($result))", [ConsoleColor]::DarkMagenta)
        return $result
    }

    [object] GetAzResourceByType([string]$resourceGroupName, [string]$resourceType) {
        <#
        .SYNOPSIS
            enumerate azure resource by azure resource group name and resource type using get-azresource with expanded properties
            outputs: object
        .OUTPUTS
            [object]
        #>

        $result = $null
        $this.WriteLog("enter:GetAzResourceByType([string]$resourceGroupName, [string]$resourceType)", [ConsoleColor]::Magenta)
        if ($resourceGroupName -and $resourceType) {
            $this.WriteLog("GetAzResourceByType:get-azResource -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ExpandProperties")
            $error.Clear()
            try {
                $result = get-azResource -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ExpandProperties
                if ($error) { throw $error }
            }
            catch [Exception] {
                $this.WriteError("GetAzResourceByType:exception:`r`n$psitem`r`n$($error | out-string)")
                $result = $null
                $error.Clear()
            }
        }
        else {
            $this.WriteError("GetAzResourceByType:resourceGroupName and/or resourceType null/empty")
        }

        $this.WriteLog("exit:GetAzResourceByType:get-azResource result:$($this.CreateJson($result))", [ConsoleColor]::DarkMagenta)
        return $result
    }

    [object] GetClusterResource() {
        <#
        .SYNOPSIS
            enumerate cluster resources[0] from $this.currentConfig
            outputs: object
        .OUTPUTS
            [object]
        #>
        $this.WriteLog("enter:GetClusterResource")
        $resources = @($this.currentConfig.resources | Where-Object type -ieq 'Microsoft.ServiceFabric/clusters')

        if ($resources.count -ne 1) {
            $this.WriteError("unable to find cluster resource")
        }

        $this.WriteVerbose("returning cluster resource $resources")
        $this.WriteLog("exit:GetClusterResource:$($resources[0])")
        return $resources[0]
    }

    [object[]] GetFromParametersSection( [string]$parameterName) {
        <#
        .SYNOPSIS
            enumerate defaultValue[] from parameters section by $parameterName
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetFromParametersSection parameterName=$parameterName")
        $results = @()

        if ($null -ne ($this.GetPSPropertyValue($this.currentConfig, "parameters.$parameterName.defaultValue"))) {
            $results = @($this.currentConfig.parameters.$parameterName)
        }

        if (@($results).Count -lt 1) {
            $this.WriteLog("GetFromParametersSection:no matching values found in parameters section for $parameterName")
        }
        if (@($results).count -gt 1) {
            $this.WriteWarning("GetFromParametersSection:multiple matching values found in parameters section for $parameterName")
        }

        $this.WriteLog("exit:GetFromParametersSection: returning: $($this.CreateJson($results))", [consolecolor]::Magenta)
        return $results
    }

    [object[]] GetIpResources() {
        <#
        .SYNOPSIS
            enumerate ip resources from $this.currentConfig
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetIpResources")
        $resources = @($this.currentConfig.resources | Where-Object type -ieq 'Microsoft.Network/publicIPAddresses')

        if ($resources.count -eq 0) {
            $this.WriteError("GetIpResources:unable to find ip resource")
        }

        $this.WriteVerbose("returning ip resource $resources")
        $this.WriteLog("exit:GetIpResources:$($resources.count)")
        return $resources
    }

    [object[]] GetLbResources() {
        <#
        .SYNOPSIS
            enumerate loadbalancer resources from $this.currentConfig
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetLbResources")
        $resources = @($this.currentConfig.resources | Where-Object type -ieq 'Microsoft.Network/loadBalancers')

        if ($resources.count -eq 0) {
            $this.WriteError("unable to find lb resource")
        }

        $this.WriteVerbose("returning lb resource $resources")
        $this.WriteLog("exit:GetLbResources:$($resources.count)")
        return $resources
    }

    [object[]] GetNodeTypeResources() {
        <#
        .SYNOPSIS
            get nodetype resources from $clusterResource
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetNodeTypeResources")
        $clusterResource = $this.GetClusterResource()
        $resources = @($clusterResource.Properties.nodetypes)

        if ($resources.count -eq 0) {
            $this.WriteError("GetNodeTypeResources:unable to find nodetype resource")
        }

        $this.WriteVerbose("returning nodetype resource $resources")
        $this.WriteLog("exit:GetNodeTypeResources:$($resources.count)")
        return $resources
    }

    [object[]] GetNsgResources() {
        <#
        .SYNOPSIS
            enumerate nsg resources from $this.currentConfig
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetNsgResources")
        $resources = @($this.currentConfig.resources | Where-Object type -ieq 'Microsoft.Network/networkSecurityGroups')

        if ($resources.count -eq 0) {
            $this.WriteWarning("unable to find nsg resource")
        }

        $this.WriteVerbose("returning nsg resources $resources")
        $this.WriteLog("exit:GetNsgResources:$($resources.count)")
        return $resources
    }

    [object] GetParameterizedNameFromValue([object]$resourceObject) {
        <#
        .SYNOPSIS
            enumerate parameter name from parameter value that is parameterized
            [regex]::match($resourceobject, "\[parameters\('(.+?)'\)\]")
            if no match, returns null
            outputs: string
        .OUTPUTS
            [string]
        #>
        $this.WriteLog("enter:GetParameterizedNameFromValue($resourceObject)")
        $retval = $null
        if ($this.IsParameterizedValue($resourceObject)) {
            if ([regex]::IsMatch($resourceobject, "\[parameters\('(.+?)'\)\]", $this.ignoreCase)) {
                $retval = [regex]::match($resourceobject, "\[parameters\('(.+?)'\)\]", $this.ignoreCase).groups[1].Value
            }
        }
        $this.WriteLog("exit:GetParameterizedNameFromValue:returning $retval")
        return $retval
    }

    [object[]] GetPrimaryIpResources() {
        <#
        .SYNOPSIS
            get primary ip resource from $clusterModel
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetPrimaryIpResources")
        $resources = [collections.arraylist]::new()
        $ipResources = $this.GetIpResources()

        foreach ($vmss in $this.GetPrimaryVmss()) {
            foreach ($ipResource in $ipResources) {
                if ($this.GetResourceIdFromResourceComments($ipResource) -imatch $vmss.ipAddressIds) {
                    $resources.Add($ipResource)
                }
            }
        }

        if ($resources.count -lt 1) {
            $this.WriteError("GetPrimaryIpResources:unable to find primary ip resource")
        }
        elseif ($resources.count -gt 1) {
            $this.WriteError("GetPrimaryIpResources:multiple ip resource")
        }

        $this.WriteVerbose("GetPrimaryIpResources:returning primary ip resource $resources")
        $this.WriteLog("exit:GetPrimaryIpResources:$($resources.count)")
        return $resources
    }

    [object[]] GetPrimaryLbResources() {
        <#
        .SYNOPSIS
            get primary lb resource from $clusterModel
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetPrimaryLbResources")
        $resources = [collections.arraylist]::new()
        $lbResources = $this.GetLbResources()

        foreach ($vmss in $this.GetPrimaryVmss()) {
            foreach ($lbResource in $lbResources) {
                if ($this.GetResourceIdFromResourceComments($lbresource) -imatch $vmss.loadbalancerIds) {
                    $resources.Add($lbResource)
                }
            }
        }

        if ($resources.count -lt 1) {
            $this.WriteError("GetPrimaryLbResources:unable to find primary lb resource")
        }
        elseif ($resources.count -gt 1) {
            $this.WriteError("GetPrimaryLbResources:multiple lb resource")
        }

        $this.WriteVerbose("GetPrimaryLbResources:returning primary lb resource $resources")
        $this.WriteLog("exit:GetPrimaryLbResources:$($resources.count)")
        return $resources
    }

    [object[]] GetPrimaryNodeType() {
        <#
        .SYNOPSIS
            get primary nodetype resource from $clusterResource
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetPrimaryNodeType")
        $primaryNodeTypes = [collections.arraylist]::new()

        # check for name and parameterized name before adding
        # use parameterized nodetypes if possible
        foreach ($nodeType in @($this.GetNodeTypeResources())) {
            $addedNodeType = $null
            $isParameterizedNodetype = $this.IsParameterizedValue($nodetype.name)
            $isPrimary = $this.GetResourceParameterValue($nodeType.isPrimary)
            $nodeTypeName = $this.GetResourceParameterValue($nodeType.name)
            $addedNodeType = $primaryNodeTypes.Where({ $psitem.name -ieq $nodeTypeName })
            
            $addedParameterizedNodeType = $false
            if ($isParameterizedNodetype) {
                $addedParameterizedNodeType = $primaryNodeTypes.Where({ $psitem.name -ieq $nodeType.name })
            }
            
            if ($isPrimary -eq $true) {
                if ($isParameterizedNodetype -and $addedNodeType -and !$addedParameterizedNodeType) {
                    $primaryNodeTypes.Remove($addedNodeType[0]) # unbox collection to psobject
                    $addedNodeType = $null
                }
                
                if (!$addedNodeType -and !$addedParameterizedNodeType) {
                    $primaryNodeTypes.Add($nodeType)
                }
            }
        }

        if ($primaryNodeTypes.count -lt 1) {
            $this.WriteError("GetPrimaryNodeType:unable to find primary nodetype resource")
        }
        elseif ($primaryNodeTypes.count -gt 1) {
            $this.WriteError("GetPrimaryNodeType:multiple primary nodetypes resource")
        }

        $this.WriteVerbose("GetPrimaryNodeType:returning primary nodetype resource $primaryNodeTypes")
        $this.WriteLog("exit:GetPrimaryNodeType:$($primaryNodeTypes.count)")
        return $primaryNodeTypes
    }

    [object[]] GetPrimaryVmss() {
        <#
        .SYNOPSIS
            get primary vmss resource from $clusterModel
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetPrimaryVmss")
        $resources = [collections.arraylist]::new()

        foreach ($nodeType in $this.GetPrimaryNodeType()) {
            $nodeName = $this.GetResourceParameterValue($nodeType.name)
            $resources.AddRange(@($this.clusterModel.FindVmssByExpression("`$psitem.resource.name -ieq '$($nodeName)'")))
        }

        if ($resources.count -lt 1) {
            $this.WriteError("GetPrimaryVmss:unable to find primary vmss resource")
        }
        elseif ($resources.count -gt 1) {
            $this.WriteError("GetPrimaryVmss:multiple vmss resource")
        }

        $this.WriteVerbose("GetPrimaryVmss:returning primary vmss resource $resources")
        $this.WriteLog("exit:GetPrimaryVmss:$($resources.count)")
        return $resources
    }

    [object] GetPSPropertyValue([object]$baseObject, [string]$property) {
        <#
        .SYNOPSIS
            enumerate powershell object property value
            [object]$baseObject powershell object
            outputs: object
        .OUTPUTS
            [object]
        #>
        $this.WriteVerbose("enter:GetPSPropertyValue([object]$baseObject,[string]$property)")
        $retvals = @($this.GetPSPropertyValues($baseObject, $property))

        if ($retvals.Count -gt 1) {
            $this.WriteError("GetPSPropertyValue:error more than one item found. returning first value.")
        }
        elseif ($retvals.Count -lt 1) {
            $this.WriteVerbose("GetPSPropertyValue:no items found")
            $retvals = @($null)
        }

        $this.WriteVerbose("exit:GetPSPropertyValue returning:$($retvals[0])")
        return $retvals[0]
    }

    [object[]] GetPSPropertyValues([object]$baseObject, [string]$property) {
        <#
        .SYNOPSIS
            enumerate powershell object property values
            [object]$baseObject powershell object
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>

        $this.WriteVerbose("enter:GetPSPropertyValues([object]$baseObject,[string]$property)")
        $retval = [collections.arraylist]::new()
        $properties = @($property.Split('.'))
        $childProperties = $property

        if ($properties.Count -lt 1) {
            $this.WriteWarning("property string empty:$property")
        }
        elseif ($null -ne $baseObject) {
            $propertyObject = $baseObject
            if ($propertyObject.GetType().isarray) {
                foreach ($propertyItem in $propertyObject) {
                    [void]$retval.AddRange($this.GetPSPropertyValues($propertyItem, $property))
                }
            }
            else {
                $subItem = $properties[0]
                $childProperties = $childProperties.trimStart($subItem).trimStart('.')
                $this.WriteVerbose("checking property:$($subItem) childProperties:$childProperties")

                if ($propertyObject.GetType().isarray) {
                    foreach ($propertyItem in $propertyObject) {
                        [void]$retval.AddRange($this.GetPSPropertyValues($propertyItem, $subItem))
                    }
                }
                elseif ($propertyObject.psobject.Properties.match($subItem).count -gt 0) {
                    foreach ($match in $propertyObject.psobject.Properties.match($subItem)) {
                        $this.WriteVerbose("found property:$($match.Name)")
                        $propertyObject = $propertyObject.($match.Name)
                        $this.WriteVerbose("property value:$($propertyObject | convertto-json)")

                        if ($childProperties) {
                            [void]$retval.AddRange($this.GetPSPropertyValues($propertyObject, $childProperties))
                        }
                        else {
                            [void]$retval.Add($propertyObject)
                        }
                    }
                }
                else {
                    $this.WriteVerbose("property not found:$($subItem)")
                }
            }
        }

        $this.WriteVerbose("exit:GetPSPropertyValues returning:$($retval)")
        return $retval.ToArray()
    }

    [string] GetResourceIdFromResourceComments([object]$resource) {
        <#
        .SYNOPSIS
            parses given resource.comments and returns resourceid
            outputs: string
        .OUTPUTS
            [string]
        #>

        $this.WriteLog("enter:GetResourceIdFromResourceComments([object]$resource)")
        $comments = $this.GetPSPropertyValue($resource, 'comments')
        if (!$comments) {
            $this.WriteError("exit:GetResourceIdFromResourceComments:error:unable to find resource.comments in resource")
            return $null
        }

        $resourceId = [regex]::match($comments, "Generalized from resource: '(.+?)'.").groups.value
        $this.WriteLog("exit:GetResourceIdFromResourceComments:name: $resourceId")
        if (!$this.IsValidResourceId($resourceId)) {
            $this.WriteError("error:unable to find valid resource id")
        }
        return $resourceId
    }

    [string] GetResourceNameFromResourceId([string]$resourceId) {
        <#
        .SYNOPSIS
            parses given resource id and returns name
            outputs: string
        .OUTPUTS
            [string]
        #>
        $this.WriteLog("enter:GetResourceNameFromResourceId([string]$resourceId)")
        $resourceName = [regex]::match($resourceId, "/subscriptions/.+/([^/]+?)?$").groups.value
        $this.WriteLog("exit:GetResourceNameFromResourceId:name: $resourceName")
        return $resourceName
    }

    [object] GetResourceParameterValue([object]$resourceProperty) {
        <#
        .SYNOPSIS
            gets resource parameter value from $resourceProperty object
            populates parameterized value from parameters section defaultValue
            outputs: object
        .OUTPUTS
            [object]
        #>
        return $this.GetResourceParameterValue($resourceProperty, $true)
    }

    [object] GetResourceParameterValue([object]$resourceProperty, [bool]$populateParameterizedValues = $false) {
        <#
        .SYNOPSIS
            gets resource parameter value from $resourceProperty object
            optionally populate parameterized value from parameters section defaultValue if exists
            outputs: object
        .OUTPUTS
            [object]
        #>
        $this.WriteLog("enter:GetResourceParameterValue([object]$resourceProperty, [bool]$populateParameterizedValues = $false)")
        $retval = $resourceProperty
        if ($populateParameterizedValues -and $this.IsParameterizedValue($resourceProperty)) {
            $retval = $this.GetFromParametersSection($this.GetParameterizedNameFromValue($resourceProperty)).defaultValue
        }

        $this.WriteLog("exit:GetResourceParameterValue:returning $retval")
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
        return $this.GetResourceParameterValue($resource, $name, $false)
    }

    [object] GetResourceParameterValue([object]$resource, [string]$name, [bool]$populateParameterizedValues = $false) {
        <#
        .SYNOPSIS
            gets resource parameter value from $resource object by $name
            optionally populate parameterized value from parameters section defaultValue if exists
            outputs: object
        .OUTPUTS
            [object]
        #>
        $this.WriteLog("enter:GetResourceParameterValue:resource:$($this.CreateJson($resource)) name:$name")
        $retval = $null
        $values = [collections.arraylist]::new()
        [void]$values.AddRange(@($this.GetResourceParameterValues($resource, $name, $populateParameterizedValues)))

        if ($values.Count -eq 1) {
            $this.WriteLog("GetResourceParameterValue:parameter name:$name found in resource. returning:$($this.CreateJson($values[0]))", [consolecolor]::Magenta)
            $retval = @($values)[0]
        }
        elseif ($values.Count -gt 1) {
            $this.WriteError("GetResourceParameterValue:multiple parameter names found in resource. returning first value:$($this.CreateJson($values))")
            $retval = @($values)[0]
        }
        elseif ($values.Count -lt 1) {
            $this.WriteError("GetResourceParameterValue:no parameter name found in resource. returning $null")
        }
        $this.WriteLog("exit:GetResourceParameterValue:returning:$($this.CreateJson($retval))", [consolecolor]::Magenta)
        return $retval
    }

    [object] GetResourceParameterValues([object]$resource, [string]$name) {
        <#
        .SYNOPSIS
            gets resource parameter values from $resource object by $name
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        return $this.GetResourceParameterValues($resource, $name, $false)
    }

    [object] GetResourceParameterValues([object]$resource, [string]$name, [bool]$populateParameterizedValues = $false) {
        <#
        .SYNOPSIS
            gets resource parameter values from $resource object by regex ^$name$
            optionally populate parameterized values from parameters section defaultValue if exists
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetResourceParameterValues:resource:$($this.CreateJson($resource)) name:$name")
        $retval = [collections.arraylist]::new()

        if ($resource.psobject.members.name -imatch 'ToArray') {
            foreach ($resourceObject in $resource.ToArray()) {
                [void]$retval.AddRange(@($this.GetResourceParameterValues($resourceObject, $name)))
            }
        }
        elseif ($resource.psobject.members.name -imatch 'GetEnumerator') {
            foreach ($resourceObject in $resource.GetEnumerator()) {
                [void]$retval.AddRange(@($this.GetResourceParameterValues($resourceObject, $name)))
            }
        }

        foreach ($psObjectProperty in $resource.psobject.Properties.GetEnumerator()) {

            $this.WriteVerbose("GetResourceParameterValues:checking parameter name:$($psobjectProperty.name)`r`n`tparameter type:$($psObjectProperty.TypeNameOfValue)`r`n`tfilter:$name")

            if (($psObjectProperty.Name -imatch "^$name$")) {
                $parameterValues = @($psObjectProperty | Where-Object Name -imatch "^$name$")
                if ($parameterValues.Count -eq 1) {
                    $parameterValue = $psObjectProperty.Value
                    if (!($parameterValue)) {
                        if ($parameterValue.GetType().Name -ieq 'boolean') {
                            $this.WriteLog("GetResourceParameterValues:returning:bool:false", [consolecolor]::green)
                            [void]$retval.Add($false)
                        }
                        elseif ($parameterValue.GetType().Name -ieq 'string') {
                            $this.WriteLog("GetResourceParameterValues:returning:string::empty", [consolecolor]::green)
                            [void]$retval.Add([string]::Empty)
                        }
                        else {
                            $this.WriteLog("GetResourceParameterValues:returning:null", [consolecolor]::green)
                            [void]$retval.Add($null)
                        }
                    }
                    else {
                        $this.WriteLog("GetResourceParameterValues:returning:$parameterValue", [consolecolor]::green)
                        if ($populateParameterizedValues -and $this.IsParameterizedValue($parameterValue)) {
                            $parameterValue = $this.GetFromParametersSection($this.GetParameterizedNameFromValue($parameterValue))
                        }
                        [void]$retval.Add($parameterValue)
                    }
                }
                else {
                    $this.WriteLog("GetResourceParameterValues:multiple parameter names found in resource")
                    foreach ($parameterValue in $parameterValues) {
                        if ($populateParameterizedValues -and $this.IsParameterizedValue($parameterValue)) {
                            $parameterValue = $this.GetFromParametersSection($this.GetParameterizedNameFromValue($parameterValue))
                        }
                        [void]$retval.Add($parameterValues)    
                    }
                }
            }
            elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Management.Automation.PSCustomObject') {
                [void]$retval.AddRange(@($this.GetResourceParameterValues($psObjectProperty.Value, $name)))
            }
            elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Collections.Hashtable') {
                [void]$retval.AddRange(@($this.GetResourceParameterValues($psObjectProperty.Value, $name)))
            }
            elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Collections.ArrayList') {
                [void]$retval.AddRange(@($this.GetResourceParameterValues($psObjectProperty.Value, $name)))
            }
            else {
                $this.WriteLog("GetResourceParameterValues:skipping property name:$($psObjectProperty.Name) type:$($psObjectProperty.TypeNameOfValue) filter:$name")
            }
        }
        $this.WriteLog("exit:GetResourceParameterValues:returning:$retval", [consolecolor]::Magenta)
        return $retval.ToArray()
    }

    [bool] GetUpdate($updateUrl) {
        <#
        .SYNOPSIS
            checks for script update
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        $this.WriteLog("GetUpdate:checking for updated script: $($updateUrl)")
        $gitScript = $null
        $scriptFile = $MyInvocation.ScriptName

        $error.Clear()
        $gitScript = Invoke-RestMethod -Uri $updateUrl

        if (!$error -and $gitScript) {
            $this.WriteLog("reading $scriptFile")
            $currentScript = get-content -raw $scriptFile

            $this.WriteVerbose("comparing export and current functions")
            if ([string]::Compare([regex]::replace($gitScript, "\s", ""), [regex]::replace($currentScript, "\s", "")) -eq 0) {
                $this.WriteLog("no change to $scriptFile. skipping update.", [consolecolor]::Cyan)
                $error.Clear()
                return $false
            }

            $error.clear()
            out-file -inputObject $gitScript -FilePath $scriptFile -Force

            if (!$error) {
                $this.WriteLog("$scriptFile has been updated. restart script.", [consolecolor]::yellow)
                return $true
            }

            $this.WriteWarning("$scriptFile has not been updated.")
        }
        else {
            $this.WriteWarning("error checking for updated script $error")
            $error.Clear()
            return $false
        }
        return $true
    }

    [object[]] GetVmssExtensions([object]$vmssResource, [string]$extensionType = $null) {
        <#
        .SYNOPSIS
            returns vmss extension resources from $vmssResource
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetVmssExtensions:vmssname: $($vmssResource.name)")
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
            $this.WriteError("GetVmssExtensions:unable to find extension in vmss resource $($vmssResource.name) $extensionType")
        }

        $this.WriteLog("exit:GetVmssExtensions:results count: $($results.count)")
        return $results.ToArray()
    }

    [object[]] GetVmssResources() {
        <#
        .SYNOPSIS
            returns vmss resources from $this.currentConfig
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetVmssResources")
        $resources = @($this.currentConfig.resources | Where-Object type -ieq 'Microsoft.Compute/virtualMachineScaleSets')
        if ($resources.count -eq 0) {
            $this.WriteError("GetVmssResources:unable to find vmss resource")
        }
        $this.WriteVerbose("GetVmssResources:returning vmss resource $resources")
        $this.WriteLog("exit:GetVmssResources")
        return $resources
    }

    [object[]] GetVmssResourcesByNodeType( [object]$nodetypeResource) {
        <#
        .SYNOPSIS
            returns vmss resources from $this.currentConfig by $nodetypeResource
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetVmssResourcesByNodeType")
        $vmssResources = $this.GetVmssResources()
        $vmssByNodeType = [collections.arraylist]::new()

        foreach ($vmssResource in $vmssResources) {
            $extension = $this.GetVmssExtensions($vmssResource, 'ServiceFabricNode')
            $parameterizedName = $this.GetParameterizedNameFromValue($extension.properties.settings.nodetyperef)

            if ($parameterizedName) {
                $nodetypeName = $this.GetFromParametersSection($parameterizedName)[0].defaultValue
            }
            else {
                $nodetypeName = $extension.properties.settings.nodetyperef
            }

            if ($nodetypeName -ieq $nodetypeResource.name) {
                $this.WriteLog("found scaleset by nodetyperef $nodetypeName", [consolecolor]::Cyan)
                [void]$vmssByNodeType.add($vmssResource)
            }
        }

        $this.WriteLog("exit:GetVmssResourcesByNodeType:result count:$($vmssByNodeType.count)")
        return $vmssByNodeType.ToArray()
    }

    [object[]] GetVnetResources() {
        <#
        .SYNOPSIS
            enumerate vnet resources from $this.currentConfig
            outputs: object[]
        .OUTPUTS
            [object[]]
        #>
        $this.WriteLog("enter:GetVnetResources")
        $resources = @($this.currentConfig.resources | Where-Object type -ieq 'Microsoft.Network/virtualNetworks')

        if ($resources.count -eq 0) {
            $this.WriteWarning("unable to find vnet resource")
        }

        $this.WriteVerbose("returning vnet resources $resources")
        $this.WriteLog("exit:GetVnetResources:$($resources.count)")
        return $resources
    }

    [bool] IsParameterizedValue([object]$value) {
        <#
        .SYNOPSIS
            returns whether $value is parameterized for template parameters
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        $this.WriteLog("enter:IsParameterizedValue:$value")
        $typeName = $value.gettype().name
        $retval = $false
        if ($typeName -ine "string") {
            $this.WriteVerbose("IsParameterizedValue:value type is not string. type:$typeName")
        }
        elseif ($value -imatch "^\[.+?\]$") {
            $this.WriteVerbose("IsParameterizedValue:value string has brackets. value:$value")
            $retval = $true
        }

        $this.WriteLog("exit:IsParameterizedValue:$retval")
        return $retval
    }

    [bool] IsValidResourceId([string]$resourceId) {
        <#
        .SYNOPSIS
            verifies $resourceId is valid pattern
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        $this.WriteLog("enter:IsValidResourceId:$resourceId")
        $resourceIdPattern = "/subscriptions/.+?/resourceGroups/.+?/providers/.+?/.+"
        $retval = [regex]::IsMatch($resourceId, $resourceIdPattern)
        $this.WriteLog("exit:IsValidResourceId:$retval")
        return $retval
    }

    [void] ModifyClusterResource() {
        <#
        .SYNOPSIS
            modifies cluster resource for current and deploy template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyClusterResource")

        $this.ModifyClusterResourceCerts('thumbprint')
        $this.ModifyClusterResourceCerts('thumbprintSecondary')

        $this.WriteLog("exit:ModifyClusterResource")
    }

    [void] ModifyClusterResourceCerts([string]$certificatePropertyName) {
        $clusterResource = $this.GetClusterResource()
        #parameterize certificate information
        $thumbprint = $this.GetResourceParameterValue($clusterResource.properties.certificate, $certificatePropertyName)

        if ($thumbprint) {
            $thumbprintParameterizedName = $this.CreateParameterizedName('thumbprint', $clusterResource)
            $this.WriteLog("setting $certificatePropertyName to $thumbprint")
            $null = $this.SetResourceParameterValue($clusterResource.properties.certificate, $certificatePropertyName, $thumbprintParameterizedName)
            $this.AddParameter($clusterResource, $certificatePropertyName, $certificatePropertyName, $clusterResource.properties.certificate, $thumbprint)
        }
    }

    [void] ModifyClusterResourceDeploy() {
        <#
        .SYNOPSIS
            modifies cluster resource for current and deploy template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyClusterResourceDeploy")

        # reparameterize all
        $null = $this.ParameterizeNodetypes($false, $false, $true)
        $this.WriteLog("exit:ModifyClusterResourceDeploy")
    }

    [void] ModifyClusterResourceRedeploy() {
        <#
        .SYNOPSIS
            modifies cluster resource for redeploy template from current
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyClusterResourceRedeploy")
        $sflogsParameter = $this.CreateParameterizedName('name', $this.sflogs, $true)
        $clusterResource = $this.GetClusterResource()

        $this.WriteLog("ModifyClusterResourceRedeploy:setting `$clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter")
        $clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName = $sflogsParameter

        if ($clusterResource.properties.upgradeMode -ieq 'Automatic') {
            $this.WriteLog("ModifyClusterResourceRedeploy:removing value cluster code version $($clusterResource.properties.clusterCodeVersion)", [consolecolor]::Yellow)
            [void]$clusterResource.properties.psobject.Properties.remove('clusterCodeVersion')
        }

        $reference = "[reference($($this.CreateParameterizedName('name',$clusterResource)))]"
        $this.AddOutputs('clusterProperties', $reference, 'object')
        $this.WriteLog("exit:ModifyClusterResourceRedeploy")
    }

    [void] ModifyIpAddressesRedeploy() {
        <#
        .SYNOPSIS
            modifies ip resources for redeploy template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyIpAddressesRedeploy")
        # add ip address dns parameter
        $metadataDescription = 'this name must be unique in deployment region.'
        $null = $this.AddParameterNameByResourceType("Microsoft.Network/publicIPAddresses", 'domainNameLabel', $metadataDescription)
        $null = $this.AddParameterNameByResourceType("Microsoft.Network/publicIPAddresses", 'fqdn', $metadataDescription)
        $this.WriteLog("exit:ModifyIpAddressesRedeploy")
    }

    [void] ModifyIpResourcesAddPrimary() {
        <#
        .SYNOPSIS
            modifies loadbalancer name parameter metadata for addprimary, addsecondary, new
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyIpResourcesAddPrimary")
        $primaryIpResources = $this.GetPrimaryIpResources()

        foreach ($ipResource in $this.GetIpResources()) {
            $ipName = $ipResource.name
            $description = $this.descriptionAddPrimary
            if ($primaryIpResources.name -inotmatch $ipResource.name) {
                $description = $this.descriptionPrimaryDoNotModify
            }
            $this.UpdateParametersSectionMetadataDescription($ipName, $description)
        }
        $this.WriteLog("exit:ModifyIpResourcesAddPrimary")
    }

    [void] ModifyIpResourcesAddSecondary() {
        <#
        .SYNOPSIS
            modifies loadbalancer name parameter metadata for addsecondary, new
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyIpResourcesAddSecondary")
        $primaryIpResources = $this.GetPrimaryIpResources()

        foreach ($ipResource in $this.GetIpResources()) {
            $ipName = $ipResource.name
            $description = $this.descriptionAddSecondary

            if ($primaryIpResources.name -imatch $ipResource.name) {
                $description = $this.descriptionPrimaryDoNotModify
            }

            $this.UpdateParametersSectionMetadataDescription($ipName, $description)
        }
        $this.WriteLog("exit:ModifyIpResourcesAddSecondary")
    }

    [void] ModifyLbResources() {
        <#
        .SYNOPSIS
            modifies loadbalancer resources for current
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyLbResources")
        $lbResources = $this.GetLbResources()

        foreach ($lbResource in $lbResources) {
            # fix backend pool
            $this.WriteLog("ModifyLbResources:fixing exported lb resource $($this.CreateJson($lbresource))")
            $dependsOn = [collections.arraylist]::new()
            $this.WriteLog("ModifyLbResources:removing backendpool from lb dependson")

            foreach ($depends in $lbresource.dependsOn) {
                $this.WriteLog("ModifyLbResources:checking depends:$depends")

                if ($depends -inotmatch "$($lbresource.Properties.backendAddressPools.Name -join '|')" -and $depends -inotmatch "$($lbresource.Properties.inboundNatPools.Name -join '|')") {
                    $this.WriteLog("ModifyLbResources:adding depends:$depends")
                    [void]$dependsOn.Add($depends)
                }
                else {
                    $this.WriteLog("ModifyLbResources:skipping depends:$depends")
                }
            }
            $lbResource.dependsOn = $dependsOn.ToArray()
            $this.WriteLog("ModifyLbResources:lbResource modified dependson: $($this.CreateJson($lbResource.dependson))", [consolecolor]::Yellow)
        }
        $this.WriteLog("exit:ModifyLbResources")
    }

    [void] ModifyLbResourcesAddPrimary() {
        <#
        .SYNOPSIS
            modifies loadbalancer name parameter metadata for addprimary, addsecondary, new
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyLbResourcesAddPrimary")

        foreach ($lbResource in $this.GetPrimaryLbResources()) {
            $lbName = $lbResource.name
            $this.UpdateParametersSectionMetadataDescription($lbName, $this.descriptionAddPrimary)
        }
        $this.WriteLog("exit:ModifyLbResourcesAddPrimary")
    }

    [void] ModifyLbResourcesAddSecondary() {
        <#
        .SYNOPSIS
            modifies loadbalancer name parameter metadata for addsecondary, new
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyLbResourcesAddSecondary")
        $primaryLbResources = $this.GetPrimaryLbResources()

        foreach ($lbResource in $this.GetLbResources()) {
            $lbName = $lbResource.name
            $description = $this.descriptionAddSecondary

            if ($primaryLbResources.name -imatch $lbResource.name) {
                $description = $this.descriptionPrimaryDoNotModify
            }

            $this.UpdateParametersSectionMetadataDescription($lbName, $description)
        }
        $this.WriteLog("exit:ModifyLbResourcesAddSecondary")
    }

    [void] ModifyLbResourcesRedeploy() {
        <#
        .SYNOPSIS
            modifies loadbalancer resources for redeploy template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyLbResourcesRedeploy")
        $lbResources = $this.GetLbResources()

        foreach ($lbResource in $lbResources) {
            # fix dupe pools and rules
            if ($lbResource.properties.inboundNatPools) {
                $this.WriteLog("ModifyLbResourcesRedeploy:removing natrules: $($this.CreateJson($lbResource.properties.inboundNatRules))", [consolecolor]::Yellow)
                [void]$lbResource.properties.psobject.Properties.Remove('inboundNatRules')
            }

        }
        $this.WriteLog("exit:ModifyLbResourcesRedeploy")
    }

    [void] ModifyNsgResources() {
        <#
        .SYNOPSIS
            modifies nsg dependson resources for current
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyNsgResources")
        $nsgResources = $this.GetNsgResources()

        foreach ($nsgResource in $nsgResources) {
            # fix security rules
            $this.WriteLog("ModifyNsgResources:fixing exported nsg resource $($this.CreateJson($nsgResource))")
            $dependsOn = [collections.arraylist]::new()
            $this.WriteLog("ModifyNsgResources:removing securityrules from nsg dependson")

            foreach ($depends in $nsgResource.dependsOn) {
                $this.WriteLog("ModifyNsgResources:checking depends:$depends")

                if ($depends -inotmatch "$($nsgResource.Properties.securityRules.Name -join '|')") {
                    $this.WriteLog("ModifyNsgResources:adding depends:$depends")
                    [void]$dependsOn.Add($depends)
                }
                else {
                    $this.WriteLog("ModifyNsgResources:skipping depends:$depends")
                }
            }
            $nsgResource.dependsOn = $dependsOn.ToArray()
            $this.WriteLog("ModifyNsgResources:nsg resource modified dependson: $($this.CreateJson($nsgResource.dependson))", [consolecolor]::Yellow)
        }
        $this.WriteLog("exit:ModifyNsgResources")
    }

    [string[]] ModifyStorageResourcesDeploy() {
        <#
        .SYNOPSIS
            modifies storage resources for deploy template
            outputs: string[]
        .OUTPUTS
            [string[]]
        #>
        $this.WriteLog("enter:ModifyStorageResourcesDeploy")
        $metadataDescription = 'this name must be unique in deployment region.'
        $parameterExclusions = [collections.arraylist]::new()
        $sflogsParameter = $this.CreateParametersName($this.sflogs)
        [void]$parameterExclusions.Add($sflogsParameter)
        $this.AddToParametersSection($sflogsParameter, $this.defaultSflogsValue, 'string', $metadataDescription)

        foreach ($sfdiag in $this.sfdiags) {
            $sfdiagParameter = $this.CreateParametersName($sfdiag)
            [void]$parameterExclusions.Add($sfdiagParameter)
            $this.AddToParametersSection($sfdiagParameter, $this.defaultSfdiagsValue, 'string', $metadataDescription)
        }

        $this.WriteLog("exit:ModifyStorageResourcesDeploy")
        return $parameterExclusions.ToArray()
    }

    [void] ModifyVmssResourceCertificateUrl([object]$vmssResource) {
        $this.WriteLog("enter:ModifyVmssResourceCertificateUrl")
        $certificatePropertyName = 'certificateUrl'
        $secretUrl = $this.GetResourceParameterValue($vmssResource.properties.virtualMachineProfile.osProfile.secrets, $certificatePropertyName)
        if ($secretUrl) {
            $thumbprintParameterizedName = $this.CreateParameterizedName($certificatePropertyName, $vmssResource)
            $this.WriteLog("setting $certificatePropertyName to $secretUrl")
            $null = $this.SetResourceParameterValue($vmssResource.properties.virtualMachineProfile.osProfile.secrets, $certificatePropertyName, $thumbprintParameterizedName)
            $this.AddParameter($vmssResource, $certificatePropertyName, $certificatePropertyName, $vmssResource.properties.virtualMachineProfile.osProfile.secrets, $secretUrl)
        }
        $this.WriteLog("exit:ModifyVmssResourceCertificateUrl")
    }

    [void] ModifyVmssResourceExtensionCerts([object] $vmssResource, [string] $certificatePropertyName = 'thumbprint') {
        $this.WriteLog("enter:ModifyVmssResourcesExtensionCerts")
        $extension = $this.GetVmssExtensions($vmssResource, 'ServiceFabricNode')
        #parameterize certificate information
        $thumbprint = $this.GetResourceParameterValue($extension, $certificatePropertyName)
        if ($thumbprint) {
            $thumbprintParameterizedName = $this.CreateParameterizedName($certificatePropertyName, $vmssResource)
            $this.WriteLog("setting $certificatePropertyName to $thumbprint")
            $null = $this.SetResourceParameterValue($extension.properties.settings.certificate, $certificatePropertyName, $thumbprintParameterizedName)
            $this.AddParameter($vmssResource, $certificatePropertyName, $certificatePropertyName, $extension.properties.settings.certificate, $thumbprint)
        }

        $this.WriteLog("exit:ModifyVmssResourcesExtensionCerts")
    }

    [void] ModifyVmssResources() {
        <#
        .SYNOPSIS
            modifies vmss resources dependson for current template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyVmssResources")
        $vmssResources = $this.GetVmssResources()

        foreach ($vmssResource in $vmssResources) {

            $this.WriteLog("modifying dependson")
            $dependsOn = [collections.arraylist]::new()
            $subnetIds = @($this.EnumSubnetResourceIds(@($vmssResource)))

            if ($this.GetPSPropertyValue($vmssResource, 'dependsOn')) {
                foreach ($depends in $vmssResource.dependsOn) {
                    if ($depends -imatch 'backendAddressPools') { continue }

                    if ($depends -imatch 'Microsoft.Network/loadBalancers') {
                        [void]$dependsOn.Add($depends)
                    }
                    # example depends "[resourceId('Microsoft.Network/virtualNetworks/subnets', parameters('virtualNetworks_VNet_name'), 'Subnet-0')]"
                    if ($subnetIds.contains($depends)) {
                        $this.WriteLog('cleaning subnet dependson', [consolecolor]::Yellow)
                        $depends = $depends.replace("/subnets'", "/'")
                        $depends = [regex]::replace($depends, "\), '.+?'\)\]", "))]")
                        [void]$dependsOn.Add($depends)
                    }
                }
                $vmssResource.dependsOn = $dependsOn.ToArray()
                $this.WriteLog("vmssResource modified dependson: $($this.CreateJson($vmssResource.dependson))", [consolecolor]::Yellow)
            }
            else {
                $this.WriteWarning("no dependson for $($this.CreateJson($vmssResource))")
            }
            #$this.ModifyVmssResourceExtensionCerts($vmssResource, 'thumbprint')
            #$this.ModifyVmssResourceExtensionCerts($vmssResource, 'thumbprintSecondary')

            # secreturl
            #$this.ModifyVmssResourceCertificateUrl($vmssResource)

            $adminPasswordName = 'adminPassword'

            if (!($this.GetPSPropertyValue($vmssResource, "properties.virtualMachineProfile.osProfile.$adminPasswordName"))) {
                $this.WriteLog("ModifyVmssResources:adding admin password")
                $vmssResource.properties.virtualMachineProfile.osProfile | Add-Member -MemberType NoteProperty -Name $adminPasswordName -Value $this.adminPassword

                $this.AddParameter(
                    $vmssResource, # resource
                    $adminPasswordName, # name
                    $adminPasswordName, # aliasName
                    $vmssResource.properties.virtualMachineProfile.osProfile, # resourceObject
                    $null, # value
                    'string', # type
                    'password must be set before deploying template.' # metadataDescription
                )
            }

            # fix The property 'requireGuestProvisionSignal' is not valid because the 'Microsoft.Compute/Agentless' feature is not enabled for this subscription."
            if ($this.GetPSPropertyValue($vmssResource, 'properties.virtualMachineProfile.osProfile.requireGuestProvisionSignal')) {
                $this.WriteLog("ModifyVmssResources:setting requireGuestProvisionSignal to false")
                $vmssResource.properties.virtualMachineProfile.osProfile.requireGuestProvisionSignal = $null
            }
        }
        $this.WriteLog("exit:ModifyVmssResources")
    }

    [void] ModifyVmssResourcesAddPrimary() {
        <#
        .SYNOPSIS
            modifies vmss resources for AddPrimary and AddSecondary template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyVmssResourcesAddPrimary")
        $primaryVmss = $this.GetPrimaryVmss()

        foreach ($vmssResource in $this.GetVmssResources()) {
            $description = $this.descriptionAddPrimary
            if ($primaryVmss.resource.name -inotmatch $vmssResource.name) {
                $description = $this.descriptionAddSecondary
            }
            $this.UpdateParametersSectionMetadataDescription($vmssResource.Name, $description)
            $this.WriteLog("ModifyVmssResourcesReDeploy:parameterizing hardware capacity")
            $this.AddParameter(
                $vmssResource, # resource
                'capacity', # name
                $vmssResource.sku, # resourceObject
                'int' # type
            )
        }
        $this.WriteLog("exit:ModifyVmssResourcesAddPrimary")
    }

    [void] ModifyVmssResourcesAddSecondary() {
        <#
        .SYNOPSIS
            modifies vmss resources for AddSecondary template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyVmssResourcesAddSecondary")
        $primaryVmss = $this.GetPrimaryVmss()

        foreach ($vmssResource in $this.GetVmssResources()) {
            $description = $this.descriptionAddSecondary
            if ($primaryVmss.resource.name -imatch $vmssResource.name) {
                $description = $this.descriptionPrimaryDoNotModify
            }
            $this.UpdateParametersSectionMetadataDescription($vmssResource.Name, $description)
        }
        $this.WriteLog("exit:ModifyVmssResourcesAddSecondary")
    }

    [void] ModifyVmssResourcesRedeploy() {
        <#
        .SYNOPSIS
            modifies vmss resources for redeploy template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyVmssResourcesReDeploy")
        $vmssResources = $this.GetVmssResources()

        foreach ($vmssResource in $vmssResources) {
            # add protected settings
            $this.AddVmssProtectedSettings($vmssResource)

            # remove mma
            $extensions = [collections.arraylist]::new()
            foreach ($extension in $vmssResource.properties.virtualMachineProfile.extensionProfile.extensions) {
                if ($extension.properties.type -ieq 'MicrosoftMonitoringAgent') {
                    continue
                }
                if ($extension.properties.type -ieq 'ServiceFabricNode') {
                    $this.WriteLog("ModifyVmssResourcesReDeploy:parameterizing cluster endpoint")
                    $clusterResource = $this.GetClusterResource()
                    $parameterizedName = $this.CreateParameterizedName('name', $clusterResource)
                    $newName = "[reference($parameterizedName).clusterEndpoint]"

                    $this.WriteLog("ModifyVmssResourcesReDeploy:setting cluster endpoint value to:$newName")
                    $null = $this.SetResourceParameterValue($extension.properties.settings, 'clusterEndpoint', $newName)
                }
                [void]$extensions.Add($extension)
            }

            $vmssResource.properties.virtualMachineProfile.extensionProfile.extensions = $extensions

            $this.WriteLog("ModifyVmssResourcesReDeploy:modifying dependson")
            $dependsOn = [collections.arraylist]::new()
            $subnetIds = @($this.EnumSubnetResourceIds(@($vmssResource)))

            foreach ($depends in $vmssResource.dependsOn) {
                if ($depends -imatch 'backendAddressPools') { continue }

                if ($depends -imatch 'Microsoft.Network/loadBalancers') {
                    [void]$dependsOn.Add($depends)
                }
                # example depends "[resourceId('Microsoft.Network/virtualNetworks/subnets', parameters('virtualNetworks_VNet_name'), 'Subnet-0')]"
                if ($subnetIds.contains($depends)) {
                    $this.WriteLog('ModifyVmssResourcesReDeploy:cleaning subnet dependson', [consolecolor]::Yellow)
                    $depends = $depends.replace("/subnets'", "/'")
                    $depends = [regex]::replace($depends, "\), '.+?'\)\]", "))]")
                    [void]$dependsOn.Add($depends)
                }
            }

            $vmssResource.dependsOn = $dependsOn.ToArray()
            $this.WriteLog("ModifyVmssResourcesReDeploy:vmssResource modified dependson: $($this.CreateJson($vmssResource.dependson))", [consolecolor]::Yellow)

            $this.WriteLog("ModifyVmssResourcesReDeploy:parameterizing hardware sku")
            $this.AddParameter(
                $vmssResource, # resource
                'name', # name
                'hardwareSku', # aliasName
                $vmssResource.sku # resourceObject
            )

            $this.WriteLog("ModifyVmssResourcesReDeploy:parameterizing os sku")
            $this.AddParameter(
                $vmssResource, # resource
                'sku', # name
                'osSku', # aliasName
                $vmssResource.properties.virtualMachineProfile.storageProfile.imageReference # resourceObject
            )
        }
        $this.WriteLog("exit:ModifyVmssResourcesReDeploy")
    }

    [void] ModifyVnetResources() {
        <#
        .SYNOPSIS
            modifies vnet dependson resources for current
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ModifyVnetResources")
        $vnetResources = $this.GetVnetResources()

        foreach ($vnetResource in $vnetResources) {
            # fix security rules
            $this.WriteLog("ModifyVnetResources:fixing exported vnet resource $($this.CreateJson($vnetResource))")
            $dependsOn = [collections.arraylist]::new()
            $this.WriteLog("ModifyVnetResources:removing subnets from nsg dependson")

            foreach ($depends in $vnetResource.dependsOn) {
                $this.WriteLog("ModifyVnetResources:checking depends:$depends")

                if ($depends -inotmatch "$($vnetResource.Properties.subnets.Name -join '|')") {
                    $this.WriteLog("ModifyVnetResources:adding depends:$depends")
                    [void]$dependsOn.Add($depends)
                }
                else {
                    $this.WriteLog("ModifyVnetResources:skipping depends:$depends")
                }
            }
            $vnetResource.dependsOn = $dependsOn.ToArray()
            $this.WriteLog("ModifyVnetResources:nsg resource modified dependson: $($this.CreateJson($vnetResource.dependson))", [consolecolor]::Yellow)
        }
        $this.WriteLog("exit:ModifyVnetResources")
    }

    [void] ParameterizeNodetype( [object]$nodetype, [string]$parameterName) {
        <#
        .SYNOPSIS
            parameterizes nodetype for addnodetype template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.ParameterizeNodetype($nodetype, $parameterName, $null, 'string')
    }

    [void] ParameterizeNodetype( [object]$nodetype, [string]$parameterName, [object]$parameterValue = $null) {
        <#
        .SYNOPSIS
            parameterizes nodetype for addnodetype template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.ParameterizeNodetype($nodetype, $parameterName, $parameterValue, 'string')
    }

    [void] ParameterizeNodetype( [object]$nodetype, [string]$parameterName, [string]$type = 'string') {
        <#
        .SYNOPSIS
            parameterizes nodetype for addnodetype template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.ParameterizeNodetype($nodetype, $parameterName, $null, $type)
    }

    [void] ParameterizeNodetype( [object]$nodetype, [string]$parameterName, [object]$parameterValue = $null, [string]$type = 'string') {
        <#
        .SYNOPSIS
            parameterizes nodetype for addnodetype template
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:ParameterizeNodetype:nodetype:$($this.CreateJson($nodetype)) parameterName:$parameterName parameterValue:$parameterValue type:$type")
        $vmssResources = @($this.GetVmssResourcesByNodeType($nodetype))
        $parameterizedName = $null

        if ($null -eq $parameterValue) {
            $parameterValue = $this.GetResourceParameterValue($nodetype, $parameterName)
        }
        foreach ($vmssResource in $vmssResources) {
            $parametersName = $this.CreateParametersName($vmssResource, $parameterName)

            $parameterizedName = $this.GetParameterizedNameFromValue($this.GetResourceParameterValue($nodetype, $parameterName))
            if (!$parameterizedName) {
                $parameterizedName = $this.CreateParameterizedName($parameterName, $vmssResource)
            }

            $metadataDescription = $null
            $null = $this.AddToParametersSection($parametersName, $parameterValue, $type, $metadataDescription)
            $this.WriteLog("ParameterizeNodetype:setting $parametersName to $parameterValue for $($nodetype.name)", [consolecolor]::Magenta)

            $this.WriteLog("ParameterizeNodetype:AddParameter `
                -resource $vmssResource `
                -name $parameterName `
                -resourceObject $nodetype `
                -value $parameterizedName `
                -type $type `
                -metadataDescription $metadataDescription
            ")

            $this.AddParameter(
                $vmssResource, # resource
                $parameterName, # name
                $parameterName, # aliasName
                $nodetype, # resourceObject
                $parameterizedName, # value
                $type, # type
                $metadataDescription # description
            )

            $extension = $this.GetVmssExtensions($vmssResource, 'ServiceFabricNode')

            $this.WriteLog("ParameterizeNodetype:AddParameter `
                -resource $vmssResource `
                -name $parameterName `
                -resourceObject $($extension.properties.settings) `
                -value $parameterizedName `
                -type $type
            ")

            $this.AddParameter(
                $vmssResource, # resource
                $parameterName, # name
                $parameterName, # aliasName
                $extension.properties.settings, # resourceObject
                $parameterizedName, # value
                $type, # type
                '' # description
            )
        }
        $this.WriteLog("exit:ParameterizeNodetype")
    }

    [bool] ParameterizeNodetypes() {
        <#
        .SYNOPSIS
            parameterizes nodetypes for addnodetype template filtered by $isPrimaryFilter and isPrimary value set to $isPrimaryValue
            there will always be at least one primary nodetype unparameterized except for 'new' template
            there will only be one parameterized nodetype
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        return $this.ParameterizeNodetypes($false, $false, $false)
    }

    [bool] ParameterizeNodetypes([bool]$isPrimaryFilter = $false) {
        <#
        .SYNOPSIS
            parameterizes nodetypes for addnodetype template filtered by $isPrimaryFilter and isPrimary value set to $isPrimaryValue
            there will always be at least one primary nodetype unparameterized except for 'new' template
            there will only be one parameterized nodetype
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        return $this.ParameterizeNodetypes($isPrimaryFilter, $isPrimaryFilter, $false)
    }

    [bool] ParameterizeNodetypes([bool]$isPrimaryFilter = $false, [bool]$isPrimaryValue = $isPrimaryFilter) {
        <#
        .SYNOPSIS
            parameterizes nodetypes for addnodetype template filtered by $isPrimaryFilter and isPrimary value set to $isPrimaryValue
            there will always be at least one primary nodetype unparameterized except for 'new' template
            there will only be one parameterized nodetype
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        return $this.ParameterizeNodetypes($isPrimaryFilter, $isPrimaryValue, $false)
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
        $this.WriteLog("enter:ParameterizeNodetypes([bool]$isPrimaryFilter, [bool]$isPrimaryValue, [switch]$all)")
        # todo. should validation be here? how many nodetypes
        $null = $this.RemoveParameterizedNodeTypes()
        $clusterResource = $this.GetClusterResource()
        $nodetypes = [collections.arraylist]::new($this.GetNodeTypeResources())
        $filterednodetypes = $nodetypes.psobject.copy()

        if ($nodetypes.Count -lt 1) {
            $this.WriteError("exit:ParameterizeNodetypes:no nodetypes detected!")
            return $false
        }

        $this.WriteLog("ParameterizeNodetypes:current nodetypes $($nodetypes.name)", [consolecolor]::Green)

        if ($all) {
            $nodetypes.Clear()
        }
        else {
            $filterednodetypes = @($nodetypes | Where-Object isPrimary -ieq $isPrimaryFilter)
        }

        if ($filterednodetypes.count -eq 0) {
            $this.WriteWarning("exit:ParameterizeNodetypes:unable to find nodetype where isPrimary=$isPrimaryFilter")
            return $false
        }

        if ($filterednodetypes.count -gt 1 -and $isPrimaryFilter) {
            $this.WriteWarning("ParameterizeNodetypes:more than one primary node type detected!")
        }

        if (!$all) {
            $filterednodetypes = $filterednodetypes[0]
        }

        foreach ($filterednodetype in $filterednodetypes) {
            $this.WriteLog("ParameterizeNodetypes:adding new nodetype", [consolecolor]::Cyan)
            $newNodeType = $filterednodetype.psobject.copy()
            $existingVmssNodeTypeRef = @($this.GetVmssResourcesByNodeType($newNodeType))

            if ($existingVmssNodeTypeRef.count -lt 1) {
                $this.WriteError("exit:ParameterizeNodetypes:unable to find existing nodetypes by nodetyperef")
                return $false
            }

            $this.WriteLog("ParameterizeNodetypes:parameterizing new nodetype ", [consolecolor]::Cyan)

            # setting capacity value should be parametized value to vmInstanceCount value
            $capacity = $this.GetResourceParameterValue($existingVmssNodeTypeRef[0].sku, 'capacity')
            $null = $this.SetResourceParameterValue($newNodeType, 'vmInstanceCount', $capacity)

            $this.ParameterizeNodetype(
                $newNodeType, # nodetype
                'durabilityLevel' # parameterName
            )

            if ($all) {
                $this.ParameterizeNodetype(
                    $newNodeType, # nodetype
                    'isPrimary', # parameterName
                    'bool' # type
                )
            }
            else {
                $this.ParameterizeNodetype(
                    $newNodeType, # nodetype
                    'isPrimary', # parameterName
                    $isPrimaryValue, # parameterValue
                    'bool' # type
                )
            }

            # todo: currently name has to be parameterized last so parameter names above can be found
            $this.ParameterizeNodetype(
                $newNodeType, # nodetype
                'name' # parameterName
            )

            [void]$nodetypes.Add($newNodeType)
        }

        $clusterResource.properties.nodetypes = $nodetypes
        $this.WriteLog("exit:ParameterizeNodetypes:result:`r`n$($this.CreateJson($nodetypes))")
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
        $this.WriteLog("enter:RemoveDuplicateResources")
        # fix up deploy errors by removing duplicated sub resources on root like lb rules by
        # removing any 'type' added by export-azresourcegroup that was not in the $this.configuredRGResources
        $currentResources = [collections.arraylist]::new()

        $resourceTypes = $this.configuredRGResources.resourceType
        foreach ($resource in $this.currentConfig.resources.GetEnumerator()) {
            $this.WriteLog("RemoveDuplicateResources:checking exported resource $($resource.name)", [consolecolor]::Magenta)
            $this.WriteVerbose("RemoveDuplicateResources:checking exported resource $($this.CreateJson($resource))")

            if ($resourceTypes.Contains($resource.type)) {
                $this.WriteLog("RemoveDuplicateResources:adding exported resource $($resource.name)", [consolecolor]::Cyan)
                $this.WriteVerbose("RemoveDuplicateResources:adding exported resource $($this.CreateJson($resource))")
                [void]$currentResources.Add($resource)
            }
        }
        $this.currentConfig.resources = $currentResources
        $this.WriteLog("exit:RemoveDuplicateResources")
    }

    [bool] RemoveParameterizedNodeTypes() {
        <#
        .SYNOPSIS
            removes parameterized nodetypes for from cluster resource section in $this.currentConfig
            there will always be at least one primary nodetype unparameterized unless 'new' template
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        $this.WriteLog("enter:RemoveParameterizedNodeTypes")
        $clusterResource = $this.GetClusterResource()
        $cleanNodetypes = [collections.arraylist]::new()
        $nodetypes = [collections.arraylist]::new($this.GetNodeTypeResources())
        $retval = $false

        if ($nodetypes.Count -lt 1) {
            $this.WriteError("exit:RemoveParameterizedNodeTypes:no nodetypes detected!")
            return $false
        }

        foreach ($nodetype in $nodetypes) {
            if (!($this.GetParameterizedNameFromValue($nodetype.name))) {
                $this.WriteLog("RemoveParameterizedNodeTypes:skipping:$($nodetype.name)")
                [void]$cleanNodetypes.Add($nodetype)
            }
            else {
                $this.WriteLog("RemoveParameterizedNodeTypes:removing:$($nodetype.name)")
            }
        }

        if ($cleanNodetypes.Count -gt 0) {
            $retval = $true
            $clusterResource.properties.nodetypes = $cleanNodetypes
            $null = $this.RemoveUnusedParameters()
        }
        else {
            $this.WriteError("RemoveParameterizedNodeTypes:no clean nodetypes")
        }

        $this.WriteLog("exit:RemoveParameterizedNodeTypes:$retval")
        return $retval
    }

    [bool] RemoveUnparameterizedNodeTypes() {
        <#
        .SYNOPSIS
            removes unparameterized nodetypes for from cluster resource section in $this.currentConfig
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        $this.WriteLog("enter:RemoveUnparameterizedNodeTypes")
        $clusterResource = $this.GetClusterResource()
        $cleanNodetypes = [collections.arraylist]::new()
        $nodetypes = [collections.arraylist]::new($this.GetNodeTypeResources())
        $retval = $false

        if ($nodetypes.Count -lt 1) {
            $this.WriteError("exit:RemoveUnparameterizedNodeTypes:no nodetypes detected!")
            return $false
        }

        foreach ($nodetype in $nodetypes) {
            if (($this.GetParameterizedNameFromValue($nodetype.name))) {
                $this.WriteLog("RemoveUnparameterizedNodeTypes:removing:$($nodetype.name)")
                [void]$cleanNodetypes.Add($nodetype)
            }
            else {
                $this.WriteLog("RemoveUnparameterizedNodeTypes:skipping:$($nodetype.name)")
            }
        }

        if ($cleanNodetypes.Count -gt 0) {
            $retval = $true
            $clusterResource.properties.nodetypes = $cleanNodetypes
            #$null = RemoveUnusedParameters
        }
        else {
            $this.WriteError("RemoveUnparameterizedNodeTypes:no parameterized nodetypes")
        }

        $this.WriteLog("exit:RemoveUnparameterizedNodeTypes:$retval")
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
        $this.WriteLog("enter:RemoveUnusedParameters")
        $parametersRemoveList = [collections.arraylist]::new()
        #serialize and copy
        $currentConfigResourcejson = $this.CreateJson($this.currentConfig)
        $currentConfigJson = $currentConfigResourcejson | convertfrom-json

        # remove parameters section but keep everything else like variables, resources, outputs
        [void]$currentConfigJson.psobject.properties.remove('Parameters')
        $currentConfigResourcejson = $this.CreateJson($currentConfigJson)

        foreach ($psObjectProperty in $this.currentConfig.parameters.psobject.Properties) {
            $parameterizedName = $this.CreateParameterizedName($psObjectProperty.name)
            $this.WriteLog("RemoveUnusedParameters:checking to see if $parameterizedName is being used")
            if ([regex]::IsMatch($currentConfigResourcejson, [regex]::Escape($parameterizedName), $this.ignoreCase)) {
                $this.WriteVerbose("RemoveUnusedParameters:$parameterizedName is being used")
                continue
            }
            $this.WriteVerbose("RemoveUnusedParameters:removing $parameterizedName")
            [void]$parametersRemoveList.Add($psObjectProperty)
        }

        foreach ($parameter in $parametersRemoveList) {
            $this.WriteLog("RemoveUnusedParameters:removing $($parameter.name)")
            [void]$this.currentConfig.parameters.psobject.Properties.Remove($parameter.name)
        }
        $this.WriteLog("exit:RemoveUnusedParameters")
    }

    [bool] RenameParameter( [string]$oldParameterName, [string]$newParameterName) {
        <#
        .SYNOPSIS
            renames parameter from $oldParameterName to $newParameterName by $oldParameterName in all template sections
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        $this.WriteLog("enter:RenameParameter: $oldParameterName, $newParameterName")

        if (!$oldParameterName -or !$newParameterName) {
            $this.WriteError("exit:RenameParameter:error:empty parameters:oldParameterName:$oldParameterName newParameterName:$newParameterName")
            return $false
        }

        $oldParameterizedName = CreateParameterizedName -parameterName $oldParameterName
        $newParameterizedName = CreateParameterizedName -parameterName $newParameterName
        $this.currentConfigResourcejson = $null

        if (!$this.currentConfig.parameters) {
            $this.WriteError("exit:RenameParameter:error:empty parameters section")
            return $false
        }

        #serialize
        $this.currentConfigParametersjson = $this.CreateJson($this.currentConfig.parameters)
        $this.currentConfigResourcejson = $this.CreateJson($this.currentConfig)

        if ([regex]::IsMatch($this.currentConfigResourcejson, [regex]::Escape($newParameterizedName), $this.ignoreCase)) {
            $this.WriteError("exit:RenameParameter:new parameter already exists in resources section:$newParameterizedName")
            return $false
        }

        if ([regex]::IsMatch($this.currentConfigParametersjson, [regex]::Escape($newParameterName), $this.ignoreCase)) {
            $this.WriteError("exit:RenameParameter:new parameter already exists in parameters section:$newParameterizedName")
            return $false
        }

        if ([regex]::IsMatch($this.currentConfigParametersjson, [regex]::Escape($oldParameterName), $this.ignoreCase)) {
            $this.WriteVerbose("RenameParameter:found parameter Name:$oldParameterName")
            $this.currentConfigParametersjson = [regex]::Replace($this.currentConfigParametersjson, [regex]::Escape($oldParameterName), $newParameterName, $this.ignoreCase)
            $this.WriteVerbose("RenameParameter:replaced $oldParameterName json:$this.currentConfigParametersJson")
            $this.currentConfig.parameters = $this.currentConfigParametersjson | convertfrom-json

            # reserialize with modified parameters section
            $this.currentConfigResourcejson = $this.CreateJson($this.currentConfig)
        }
        else {
            $this.WriteWarning("RenameParameter:parameter not found:$oldParameterName")
        }

        if ($this.currentConfigResourcesjson) {
            if ([regex]::IsMatch($this.currentConfigResourcejson, [regex]::Escape($oldParameterizedName), $this.ignoreCase)) {
                $this.WriteVerbose("RenameParameter:found parameterizedName:$oldParameterizedName")
                $this.currentConfigResourceJson = [regex]::Replace($this.currentConfigResourcejson, [regex]::Escape($oldParameterizedName), $newParameterizedName, $this.ignoreCase)
                $this.WriteVerbose("RenameParameter:replaced $oldParameterizedName json:$this.currentConfigResourceJson")
                $this.currentConfig = $this.currentConfigResourcejson | convertfrom-json
            }
            else {
                $this.WriteWarning("RenameParameter:parameter not found:$oldParameterizedName")
            }
        }

        $this.WriteVerbose("RenameParameter:result:$($this.CreateJson($this.currentConfig))")
        $this.WriteLog("exit:RenameParameter")
        return $true
    }

    [bool] SetResourceParameterValue([object]$resource, [string]$name, [object]$newValue) {
        <#
        .SYNOPSIS
            sets resource parameter value in resources section
            outputs: bool
        .OUTPUTS
            [bool]
        #>
        $this.WriteLog("enter:SetResourceParameterValue:resource:$($this.CreateJson($resource)) name:$name,newValue:$newValue", [consolecolor]::DarkCyan)
        $retval = $false
        foreach ($psObjectProperty in $resource.psobject.Properties.GetEnumerator()) {
            $this.WriteVerbose("SetResourceParameterValue:checking parameter name $psobjectProperty")

            if (($psObjectProperty.Name -ieq $name)) {
                $parameterValues = @($psObjectProperty.Name)
                if ($parameterValues.Count -eq 1) {
                    $psObjectProperty.Value = $newValue
                    $retval = $true
                    break
                }
                else {
                    $this.WriteError("SetResourceParameterValue:multiple parameter names found in resource. returning")
                    $retval = $false
                    break
                }
            }
            elseif ($psObjectProperty.TypeNameOfValue -ieq 'System.Management.Automation.PSCustomObject') {
                $retval = $this.SetResourceParameterValue($psObjectProperty.Value, $name, $newValue)
            }
            else {
                $this.WriteVerbose("SetResourceParameterValue:skipping type:$($psObjectProperty.TypeNameOfValue)")
            }
        }

        $this.WriteLog("exit:SetResourceParameterValue:returning:$retval")
        return $retval
    }

    [void] UpdateParametersSectionMetadataDescription( [string]$parameterName, [string]$metadataDescription) {
        <#
        .SYNOPSIS
            updates metadatadescription for existing parameter based on $parameterName
            outputs: null
        .OUTPUTS
            [null]
        #>

        $this.WriteLog("enter:UpdateParametersSectionMetadataDescription:parameterName:$parameterName, metadataDescription:$metadataDescription")
        if ($this.IsParameterizedValue($parameterName)) {
            $parameterName = $this.GetParameterizedNameFromValue($parameterName)
        }

        $existingParameters = @($this.GetFromParametersSection($parameterName))

        if ($existingParameters.Count -lt 1) {
            $this.WriteError("exit:UpdateParametersSectionMetadataDescription:$parameterName not found in parameters sections. returning.")
            return
            #$this.AddToParametersSection($parameterName, $parameterNameValue, $type, $metadataDescription)
        }
        elseif ($existingParameters.Count -lt 1) {
            $this.WriteError("exit:UpdateParametersSectionMetadataDescription: multiple $parameterName found in parameters sections. returning.")
            return
            #$this.AddToParametersSection($parameterName, $parameterNameValue, $type, $metadataDescription)
        }

        $existingParameter = $existingParameters[0]
        $parameterObject = [pscustomobject]@{
            type         = $existingParameter.type
            defaultValue = $existingParameter.defaultValue
            metadata     = [pscustomobject]@{description = $metadataDescription }
        }

        foreach ($psObjectProperty in $this.currentConfig.parameters.psobject.Properties) {
            if (($psObjectProperty.Name -ieq $parameterName)) {
                $psObjectProperty.Value = $parameterObject
                $this.WriteLog("exit:UpdateParametersSectionMetadataDescription:parameterObject value added to existing parameter:$($this.CreateJson($parameterObject))")
                return
            }
        }

        $this.WriteLog("exit:UpdateParametersSectionMetadataDescription:new parameter name:$parameterName added $($this.CreateJson($parameterObject))")
    }

    [void] VerifyConfig( [string]$templateParameterFile) {
        <#
        .SYNOPSIS
            verifies current configuration $this.currentConfig using test-resourcegroupdeployment
            outputs: null
        .OUTPUTS
            [null]
        #>
        $this.WriteLog("enter:VerifyConfig:templateparameterFile:$templateParameterFile")
        $json = '.\VerifyConfig.json'
        $this.CreateJson($this.currentConfig) | out-file -FilePath $json -Force

        $this.WriteLog("Test-AzResourceGroupDeployment -ResourceGroupName $($this.resourceGroupName) `
            -Mode Incremental `
            -Templatefile $json `
            -TemplateParameterFile $templateParameterFile `
            -Verbose
        " , [consolecolor]::Green)

        $error.Clear()
        $result = Test-AzResourceGroupDeployment -ResourceGroupName $this.resourceGroupName `
            -Mode Incremental `
            -TemplateFile $json `
            -TemplateParameterFile $templateParameterFile `
            -Verbose

        if ($error -or $result) {
            $this.WriteError("exit:VerifyConfig:error:$($this.CreateJson($result)) `r`n$($error | out-string)")
        }
        else {
            $this.WriteLog("exit:VerifyConfig:success", [consolecolor]::Green)
        }

        remove-item $json
        $error.Clear()
    }

    static [void]WriteErrorStatic([object]$data) {
        if ([SFTemplate]::instance) {
            [SFTemplate]::instance.WriteError($data)
        }
    }

    [void] WriteError([object]$data) {
        $this.WriteLog($data, $true, $false, $false, [consolecolor]::Gray)
    }

    [void] WriteWarning([object]$data) {
        $this.WriteLog($data, $false, $true, $false, [consolecolor]::Gray)
    }

    [void] WriteVerbose([object]$data) {
        $this.WriteLog($data, $false, $false, $true, [consolecolor]::Gray)
    }

    [void] WriteLog([object]$data) {
        $this.WriteLog($data, $null, $null, $null, [consolecolor]::Gray)
    }

    [void] WriteLog([object]$data, [ConsoleColor]$foregroundcolor = [ConsoleColor]::Gray) {
        $this.WriteLog($data, $null, $false, $false, $foregroundcolor)
    }

    # [void] WriteLog([object]$data, [switch]$isError, [switch]$isWarning) {
    #     $this.WriteLog($data, $null, $isError, $isWarning, $false)
    # }

    [void] WriteLog([object]$data, [switch]$isError, [switch]$isWarning, [switch]$verbose, [ConsoleColor]$foregroundcolor = [ConsoleColor]::Gray) {
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
                    $this.WriteWarning((@($job.Warning.ReadAll()) -join "`r`n"))
                    [void]$stringData.appendline(@($job.Warning.ReadAll()) -join "`r`n")
                    [void]$stringData.appendline(($job | format-list * | out-string))
                    $this.resourceWarnings++
                }
                if ($job.Error) {
                    $this.WriteError((@($job.Error.ReadAll()) -join "`r`n"))
                    [void]$stringData.appendline(@($job.Error.ReadAll()) -join "`r`n")
                    [void]$stringData.appendline(($job | format-list * | out-string))
                    $this.resourceErrors++
                }
                if ($stringData.tostring().Trim().Length -lt 1) {
                    return
                }
            }
        }
        else {
            if ($data.startswith('enter:')) {
                $this.functionDepth++
            }
            elseif ($data.startswith('exit:')) {
                $this.functionDepth--

                if ($this.functionDepth -lt 0) {
                    $this.WriteWarning("function depth enter / exit traces not equal: $data")
                    $this.functionDepth = 0
                }
            }

            #write-verbose "$($this.functionDepth) $data"
            $stringData = ("$((get-date).tostring('HH:mm:ss.fff')):$([string]::empty.PadLeft($this.functionDepth,'|'))$verboseTag$($data | format-list * | out-string)").trim()
        }

        if ($isError) {
            write-error $stringData
            [void]$this.errors.add($stringData)
        }
        elseif ($isWarning) {
            Write-Warning $stringData
            [void]$this.warnings.add($stringData)
        }
        elseif ($verbose) {
            write-verbose $stringData
        }
        else {
            write-host $stringData -ForegroundColor $foregroundcolor
        }

        if ($this.logFile) {
            out-file -Append -inputobject $stringData.ToString() -filepath $this.logFile
        }
    }
}

$global:addPrimaryNodeTypeReadme = @"
steps in this readme are to add a new primary nodetype to existing cluster.
typical use case scenarios are if OS is being upgraded or hardware sku is modified.

required: steps to add new node type:
1. open template.addprimarynodetype.parameters.json for modification
2. set new domainNameLabel value 'publicIPAddresses_x_domainNameLabel'
3. set new public ip address name value 'publicIPAddresses_x_name'
4. set new fqdn value 'publicIPAddresses_x_fqdn'
5. set node admin password value 'virtualMachineScaleSets_x_adminPassword'
6. set new nodetype name value 'virtualMachineScaleSets_x_name'
7. set new loadbalancer name value 'loadBalancers_x_x_name'

optional: steps:
1. open template.addprimarynodetype.parameters.json for modification
2. optionally set new nodetype sku value 'virtualMachineScaleSets_x_hardwareSku'
3. optionally set new nodetype OS value 'virtualMachineScaleSets_x_osSku'

required: to update deployment with new primary node type:
1. test: Test-AzResourceGroupDeployment -Verbose -ResourceGroupName <resource group name> -Mode Incremental -TemplateFile .\template.addprimarynodetype.json -TemplateParameterFile .\template.addprimarynodetype.parameters.json
2. deploy: New-AzResourceGroupDeployment -ResourceGroupName <resource group name> -DeploymentDebugLogLevel All -Mode Incremental -TemplateFile .\template.addprimarynodetype.json -TemplateParameterFile .\template.addprimarynodetype.parameters.json

required: after successful template update, change *old* primary nodetype 'isPrimary' to 'false':
1. export cluster again: .\azure-az-export-arm-template.ps1 -resourceGroupName <resource group name> -templatePath c:\temp
2. open template.current.parameters.json for modification
3. set *old* isPrimary value 'virtualMachineScaleSets_nt0_isPrimary' to 'false'
4. set node admin password value 'virtualMachineScaleSets_x_adminPassword'
5. test: Test-AzResourceGroupDeployment -Verbose -ResourceGroupName <resource group name> -Mode Incremental -TemplateFile .\template.current.json -TemplateParameterFile .\template.current.parameters.json
6. deploy: New-AzResourceGroupDeployment -ResourceGroupName <resource group name> -DeploymentDebugLogLevel All -Mode Incremental -TemplateFile .\template.current.json -TemplateParameterFile .\template.current.parameters.json

optional: after successful update *and* migration of system and app services to new nodetype, perform the following:
1. set new nodetype domainNameLabel value 'publicIPAddresses_x_domainNameLabel' to old primary nodetype domainNameLabel
2. set new nodetype fqdn value 'publicIPAddresses_x_fqdn' to old primary nodetype fqdn
3. test: Test-AzResourceGroupDeployment -Verbose -ResourceGroupName <resource group name> -Mode Incremental -TemplateFile .\template.current.json -TemplateParameterFile .\template.current.parameters.json
4. deploy: New-AzResourceGroupDeployment -ResourceGroupName <resource group name> -DeploymentDebugLogLevel All -Mode Incremental -TemplateFile .\template.current.json -TemplateParameterFile .\template.current.parameters.json

optional: after successful update, remove *old* primary nodetype in template.json if no longer being used by removing nodetypes[nodetype] from Microsoft.ServiceFabric/clusters resource
1. test: Test-AzResourceGroupDeployment -Verbose -ResourceGroupName <resource group name> -Mode Incremental -TemplateFile .\template.current.json -TemplateParameterFile .\template.current.parameters.json
2. deploy: New-AzResourceGroupDeployment -ResourceGroupName <resource group name> -DeploymentDebugLogLevel All -Mode Incremental -TemplateFile .\template.current.json -TemplateParameterFile .\template.current.parameters.json
3. after nodetype has been removed from cluster resource. the vmss, ip, and loadbalancer resources that are no longer used can be removed from portal or with powershell cmdlet 'remove-azresource'.

addnodetype modifications:
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
"@

$global:addSecondaryNodeTypeReadme = @"
steps in this readme are to add a new secondary nodetype to existing cluster.
typical use case scenarios are if OS is being upgraded or hardware sku is modified or additional capacity is needed.

required: steps to add new node type:
1. open template.addsecondarynodetype.parameters.json for modification
2. set new domainNameLabel value 'publicIPAddresses_x_domainNameLabel'
3. set new public ip address name value 'publicIPAddresses_x_name'
4. set new fqdn value 'publicIPAddresses_x_fqdn'
5. set node admin password value 'virtualMachineScaleSets_x_adminPassword'
6. set new nodetype name value 'virtualMachineScaleSets_x_name'
7. set new loadbalancer name value 'loadBalancers_x_x_name'

optional: steps:
1. open template.addsecondarynodetype.parameters.json for modification
2. optionally set new nodetype sku value 'virtualMachineScaleSets_x_hardwareSku'
3. optionally set new nodetype OS value 'virtualMachineScaleSets_x_osSku'

required: to update deployment with new secondary node type:
1. test: Test-AzResourceGroupDeployment -Verbose -ResourceGroupName <resource group name> -Mode Incremental -TemplateFile .\template.addsecondarynodetype.json -TemplateParameterFile .\template.addsecondarynodetype.parameters.json
2. deploy: New-AzResourceGroupDeployment -ResourceGroupName <resource group name> -DeploymentDebugLogLevel All -Mode Incremental -TemplateFile .\template.addsecondarynodetype.json -TemplateParameterFile .\template.addsecondarynodetype.parameters.json

addnodetype modifications:
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
"@

$readme = $global:currentReadme = @"
steps in this readme are to modify settings of current cluster.
typical use case scenarios are changing isprimary for primary nodetype migrations

current modifications:
- additional parameters have been added
- extra / duplicate child resources removed from root
- dependsOn modified to remove conflicting / unneeded resources
- isPrimary is a parameter
- protectedSettings for vmss extensions cluster and diagnostic extensions are added and set to storage account settings
"@

$readme = $global:exportReadme = @"
export modifications: none
- this is raw export from ps cmdlet export-azresourcegroup -includecomments -includeparameterdefaults
- this template File will *not* be usable to recreate / create new cluster in this state
- use 'current' to modify existing cluster
- use 'redeploy' or 'new' to recreate / create cluster
"@

$readme = $global:newReadme = @"
new / add modifications:
- microsoft monitoring agent extension has been removed (provisions automatically on deployment)
- adminPassword required parameter added (needs to be set)
- if upgradeMode for cluster resource is set to 'Automatic', clusterCodeVersion is removed
- protectedSettings for vmss extensions cluster and diagnostic extensions are added and set to storage account settings
- dnsSettings for public Ip Address needs to be unique
- storageAccountNames required parameters (needs to be unique or will be generated)
- if adding new vmss, each vmss resource needs a cluster nodetype resource added
- if adding new vmss, only one nodetype should be isprimary unless upgrading primary nodetype
- if adding new vmss, verify isprimary nodetype durability matches durability in cluster resource
"@

$readme = $global:redeployReadme = @"
redeploy modifications:
- microsoft monitoring agent extension has been removed (provisions automatically on deployment)
- adminPassword required parameter added (needs to be set)
- if upgradeMode for cluster resource is set to 'Automatic', clusterCodeVersion is removed
- protectedSettings for vmss extensions cluster and diagnostic extensions are added and set to storage account settings
"@

$error.Clear()
[SFTemplate]$global:sftemplate = [SFTemplate]::new()
$global:sftemplate.Export();

$ErrorActionPreference = $currentErrorActionPreference
$VerbosePreference = $currentVerbosePreference
