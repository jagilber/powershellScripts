$jsonData = @'
{
    "$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "clusterLocation": {
            "type": "string",
            "metadata": {
                "description": "Location of the Cluster"
            }
        },
        "clusterName": {
            "type": "string",
            "defaultValue": "Cluster",
            "metadata": {
                "description": "Name of your cluster - Between 3 and 23 characters. Letters and numbers only"
            }
        },
        "nt0applicationStartPort": {
            "type": "int",
            "defaultValue": 20000
        },
        "nt0applicationEndPort": {
            "type": "int",
            "defaultValue": 30000
        },
        "nt0ephemeralStartPort": {
            "type": "int",
            "defaultValue": 49152
        },
        "nt0ephemeralEndPort": {
            "type": "int",
            "defaultValue": 65534
        },
        "nt0fabricTcpGatewayPort": {
            "type": "int",
            "defaultValue": 19000
        },
        "nt0fabricHttpGatewayPort": {
            "type": "int",
            "defaultValue": 19080
        },
        "subnet0Name": {
            "type": "string",
            "defaultValue": "Subnet-0"
        },
        "subnet0Prefix": {
            "type": "string",
            "defaultValue": "10.0.0.0/24"
        },
        "computeLocation": {
            "type": "string"
        },
        "publicIPAddressName": {
            "type": "string",
            "defaultValue": "PublicIP-VM"
        },
        "publicIPAddressType": {
            "type": "string",
            "allowedValues": [
                "Dynamic"
            ],
            "defaultValue": "Dynamic"
        },
        "vmStorageAccountContainerName": {
            "type": "string",
            "defaultValue": "vhds"
        },
        "adminUserName": {
            "type": "string",
            "defaultValue": "testadm",
            "metadata": {
                "description": "Remote desktop user Id"
            }
        },
        "adminPassword": {
            "type": "securestring",
            "metadata": {
                "description": "Remote desktop user password. Must be a strong password"
            }
        },
        "virtualNetworkName": {
            "type": "string",
            "defaultValue": "VNet"
        },
        "addressPrefix": {
            "type": "string",
            "defaultValue": "10.0.0.0/16"
        },
        "dnsName": {
            "type": "string"
        },
        "nicName": {
            "type": "string",
            "defaultValue": "NIC"
        },
        "lbName": {
            "type": "string",
            "defaultValue": "LoadBalancer"
        },
        "lbIPName": {
            "type": "string",
            "defaultValue": "PublicIP-LB-FE"
        },
        "overProvision": {
            "type": "string",
            "defaultValue": "false"
        },
        "vmImagePublisher": {
            "type": "string",
            "defaultValue": "MicrosoftWindowsServer"
        },
        "vmImageOffer": {
            "type": "string",
            "defaultValue": "WindowsServer"
        },
        "vmImageSku": {
            "type": "string",
            "defaultValue": "2012-R2-Datacenter"
        },
        "vmImageVersion": {
            "type": "string",
            "defaultValue": "latest"
        },
        "clusterProtectionLevel": {
            "type": "string",
            "allowedValues": [
                "None",
                "Sign",
                "EncryptAndSign"
            ],
            "defaultValue": "EncryptAndSign",
            "metadata": {
                "description": "Protection level.Three values are allowed - EncryptAndSign, Sign, None. It is best to keep the default of EncryptAndSign, unless you have a need not to"
            }
        },
        "certificateStoreValue": {
            "type": "string",
            "allowedValues": [
                "My"
            ],
            "defaultValue": "My",
            "metadata": {
                "description": "The store name where the cert will be deployed in the virtual machine"
            }
        },
        "certificateThumbprint": {
            "type": "string",
            "metadata": {
                "description": "Certificate Thumbprint"
            }
        },
        "sourceVaultValue": {
            "type": "string",
            "metadata": {
                "description": "Resource Id of the key vault, is should be in the format of /subscriptions/<Sub ID>/resourceGroups/<Resource group name>/providers/Microsoft.KeyVault/vaults/<vault name>"
            }
        },
        "certificateUrlValue": {
            "type": "string",
            "metadata": {
                "description": "Refers to the location URL in your key vault where the certificate was uploaded, it is should be in the format of https://<name of the vault>.vault.azure.net:443/secrets/<exact location>"
            }
        },
        "storageAccountType": {
            "type": "string",
            "allowedValues": [
                "Standard_LRS",
                "Standard_GRS"
            ],
            "defaultValue": "Standard_LRS",
            "metadata": {
                "description": "Replication option for the VM image storage account"
            }
        },
        "supportLogStorageAccountType": {
            "type": "string",
            "allowedValues": [
                "Standard_LRS",
                "Standard_GRS"
            ],
            "defaultValue": "Standard_LRS",
            "metadata": {
                "description": "Replication option for the support log storage account"
            }
        },
        "supportLogStorageAccountName": {
            "type": "string",
            "defaultValue": "[toLower( concat('sflogs', uniqueString(resourceGroup().id),'2'))]",
            "metadata": {
                "description": "Name for the storage account that contains support logs from the cluster"
            }
        },
        "applicationDiagnosticsStorageAccountType": {
            "type": "string",
            "allowedValues": [
                "Standard_LRS",
                "Standard_GRS"
            ],
            "defaultValue": "Standard_LRS",
            "metadata": {
                "description": "Replication option for the application diagnostics storage account"
            }
        },
        "applicationDiagnosticsStorageAccountName": {
            "type": "string",
            "defaultValue": "[toLower(concat(uniqueString(resourceGroup().id), '3' ))]",
            "metadata": {
                "description": "Name for the storage account that contains application diagnostics data from the cluster"
            }
        },
        "nt0InstanceCount": {
            "type": "int",
            "defaultValue": 1,
            "metadata": {
                "description": "Instance count for node type"
            }
        },
        "vmNodeType0Name": {
            "type": "string",
            "defaultValue": "nt0",
            "maxLength": 9
        },
        "vmNodeType0Size": {
            "type": "string",
            "defaultValue": "Standard_D1_v2"
        }
    },
    "variables": {
        "vmssApiVersion": "2017-03-30",
        "lbApiVersion": "2015-06-15",
        "vNetApiVersion": "2015-06-15",
        "storageApiVersion": "2016-01-01",
        "publicIPApiVersion": "2015-06-15",
        "vnetID": "[resourceId('Microsoft.Network/virtualNetworks',parameters('virtualNetworkName'))]",
        "subnet0Ref": "[concat(variables('vnetID'),'/subnets/',parameters('subnet0Name'))]",
        "lbID0": "[resourceId('Microsoft.Network/loadBalancers', concat('LB','-', parameters('clusterName'),'-',parameters('vmNodeType0Name')))]",
        "lbIPConfig0": "[concat(variables('lbID0'),'/frontendIPConfigurations/LoadBalancerIPConfig')]",
        "lbPoolID0": "[concat(variables('lbID0'),'/backendAddressPools/LoadBalancerBEAddressPool')]",
        "lbProbeID0": "[concat(variables('lbID0'),'/probes/FabricGatewayProbe')]",
        "lbHttpProbeID0": "[concat(variables('lbID0'),'/probes/FabricHttpGatewayProbe')]",
        "lbNatPoolID0": "[concat(variables('lbID0'),'/inboundNatPools/LoadBalancerBEAddressNatPool')]",
        "vmStorageAccountName0": "[toLower(concat(uniqueString(resourceGroup().id), '1', '0' ))]"
    },
    "resources": [
        {
            "apiVersion": "[variables('storageApiVersion')]",
            "type": "Microsoft.Storage/storageAccounts",
            "name": "[parameters('supportLogStorageAccountName')]",
            "location": "[parameters('computeLocation')]",
            "dependsOn": [],
            "properties": {},
            "kind": "Storage",
            "sku": {
                "name": "[parameters('supportLogStorageAccountType')]"
            },
            "tags": {
                "resourceType": "Service Fabric",
                "clusterName": "[parameters('clusterName')]"
            }
        },
        {
            "apiVersion": "[variables('storageApiVersion')]",
            "type": "Microsoft.Storage/storageAccounts",
            "name": "[parameters('applicationDiagnosticsStorageAccountName')]",
            "location": "[parameters('computeLocation')]",
            "dependsOn": [],
            "properties": {},
            "kind": "Storage",
            "sku": {
                "name": "[parameters('applicationDiagnosticsStorageAccountType')]"
            },
            "tags": {
                "resourceType": "Service Fabric",
                "clusterName": "[parameters('clusterName')]"
            }
        },
        {
            "apiVersion": "[variables('vNetApiVersion')]",
            "type": "Microsoft.Network/virtualNetworks",
            "name": "[parameters('virtualNetworkName')]",
            "location": "[parameters('computeLocation')]",
            "dependsOn": [],
            "properties": {
                "addressSpace": {
                    "addressPrefixes": [
                        "[parameters('addressPrefix')]"
                    ]
                },
                "subnets": [
                    {
                        "name": "[parameters('subnet0Name')]",
                        "properties": {
                            "addressPrefix": "[parameters('subnet0Prefix')]"
                        }
                    }
                ]
            },
            "tags": {
                "resourceType": "Service Fabric",
                "clusterName": "[parameters('clusterName')]"
            }
        },
        {
            "apiVersion": "[variables('publicIPApiVersion')]",
            "type": "Microsoft.Network/publicIPAddresses",
            "name": "[concat(parameters('lbIPName'),'-','0')]",
            "location": "[parameters('computeLocation')]",
            "properties": {
                "dnsSettings": {
                    "domainNameLabel": "[parameters('dnsName')]"
                },
                "publicIPAllocationMethod": "Dynamic"
            },
            "tags": {
                "resourceType": "Service Fabric",
                "clusterName": "[parameters('clusterName')]"
            }
        },
        {
            "apiVersion": "[variables('lbApiVersion')]",
            "type": "Microsoft.Network/loadBalancers",
            "name": "[concat('LB','-', parameters('clusterName'),'-',parameters('vmNodeType0Name'))]",
            "location": "[parameters('computeLocation')]",
            "dependsOn": [
                "[concat('Microsoft.Network/publicIPAddresses/',concat(parameters('lbIPName'),'-','0'))]"
            ],
            "properties": {
                "frontendIPConfigurations": [
                    {
                        "name": "LoadBalancerIPConfig",
                        "properties": {
                            "publicIPAddress": {
                                "id": "[resourceId('Microsoft.Network/publicIPAddresses',concat(parameters('lbIPName'),'-','0'))]"
                            }
                        }
                    }
                ],
                "backendAddressPools": [
                    {
                        "name": "LoadBalancerBEAddressPool",
                        "properties": {}
                    }
                ],
                "loadBalancingRules": [
                    {
                        "name": "LBRule",
                        "properties": {
                            "backendAddressPool": {
                                "id": "[variables('lbPoolID0')]"
                            },
                            "backendPort": "[parameters('nt0fabricTcpGatewayPort')]",
                            "enableFloatingIP": "false",
                            "frontendIPConfiguration": {
                                "id": "[variables('lbIPConfig0')]"
                            },
                            "frontendPort": "[parameters('nt0fabricTcpGatewayPort')]",
                            "idleTimeoutInMinutes": "5",
                            "probe": {
                                "id": "[variables('lbProbeID0')]"
                            },
                            "protocol": "tcp"
                        }
                    },
                    {
                        "name": "LBHttpRule",
                        "properties": {
                            "backendAddressPool": {
                                "id": "[variables('lbPoolID0')]"
                            },
                            "backendPort": "[parameters('nt0fabricHttpGatewayPort')]",
                            "enableFloatingIP": "false",
                            "frontendIPConfiguration": {
                                "id": "[variables('lbIPConfig0')]"
                            },
                            "frontendPort": "[parameters('nt0fabricHttpGatewayPort')]",
                            "idleTimeoutInMinutes": "5",
                            "probe": {
                                "id": "[variables('lbHttpProbeID0')]"
                            },
                            "protocol": "tcp"
                        }
                    }
                ],
                "probes": [
                    {
                        "name": "FabricGatewayProbe",
                        "properties": {
                            "intervalInSeconds": 5,
                            "numberOfProbes": 2,
                            "port": "[parameters('nt0fabricTcpGatewayPort')]",
                            "protocol": "tcp"
                        }
                    },
                    {
                        "name": "FabricHttpGatewayProbe",
                        "properties": {
                            "intervalInSeconds": 5,
                            "numberOfProbes": 2,
                            "port": "[parameters('nt0fabricHttpGatewayPort')]",
                            "protocol": "tcp"
                        }
                    }
                ],
                "inboundNatPools": [
                    {
                        "name": "LoadBalancerBEAddressNatPool",
                        "properties": {
                            "backendPort": "3389",
                            "frontendIPConfiguration": {
                                "id": "[variables('lbIPConfig0')]"
                            },
                            "frontendPortRangeEnd": "4500",
                            "frontendPortRangeStart": "3389",
                            "protocol": "tcp"
                        }
                    }
                ]
            },
            "tags": {
                "resourceType": "Service Fabric",
                "clusterName": "[parameters('clusterName')]"
            }
        },
        {
            "apiVersion": "[variables('vmssApiVersion')]",
            "type": "Microsoft.Compute/virtualMachineScaleSets",
            "name": "[parameters('vmNodeType0Name')]",
            "location": "[parameters('computeLocation')]",
            "dependsOn": [
                "[concat('Microsoft.Network/virtualNetworks/', parameters('virtualNetworkName'))]",
                "[concat('Microsoft.Network/loadBalancers/', concat('LB','-', parameters('clusterName'),'-',parameters('vmNodeType0Name')))]",
                "[concat('Microsoft.Storage/storageAccounts/', parameters('supportLogStorageAccountName'))]",
                "[concat('Microsoft.Storage/storageAccounts/', parameters('applicationDiagnosticsStorageAccountName'))]"
            ],
            "properties": {
                "overprovision": "[parameters('overProvision')]",
                "upgradePolicy": {
                    "mode": "Automatic"
                },
                "virtualMachineProfile": {
                    "extensionProfile": {
                        "extensions": [
                            {
                                "name": "[concat(parameters('vmNodeType0Name'),'_ServiceFabricNode')]",
                                "properties": {
                                    "type": "ServiceFabricNode",
                                    "autoUpgradeMinorVersion": true,
                                    "protectedSettings": {
                                        "StorageAccountKey1": "[listKeys(resourceId('Microsoft.Storage/storageAccounts', parameters('supportLogStorageAccountName')),'2015-05-01-preview').key1]",
                                        "StorageAccountKey2": "[listKeys(resourceId('Microsoft.Storage/storageAccounts', parameters('supportLogStorageAccountName')),'2015-05-01-preview').key2]"
                                    },
                                    "publisher": "Microsoft.Azure.ServiceFabric",
                                    "settings": {
                                        "clusterEndpoint": "[reference(parameters('clusterName')).clusterEndpoint]",
                                        "nodeTypeRef": "[parameters('vmNodeType0Name')]",
                                        "dataPath": "D:\\\\SvcFab",
                                        "durabilityLevel": "Bronze",
                                        "enableParallelJobs": true,
                                        "nicPrefixOverride": "[parameters('subnet0Prefix')]",
                                        "certificate": {
                                            "thumbprint": "[parameters('certificateThumbprint')]",
                                            "x509StoreName": "[parameters('certificateStoreValue')]"
                                        }
                                    },
                                    "typeHandlerVersion": "1.0"
                                }
                            },
                            {
                                "name": "[concat('VMDiagnosticsVmExt','_vmNodeType0Name')]",
                                "properties": {
                                    "type": "IaaSDiagnostics",
                                    "autoUpgradeMinorVersion": true,
                                    "protectedSettings": {
                                        "storageAccountName": "[parameters('applicationDiagnosticsStorageAccountName')]",
                                        "storageAccountKey": "[listKeys(resourceId('Microsoft.Storage/storageAccounts', parameters('applicationDiagnosticsStorageAccountName')),'2015-05-01-preview').key1]",
                                        "storageAccountEndPoint": "https://core.windows.net/"
                                    },
                                    "publisher": "Microsoft.Azure.Diagnostics",
                                    "settings": {
                                        "WadCfg": {
                                            "DiagnosticMonitorConfiguration": {
                                                "overallQuotaInMB": "50000",
                                                "EtwProviders": {
                                                    "EtwEventSourceProviderConfiguration": [
                                                        {
                                                            "provider": "Microsoft-ServiceFabric-Actors",
                                                            "scheduledTransferKeywordFilter": "1",
                                                            "scheduledTransferPeriod": "PT5M",
                                                            "DefaultEvents": {
                                                                "eventDestination": "ServiceFabricReliableActorEventTable"
                                                            }
                                                        },
                                                        {
                                                            "provider": "Microsoft-ServiceFabric-Services",
                                                            "scheduledTransferPeriod": "PT5M",
                                                            "DefaultEvents": {
                                                                "eventDestination": "ServiceFabricReliableServiceEventTable"
                                                            }
                                                        }
                                                    ],
                                                    "EtwManifestProviderConfiguration": [
                                                        {
                                                            "provider": "cbd93bc2-71e5-4566-b3a7-595d8eeca6e8",
                                                            "scheduledTransferLogLevelFilter": "Information",
                                                            "scheduledTransferKeywordFilter": "4611686018427387904",
                                                            "scheduledTransferPeriod": "PT5M",
                                                            "DefaultEvents": {
                                                                "eventDestination": "ServiceFabricSystemEventTable"
                                                            }
                                                        }
                                                    ]
                                                }
                                            }
                                        },
                                        "StorageAccount": "[parameters('applicationDiagnosticsStorageAccountName')]"
                                    },
                                    "typeHandlerVersion": "1.5"
                                }
                            }
                        ]
                    },
                    "networkProfile": {
                        "networkInterfaceConfigurations": [
                            {
                                "name": "[concat(parameters('nicName'), '-0')]",
                                "properties": {
                                    "ipConfigurations": [
                                        {
                                            "name": "[concat(parameters('nicName'),'-',0)]",
                                            "properties": {
                                                "loadBalancerBackendAddressPools": [
                                                    {
                                                        "id": "[variables('lbPoolID0')]"
                                                    }
                                                ],
                                                "loadBalancerInboundNatPools": [
                                                    {
                                                        "id": "[variables('lbNatPoolID0')]"
                                                    }
                                                ],
                                                "subnet": {
                                                    "id": "[variables('subnet0Ref')]"
                                                }
                                            }
                                        }
                                    ],
                                    "primary": true
                                }
                            }
                        ]
                    },
                    "osProfile": {
                        "adminPassword": "[parameters('adminPassword')]",
                        "adminUsername": "[parameters('adminUsername')]",
                        "computernamePrefix": "[parameters('vmNodeType0Name')]",
                        "secrets": [
                            {
                                "sourceVault": {
                                    "id": "[parameters('sourceVaultValue')]"
                                },
                                "vaultCertificates": [
                                    {
                                        "certificateStore": "[parameters('certificateStoreValue')]",
                                        "certificateUrl": "[parameters('certificateUrlValue')]"
                                    }
                                ]
                            }
                        ]
                    },
                    "storageProfile": {
                        "imageReference": {
                            "publisher": "[parameters('vmImagePublisher')]",
                            "offer": "[parameters('vmImageOffer')]",
                            "sku": "[parameters('vmImageSku')]",
                            "version": "[parameters('vmImageVersion')]"
                        },
                        "osDisk": {
                            "caching": "ReadOnly",
                            "createOption": "FromImage",
                            "managedDisk": {
                                "storageAccountType": "[parameters('storageAccountType')]"
                            }
                        }
                    }
                }
            },
            "sku": {
                "name": "[parameters('vmNodeType0Size')]",
                "capacity": "[parameters('nt0InstanceCount')]",
                "tier": "Standard"
            },
            "tags": {
                "resourceType": "Service Fabric",
                "clusterName": "[parameters('clusterName')]"
            }
        },
        {
            "apiVersion": "2017-07-01-preview",
            "type": "Microsoft.ServiceFabric/clusters",
            "name": "[parameters('clusterName')]",
            "location": "[parameters('clusterLocation')]",
            "dependsOn": [
                "[concat('Microsoft.Storage/storageAccounts/', parameters('supportLogStorageAccountName'))]"
            ],
            "properties": {
                "addonFeatures": [],
                "certificate": {
                    "thumbprint": "[parameters('certificateThumbprint')]",
                    "x509StoreName": "[parameters('certificateStoreValue')]"
                },
                "clientCertificateCommonNames": [],
                "clientCertificateThumbprints": [],
                "clusterState": "Default",
                "diagnosticsStorageAccountConfig": {
                    "blobEndpoint": "[reference(concat('Microsoft.Storage/storageAccounts/', parameters('supportLogStorageAccountName')), variables('storageApiVersion')).primaryEndpoints.blob]",
                    "protectedAccountKeyName": "StorageAccountKey1",
                    "queueEndpoint": "[reference(concat('Microsoft.Storage/storageAccounts/', parameters('supportLogStorageAccountName')), variables('storageApiVersion')).primaryEndpoints.queue]",
                    "storageAccountName": "[parameters('supportLogStorageAccountName')]",
                    "tableEndpoint": "[reference(concat('Microsoft.Storage/storageAccounts/', parameters('supportLogStorageAccountName')), variables('storageApiVersion')).primaryEndpoints.table]"
                },
                "fabricSettings": [
                    {
                        "parameters": [
                            {
                                "name": "ClusterProtectionLevel",
                                "value": "[parameters('clusterProtectionLevel')]"
                            }
                        ],
                        "name": "Security"
                    }
                ],
                "managementEndpoint": "[concat('https://',reference(concat(parameters('lbIPName'),'-','0')).dnsSettings.fqdn,':',parameters('nt0fabricHttpGatewayPort'))]",
                "nodeTypes": [
                    {
                        "name": "[parameters('vmNodeType0Name')]",
                        "applicationPorts": {
                            "endPort": "[parameters('nt0applicationEndPort')]",
                            "startPort": "[parameters('nt0applicationStartPort')]"
                        },
                        "clientConnectionEndpointPort": "[parameters('nt0fabricTcpGatewayPort')]",
                        "durabilityLevel": "Bronze",
                        "ephemeralPorts": {
                            "endPort": "[parameters('nt0ephemeralEndPort')]",
                            "startPort": "[parameters('nt0ephemeralStartPort')]"
                        },
                        "httpGatewayEndpointPort": "[parameters('nt0fabricHttpGatewayPort')]",
                        "isPrimary": true,
                        "vmInstanceCount": "[parameters('nt0InstanceCount')]"
                    }
                ],
                "provisioningState": "Default",
                "reliabilityLevel": "None",
                "upgradeMode": "Automatic",
                "vmImage": "Windows"
            },
            "tags": {
                "resourceType": "Service Fabric",
                "clusterName": "[parameters('clusterName')]"
            }
        }
    ],
    "outputs": {
        "clusterProperties": {
            "value": "[reference(parameters('clusterName'))]",
            "type": "object"
        }
    }
}
'@

