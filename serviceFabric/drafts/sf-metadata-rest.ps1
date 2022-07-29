<#
    Script to test azure metadata identity and instance from a configured vm scaleset
    Script runs on vm scaleset node

    to run with no arguments:
    iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/sf-metadata-rest.ps1" -UseBasicParsing|iex

    or use the following to save and pass arguments:
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/sf-metadata-rest.ps1" -outFile "$pwd/sf-metadata-rest.ps1";
    .\sf-metadata-rest.ps1


    # https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-use-vm-token#get-a-token-using-azure-powershell
    # https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/qs-configure-powershell-windows-vmss

    # if needed, enable system / user managed identity on scaleset
    PS C:\Users\jagilber> Update-AzVmss -ResourceGroupName sfcluster -Name nt0 -IdentityType "SystemAssigned"


    ResourceGroupName                           : sfcluster
    Sku                                         :
    Name                                      : Standard_D2_v2
    Tier                                      : Standard
    Capacity                                  : 1
    UpgradePolicy                               :
    Mode                                      : Automatic
    VirtualMachineProfile                       :
    OsProfile                                 :
        ComputerNamePrefix                      : nt0
        AdminUsername                           : cloudadmin
        WindowsConfiguration                    :
        ProvisionVMAgent                      : True
        EnableAutomaticUpdates                : True
        Secrets[0]                              :
        SourceVault                           :
            Id                                  : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/certsj                                                                                  agilber/providers/Microsoft.KeyVault/vaults/sfjagilber
        VaultCertificates[0]                  :
            CertificateUrl                      :
    https://sfjagilber.vault.azure.net/secrets/sfjagilber/xxxxxxxxxxxxxxxxxxxxxxxxxxxx
            CertificateStore                    : My
    StorageProfile                            :
        ImageReference                          :
        Publisher                             : MicrosoftWindowsServer
        Offer                                 : WindowsServer
        Sku                                   : 2016-Datacenter-with-containers
        Version                               : latest
        OsDisk                                  :
        Caching                               : ReadOnly
        CreateOption                          : FromImage
        DiskSizeGB                            : 127
        ManagedDisk                           :
            StorageAccountType                  : Standard_LRS
    NetworkProfile                            :
        NetworkInterfaceConfigurations[0]       :
        Name                                  : NIC-0
        Primary                               : True
        EnableAcceleratedNetworking           : False
        DnsSettings                           :
        IpConfigurations[0]                   :
            Name                                : NIC-0
            Subnet                              :
            Id                                : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sfjagi                                                                                  lber1nt1/providers/Microsoft.Network/virtualNetworks/VNet/subnets/Subnet-0
            PrivateIPAddressVersion             : IPv4
            LoadBalancerBackendAddressPools[0]  :
            Id                                : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sfjagi                                                                                  lber1nt1/providers/Microsoft.Network/loadBalancers/LB-sfcluster-nt0/backendAddressPools/LoadBalancerBEAddressPool                                                                                           LoadBalancerInboundNatPools[0]      :
            Id                                : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sfjagi                                                                                  lber1nt1/providers/Microsoft.Network/loadBalancers/LB-sfcluster-nt0/inboundNatPools/LoadBalancerBEAddressNatPool                                                                                          EnableIPForwarding                    : False
    ExtensionProfile                          :
        Extensions[0]                           :
        Name                                  : nt0_ServiceFabricNode
        Publisher                             : Microsoft.Azure.ServiceFabric
        Type                                  : ServiceFabricNode
        TypeHandlerVersion                    : 1.0
        AutoUpgradeMinorVersion               : True
        Settings                              : {"clusterEndpoint":"https://eastus.servicefabric.azure.com/runtime/cluste                                                                                  rs/9d46533d-02ec-4cf2-9554-a3269bbaea3e","nodeTypeRef":"nt0","dataPath":"D:\\\\SvcFab","durabilityLevel":"Bronze","enab                                                                                  leParallelJobs":true,"nicPrefixOverride":"10.0.0.0/24","certificate":{"thumbprint":"0CB9ED28A3582424DD423321915E6C6A584                                                                                  6E3DF","x509StoreName":"My"}}
        Extensions[1]                           :
        Name                                  : VMDiagnosticsVmExt_vmNodeType0Name
        Publisher                             : Microsoft.Azure.Diagnostics
        Type                                  : IaaSDiagnostics
        TypeHandlerVersion                    : 1.5
        AutoUpgradeMinorVersion               : True
        Settings                              : {"WadCfg":{"DiagnosticMonitorConfiguration":{"overallQuotaInMB":"50000","                                                                                  EtwProviders":{"EtwEventSourceProviderConfiguration":[{"provider":"Microsoft-ServiceFabric-Actors","scheduledTransferKe                                                                                  ywordFilter":"1","scheduledTransferPeriod":"PT5M","DefaultEvents":{"eventDestination":"ServiceFabricReliableActorEventT                                                                                  able"}},{"provider":"Microsoft-ServiceFabric-Services","scheduledTransferPeriod":"PT5M","DefaultEvents":{"eventDestinat                                                                                  ion":"ServiceFabricReliableServiceEventTable"}}],"EtwManifestProviderConfiguration":[{"provider":"cbd93bc2-71e5-4566-b3                                                                                  a7-595d8eeca6e8","scheduledTransferLogLevelFilter":"Information","scheduledTransferKeywordFilter":"4611686018427387904"                                                                                  ,"scheduledTransferPeriod":"PT5M","DefaultEvents":{"eventDestination":"ServiceFabricSystemEventTable"}}]}}},"StorageAcc                                                                                  ount":"ho4nhzqerrwe23"}
        Extensions[2]                           :
        Name                                  : MMAExtension
        Publisher                             : Microsoft.EnterpriseCloud.Monitoring
        Type                                  : MicrosoftMonitoringAgent
        TypeHandlerVersion                    : 1.0
        AutoUpgradeMinorVersion               : True
        Settings                              :
    {"workspaceId":"4c56471a-7c26-4d4d-9c05-4ea067dfa775","stopOnMultipleConnections":"true"}
    ProvisioningState                           : Succeeded
    Overprovision                               : False
    DoNotRunExtensionsOnOverprovisionedVMs      : False
    UniqueId                                    : 220ebcb3-05bd-4b31-a3bb-a8e4eead00d6
    SinglePlacementGroup                        : True
    Identity                                    :
    PrincipalId                               : 542e061b-4ef2-4273-a509-2650f323fc06
    TenantId                                  : ***REMOVED***
    Type                                      : SystemAssigned
    Id                                          : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sfjagi
    lber1nt1/providers/Microsoft.Compute/virtualMachineScaleSets/nt0
    Name                                        : nt0
    Type                                        : Microsoft.Compute/virtualMachineScaleSets
    Location                                    : eastus
    Tags                                        : {"resourceType":"Service Fabric","clusterName":"sfcluster"}


    # acquire system managed identity oauth token from within node
    (iwr -Method GET -Uri 'http://$ipAddress/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://management.azure.com' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json
    PS C:\Users\cloudadmin> (iwr -Method GET -Uri 'http://$ipAddress/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://management.azure.com' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json
    {
        "access_token":  "eyJ0eXAiOiJKV...",
        "client_id":  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "expires_in":  "28799",
        "expires_on":  "1581563814",
        "ext_expires_in":  "28799",
        "not_before":  "1581534714",
        "resource":  "https://management.azure.com/",
        "token_type":  "Bearer"
    }

    # example instance rest query from within node
    (iwr -Method GET -Uri 'http://$ipAddress/metadata/instance?api-version=2021-02-01' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json

    PS C:\Users\cloudadmin> (iwr -Method GET -Uri 'http://$ipAddress/metadata/instance?api-version=2021-02-01' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json
    {
        "compute":  {
                        "location":  "eastus",
                        "name":  "nt0_0",
                        "offer":  "WindowsServer",
                        "osType":  "Windows",
                        "placementGroupId":  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                        "platformFaultDomain":  "0",
                        "platformUpdateDomain":  "0",
                        "publisher":  "MicrosoftWindowsServer",
                        "resourceGroupName":  "sfcluster",
                        "sku":  "2016-Datacenter-with-containers",
                        "subscriptionId":  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                        "tags":  "clusterName:sfcluster;resourceType:Service Fabric",
                        "version":  "14393.3443.2001090113",
                        "vmId":  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                        "vmScaleSetName":  "nt0",
                        "vmSize":  "Standard_D2_v2",
                        "zone":  ""
                    },
        "network":  {
                        "interface":  [
                                        "@{ipv4=; ipv6=; macAddress=xxxxxxxxxxxx}"
                                    ]
                    }
    }
#>
param(
    $iterations = 1,
    $logFile = "$pwd\azure-metadata-rest.log",
    $sleepMilliseconds = 1000,
    $apiVersion = '2021-02-01',
    $ipaddress =  '10.0.0.4:2377'
)

[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
$error.Clear()
$ErrorActionPreference = "continue"
$count = 0
$errorCounter = 0

function main() {
    if((whoami -inotmatch 'network service')) {
        write-error "script has to run under 'network service' context"
        return
    }

    $cert = Get-ChildItem -Path cert:\LocalMachine -Recurse | Where-Object Issuer -imatch 'FabricManagedIdentityTokenSvc'

    while ($count -le $iterations) {
        # acquire system managed identity oauth token from within node
        $global:managementOauthResult = query-metadata -url "https://$ipAddress/metadata/identity/oauth2/token?api-version=$apiVersion&resource=https://management.azure.com" -Cert $cert
       # $global:managementOauthResultAz = query-metadata -url "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$apiVersion&resource=https://management.azure.com"
        
        # key vault
        $global:vaultOauthResult = query-metadata -url "https://$ipAddress/metadata/identity/oauth2/token?api-version=$apiVersion&resource=https://vault.azure.net" -Cert $cert
      #  $global:vaultOauthResultAz = query-metadata -url "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$apiVersion&resource=https://vault.azure.net"

        # example instance rest query from within node
        $global:instanceResult = query-metadata -url "https://$ipAddress/metadata/instance?api-version=$apiVersion" -Cert $cert
      #  $global:instanceResultAz = query-metadata -url "http://169.254.169.254/metadata/instance?api-version=$apiVersion"

        if ($error) {
            if ($logFile) {
                Out-File -InputObject "$(get-date) $($error | Format-List * | out-string)`r`n$result" -FilePath $logFile -Append
            }
            $errorCounter ++
            $error.Clear()
        }

        write-host $global:vaultOauthResult
        write-host $global:managementOauthResult
        write-host ($global:instanceResult | convertto-json -Depth 99)
        start-sleep -Milliseconds $sleepMilliseconds
        $count++
    }

    write-host "objects stored in `$global:managementOauthResult `$global:managementOauthResultAz `$global:vaultOauthResult `$global:vaultOauthResultAz `$global:instanceResult and `$global:instanceResultAz"
    write-host "finished. total errors:$errorCounter logfile:$logFile"
}

function query-metadata($url,$cert) {
    $headers = @{'Metadata' = 'true' }
    if($cert){
        write-host "Invoke-RestMethod -Method GET -Uri $url -Headers $headers -certificate $cert" -ForegroundColor Green
        $result = Invoke-RestMethod -Method GET -Uri $url -Headers $headers -Certificate $cert
    }
    else {
        write-host "Invoke-RestMethod -Method GET -Uri $url -Headers $headers" -ForegroundColor Green
        $result = Invoke-RestMethod -Method GET -Uri $url -Headers $headers
    }
    write-host "$($result | convertto-json -depth 99)" -ForegroundColor Cyan
    return $result
}

main