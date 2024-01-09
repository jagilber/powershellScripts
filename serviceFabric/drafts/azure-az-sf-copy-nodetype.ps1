<#
.Synopsis
    provide powershell commands to copy a reference node type to an existing Azure Service Fabric cluster
    provide powershell commands to configure all existing applications to use PLB before adding new nodetype if not already done
    https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-resource-manager-cluster-description#node-properties-and-placement-constraints

.NOTE
    this script is a work in progress
    this script is not supported by Microsoft
    this script is not supported under any Microsoft standard support program or service
    the script is provided AS IS without warranty of any kind
    Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose
    the entire risk arising out of the use or performance of the sample scripts and documentation remains with you
    in no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages 

    version:
        231219 # add function find-nodeType to find vmss by nodetype name and cluster endpoint
            using get-azresource instead of get-azvmss to get vmss by name
        231122 # add set-value to set default values if null
        231121 # add fix for space in template path. require admin username and password for platform image
        231114 # convert-fromjson -ashashtable requires ps version 6+ (core)
    todo:
        private ip?

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/drafts/azure-az-sf-copy-nodetype.ps1" -outFile "$pwd/azure-az-sf-copy-nodetype.ps1";
    ./azure-az-sf-copy-nodetype.ps1 -resourceGroupName <resource group name> -clusterName <cluster name> -referenceNodeTypeName <nt1> -newNodeTypeName <nt2>
.PARAMETER resourceGroupName
    the resource group name of the service fabric cluster
.PARAMETER clusterName
    the name of the service fabric cluster
.PARAMETER newNodeTypeName
    the name of the new node type to add to the service fabric cluster
.PARAMETER referenceNodeTypeName
    the name of the existing node type to use as a reference for the new node type
.PARAMETER isPrimaryNodeType
    whether the new node type is a primary node type
.PARAMETER vmImagePublisher
    the publisher of the vm image to use for the new node type
.PARAMETER vmImageOffer
    the offer of the vm image to use for the new node type
.PARAMETER vmImageSku
    the sku of the vm image to use for the new node type
.PARAMETER vmImageVersion
    the version of the vm image to use for the new node type
.PARAMETER vmInstanceCount
    the number of vm instances to use for the new node type
.PARAMETER vmSku
    the sku of the vm to use for the new node type
.PARAMETER durabilityLevel
    the durability level of the new node type
.PARAMETER adminUserName
    the admin username of the new node type
.PARAMETER adminPassword
    the admin password of the new node type
.PARAMETER newIpAddress
    the ip address of the new node type
.PARAMETER newIpAddressName
    the name of the new ip address
.PARAMETER newLoadBalancerName
    the name of the new load balancer
.PARAMETER template
    the path to the template file to use for deployment
.PARAMETER deploy
    whether to perform a deploy deployment. default creates template for modification and deployment
.PARAMETER customOsImage
    whether to use a custom os image for the new node type

.EXAMPLE
    ./azure-az-sf-copy-nodetype.ps1 -resourceGroupName <resource group name>
.EXAMPLE
    ./azure-az-sf-copy-nodetype.ps1 -resourceGroupName <resource group name> -deploy
.EXAMPLE
    ./azure-az-sf-copy-nodetype.ps1 -resourceGroupName <resource group name> -referenceNodeTypeName nt0 -newNodeTypeName nt1
.EXAMPLE
    ./azure-az-sf-copy-nodetype.ps1 -resourceGroupName <resource group name> -newNodeTypeName nt1 -referenceNodeTypeName nt0 -isPrimaryNodeType $false -vmImagePublisher MicrosoftWindowsServer -vmImageOffer WindowsServer -vmImageSku 2022-Datacenter -vmImageVersion latest -vmInstanceCount 5 -vmSku Standard_D2_v2 -durabilityLevel Silver -adminUserName cloudadmin -adminPassword P@ssw0rd!
#>