function member-exists($customObject, $name)
{
    if([regex]::Matches(($customObject | out-string),[regex]::Escape($name), [text.regularexpressions.regexoptions]::IgnoreCase).Count -gt 0)
    {
        Write-Warning "$Name already exists in customObject"
        return $false
    }
    else
    {
        return $true
    }

}

function add-newMember($customObject, $name, $value, [bool]$whatif, [bool]$isList)
{
    if((member-exists -customObject $customObject -name $name))
    {
        if(!$whatIf)
        {
            if($isList)
            {
                $customObject += $value
            }
            else
            {
                $customObject | add-member -name $name -value $value -MemberType NoteProperty
            }
        }

        return $customObject
    }
    else
    {
        Write-Warning "$Name already exists in customObject. skipping"
        return $false
    }

    
}

$jsonObject = ConvertFrom-Json $jsonData

# determine existing nodetype count
# todo verify name / count not in use
$currentNodeTypeCount = [regex]::Matches(($jsonObject.resources.type),"Microsoft.Compute/virtualMachineScaleSets").Count
write-host "currentnodetypecount $($currentNodeTypeCount)"
$newNodeTypeCount = $currentNodeTypeCount +1

$count = $newNodeTypeCount
$whatif = $true

while($true)
{
    # testing node type parameters
    $ret = $true 
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.parameters) -name "nt$($count)applicationStartPort" -value ([pscustomobject]@{type='int'; defaultValue=20000}) -whatif $whatif)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.parameters) -name "nt$($count)applicationEndPort" -Value ([pscustomobject]@{type='int'; defaultValue=30000}) -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.parameters) -name "nt$($count)ephemeralStartPort" -Value ([pscustomobject]@{type='int'; defaultValue=49152}) -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.parameters) -name "nt$($count)ephemeralEndPort" -Value ([pscustomobject]@{type='int'; defaultValue=65534}) -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.parameters) -name "nt$($count)fabricTcpGatewayPort" -Value ([pscustomobject]@{type='int'; defaultValue=19000}) -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.parameters) -name "nt$($count)fabricHttpGatewayPort" -Value ([pscustomobject]@{type='int'; defaultValue=19080}) -whatif $whatIf)
    
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.parameters) -name "subnet$($count)Name" -value ([pscustomobject]@{'type'='string'; 'defaultValue'="Subnet-$($count)"}) -whatif $whatIf)
    $ret = $ret -band [bool](member-exists -customObject ($jsonObject.parameters) -name "10.0.$($count).0/24")
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.parameters) -name "subnet$($count)Prefix" -value ([pscustomobject]@{'type'='string'; 'defaultValue'="10.0.$($count).0/24"}) -whatif $whatIf)

    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.parameters) -name "nt$($count)InstanceCount" -value ([pscustomobject]@{'type'='int'; 'defaultValue'=5}) -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.parameters) -name "vmNodeType$($count)Name" -value ([pscustomobject]@{'type'='string'; 'defaultValue'="nt$($count)"}) -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.parameters) -name "vmNodeType$($count)Size" -value ([pscustomobject]@{'type'='string'; 'defaultValue'="Standard_D1_v2"}) -whatif $whatIf)

    # testing node type variable
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.variables) -name "subnet$($count)Ref" -value "[concat(variables('vnetID'),'/subnets/',parameters('subnet$($count)Name'))]" -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.variables) -name "lbID$($count)" -value "[resourceId('Microsoft.Network/loadBalancers', concat('LB','-', parameters('clusterName'),'-',parameters('vmNodeType$($count)Name')))]" -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.variables) -name "lbIPConfig$($count)" -value "[concat(variables('lbID$($count)'),'/frontendIPConfigurations/LoadBalancerIPConfig')]" -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.variables) -name "lbPoolID$($count)" -value "[concat(variables('lbID$($count)'),'/backendAddressPools/LoadBalancerBEAddressPool')]" -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.variables) -name "lbProbeID$($count)" -value "[concat(variables('lbID$($count)'),'/probes/FabricGatewayProbe')]" -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.variables) -name "lbHttpProbeID$($count)" -value "[concat(variables('lbID$($count)'),'/probes/FabricHttpGatewayProbe')]" -whatif $whatIf)
    $ret = $ret -band [bool](add-newMember -customObject ($jsonObject.variables) -name "lbNatPoolID$($count)" -value "[concat(variables('lbID$($count)'),'/inboundNatPools/LoadBalancerBEAddressNatPool')]" -whatif $whatIf)
    #$ret = $ret -band [bool](add-newMember -customObject ($jsonObject.variables) -name "vmStorageAccountName$($count)" -value "[toLower(concat(uniqueString(resourceGroup().id), '1', '0' ))]" -whatif $whatIf)

    # testing node type resources
   
    $json = @'
    {
            "apiVersion": "[variables('publicIPApiVersion')]",
            "type": "Microsoft.Network/publicIPAddresses",
            "name": "[concat(parameters('lbIPName'),'-','$($count)')]",
            "location": "[parameters('computeLocation')]",
            "properties": {
                "dnsSettings": {
                    "domainNameLabel": "[parameters('dnsName')]"
                },
                "publicIPAllocationMethod": "Dynamic"
            },
            "tags": {
                "resourceType": "Service Fabric",
                "clusterName": "[parameters('clusterName')]"
            }
        }

'@
    $json = $json.Replace('$($count)',$count)
    $ret = $ret -band [bool]($jsonObject.resources = (add-newMember -customObject @($jsonObject.resources) -name "[concat(parameters('lbIPName'),'-','$($count)')]" -isList $true -whatif $whatIf -value (ConvertFrom-Json $json)))
    
    $json = @'
    {
            "apiVersion": "[variables('lbApiVersion')]",
            "type": "Microsoft.Network/loadBalancers",
            "name": "[concat('LB','-', parameters('clusterName'),'-',parameters('vmNodeType$($count)Name'))]",
            "location": "[parameters('computeLocation')]",
            "dependsOn": [
                "[concat('Microsoft.Network/publicIPAddresses/',concat(parameters('lbIPName'),'-','$($count)'))]"
            ],
            "properties": {
                "frontendIPConfigurations": [
                    {
                        "name": "LoadBalancerIPConfig",
                        "properties": {
                            "publicIPAddress": {
                                "id": "[resourceId('Microsoft.Network/publicIPAddresses',concat(parameters('lbIPName'),'-','$($count)'))]"
                            }
                        }
                    }
                ],
                "backendAddressPools": [
                    {
                        "name": "LoadBalancerBEAddressPool",
                        "properties": {}
                    }
                ],
                "loadBalancingRules": [
                    {
                        "name": "LBRule",
                        "properties": {
                            "backendAddressPool": {
                                "id": "[variables('lbPoolID$($count)')]"
                            },
                            "backendPort": "[parameters('nt$($count)fabricTcpGatewayPort')]",
                            "enableFloatingIP": "false",
                            "frontendIPConfiguration": {
                                "id": "[variables('lbIPConfig$($count)')]"
                            },
                            "frontendPort": "[parameters('nt$($count)fabricTcpGatewayPort')]",
                            "idleTimeoutInMinutes": "5",
                            "probe": {
                                "id": "[variables('lbProbeID$($count)')]"
                            },
                            "protocol": "tcp"
                        }
                    },
                    {
                        "name": "LBHttpRule",
                        "properties": {
                            "backendAddressPool": {
                                "id": "[variables('lbPoolID$($count)')]"
                            },
                            "backendPort": "[parameters('nt$($count)fabricHttpGatewayPort')]",
                            "enableFloatingIP": "false",
                            "frontendIPConfiguration": {
                                "id": "[variables('lbIPConfig$($count)')]"
                            },
                            "frontendPort": "[parameters('nt$($count)fabricHttpGatewayPort')]",
                            "idleTimeoutInMinutes": "5",
                            "probe": {
                                "id": "[variables('lbHttpProbeID$($count)')]"
                            },
                            "protocol": "tcp"
                        }
                    }
                ],
                "probes": [
                    {
                        "name": "FabricGatewayProbe",
                        "properties": {
                            "intervalInSeconds": 5,
                            "numberOfProbes": 2,
                            "port": "[parameters('nt$($count)fabricTcpGatewayPort')]",
                            "protocol": "tcp"
                        }
                    },
                    {
                        "name": "FabricHttpGatewayProbe",
                        "properties": {
                            "intervalInSeconds": 5,
                            "numberOfProbes": 2,
                            "port": "[parameters('nt$($count)fabricHttpGatewayPort')]",
                            "protocol": "tcp"
                        }
                    }
                ],
                "inboundNatPools": [
                    {
                        "name": "LoadBalancerBEAddressNatPool",
                        "properties": {
                            "backendPort": "3389",
                            "frontendIPConfiguration": {
                                "id": "[variables('lbIPConfig$($count)')]"
                            },
                            "frontendPortRangeEnd": "4500",
                            "frontendPortRangeStart": "3389",
                            "protocol": "tcp"
                        }
                    }
                ]
            },
            "tags": {
                "resourceType": "Service Fabric",
                "clusterName": "[parameters('clusterName')]"
            }
        }