[CmdletBinding(DefaultParameterSetName = "Platform")]
param(
    [Parameter(ParameterSetName = 'Custom', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Platform', Mandatory = $true)]
    $resourceGroupName = '', #'sfcluster',

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $clusterName = $resourceGroupName,
    
    [Parameter(ParameterSetName = 'Custom', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Platform', Mandatory = $true)]
    $newNodeTypeName = 'nt1', #'nt1'
    
    [Parameter(ParameterSetName = 'Custom', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Platform', Mandatory = $true)]
    $referenceNodeTypeName = 'nt0', #'nt0',

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $isPrimaryNodeType = $false,
    
    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $vmImageSku = '2022-Datacenter',

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $vmImagePublisher, # = 'MicrosoftWindowsServer'
    
    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $vmImageOffer, # = 'WindowsServer'

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $vmImageVersion, # = 'latest'

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $vmInstanceCount, # = 3,
    
    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $vmSku, # = 'Standard_D2_v2',
    
    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    [ValidateSet('Bronze', 'Silver', 'Gold')]
    $durabilityLevel, #'Silver',
    
    #[Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform', Mandatory = $true)]
    $adminUserName, # = 'cloudadmin', # required for platform image
    
    #[Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform', Mandatory = $true)]
    $adminPassword, # = 'P@ssw0rd!', # required for platform image

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $newIpAddress = $null,
    
    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $newIpAddressName = 'pip-' + $newNodeTypeName,
    
    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $newLoadBalancerName = 'lb-' + $newNodeTypeName,
    
    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    $template = "'$psscriptroot\azure-az-sf-copy-nodetype.json'",
    
    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    [switch]$deploy,
        
    [Parameter(ParameterSetName = 'Custom')]
    [switch]$customOsImage,

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    [switch]$upgradeLoadBalancer,

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    [switch]$addNsg,

    [Parameter(ParameterSetName = 'Custom')]
    [Parameter(ParameterSetName = 'Platform')]
    [switch]$loadFunctionsOnly
)

Set-StrictMode -Version Latest
$PSModuleAutoLoadingPreference = 'auto'
$deployedServices = @{}
$regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
$nameFindPattern = '(?<initiator>/|"|_|,|\\){0}(?<terminator>/|$|"|_|,|\\)'
$nameReplacePattern = '${{initiator}}{0}${{terminator}}'
$vmssName = $referenceNodeTypeName
#$nameReplacePattern = "`${initiator}{0}`${terminator}"


$error.clear()

function main() {
    write-console "starting..."
    $error.Clear()
    try {
        # convert-fromjson requires ps version 6+ to handle comments, trailing commas and ashashtable
        if ($psversiontable.psversion.major -lt 6) {
            write-console "powershell version 6+ required. use pwsh.exe. https://aka.ms/pwsh" -foregroundColor 'Red'
            return
        }

        if (!(Get-Module az)) {
            Import-Module az
        }

        if (!(get-azresourceGroup)) {
            Connect-AzAccount
        }

        $location = (get-azresourceGroup -Name $resourceGroupName).Location

        $clusterEndpoint = get-sfClusterEndpoint $resourceGroupName $clusterName
        if (!$clusterEndpoint) {
            write-console "service fabric cluster $clusterName not found" -err
            return $error
        }

        $vmss = find-nodeType -resourceGroupName $resourceGroupName -clusterName $clusterName -nodeTypeName $newNodeTypeName
        if ($vmss) {
            write-console "new node type $newNodeTypeName already exists" -err
            return $error
        }

        $vmss = find-nodeType -resourceGroupName $resourceGroupName -clusterName $clusterName -nodeTypeName $referenceNodeTypeName
        if (!$vmss) {
            write-console "reference node type $referenceNodeTypeName does not exist" -err
            return $error
        }

        if ($vmssName -ine $vmss.Name) {
            write-console "reference node type $referenceNodeTypeName does not match vmss name $($vmss.Name)" -warn
            $vmssName = $vmss.Name
        }

        write-console "get-azpublicipaddress -ResourceGroupName $resourceGroupName -Name $newIpAddressName" -foregroundColor cyan
        if ((Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name $newIpAddressName -ErrorAction SilentlyContinue)) {
            write-console "ip address $newIpAddressName already exists" -err
            return $error
        }

        write-console "get-azloadbalancer -ResourceGroupName $resourceGroupName -Name $newLoadBalancerName" -foregroundColor cyan
        if ((Get-AzLoadBalancer -ResourceGroupName $resourceGroupName -Name $newLoadBalancerName -ErrorAction SilentlyContinue)) {
            write-console "load balancer $newLoadBalancerName already exists" -err
            return $error
        }

        $error.Clear()
        $referenceVmssCollection = new-vmssCollection
        $serviceFabricResource = get-sfResource -vmssCollection $referenceVmssCollection -resourceGroupName $resourceGroupName -clusterName $clusterName

        if (!$serviceFabricResource) {
            write-console "service fabric cluster $clusterName not found" -err
            return $error
        }
        write-console $serviceFabricResource

        #$referenceVmssCollection = get-vmssResources -resourceGroupName $resourceGroupName -vmssName $vmssName
        $referenceVmssCollection = get-vmssCollection -nodeTypeName $referenceNodeTypeName -vmssCollection $referenceVmssCollection
        write-console $referenceVmssCollection
        
        $templateJson = new-TemplateJson
        $newVmssCollection = copy-vmssCollection -vmssCollection $referenceVmssCollection -templateJson $templateJson
        $templateJson = upgrade-loadBalancer -vmssCollection $newVmssCollection -templateJson $templateJson

        $sfTemplateJson = new-TemplateJson
        $sfTemplateJson = update-serviceFabricResource -serviceFabricResource $serviceFabricResource -templateJson $sfTemplateJson

        # deployments
        $resourceGroup = $referenceVmssCollection.vmssConfig.ResourceGroupName
        $templateFile = $template.replace('.json', '-vmss.json')    
        $result = deploy-template -templateJson $templateJson -vmssCollection $newVmssCollection -resourceGroup $resourceGroup -templateFile $templateFile
        
        #todo: make sf resource update separate template and deployment due to upgrade process and potential different resource groups
        $resourceGroup = $referenceVmssCollection.sfResourceConfig.ResourceGroupName
        $templateFile = $template.replace('.json', '-sf.json')    
        $result = deploy-template -templateJson $sfTemplateJson -vmssCollection $newVmssCollection -resourceGroup $resourceGroup -templateFile $templateFile
        
        $global:vmssCollection = $newVmssCollection
        $global:templateJson = $templateJson
        write-console "deploy result: $result template also stored in `$global:templateJson" -foregroundColor 'Green'
    }
    catch [Exception] {
        $errorString = "exception: $($psitem.Exception)`r`nexception:`r`n$($psitem.Exception.Message)`r`n$($error | out-string)`r`n$($psitem.ScriptStackTrace)"
        write-console $errorString -foregroundColor 'Red'
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

function add-templateJsonResource($templateJson, $resource) {
    write-console "add-templateJsonResource:$resource"
    $templateJson = remove-templateJsonResource -templateJson $templateJson -resource $resource
    $templateJson.resources += $resource
    return $templateJson
}

function compare-sfExtensionSettings([object]$sfExtSettings, [string]$clusterEndpoint, [string]$nodeTypeRef) {
    write-console "compare-sfExtensionSettings:`$settings, $clusterEndpoint, $nodeTypeRef"
    if (!$sfExtSettings -or !$sfExtSettings.clusterEndpoint -or !$sfExtSettings.NodeTypeRef) {
        write-console "settings not found" -foregroundColor 'Yellow'
        return $null
    }

    $clusterEndpointRef = $sfExtSettings.clusterEndpoint
    if (!$clusterEndpointRef) {
        write-console "cluster endpoint not found" -foregroundColor 'Yellow'
        return $null
    }

    $nodeRef = $sfExtSettings.NodeTypeRef
    if (!$nodeRef) {
        write-console "node type ref not found in cluster settings" -foregroundColor 'Yellow'
        return $null
    }

    if ($clusterEndpointRef -ieq $clusterEndpoint -and $nodeTypeRef -ieq $nodeRef) {
        write-console "node type ref: $nodeTypeRef matches reference node type: $nodeRef" -foregroundColor 'Green'
        write-console "cluster endpoint ref: $clusterEndpointRef matches cluster endpoint: $clusterEndpoint" -foregroundColor 'Green'
        return $true
    }
    elseif ($nodeRef -ine $nodeTypeRef) {
        write-console "node type ref: $nodeTypeRef does not match reference node type: $nodeRef" -foregroundColor 'Yellow'
        return $false
    }
    else {
        write-console "cluster endpoint ref: $clusterEndpointRef does not match cluster endpoint: $clusterEndpoint" -foregroundColor 'Yellow'
        return $false
    }
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

function copy-vmssCollection($vmssCollection, $templateJson) {
    $vmss = $vmssCollection.vmssConfig
    $ip = $null
    $lb = $vmssCollection.loadBalancerConfig
    $sf = $vmssCollection.sfResourceConfig

    # set api versions get-azresource does not return version
    $vmss = add-property -resource $vmss `
        -name 'apiVersion' `
        -value (get-latestApiVersion -resourceType $vmss.Type)

    $lb = add-property -resource $lb `
        -name 'apiVersion' `
        -value (get-latestApiVersion -resourceType $lb.Type)

    # set credentials
    # custom images may hot have OsProfile
    if ($vmss.properties.VirtualMachineProfile.OsProfile) {
        if (!$adminUserName -or !$adminPassword) {
            write-console "-adminUserName and -adminPassword required" -err
        }
        $vmss.properties.VirtualMachineProfile.OsProfile.AdminUsername = $adminUserName
        $vmss = add-property -resource $vmss -name 'properties.VirtualMachineProfile.OsProfile.adminPassword' -value ''
        $vmss.properties.VirtualMachineProfile.OsProfile.AdminPassword = $adminPassword    
    }
    $vmss = add-property -resource $vmss -name 'dependsOn' -value @()
    $vmss.dependsOn += $lb.Id

    $extensions = [collections.arraylist]::new($vmss.properties.VirtualMachineProfile.ExtensionProfile.Extensions)

    $wadExtension = $extensions | where-object { $psitem.properties.publisher -ieq 'Microsoft.Azure.Diagnostics' }
    $wadStorageAccount = $wadExtension.properties.settings.StorageAccount
    $protectedSettings = get-wadProtectedSettings -storageAccountName $wadStorageAccount -templateJson $templateJson
    $wadExtension = add-property -resource $wadExtension -name 'properties.protectedSettings' -value $protectedSettings

    $sfExtension = $extensions | where-object { $psitem.properties.publisher -ieq 'Microsoft.Azure.ServiceFabric' }
    $sfStorageAccount = $sf.Properties.DiagnosticsStorageAccountConfig.StorageAccountName
    $protectedSettings = get-sfProtectedSettings -storageAccountName $sfStorageAccount -templateJson $templateJson
    $sfExtension = add-property -resource $sfExtension -name 'properties.protectedSettings' -value $protectedSettings

    # remove microsoft monitoring agent extension to prevent deployment error
    # reinstalls automatically
    $mmsExtension = $extensions | where-object { $psitem.properties.publisher -ieq 'Microsoft.EnterpriseCloud.Monitoring' }
    $extensions.Remove($mmsExtension)

    # set durabilty level
    $sfExtension.properties.settings.durabilityLevel = set-value $durabilityLevel $sfExtension.properties.settings.durabilityLevel

    # set storage profile information
    $vmss.properties.VirtualMachineProfile.StorageProfile.ImageReference.Publisher = set-value $vmImagePublisher $vmss.properties.VirtualMachineProfile.StorageProfile.ImageReference.Publisher
    $vmss.properties.VirtualMachineProfile.StorageProfile.ImageReference.Offer = set-value $vmImageOffer $vmss.properties.VirtualMachineProfile.StorageProfile.ImageReference.Offer
    $vmss.properties.VirtualMachineProfile.StorageProfile.ImageReference.Version = set-value $vmImageVersion $vmss.properties.VirtualMachineProfile.StorageProfile.ImageReference.Version

    # set extensions
    $vmss.properties.VirtualMachineProfile.ExtensionProfile.Extensions = $extensions

    # todo parameterize cluster id ?
    #$clusterEndpoint = $serviceFabricResource.Properties.ClusterEndpoint

    # set sku information
    $vmss.Sku.Capacity = set-value $vmInstanceCount $vmss.Sku.Capacity
    $vmss.Sku.Name = set-value $vmSku $vmss.Sku.Name

    $vmssName = $nameFindPattern -f $vmss.Name
    $newVmssName = $nameReplacePattern -f $newNodeTypeName
    $lbName = $nameFindPattern -f $lb.Name
    $newLBName = $nameReplacePattern -f $newLoadBalancerName

    # convert to json
    $vmssJson = convert-toJson $vmss
    #$ipJson = convert-toJson $ip
    $lbJson = convert-toJson $lb
  
    if ($vmssCollection.isPublicIp) {
        write-console "setting public ip address to $newIpAddress"
        $ip = $vmssCollection.ipConfig
        $ip = add-property -resource $ip `
            -name 'apiVersion' `
            -value (get-latestApiVersion -resourceType $ip.Type)

        $ipName = $nameFindPattern -f $ip.Name
        $newIpName = $nameReplacePattern -f $newIpAddressName
  
        $lb = add-property -resource $lb -name 'dependsOn' -value @()
        $lb.dependsOn += $ip.Id
        $lbJson = convert-toJson $lb

        $ipJson = convert-toJson $ip
        $ipJson = remove-nulls -json $ipJson
        $ipJson = remove-commonProperties -json $ipJson

        # set new resource names
        $ipJson = set-resourceName -referenceName $ipName -newName $newIpName -json $ipJson
        $ipJson = set-resourceName -referenceName $vmssName -newName $newVmssName -json $ipJson
        $ipJson = set-resourceName -referenceName $lbName -newName $newLBName -json $ipJson
        $ip = convert-fromJson $ipJson
  
        $lbJson = set-resourceName -referenceName $ipName -newName $newIpName -json $lbJson
        $vmssJson = set-resourceName -referenceName $ipName -newName $newIpName -json $vmssJson
  
        # set names
        $ip.Name = $newIpAddressName
        $ip.Properties.dnsSettings.fqdn = "$newNodeTypeName-$($ip.Properties.dnsSettings.fqdn)"
        $ip.Properties.dnsSettings.domainNameLabel = "$newNodeTypeName-$($ip.Properties.dnsSettings.domainNameLabel)"
  

        if ($vmssCollection.ipType -ieq 'Static') {
            $ip.Properties.ipAddress = $newIpAddress
        }
    }
    else {
        # remove ip address from new loadbalancer to avoid conflict
        write-console "setting private ip address to $newIpAddress"
        if ($vmssCollection.ipType -ieq 'Static' -and $newIpAddress) {
            $loadBalancer.FrontendIpConfigurations.properties.privateIpAddress = $newIpAddress
        }
    }

    # remove existing state
    $vmssJson = remove-nulls -json $vmssJson
    $lbJson = remove-nulls -json $lbJson

    #$ipJson = remove-commonProperties -json $ipJson
    $vmssJson = remove-commonProperties -json $vmssJson
    $lbJson = remove-commonProperties -json $lbJson

    # set new names
    $lbJson = set-resourceName -referenceName $lbName -newName $newLBName -json $lbJson
    $lbJson = set-resourceName -referenceName $vmssName -newName $newVmssName -json $lbJson
    $lb = convert-fromJson $lbJson

    $vmssJson = set-resourceName -referenceName $vmssName -newName $newVmssName -json $vmssJson
    $vmssJson = set-resourceName -referenceName $lbName -newName $newLBName -json $vmssJson
    $vmss = convert-fromJson $vmssJson
    # remove user assigned managed identity principal id and client id
    if ((get-psPropertyValue $vmss 'Identity') -and (get-psPropertyValue $vmss.Identity 'UserAssignedIdentities')) {
        write-console 'removing user assigned managed identity principal id and client id'
        $userIdentitiesJson = convert-toJson $vmss.Identity.UserAssignedIdentities
        $userIdentitiesJson = remove-property -name 'principalId' -json $userIdentitiesJson
        $userIdentitiesJson = remove-property -name 'clientId' -json $userIdentitiesJson
        $vmss.Identity.UserAssignedIdentities = convert-fromJson $userIdentitiesJson
    }

    # set names
    $vmss.Name = $newNodeTypeName

    $lb.Name = $newLoadBalancerName
    $lb.Properties.inboundNatRules = @()
    $lb.Properties.frontendIPConfigurations.properties.inboundNatRules = @()

    if ($vmssCollection.isPublicIp) {
        $templateJson = add-templateJsonResource -templateJson $templateJson -resource $ip
    }
  
    $templateJson = add-templateJsonResource -templateJson $templateJson -resource $lb
    $templateJson = add-templateJsonResource -templateJson $templateJson -resource $vmss
    write-console $vmssCollection  -foregroundColor 'Green'
    
    $newVmssCollection = $vmssCollection.clone()
    $newVmssCollection.vmssConfig = $vmss
    $newVmssCollection.loadBalancerConfig = $lb
    $newVmssCollection.sfResourceConfig = $sf
    $newVmssCollection.ipConfig = $ip
    
    return $newVmssCollection
}

function deploy-template($templateJson, $vmssCollection, $resourceGroup, $templateFile) {
    write-console "deploy-template:$templateFile"
    write-console $templateJson -foregroundColor 'Cyan'
    $tempDir = [io.path]::GetDirectoryName($templateFile)
    if (!(test-path $tempDir)) {
        write-console "creating temp directory $tempDir"
        new-item -Path $tempDir -ItemType Directory
    }

    save-template -templateJson $templateJson -templateFile $templateFile
    write-console "Test-AzResourceGroupDeployment -resourceGroupName $resourceGroup ``
        -TemplateFile $templateFile ``
        -Verbose" -foregroundColor 'Cyan'
    
    $result = test-azResourceGroupDeployment -templateFile $templateFile -resourceGroupName $resourceGroup -Verbose

    if ($result) {
        write-console "error: test-azResourceGroupDeployment failed:$($result | out-string)" -err
        return $result
    }
  
    $deploymentName = "$($MyInvocation.MyCommand.Name)-$(get-date -Format 'yyMMddHHmmss')"
    write-console "New-AzResourceGroupDeployment -Name $deploymentName ``
        -ResourceGroupName $resourceGroup ``
        -TemplateFile $templateFile ``
        -DeploymentDebugLogLevel All ``
        -Verbose" -foregroundColor 'Magenta'
  
    if ($deploy) {
        $error.clear()
        $result = new-azResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroup -TemplateFile $templateFile -Verbose -DeploymentDebugLogLevel All
        if ($result -or $error) {
            write-console "error: new-azResourceGroupDeployment failed:$($result | out-string)`r`n$($error | out-string)" -err
            return $result
        }
    }
    else {
        write-console "after verifying / modifying $templateFile`r`nrun the above 'new-azresourcegroupdeployment' command to deploy the template" -foregroundColor 'Yellow'
    }

    return $result
}

function find-nodeType([string]$resourceGroupName, [string]$clusterName, [string]$nodeTypeName) {
    write-console "find-nodeType:$resourceGroupName,$clusterName,$nodeTypeName"
    $serviceFabricResource = get-sfClusterResource -resourceGroupName $resourceGroupName -clusterName $clusterName
    if (!$serviceFabricResource) {
        write-console "service fabric cluster $clusterName not found" -err
        return $error
    }

    $nodeType = get-referenceNodeType $nodeTypeName $serviceFabricResource
    if (!$nodeType) {
        write-console "reference node type $nodeTypeName does not exist"
        #return $error
    }

    write-console $serviceFabricResource.ResourceId

    # get vmss for reference node type by name from resource group first
    $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
        -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
        -vmssResources @(get-vmssResources -resourceGroupName $resourceGroupName -vmssName $nodeTypeName)

    # get vmss for reference node type by name from all resource groups
    if (!$currentVmss) {
        $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
            -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
            -vmssResources @(get-vmssResources -resourceGroupName $resourceGroupName)
    }

    # get vmss for reference node type by name from all resource groups
    if (!$currentVmss) {
        $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
            -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
            -vmssResources @(get-vmssResources -vmssName $nodeTypeName)
    }

    # get vmss for reference node type by name from all resource groups
    if (!$currentVmss) {
        $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
            -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
            -vmssResources @(get-vmssResources)
    }

    if (!$currentVmss) {
        write-console "vmss for reference node type: $nodeTypeName not found" -foregroundColor 'Red'
        $global:referenceNodeType = $null
        return $null
    }

    write-console $currentVmss.ResourceId -foregroundColor 'Cyan'
    return $currentVmss
}

function get-latestApiVersion($resourceType) {
    $provider = get-azresourceProvider -ProviderNamespace $resourceType.Split('/')[0]
    $resource = $provider.ResourceTypes | where-object ResourceTypeName -eq $resourceType.Split('/')[1]
    $apiVersion = $resource.ApiVersions[0]

    write-console "latest api version for $resourceType is $apiVersion"

    return $apiVersion
}

function get-loadBalancer($vmss) {
    $nicConfig = $vmss.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties
    $ipConfig = $nicConfig.ipconfigurations.properties
    $natPools = @($ipConfig.loadbalancerinboundnatpools)
    $loadBalancerName = $natPools[0].Id.Split('/')[8]
    
    if (!$loadBalancerName) {
        write-console "load balancer name not found" -err
        return $error
    }
    else {
        write-console "load balancer: $loadBalancerName"
    }

    write-console "get-azloadbalancer -ResourceGroupName $resourceGroupName -Name $loadBalancerName" -foregroundColor cyan
    #$loadBalancer = Get-AzLoadBalancer -ResourceGroupName $resourceGroupName -Name $loadBalancerName -ExpandResource
    $loadBalancer = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType 'Microsoft.Network/loadBalancers' -Name $loadBalancerName -ExpandProperties
    if (!$loadBalancer) {
        write-console "load balancer $loadBalancerName not found" -err
        return $error
    }
    return $loadBalancer
}

function get-nsg($vmssCollection) {
    $nsgId = get-nsgId $vmssCollection
    if (!$nsgId) {
        write-console "nsg not found" -foregroundColor 'Yellow'
        return $null
    }

    $nsgName = $nsgId.Split('/')[8]
    write-console "get-aznetworksecuritygroup -ResourceGroupName $resourceGroupName -Name $nsgName" -foregroundColor cyan
    $nsg = get-azresource -ResourceGroupName $resourceGroupName -ResourceType 'Microsoft.Network/networkSecurityGroups' -Name $nsgName -ExpandProperties
    if (!$nsg) {
        write-console "network security group $nsgName not found" -err
        return $null
    }

    $vmssCollection.nsgConfig = $nsg
    write-console "returning: $($nsg.Name)"
    return $nsg
}

function get-nsgId($vmssCollection) {
    write-console "get-nsgId:$vmssCollection"
    $nsgId = $null
    $vmss = $vmssCollection.vmssConfig
    $nicConfig = $vmss.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties
    $ipConfig = $nicConfig.ipConfigurations.properties
    
    if ((get-psPropertyValue $ipConfig 'networkSecurityGroup.id')) {
        $nsgId = $ipConfig.networkSecurityGroup.id
    }

    # if (!$nsgId) {
    #     write-console "nsg not found in nic, checking load balancer front end"
    #     $lb = $vmssCollection.loadBalancerConfig
    #     $frontendIpConfigurations = @($lb.properties.frontendIPConfigurations)

    #     if ((get-psPropertyValue $frontendIpConfigurations[0].properties 'networkSecurityGroup.id')) {
    #         $nsgId = $frontendIpConfigurations[0].properties.networkSecurityGroup.id
    #     }
    # }

    if (!$nsgId) {
        write-console "nsg not found in load balancer, checking subnet"
        $subnet = get-subnet -vmssCollection $vmssCollection
        $nsgId = $subnet.properties.networkSecurityGroup.id
    }

    if ($nsgId) {
        write-console "network security group found: $nsgId" -foregroundColor 'Green'
    }
    else {
        write-console "network security group not found" -foregroundColor 'Yellow'
    }

    write-console "get-nsgId:$nsgId"
    return $nsgId
}

function get-psPropertyValue([object]$baseObject, [string]$property) {
    <#
    .SYNOPSIS
        enumerate powershell object property value
        [object]$baseObject powershell object
        outputs: object
    .OUTPUTS
        [object]
    #>
    write-console "get-psPropertyValue([object]$baseObject,[string]$property)"
    $retvals = @(get-psPropertyValues $baseObject $property)

    if ($retvals.Count -gt 1) {
        write-console "GetPSPropertyValue:error more than one item found. returning first value." -err
    }
    elseif ($retvals.Count -lt 1) {
        write-console "GetPSPropertyValue:no items found"
        $retvals = @($null)
    }

    write-console "get-psPropertyValue returning:$($retvals[0])"
    return $retvals[0]
}

function get-psPropertyValues([object]$baseObject, [string]$property) {
    <#
    .SYNOPSIS
        enumerate powershell object property values
        [object]$baseObject powershell object
        outputs: object[]
    .OUTPUTS
        [object[]]
    #>

    write-console "get-psPropertyValues([object]$baseObject,[string]$property)"
    $retval = [collections.arraylist]::new()
    $properties = @($property.Split('.'))
    $childProperties = $property

    if ($properties.Count -lt 1) {
        write-console "property string empty:$property" -warn
        return $retval.ToArray()
    }

    if (!$baseObject) {
        write-console "baseobject null" -warn
        return $retval.ToArray()
    }

    $propertyObject = $baseObject
    # enumerate property path based on type
    if ($propertyObject.GetType().isarray) {
        foreach ($propertyItem in $propertyObject) {
            $result = get-psPropertyValue $propertyItem $property
            if ($result) {
                [void]$retval.Add($result)
            }
        }
    }
    elseif ($propertyObject.GetType().Name -ieq 'OrderedHashtable') {
        # foreach ($propertyItem in $propertyObject.Keys) {
        #     $result = get-psPropertyValue $propertyItem $property
        #     if ($result) {
        #         [void]$retval.Add($result)
        #     }
        # }

        if ($propertyObject.ContainsKey($property)) {
            $result = $propertyObject.Keys.IndexOf($property)
            [void]$retval.Add($propertyObject.Keys[$result])
        }
    }
    else {
        #foreach ($subItem in $properties) {
        $subItem = $properties[0]
        $childProperties = $childProperties.trimStart($subItem).trimStart('.')
        write-console "checking property:$($subItem) childProperties:$childProperties"
        #write-console "checking property:$($subItem)"

        if ($propertyObject.GetType().isarray) {
            foreach ($propertyItem in $propertyObject) {
                $result = get-psPropertyValue $propertyItem $subItem
                if ($result) {
                    [void]$retval.Add($result)
                }        
            }
        }
        elseif ($propertyObject.psobject.Properties.match($subItem).count -gt 0) {
            foreach ($match in $propertyObject.psobject.Properties.match($subItem)) {
                write-console "found property:$($match.Name)"
                $propertyObject = $propertyObject.($match.Name)
                write-console "property value:$($propertyObject | convertto-json)"
                
                #[void]$retval.Add($propertyObject)
                if ($childProperties) {
                    $result = get-psPropertyValue $propertyObject $childProperties
                    if ($result) {
                        [void]$retval.Add($result)
                    }            
                }
                else {
                    [void]$retval.Add($propertyObject)
                }
            }
        }
        else {
            write-console "property not found:$($subItem)"
        }
        #}
    }

    write-console "get-psPropertyValues returning:$($retval)"
    return $retval.ToArray()
}

function get-publicIp($loadBalancer) {
    $frontendIpConfigurations = @($loadBalancer.properties.frontendIPConfigurations)
    $publicIpId = $frontendIpConfigurations[0].properties.publicIPAddress.id
    $publicIpName = $publicIpId.Split('/')[8]
    write-console "get-azpublicipaddress -ResourceGroupName $resourceGroupName -Name $publicIpName" -foregroundColor cyan
    $publicIp = get-azresource -ResourceGroupName $resourceGroupName -ResourceType 'Microsoft.Network/publicIPAddresses' -Name $publicIpName -ExpandProperties
    if (!$publicIp) {
        write-console "public ip $publicIpName not found" -err
        return $error
    }
    return $publicIp
}

function get-referenceNodeType([string]$nodeTypeName, $clusterResource) {
    write-console "get-referenceNodeType:$nodeTypeName,$clusterResource"

    $nodetypes = @($clusterResource.Properties.NodeTypes)
    $nodeType = $nodetypes | where-object name -ieq $nodeTypeName

    if (!$nodeType) {
        write-console "node type $nodeTypeName not found"
        return $null
    }
    write-console "returning: $($nodeType.Name)"
    return $nodeType
}

function get-referenceNodeTypeVMSS([string]$nodetypeName, [string]$clusterEndpoint, $vmssResources) {
    # nodetype name should match vmss name but not always the case
    # get-azvmss returning jobject 23-11-29 mitigation to use get-azresource
    #$referenceVmss = Get-AzVmss -ResourceGroupName $resourceGroupName -VMScaleSetName $nodeTypeName -ErrorAction SilentlyContinue
    $referenceVmss = $null

    if (!$vmssResources) {
        write-console "vmss for reference node type: $referenceNodeTypeName not found" -warn
        return $null
    }

    foreach ($vmss in $vmssResources) {
        $sfExtSettings = get-sfExtensionSettings $vmss
        $isNodeTypeRef = compare-sfExtensionSettings -sfExtSettings $sfExtSettings -clusterEndpoint $clusterEndpoint -nodeTypeRef $nodeTypeName
    
        if ($isNodeTypeRef) {
            write-console "found vmss: $($vmss.Name) for node type: $nodetypeName" -ForegroundColor Green
            $referenceVmss = $vmss
            break
        }
    }

    if (!$referenceVmss) {
        write-console "vmss for reference node type: $nodetypeName not found" -warn
        return $null
    }

    write-console "returning $($referenceVmss.ResourceId)"
    return $referenceVmss
}

function get-sfClusterEndpoint($resourceGroupName, $clusterName) {
    write-console "get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties"
    $serviceFabricResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties
    if (!$serviceFabricResource) {
        write-console "service fabric cluster $clusterName not found" -err
        return $error
    }

    $clusterEndpoint = $serviceFabricResource.Properties.ClusterEndpoint
    if (!$clusterEndpoint) {
        write-console "cluster endpoint not found" -err
        return $error
    }

    write-console "cluster endpoint: $clusterEndpoint"
    return $clusterEndpoint
}

function get-sfClusterResource([string]$resourceGroupName, [string]$clusterName) {
    write-console "get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties"
    $serviceFabricResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties
    if (!$serviceFabricResource) {
        write-console "service fabric cluster $clusterName not found" -warn
    }
    else {
        write-console "cluster endpoint: $($serviceFabricResource.Properties.ClusterEndpoint)"
    }

    return $serviceFabricResource
}

function get-sfExtensionSettings($vmss) {
    write-console "get-sfExtensionSettings $($vmss.Name)"
    #check extension
    $sfExtension = $vmss.properties.virtualMachineProfile.extensionProfile.extensions.properties `
    | where-object publisher -ieq 'Microsoft.Azure.ServiceFabric'
    
    if (!$sfExtension -or !(get-psPropertyValue $sfExtension 'settings')) {
        write-console "service fabric extension not found for node type: $($vmss.Name)" -warn
        return $null
    }
    else {
        write-console "service fabric extension found for node type: $($vmss.Name) $(convert-toJson $sfExtension.settings)"
    }
    return $sfExtension.settings
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

function get-sfResource($vmssCollection, $resourceGroupName, $clusterName) {
    write-console "get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties"
    $serviceFabricResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties
  
    if (!$serviceFabricResource) {
        write-console "service fabric cluster $clusterName not found" -err
        return $null
    }

    $vmssCollection.sfResourceConfig = $serviceFabricResource
    write-console $serviceFabricResource
    return $serviceFabricResource
}

function get-subnet($vmssCollection) {
    $subnetId = get-subnetId $vmssCollection
    if (!$subnetId) {
        write-console "subnet not found" -foregroundColor 'Yellow'
        return $null
    }

    write-console "get-azresource -ResourceId $subnetId -ExpandProperties"
    $subnet = get-azresource -ResourceId $subnetId -ExpandProperties
    if (!$subnet) {
        write-console "subnet $subnetId not found" -err
        return $null
    }

    $vmssCollection.subnetConfig = $subnet
    write-console "returning: $($subnet.Name)"
    return $subnet
}

function get-subnetId($vmssCollection) {
    write-console "get-subnetId:$vmssCollection"

    $vmss = $vmssCollection.vmssConfig
    $nicConfig = $vmss.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties
    $ipConfig = $nicConfig.ipConfigurations.properties
    
    $subnetId = $ipConfig.subnet.id
    if (!$subnetId) {
        write-console "subnet not found" -foregroundColor 'Yellow'
        return $null
    }

    write-console "subnet found: $subnetId" -foregroundColor 'Green'
    write-console "get-subnetId:$subnetId"
    return $subnetId
}

function get-vmssCollection($nodeTypeName, $vmssCollection) {
    write-console "using node type $nodeTypeName"
    $vmss = find-nodeType -resourceGroupName $resourceGroupName -clusterName $clusterName -nodeTypeName $nodeTypeName
    if (!$vmss) {
        write-console "node type $nodeTypeName not found" -err
        return $error
    }

    $vmssCollection.vmssConfig = $vmss

    $loadBalancer = get-loadBalancer -vmss $vmss
    if (!$loadBalancer) {
        write-console "load balancer not found" -err
        return $error
    }

    $vmssCollection.loadBalancerConfig = $loadBalancer

    # private ip check
    $publicIp = get-publicIp -loadBalancer $loadBalancer
    $vmssCollection.isPublicIp = if ($publicIp) { $true } else { $false }

    if ($vmssCollection.isPublicIp) {
        write-console "public ip found"
        $vmssCollection.ipAddress = $publicIp.properties.ipAddress
        $vmssCollection.ipType = $publicIp.properties.publicIPAllocationMethod
    }
    else {
        write-console "private ip found"
        $vmssCollection.ipAddress = $loadBalancer.properties.frontendIpConfigurations.PrivateIpAddress
        $vmssCollection.ipType = $loadBalancer.properties.frontendIpConfigurations.PrivateIpAllocationMethod
    }

    if (!$publicIp) {
        write-console "public ip not found" -foregroundColor 'Yellow'
    }
    else {
        $vmssCollection.ipConfig = $publicIp
    }

    write-console "current ip address is type:$($vmssCollection.ipType) public:$($vmssCollection.isPublicIp) address:$($vmssCollection.ipAddress)" -foregroundColor 'Cyan'
    write-console $vmssCollection

    return $vmssCollection
}

function get-vmssResources([string]$resourceGroupName, [string]$vmssName) {
    write-console "get-vmssResources -resourceGroupName $resourceGroupName -vmssName $vmssName"
    $paramValues = @{
        resourceType     = 'Microsoft.Compute/virtualMachineScaleSets'
        expandProperties = $true
    }

    if ($resourceGroupName) { [void]$paramValues.Add('resourceGroupName', $resourceGroupName) }
    if ($vmssName) { [void]$paramValues.Add('name', $vmssName) }

    write-console "get-azresource $($paramValues | convertto-json)" -foregroundColor cyan
    try {
        $vmssResources = @(get-azresource @paramValues -ErrorAction SilentlyContinue)
    }
    catch {
        write-console "exception:vmss $vmssName $($error | out-string)" -err
        return $null
    }

    if (!$vmssResources) {
        write-console "vmss $vmssName not found"
        return $null
    }
    elseif ($vmssResources.Count -gt 1) {
        write-console "returning: $($vmssResources.Count) vmss resource(s)"
    }
    else {
        write-console "returning: $(@($vmssResources)[0].ResourceId)"
    }
    return $vmssResources
}

function get-wadProtectedSettings($storageAccountName, $templateJson) {
    $storageAccountTemplate = "[variables('applicationDiagnosticsStorageAccountName')]"
    $storageAccountKey = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('applicationDiagnosticsStorageAccountName')),'2015-05-01-preview').key1]"
    $storageAccountEndPoint = "https://core.windows.net/"

    write-console "get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName"
    write-console "get-azStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName" -foregroundColor cyan
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

# function new-nsg($vmssCollection, $nsgName, $nsgRules = $null, $subnetId = $null) {
#     write-console "new-nsg:$vmssCollection,$nsgName,$nsgRules,$subnetId"
#     $nsg = $null

#     if (!$nsgName) {
#         write-console "nsg name not found" -err
#         return $nsg
#     }

#     $resourceGroup = $vmssCollection.vmssConfig.ResourceGroupName
#     $location = $vmssCollection.vmssConfig.Location
#     write-console "new-aznetworksecuritygroup -ResourceGroupName $resourceGroup -Name $nsgName -Location $location -Verbose"
#     $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup -Name $nsgName -Location $location -Verbose

#     if ($nsgRules) {
#         write-console "set-aznetworksecurityrule -NetworkSecurityGroup $nsg -SecurityRule $nsgRules -Verbose"
#         $nsg = Set-AzNetworkSecurityRule -NetworkSecurityGroup $nsg -SecurityRule $nsgRules -Verbose
#     }

#     if ($subnetId) {
#         write-console "set-aznetworksecuritygroup -NetworkSecurityGroup $nsg -SubnetId $subnetId -Verbose"
#         $nsg = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg -SubnetId $subnetId -Verbose
#     }
    
#     $vmssCollection.nsgConfig = $nsg
#     write-console "returning: $($nsg.Name)"
#     return $nsg
# }


# function new-genericResource(){

# }

function new-nsgResource($name, $location, $securityRules = $null) {
    $type = 'Microsoft.Network/networkSecurityGroups'
    $nsgResource = [ordered]@{
        Name       = $name
        Type       = $type
        ApiVersion = (get-latestApiVersion $type)
        Location   = $location
        Properties = [ordered]@{
            SecurityRules = @($securityRules)
        }
    }
    return $nsgResource
}

# function new-resource($resourceType, $resourceName, $resourceLocation, $resourceId = $null) {
#     write-console "new-resource:$resourceType,$resourceName,$resourceLocation,$resourceId"

#     $resource = [Microsoft.Azure.Management.ResourceManager.Models.Resource]::new($resourceId, $resourceName, $resourceType, $resourceLocation)
#     return $resource
# }

function new-securityRule($name, 
    [int]$priority,
    [ValidateSet('Inbound', 'Outbound')]
    $direction,
    [ValidateSet('Allow', 'Deny')]
    $access, 
    [ValidateSet('Tcp', 'Udp', '*')]
    $protocol, 
    $sourceAddressPrefix, 
    $sourcePortRange, 
    $destinationAddressPrefix, 
    $destinationPortRange) {
    write-console "new-securityRule:$name,$priority,$direction,$access,$protocol,$sourceAddressPrefix,$sourcePortRange,$destinationAddressPrefix,$destinationPortRange"
    $nsgRule = @{
        name       = $name
        type       = 'Microsoft.Network/networkSecurityGroups/securityRules'
        properties = [ordered]@{
            description              = $name
            priority                 = $priority
            direction                = $direction
            access                   = $access
            protocol                 = $protocol
            sourceAddressPrefix      = $sourceAddressPrefix
            sourcePortRange          = $sourcePortRange
            destinationAddressPrefix = $destinationAddressPrefix
            destinationPortRange     = $destinationPortRange
        }
    }

    write-console "returning: $(convert-toJson $nsgRule)"
    return $nsgRule
}

function new-securityRules() {
    $securityRules = @()

    # todo: needed?
    # $securityRules += new-securityRule -name 'AllowSFRPToServiceFabricGateway' `
    #     -priority 500 `
    #     -direction 'Inbound' `
    #     -access 'Allow' `
    #     -protocol 'Tcp' `
    #     -sourceAddressPrefix 'ServiceFabric' `
    #     -sourcePortRange '*' `
    #     -destinationAddressPrefix 'VirtualNetwork' `
    #     -destinationPortRange '19000, 19079, 19080'


    $securityRules += new-securityRule -name 'AllowServiceFabricGatewayPorts' `
        -priority 501 `
        -direction 'Inbound' `
        -access 'Allow' `
        -protocol 'Tcp' `
        -sourceAddressPrefix '*' `
        -sourcePortRange '*' `
        -destinationAddressPrefix 'VirtualNetwork' `
        -destinationPortRange '19000, 19079, 19080'

    # $securityRules += new-securityRule -name 'AllowServiceFabricGatewayReverseProxyPort' `
    #     -priority 502 `
    #     -direction 'Inbound' `
    #     -access 'Allow' `
    #     -protocol 'Tcp' `
    #     -sourceAddressPrefix '*' `
    #     -sourcePortRange '*' `
    #     -destinationAddressPrefix 'VirtualNetwork' `
    #     -destinationPortRange '19081'

    # todo: is this needed?
    $securityRules += new-securityRule -name 'AllowSFExtensionToDLC' `
        -priority 500 `
        -direction 'Outbound' `
        -access 'Allow' `
        -protocol '*' `
        -sourceAddressPrefix '*' `
        -sourcePortRange '*' `
        -destinationAddressPrefix 'AzureFrontDoor.FirstParty' `
        -destinationPortRange '*'
        
    write-console "returning: $($securityRules.Count) security rule(s)"
    write-console $securityRules -verbose
    return $securityRules
}

function new-TemplateJson() {
    $templateJson = [ordered]@{
        "`$schema"       = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
        "contentVersion" = "1.0.0.0"
        "parameters"     = @{}
        "variables"      = @{}
        "resources"      = @()
        "outputs"        = @{}
    }
    return $templateJson    
}

function new-vmssCollection(
    [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResource]$vmss = $null, 
    [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResource]$ip = $null, 
    [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResource]$loadBalancer = $null, 
    [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResource]$nsg = $null, 
    [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResource]$sfResource = $null) {
    $vmssCollection = @{
        #[Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet]
        vmssConfig         = $vmss
        #[Microsoft.Azure.Commands.Network.Models.PSPublicIPAddress]
        ipConfig           = $ip
        #[Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]
        loadBalancerConfig = $loadBalancer
        #[Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup]
        nsgConfig          = $nsg
        #$c = [Microsoft.Azure.Management.ServiceFabric.Models.Cluster]::new()
        #[Microsoft.Azure.Commands.ServiceFabric.Models.PSCluster]::($c)
        sfResourceConfig   = $sfResource
        isPublicIp         = $false
        ipAddress          = ''
        ipType             = ''
    }
    return $vmssCollection
}

function remove-commonProperties($json) {
    $commonProperties = @(
        'ResourceId',
        'SubscriptionId',
        'TagsTable',
        'ResourceGuid',
        'ResourceName',
        'ResourceType',
        'ResourceGroupName',
        'ProvisioningState',
        'CreatedTime',
        'ChangedTime',
        'Etag',
        'requireGuestProvisionSignal'
    )

    foreach ($property in $commonProperties) {
        $json = remove-property -name $property -json $json
    }
    return $json
}

function remove-nulls($json, $name = $null) {
    $findName = "`"(?<propertyName>.+?)`": null,"
    $replaceName = "//`"`${propertyName}`": null,"

    if (!$json) {
        write-console "error: json is null" -err
    }

    if ($name) {
        $findName = "`"$name`": null,"
        $replaceName = "//`"$name`": null,"
    }

    if ([regex]::isMatch($json, $findName, $regexOptions)) {
        write-console "replacing $findName with $replaceName in `$json" -foregroundColor 'Green'
        $json = [regex]::Replace($json, $findName, $replaceName, $regexOptions)
    }
    else {
        write-console "$findName not found" #-err
    }
    return $json
}

function remove-property($name, $json) {
    # todo implement same as add-property?
    $findName = "`"$name`":"
    $replaceName = "//`"$name`":"

    if (!$json) {
        write-console "error: json is null" -err
    }
    elseif (!$name) {
        write-console "error: name is null" -err
    }

    if ([regex]::isMatch($json, $findName, $regexOptions)) {
        write-console "replacing $findName with $replaceName in `$json" -foregroundColor 'Green'
        $json = [regex]::Replace($json, $findName, $replaceName, $regexOptions)
    }
    else {
        write-console "$findName not found" #-err
    }
    return $json
}

function remove-templateJsonResource($templateJson, $resource) {
    write-console "remove-templateJsonResource: $(convert-toJson $resource)"
    $templateResources = @($templateJson.resources | where-object { $psitem.Name -ieq $resource.Name -and $psitem.Type -ieq $resource.Type })
    if ($templateResources -and $templateResources.Count -eq 1) {
        $resources = [collections.arraylist]::new($templateJson.resources)
        [void]$resources.Remove($templateResources[0])
        $templateJson.resources = $resources
    }
    elseif ($templateResources -and $templateResources.Count -gt 1) {
        write-console "multiple resources found with name: $($resource.Name) and type: $($resource.Type)" -err
    }
    else {
        write-console "resource not found: $(convert-toJson $resource)"
    }
    return $templateJson
}

function save-template($templateJson, $templateFile) {
    $tempDir = [io.path]::GetDirectoryName($templateFile)
    if (!(test-path $tempDir)) {
        write-console "creating temp directory $tempDir"
        new-item -Path $tempDir -ItemType Directory
    }

    convert-toJson $templateJson | Out-File $templateFile -Force
    write-console "template saved to path: '$templateFile'" -foregroundColor 'Green'
}

function set-value($paramValue, $referenceValue) {
    write-console "comparing values '$paramValue' and '$referenceValue'"
    $returnValue = $paramValue
    if ($paramValue -eq $null) {
        $returnValue = $referenceValue
    }
    elseif ($paramValue -eq 0) {
        $returnValue = $referenceValue
    }

    write-console "returning value: '$returnValue'"
    return $returnValue
}

function set-resourceName($referenceName, $newName, $json) {
    if (!$json) {
        write-console "error: json is null" -err
    }
    elseif (!$referenceName) {
        write-console "error: referenceName is null" -err
    }
    elseif (!$newName) {
        write-console "newName is null" -err
    }

    if ([regex]::isMatch($json, $referenceName, $regexOptions)) {
        write-console "replacing $referenceName with $newName in `$json" -foregroundColor 'Green'
        write-console "[regex]::Replace($json, $referenceName, $newName, $regexOptions)"
        $json = [regex]::Replace($json, $referenceName, $newName, $regexOptions)
    }
    else {
        write-console "$referenceName not found" #-err
    }
    return $json
}

function update-publicIp($vmssCollection) {
    write-console "update-publicIp:$vmssCollection"
    $publicIp = $vmssCollection.ipConfig
    if (!$publicIp) {
        write-console "public ip not found" -err
        return $null
    }

    if (!(get-psPropertyValue $publicIp.Properties 'publicIPAllocationMethod')) {
        write-console "public ip not configured" -err
        return $null
    }
    $publicIpAllocationMethod = $publicIp.Properties.publicIPAllocationMethod
    if ($publicIpAllocationMethod -ine 'Static') {
        write-console "public ip allocation method is $publicIpAllocationMethod" -foregroundColor 'Yellow'
        $publicIp.Properties.publicIPAllocationMethod = 'Static'
    }

    $sku = $publicIp.Sku.Name
    if ($sku -ine 'Standard') {
        write-console "sku currently: $sku. updating public ip sku to Standard"
        $publicIp.Sku.Name = 'Standard'
    }
    else {
        write-console "public ip sku is 'Standard'"
    }

    return $true
}

function update-serviceFabricResource($serviceFabricResource, $templateJson) {

    if (!$serviceFabricResource) {
        write-console "service fabric cluster $clusterName not found" -err
        return $null #$error
    }

    $sfJson = convert-toJson $serviceFabricResource

    # remove properties not supported for deployment
    $sfJson = remove-nulls -json $sfJson
    $sfJson = remove-commonProperties -json $sfJson

    $serviceFabricResource = convert-fromJson $sfJson

    # todo parameterize cluster id ?
    #$clusterEndpoint = $serviceFabricResource.Properties.ClusterId

    # remove version if upgradeMode is Automatic
    if ($serviceFabricResource.Properties.upgradeMode -ieq 'Automatic') {
        write-console "removing cluster code version since upgrade mode is Automatic" -foregroundColor 'Yellow'
        $serviceFabricResource.Properties.clusterCodeVersion = $null
    }

    # check cluster provisioning state
    if ($serviceFabricResource.Properties.clusterState -ine 'Ready') {
        write-console "cluster provisioning state is $($serviceFabricResource.Properties.clusterState)"
        if ($deploy) {
            write-console "error: cluster must be in 'Ready' state to add node type" -err
            return $null #$serviceFabricResource
        }
        else {
            write-console "cluster must be in 'Ready' state to add node type" -foregroundColor 'Yellow'
        }
    }

    $nodeTypes = $serviceFabricResource.Properties.nodeTypes

    if (!$nodeTypes) {
        write-console "node types not found" -err
        return $null #$serviceFabricResource
    }

    $serviceFabricResource = add-property -resource $serviceFabricResource `
        -name 'apiVersion' `
        -value (get-latestApiVersion -resourceType $serviceFabricResource.Type)
    $referenceNodeTypeJson = convert-toJson ($nodeTypes | where-object name -ieq $referenceNodeTypeName)

    if (!$referenceNodeTypeJson) {
        write-console "node type $referenceNodeTypeName not found" -err
        return $null #$serviceFabricResource
    }

    $nodeType = $nodeTypes | where-object Name -ieq $newNodeTypeName
    if ($nodeType) {
        write-console "node type $referenceNodeTypeName already exists" -err
        return $null #$serviceFabricResource
    }

    $newList = [collections.arrayList]::new()
    [void]$newList.AddRange($nodeTypes)
    $nodeTypeTemplate = convert-fromJson $referenceNodeTypeJson
    $nodeTypeTemplate.isPrimary = $isPrimaryNodeType
    $nodeTypeTemplate.name = $newNodeTypeName
    $nodeTypeTemplate.vmInstanceCount = set-value $vmInstanceCount $nodeTypeTemplate.vmInstanceCount
    $nodeTypeTemplate.durabilityLevel = set-value $durabilityLevel $nodeTypeTemplate.durabilityLevel

    [void]$newList.Add($nodeTypeTemplate)
    $serviceFabricResource.Properties.nodeTypes = $newList.ToArray()

    write-console $serviceFabricResource
    $templateJson = add-templateJsonResource -templateJson $templateJson -resource $serviceFabricResource
    return $templateJson
}

function update-subnet($vmssCollection, $nsg) {
    write-console "update-subnet:$vmssCollection,$nsg"
    $subnet = get-subnet $vmssCollection
    if (!$subnet) {
        write-console "subnet not found" -err
        return $null
    }

    if (get-psPropertyValue $subnet.Properties 'networkSecurityGroup.id') {
        write-console "subnet already has network security group" -err
        return $null
    }

    $null = add-property -resource $subnet.Properties -name 'networkSecurityGroup' -value @{}
    #$subnetNsg = add-property -resource $subnet.Properties.networkSecurityGroup -name 'id' -value $nsg.Id
    $null = add-property -resource $subnet.Properties.networkSecurityGroup -name 'id' -value "[resourceId('Microsoft.Network/networkSecurityGroups', '$($nsg.Name)')]"
    
    $templateJson = convert-toJson $subnet
    $templateFile = $template.replace('.json', '-network.json')
    save-template -templateJson $templateJson -templateFile $templateFile
    return $templateJson -ne $null
}

function upgrade-loadBalancer($vmssCollection, $templateJson) {
    if (!$upgradeLoadBalancer) {
        write-console "upgradeLoadBalancer is false"
        return $templateJson
    }

    # verity load balancer sku is basic
    $loadBalancer = $vmssCollection.loadBalancerConfig
    if (!$loadBalancer) {
        write-console "load balancer not found" -err
        return $templateJson
    }

    #$loadBalancerJson = convert-toJson $loadBalancer

    $loadBalancerSku = $loadbalancer.Sku.Name
    if ($loadBalancerSku -ine 'Basic') {
        write-console "load balancer sku is $loadBalancerSku" -foregroundColor 'Yellow'
        return $templateJson
    }
    
    # save template with basic load balancer for backup
    $templateFile = $template.replace('.json', '-basic.json')
    save-template -templateJson $templateJson -templateFile $templateFile

    # todo: remove test
    $nsg = get-nsg -vmssCollection $vmssCollection
    #$nsg = $null
    # end test

    if (!$nsg) {
        write-console "nsg not found. creating new nsg"
        # $nsg = new-nsg -vmssCollection $vmssCollection `
        #     -nsgName $vmssCollection.sfResourceConfig.Name + '-nsg' `
        #     -nsgRules @(new-securityRules) `
        #     -subnetId (get-subnetId -vmssCollection $vmssCollection)
        $nsg = new-nsgResource -name ($vmssCollection.sfResourceConfig.Name + '-nsg') `
            -location $vmssCollection.vmssConfig.Location `
            -securityRules @(new-securityRules)

        $templateJson = add-templateJsonResource -templateJson $templateJson -resource $nsg
        $vmss = $vmssCollection.vmssConfig
        $nicConfig = $vmss.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties
        $ipConfig = $nicConfig.ipConfigurations.properties
        
        $ipConfig = add-property -resource $ipConfig -name 'networkSecurityGroup' -value @{}
        $ipConfig = add-property -resource $ipConfig.networkSecurityGroup -name 'id' -value "[resourceId('Microsoft.Network/networkSecurityGroups', '$($nsg.Name)')]"

        $templateJson = add-templateJsonResource -templateJson $templateJson -resource $vmss

        # add nsg to subnet
        if (!(update-subnet -vmssCollection $vmssCollection -nsg $nsg)) {
            write-console "error: failed to update subnet" -err
            return $templateJson
        }
    }

    # set public ip address to standard
    # set public ip address to static
    if (!(update-publicIp -vmssCollection $vmssCollection)) {
        write-console "error: failed to update public ip" -err
        return $templateJson
    }

    # set load balancer sku to standard
    # set disableOutboundSnat to true
    $loadBalancer.Sku.Name = 'Standard'
    $null = add-property -resource $loadBalancer.Properties -name 'disableOutboundSnat' -value $true
    $loadBalancer.Properties.disableOutboundSnat = $true
    
    $templateJson = add-templateJsonResource -templateJson $templateJson -resource $vmssCollection.vmssConfig
    $templateJson = add-templateJsonResource -templateJson $templateJson -resource $vmssCollection.loadBalancerConfig
    return $templateJson
}

function write-console($message, $foregroundColor = 'White', [switch]$verbose, [switch]$err, [switch]$warn) {
    if (!$message) { return }
    if ($message.gettype().name -ine 'string') {
        $message = $message | convertto-json -Depth 10
    }

    $message = "$(get-date -format 'yyyy-MM-ddTHH:mm:ss.fff')::$message"

    if ($verbose) {
        write-verbose($message)
    }
    else {
        write-host($message) -ForegroundColor $foregroundColor
    }

    if ($warn) {
        write-warning($message)
    }
    elseif ($err) {
        write-error($message)
        throw
    }
}

if (!$loadFunctionsOnly) {
    main
}
else {    
    if (!($MyInvocation.InvocationName -ieq '.')) {
        $scriptName = $MyInvocation.InvocationName
        write-console "to load functions from this script file, dot source the script file:. $scriptName"
    }
    else {
        write-console "loading script functions: $($MyInvocation.InvocationName)"
        write-console ((get-item function:) | Where-Object { $psitem.version -eq $null -and $psitem.module -eq $null } | out-string)
    }
}