'@
    $json = $json.Replace('$($count)',$count)
    $ret = $ret -band [bool]($jsonObject.resources = (add-newMember -customObject @($jsonObject.resources) -name "[concat('LB','-', parameters('clusterName'),'-',parameters('vmNodeType$($count)Name'))]" -isList $true -whatif $whatIf -value (ConvertFrom-Json $json)))

    $json = @'
    {
            "apiVersion": "[variables('vmssApiVersion')]",
            "type": "Microsoft.Compute/virtualMachineScaleSets",
            "name": "[parameters('vmNodeType$($count)Name')]",
            "location": "[parameters('computeLocation')]",
            "dependsOn": [
                "[concat('Microsoft.Network/virtualNetworks/', parameters('virtualNetworkName'))]",
                "[concat('Microsoft.Network/loadBalancers/', concat('LB','-', parameters('clusterName'),'-',parameters('vmNodeType$($count)Name')))]",
                "[concat('Microsoft.Storage/storageAccounts/', parameters('supportLogStorageAccountName'))]",
                "[concat('Microsoft.Storage/storageAccounts/', parameters('applicationDiagnosticsStorageAccountName'))]"
            ],
            "properties": {
                "overprovision": "[parameters('overProvision')]",
                "upgradePolicy": {
                    "mode": "Automatic"
                },
                "virtualMachineProfile": {
                    "extensionProfile": {
                        "extensions": [
                            {
                                "name": "[concat(parameters('vmNodeType$($count)Name'),'_ServiceFabricNode')]",
                                "properties": {
                                    "type": "ServiceFabricNode",
                                    "autoUpgradeMinorVersion": true,
                                    "protectedSettings": {
                                        "StorageAccountKey1": "[listKeys(resourceId('Microsoft.Storage/storageAccounts', parameters('supportLogStorageAccountName')),'2015-05-01-preview').key1]",
                                        "StorageAccountKey2": "[listKeys(resourceId('Microsoft.Storage/storageAccounts', parameters('supportLogStorageAccountName')),'2015-05-01-preview').key2]"
                                    },
                                    "publisher": "Microsoft.Azure.ServiceFabric",
                                    "settings": {
                                        "clusterEndpoint": "[reference(parameters('clusterName')).clusterEndpoint]",
                                        "nodeTypeRef": "[parameters('vmNodeType$($count)Name')]",
                                        "dataPath": "D:\\\\SvcFab",
                                        "durabilityLevel": "Bronze",
                                        "enableParallelJobs": true,
                                        "nicPrefixOverride": "[parameters('subnet$($count)Prefix')]",
                                        "certificate": {
                                            "thumbprint": "[parameters('certificateThumbprint')]",
                                            "x509StoreName": "[parameters('certificateStoreValue')]"
                                        }
                                    },
                                    "typeHandlerVersion": "1.0"
                                }
                            },
                            {
                                "name": "[concat('VMDiagnosticsVmExt','_vmNodeType$($count)Name')]",
                                "properties": {
                                    "type": "IaaSDiagnostics",
                                    "autoUpgradeMinorVersion": true,
                                    "protectedSettings": {
                                        "storageAccountName": "[parameters('applicationDiagnosticsStorageAccountName')]",
                                        "storageAccountKey": "[listKeys(resourceId('Microsoft.Storage/storageAccounts', parameters('applicationDiagnosticsStorageAccountName')),'2015-05-01-preview').key1]",
                                        "storageAccountEndPoint": "https://core.windows.net/"
                                    },
                                    "publisher": "Microsoft.Azure.Diagnostics",
                                    "settings": {
                                        "WadCfg": {
                                            "DiagnosticMonitorConfiguration": {
                                                "overallQuotaInMB": "50000",
                                                "EtwProviders": {
                                                    "EtwEventSourceProviderConfiguration": [
                                                      {
                                                        "provider": "Microsoft-ServiceFabric-Actors",
                                                        "scheduledTransferKeywordFilter": "1",
                                                        "scheduledTransferPeriod": "PT5M",
                                                        "DefaultEvents": {
                                                          "eventDestination": "ServiceFabricReliableActorEventTable"
                                                        }
                                                      },
                                                        {
                                                            "provider": "Microsoft-ServiceFabric-Services",
                                                            "scheduledTransferPeriod": "PT5M",
                                                            "DefaultEvents": {
                                                                "eventDestination": "ServiceFabricReliableServiceEventTable"
                                                            }
                                                        }
                                                    ],
                                                    "EtwManifestProviderConfiguration": [
                                                        {
                                                            "provider": "cbd93bc2-71e5-4566-b3a7-595d8eeca6e8",
                                                            "scheduledTransferLogLevelFilter": "Information",
                                                            "scheduledTransferKeywordFilter": "4611686018427387904",
                                                            "scheduledTransferPeriod": "PT5M",
                                                            "DefaultEvents": {
                                                                "eventDestination": "ServiceFabricSystemEventTable"
                                                            }
                                                        }
                                                    ]
                                                }
                                            }
                                        },
                                        "StorageAccount": "[parameters('applicationDiagnosticsStorageAccountName')]"
                                    },
                                    "typeHandlerVersion": "1.5"
                                }
                            }
                        ]
                    },
                    "networkProfile": {
                        "networkInterfaceConfigurations": [
                            {
                                "name": "[concat(parameters('nicName'), '-$($count)')]",
                                "properties": {
                                    "ipConfigurations": [
                                        {
                                            "name": "[concat(parameters('nicName'),'-',$($count))]",
                                            "properties": {
                                                "loadBalancerBackendAddressPools": [
                                                    {
                                                        "id": "[variables('lbPoolID$($count)')]"
                                                    }
                                                ],
                                                "loadBalancerInboundNatPools": [
                                                    {
                                                        "id": "[variables('lbNatPoolID$($count)')]"
                                                    }
                                                ],
                                                "subnet": {
                                                    "id": "[variables('subnet$($count)Ref')]"
                                                }
                                            }
                                        }
                                    ],
                                    "primary": true
                                }
                            }
                        ]
                    },
                    "osProfile": {
                        "adminPassword": "[parameters('adminPassword')]",
                        "adminUsername": "[parameters('adminUsername')]",
                        "computernamePrefix": "[parameters('vmNodeType$($count)Name')]",
                        "secrets": [
                            {
                                "sourceVault": {
                                    "id": "[parameters('sourceVaultValue')]"
                                },
                                "vaultCertificates": [
                                    {
                                        "certificateStore": "[parameters('certificateStoreValue')]",
                                        "certificateUrl": "[parameters('certificateUrlValue')]"
                                    }
                                ]
                            }
                        ]
                    },
                    "storageProfile": {
                        "imageReference": {
                            "publisher": "[parameters('vmImagePublisher')]",
                            "offer": "[parameters('vmImageOffer')]",
                            "sku": "[parameters('vmImageSku')]",
                            "version": "[parameters('vmImageVersion')]"
                        },
                        "osDisk": {
                            "caching": "ReadOnly",
                            "createOption": "FromImage",
                            "managedDisk": {
                                "storageAccountType": "[parameters('storageAccountType')]"
                            }
                        }
                    }
                }
            },
            "sku": {
                "name": "[parameters('vmNodeType$($count)Size')]",
                "capacity": "[parameters('nt$($count)InstanceCount')]",
                "tier": "Standard"
            },
            "tags": {
                "resourceType": "Service Fabric",
                "clusterName": "[parameters('clusterName')]"
            }
        }
'@
    $json = $json.Replace('$($count)',$count)
    $ret = $ret -band [bool]($jsonObject.resources = (add-newMember -customObject @($jsonObject.resources) -name "[parameters('vmNodeType$($count)Name')]" -isList $true -whatif $whatIf -value (ConvertFrom-Json $json)))

    $json = @'
    {
        "name": "[parameters('vmNodeType$($count)Name')]",
        "applicationPorts": {
            "endPort": "[parameters('nt$($count)applicationEndPort')]",
            "startPort": "[parameters('nt$($count)applicationStartPort')]"
        },
        "clientConnectionEndpointPort": "[parameters('nt$($count)fabricTcpGatewayPort')]",
        "durabilityLevel": "Bronze",
        "ephemeralPorts": {
            "endPort": "[parameters('nt$($count)ephemeralEndPort')]",
            "startPort": "[parameters('nt$($count)ephemeralStartPort')]"
        },
        "httpGatewayEndpointPort": "[parameters('nt$($count)fabricHttpGatewayPort')]",
        "isPrimary": true,
        "vmInstanceCount": "[parameters('nt$($count)InstanceCount')]"
    }
'@
    $json = $json.Replace('$($count)',$count)
    $nodeTypeObject = $jsonObject.resources | ? type -imatch "Microsoft.ServiceFabric/clusters"
    $ret = $ret -band [bool]($nodeTypeObject.properties.nodetypes = (add-newMember -customObject @($nodeTypeObject.properties.nodetypes) -name "[parameters('vmNodeType$($count)Name')]" -isList $true -whatif $whatIf -value (ConvertFrom-Json $json)))


    # good ?
    if($ret)
    {
        if($whatif)
        {
            $whatif = $false
        }
        else
        {
            break
        }
    }
    else
    {
        $count++
    }
}



$jsonObject.parameters
$jsonObject.resources

$dirtyJson = ConvertTo-Json -InputObject $jsonObject -Depth 99
$cleanJson = [regex]::replace($dirtyJson,'\\u[a-fA-F0-9]{4}',{[char]::ConvertFromUtf32(($args[0].Value -replace '\\u','0x'))})

write-host $cleanJson
out-file -FilePath c:\temp\test.json -Encoding ascii -InputObject $cleanJson
notepad c:\temp\test.json
