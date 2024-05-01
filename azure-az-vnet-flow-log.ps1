<#
.SYNOPSIS
    powershell script to enable vnet flow logs on azure vnet

.DESCRIPTION

    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-vnet-flow-log.ps1" -outFile "$pwd\azure-az-vnet-flow-log.ps1"
    https://learn.microsoft.com/en-us/azure/network-watcher/vnet-flow-logs-overview
    https://learn.microsoft.com/en-us/azure/network-watcher/flow-logs-read?tabs=vnet\

    We recommend disabling network security group flow logs before enabling virtual network flow logs on the same underlying workloads to avoid duplicate traffic recording and additional costs. 
    If you enable network security group flow logs on the network security group of a subnet, then you enable virtual network flow logs on the same subnet or parent virtual network, 
    you might get duplicate logging (both network security group flow logs and virtual network flow logs generated for all supported workloads in that particular subnet).
    
    Feature	Free units included	Price
    Network flow logs collected1	5 GB per month	$0.50 per GB

.NOTES
   File Name  : azure-az-vnet-flow-log.ps1
   Author     : jagilber
   Version    : 240501
   History    :

   Schema
    Example JSON
    {
        "records": [
            {
                "time": "2023-02-04T23:00:23.8575523Z",
                "flowLogVersion": 4,
                "flowLogGUID": "4c6afa0c-e30c-4866-acb0-60a6439ad918",
                "macAddress": "6045BD7431F1",
                "category": "FlowLogFlowEvent",
                "flowLogResourceID": "/SUBSCRIPTIONS/014E7430-FD92-4579-9119-E861D926508A/RESOURCEGROUPS/NETWORKWATCHERRG/PROVIDERS/MICROSOFT.NETWORK/NETWORKWATCHERS/NETWORKWATCHER_EASTUS2EUAP/FLOWLOGS/FLRUNNERSFLOWLOG",
                "targetResourceID": "/subscriptions/014e7430-fd92-4579-9119-e861d926508a/resourceGroups/samoham-eastus2euap-rg/providers/Microsoft.Network/virtualNetworks/flrunnersVnet",
                "operationName": "FlowLogFlowEvent",
                "flowRecords": {
                    "flows": [
                        {
                            "aclID": "fbd9a77e-bdab-4ce8-b4fb-64bf199d66bf",
                            "flowGroups": [
                                {
                                    "rule": "DefaultRule_AllowInternetOutBound",
                                    "flowTuples": [
                                        "1675551600689,192.168.0.8,40.79.154.85,58973,443,6,O,E,NX,15,8645,13,9044"
                                    ]
                                }
                            ]
                        },
                        {
                            "aclID": "65624055-d088-44e6-9c98-b7cadd84885a",
                            "flowGroups": [
                                {
                                    "rule": "BlockHighRiskTCPPortsFromInternet_8e593d16-5f9d-4b25-b3b2-df7b6951a08b",
                                    "flowTuples": [
                                        "1675551614124,205.210.31.32,192.168.0.8,53998,5986,6,I,D,NX,0,0,0,0"
                                    ]
                                },
                                {
                                    "rule": "Internet_d04abb96-9395-47cb-a760-7640a232c7a1",
                                    "flowTuples": [
                                        "1675551583200,91.191.209.198,192.168.0.8,50706,15800,6,I,D,NX,0,0,0,0",
                                        "1675551586719,89.248.165.195,192.168.0.8,43666,635,6,I,D,NX,0,0,0,0",
                                        "1675551607297,162.142.125.243,192.168.0.8,42356,56570,6,I,D,NX,0,0,0,0",
                                        "1675551608150,170.187.229.195,192.168.0.8,51602,9205,6,I,D,NX,0,0,0,0",
                                        "1675551618678,107.170.245.18,192.168.0.8,49147,1400,6,I,D,NX,0,0,0,0"
                                    ]
                                }
                            ]
                        }
                    ]
                }
            }
        ]
    }
    Flow logs properties
    Field Name	Description
    time	Time in UTC when the event was logged
    flowLogVersion	Version of flow log schema
    flowLogGUID	The resource GUID of the FlowLog resource
    macAddress	MAC address of the network interface where the event was captured
    category	The category of the event. The category is always FlowLogFlowEvent
    flowLogResourceID	The resource ID of the FlowLog resource
    targetResourceID	The resource ID target resource associated to the FlowLog resource
    operationName	This is always FlowLogFlowEvent
    flowRecords	A collection of flow records
    flows	A collection of flows. This property has multiple entries for different ACLs
    aclID	This is a GUID which identifies the NSG resource. For cases like traffic denied by encryption, this will be "unspecified"
    flowGroups	a collection of flow records at a rule level
    rule	The rule name which allowed or denied the traffic. For traffic denied due to encryption, this value can be "unspecified"
    flowTuples	A string that contains multiple properties for the flow tuple in comma-separated format
    Flow tuple fields
    Field Name	Description
    TimeStamp	This value is the time stamp of when the flow occurred in UNIX epoch format
    Source IP	The source IP
    Destination IP	The destination IP
    Source Port	The source port
    Destination Port	The destination Port
    Protocol	The L4 protocol of the flow expressed as IANA assigned values
    Flow direction	The direction of the traffic flow. Valid values are I for inbound and O for outbound
    Flow State	Captures the state of the flow. Possible states are B: Begin, when a flow is created, statistics are not provided. C: Continuing for an ongoing flow, statistics are provided at 5-minute intervals. E: End, when a flow is terminated, statistics are provided. D: when a flow is denied
    Flow Encryption	Captures the encryption state of the flow. Possible values: 'X' representing Encrypted, 'NX' representing Unencrypted, 'NX_HW_NOT_SUPPORTED' representing Unsupported hardware, 'NX_SW_NOT_READY' representing Software not ready, 'NX_NOT_ACCEPTED' representing Drop due to no encryption, 'NX_NOT_SUPPORTED' representing Discovery not supported, 'NX_LOCAL_DST' representing Destination on same host, 'NX_FALLBACK' representing Fallback to no encryption
    Packets from Source to destination	The total number of packets sent from source to destination since the last update
    Bytes sent from Source to destination	The total number of packet bytes sent from source to destination since the last update. Packet bytes include the packet header and payload
    Packets from Destination to source	The total number of packets sent from destination to source since the last update
    Bytes sent from Destination to source	The total number of packet bytes sent from destination to source since the last update. Packet bytes include packet header and payload
    Encryption field
    Encryption Status	Description
    Encrypted (X)	Connection is encrypted. This refers to the scenario where customer has configured encryption and the platform has encrypted the connection.
    Unencrypted (NX)	Connection is not encrypted. This will be logged in the scenario where encryption is not configured. It will also be logged in scenario where allow unencrypted policy is configured and the remote endpoint of the traffic does not support encryption.
    Unsupported Hardware (NX_HW_NOT_SUPPORTED)	Customer has configured encryption, but the VM is running on a host which does not support encryption. This can usually be the case where the FPGA is not attached to the host, or could be faulty. Needs further investigation.
    Software not ready (NX_SW_NOT_READY)	Customer has configured encryption, but the software component (GFT) in the host networking stack is not ready to process encrypted connections. Needs further investigation.
    Drop due to no encryption (NX_NOT_ACCEPTED)	Customer has configured drop on unencrypted policy as a part of VNET encryption. If the connection is not encrypted, it will be dropped.
    Discovery not supported (NX_NOT_SUPPORTED)	Encryption is configured, but the encryption session was not established, as discovery is not supported in the host networking stack. This needs further investigation.
    Destination on same host (NX_LOCAL_DST)	Encryption is configured, but the source and destination VMs are running on the same Azure host. In this case, the connection will not be encrypted by design.
    Fallback to no encryption (NX_FALLBACK)	Encryption is configured with the allow unencrypted policy. Connection will not be encrypted.

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-vnet-flow-log.ps1" -outFile "$pwd\azure-az-vnet-flow-log.ps1";
    .\azure-az-vnet-flow-log.ps1 -examples

.EXAMPLE
    .\azure-az-vnet-flow-log.ps1 -resourceGroupName "samoham-eastus2euap-rg" `
        -networkWatcherResourceGroupName "NETWORKWATCHERRG" `
        -networkWatcherName "NETWORKWATCHER_EASTUS2EUAP" `
        -flowLogName "FLRUNNERSFLOWLOG" `
        -vnetName "flrunnersVnet" `
        -storageAccountName "flrunnersstorage" `
        -location "eastus2euap" `
        -enable
    enable flow log

.EXAMPLE
    .\azure-az-vnet-flow-log.ps1 -resourceGroupName "samoham-eastus2euap-rg" `
        -networkWatcherResourceGroupName "NETWORKWATCHERRG" `
        -networkWatcherName "NETWORKWATCHER_EASTUS2EUAP" `
        -flowLogName "FLRUNNERSFLOWLOG" `
        -vnetName "flrunnersVnet" `
        -storageAccountName "flrunnersstorage" `
        -location "eastus2euap" `
        -disable
    disable flow log

.EXAMPLE
    .\azure-az-vnet-flow-log.ps1 -resourceGroupName "samoham-eastus2euap-rg" `
        -networkWatcherResourceGroupName "NETWORKWATCHERRG" `
        -networkWatcherName "NETWORKWATCHER_EASTUS2EUAP" `
        -flowLogName "FLRUNNERSFLOWLOG" `
        -vnetName "flrunnersVnet" `
        -storageAccountName "flrunnersstorage" `
        -location "eastus2euap" `
        -get
    get flow log

.EXAMPLE
    .\azure-az-vnet-flow-log.ps1 -resourceGroupName "samoham-eastus2euap-rg" `
        -networkWatcherResourceGroupName "NETWORKWATCHERRG" `
        -networkWatcherName "NETWORKWATCHER_EASTUS2EUAP" `
        -flowLogName "FLRUNNERSFLOWLOG" `
        -vnetName "flrunnersVnet" `
        -storageAccountName "flrunnersstorage" `
        -location "eastus2euap" `
        -macAddress "6045BD7431F1" `
        -get
    get flow log for mac address

.EXAMPLE
    .\azure-az-vnet-flow-log.ps1 -resourceGroupName "samoham-eastus2euap-rg" `
        -networkWatcherResourceGroupName "NETWORKWATCHERRG" `
        -networkWatcherName "NETWORKWATCHER_EASTUS2EUAP" `
        -flowLogName "FLRUNNERSFLOWLOG" `
        -vnetName "flrunnersVnet" `
        -storageAccountName "flrunnersstorage" `
        -location "eastus2euap" `
        -remove
    remove flow log

.EXAMPLE
    $global:sortedFlowTuple | ? FlowState -ieq 'denied'
    to review output for denied traffic

.PARAMETER resourceGroupName
    resource group name

.PARAMETER networkWatcherResourceGroupName
    network watcher resource group name

.PARAMETER networkWatcherName
    network watcher name

.PARAMETER flowLogName
    flow log name

.PARAMETER vnetName
    vnet name

.PARAMETER storageAccountName
    storage account name

.PARAMETER logAnalyticsWorkspaceName
    log analytics workspace name

.PARAMETER location
    location

.PARAMETER examples
    get help examples

.PARAMETER enable
    enable flow log

.PARAMETER disable
    disable flow log

.PARAMETER get
    get flow log for mac address and log time. downloads flow log to json file

.PARAMETER remove
    remove flow log

.PARAMETER force
    force

.PARAMETER logRetentionInDays
    log retention in days. requies storage account kind to be StorageV2

.PARAMETER macAddress
    mac address. default is *

.PARAMETER logTime
    log time in date time format for example (get-date) when using get switch

.PARAMETER subscriptionId
    subscription id

.PARAMETER merge
    merge all csv files into single csv file
#>

#requires -version 7.4.0
using namespace System
using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Linq
[CmdletBinding()]
param(
    [string]$resourceGroupName = 'servicefabriccluster',
    [string]$vnetName = 'VNet',
    [string]$location = 'eastus',
    [string]$networkWatcherResourceGroupName = 'NetworkWatcherRG',
    [string]$networkWatcherName = 'NetworkWatcher_' + $location,
    [string]$flowLogName = $vnetName + 'FlowLog',
    [string]$flowLogJson = "$pwd\flowLog.json",
    [string]$subscriptionId = (get-azContext).Subscription.Id,
    [string]$storageAccountName,
    [string]$logAnalyticsWorkspaceName,
    [string]$macAddress = '*',
    [datetime]$logTime = (get-date),
    # [bool]$minutePrecision = $true,
    [int]$logRetentionInDays = 0, # 0 to disable log retention
    [switch]$enable,
    [switch]$disable,
    [switch]$get,
    [switch]$remove,
    [switch]$examples,
    [switch]$force,
    [switch]$merge
)

Set-StrictMode -Version Latest
$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = "silentlycontinue"
$scriptName = "$psscriptroot\$($MyInvocation.MyCommand.Name)"
$global:sortedFlowTuple = $null

function main() {

    if ($examples) {
        write-host "get-help $scriptName -examples"
        get-help $scriptName -examples
        return
    }

    $error.Clear()
    $currentFlowLog = $null

    try {
        if (!(check-arguments)) {
            return
        }

        $currentFlowLog = get-flowLog
        $error.Clear()

        if ($enable -or $disable) {
            if (!(modify-flowLog)) {
                return
            }
        }

        $universalTime = $logTime.ToUniversalTime()
        write-host "using universalTime: $universalTime" -ForegroundColor Cyan

        if ($get -and $currentFlowLog) {
            $flowLogs = download-flowLog -currentFlowLog $currentFlowLog
            $csvFiles = @()
            foreach ($flowLogFileName in $flowLogs) {
                $csvFiles += summarize-flowLog -flowLogFileName $flowLogFileName
            }
            if ($merge) {
                # read all csv files, merge, sort, and save to new single csv file
                $parsedFlowTuple = [collections.arrayList]::new()
                foreach ($csvFile in $csvFiles) {
                    $parsedFlowTuple.AddRange((import-csv -Path $csvFile))
                }
                $flowLogFileName = generate-fileName $flowLogJson "merged"
                $csvFileName = save-flowTuple -flowLogFileName $flowLogFileName -parsedFlowTuple $parsedFlowTuple
                write-host "merged flow log saved to $csvFileName" -ForegroundColor Green
            }
        }
        elseif ($get) {
            write-host "flow log not found" -ForegroundColor Yellow
        }

        if ($remove -and $currentFlowLog) {
            write-host "Remove-AzNetworkWatcherFlowLog -Name $flowLogName -NetworkWatcherName $($networkwatcher.Name) -ResourceGroupName $networkWatcherResourceGroupName" -ForegroundColor Yellow
            Remove-AzNetworkWatcherFlowLog -Name $flowLogName -NetworkWatcherName $networkwatcher.Name -ResourceGroupName $networkWatcherResourceGroupName
        }
        elseif ($remove) {
            write-host "flow log not found" -ForegroundColor Yellow
        }

        write-host "finished. results in:`$global:sortedFlowTuple" -ForegroundColor Green
    }
    catch {
        write-verbose "variables:$((get-variable -scope local).value | convertto-json -depth 2)"
        write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
        return 1
    }
    finally {
        if ($currentFlowLog) {
            if ($currentFlowLog.enabled) {
                Write-Warning "flow log enabled. to prevent unnecessary charges, disable flow log when not in use using -disable switch"
            }
        }
    }
}

function check-arguments() {

    if (!$resourceGroupName) {
        Write-Warning "resource group name is required."
        return $false
    }        

    if ($enable -and $disable) {
        Write-Warning "enable and disable switches are mutually exclusive."
        return $false
    }

    if ($get -and $remove) {
        Write-Warning "get and remove switches are mutually exclusive."
        return $false
    }

    if (($enable -or $disable) -and ($get -or $remove)) {
        Write-Warning "enable/disable and get/remove switches are mutually exclusive."
        return $false
    }

    if (!(check-module)) {
        return $false
    }

    if (!(Get-azResourceGroup)) {
        connect-azaccount

        if ($error) {
            return $false
        }
    }
    return $true
}

function check-module() {
    $error.clear()
    get-command Set-AzNetworkWatcherFlowLog  -ErrorAction SilentlyContinue

    if ($error) {
        $error.clear()
        write-warning "Set-AzNetworkWatcherFlowLog  not installed."

        if ((read-host "is it ok to install latest az?[y|n]") -imatch "y") {
            $error.clear()
            install-module Az.Accounts
            install-module Az.Network
            install-module Az.OperationalInsights
            install-module Az.Storage
            install-module Az.Resources

            import-module Az.Accounts
            import-module Az.Network
            import-module Az.OperationalInsights
            import-module Az.Storage
            import-module Az.Resources
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

function generate-fileName($fileName, $identifier = "") {
    $flowLogFileName = [io.path]::GetFileNameWithoutExtension($fileName)
    $flowLogFilePath = [io.path]::GetDirectoryName($fileName)
    $flowLogFileNameExt = [io.path]::GetExtension($fileName)
    
    if ($identifier) {
        $name = "$($flowLogFilePath)\$($flowLogFileName)_$($identifier)_$($universalTime.ToString("yyyyMMddHHmm"))$flowLogFileNameExt"
    }
    else {
        $name = "$($flowLogFilePath)\$($flowLogFileName)_$($universalTime.ToString("yyyyMMddHHmm"))$flowLogFileNameExt"
    }
    
    return $name
}

function download-flowLog($currentFlowLog) {
    $flowLog = $currentFlowLog
    $flowLogFileNames = @()

    if ($flowLog) {
        write-host "flow log stored in global variable: `$flowLog" -ForegroundColor Magenta
        $global:blockBlobs = @(Get-VNetFlowLogCloudBlockBlob -subscriptionId $subscriptionId `
                -region $location `
                -VNetFlowLogName $flowLogName `
                -storageAccountName $storageAccountName `
                -storageAccountResourceGroup $resourceGroupName `
                -macAddress $macAddress `
                -logTime $universalTime)

        foreach ($blockBlob in $global:blockBlobs) {
            write-verbose "blockBlob: $($blockBlob | convertto-json -depth 3)"

            $global:blockList = @(Get-VNetFlowLogBlockList -CloudBlockBlob $blockBlob)
            Write-Verbose "blockList: $($global:blockList | convertto-json -depth 3)"

            $valuearray = Get-VNetFlowLogReadBlock -blockList $global:blockList -CloudBlockBlob $blockBlob
            if ($valuearray) {
                $flowMacAddress = [regex]::match($blockBlob.name, 'macAddress=(.+?)/').Groups[1].value
                $jsonFile = generate-fileName $flowLogJson $flowMacAddress
                $flowLogFileNames += $jsonFile
                write-host "saving flow json string to file $jsonFile" -ForegroundColor Green
                out-file -InputObject $valuearray -FilePath $jsonFile
            }
            else {
                write-host "error reading flow log" -ForegroundColor Red
            }
        }
    }
    else {
        write-host "flow log not found" -ForegroundColor Yellow
    }
    return $flowLogFileNames
}

function get-flowLog() {
    write-host "Get-AzNetworkWatcherFlowLog -Name $flowLogName -NetworkWatcherName $networkwatcherName -ResourceGroupName $networkWatcherResourceGroupName -ErrorAction SilentlyContinue" -ForegroundColor Cyan
    $currentFlowLog = Get-AzNetworkWatcherFlowLog -Name $flowLogName -NetworkWatcherName $networkwatcherName -ResourceGroupName $networkWatcherResourceGroupName -ErrorAction SilentlyContinue
    if ($currentFlowLog) {
        write-host "current flow log: $($currentFlowLog | convertto-json -depth 3)" -ForegroundColor Yellow
    }
    else {
        write-host "flow log not found" -ForegroundColor Yellow
    }
    return $currentFlowLog
}
function Get-VNetFlowLogCloudBlockBlob (
    # https://learn.microsoft.com/en-us/azure/network-watcher/flow-logs-read?tabs=vnet
    [string] [Parameter(Mandatory = $true)] $subscriptionId,
    [string] [Parameter(Mandatory = $true)] $region,
    [string] [Parameter(Mandatory = $true)] $VNetFlowLogName,
    [string] [Parameter(Mandatory = $true)] $storageAccountName,
    [string] [Parameter(Mandatory = $true)] $storageAccountResourceGroup,
    [string] [Parameter(Mandatory = $true)] $macAddress,
    [datetime] [Parameter(Mandatory = $true)] $logTime
) {

    # Retrieve the primary storage account key to access the virtual network flow logs
    $StorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccountResourceGroup -Name $storageAccountName).Value[0]

    # Setup a new storage context to be used to query the logs
    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey

    # Container name used by virtual network flow logs
    $ContainerName = "insights-logs-flowlogflowevent"

    # Name of the blob that contains the virtual network flow log
    $BlobName = "flowLogResourceID=/$($subscriptionId.ToUpper())_NETWORKWATCHERRG/NETWORKWATCHER_$($region.ToUpper())_$($VNetFlowLogName.ToUpper())/y=$($logTime.Year)/m=$(($logTime).ToString("MM"))/d=$(($logTime).ToString("dd"))/h=$(($logTime).ToString("HH"))/m=00/macAddress=$($macAddress)/PT1H.json"
    # if ($minutePrecision) {
    #     $BlobName = "flowLogResourceID=/$($subscriptionId.ToUpper())_NETWORKWATCHERRG/NETWORKWATCHER_$($region.ToUpper())_$($VNetFlowLogName.ToUpper())/y=$($logTime.Year)/m=$(($logTime).ToString("MM"))/d=$(($logTime).ToString("dd"))/h=$(($logTime).ToString("HH"))/m=$(($logTime).ToString("mm"))/macAddress=$($macAddress)/PT1H.json"
    # }
    # Gets the storage blog
    write-host "Get-AzStorageBlob -Context $ctx -Container $ContainerName -Blob $BlobName" -ForegroundColor Cyan
    $Blob = Get-AzStorageBlob -Context $ctx -Container $ContainerName -Blob $BlobName
    write-host "blob: $($Blob | convertto-json)" -ForegroundColor Green
    # Gets the block blog of type 'Microsoft.Azure.Storage.Blob.CloudBlob' from the storage blob
    $CloudBlockBlob = [Microsoft.Azure.Storage.Blob.CloudBlockBlob[]] @($Blob.ICloudBlob)

    #Return the Cloud Block Blob
    return $CloudBlockBlob
}

function Get-VNetFlowLogBlockList([Microsoft.Azure.Storage.Blob.CloudBlockBlob] [Parameter(Mandatory = $true)] $CloudBlockBlob) {
    # https://learn.microsoft.com/en-us/azure/network-watcher/flow-logs-read?tabs=vnet
    # Stores the block list in a variable from the block blob.
    $blockList = $CloudBlockBlob.DownloadBlockListAsync()

    # Return the Block List
    return $blockList
}

function Get-VNetFlowLogReadBlock(
    [System.Array] [Parameter(Mandatory = $true)] $blockList,
    [Microsoft.Azure.Storage.Blob.CloudBlockBlob] [Parameter(Mandatory = $true)] $CloudBlockBlob
) {
    $blocklistResult = $blockList.Result
    
    # Set the size of the byte array to the largest block
    $maxvalue = ($blocklistResult | Measure-Object Length -Maximum).Maximum
    write-verbose "Max value is ${maxvalue}"

    # Create an array to store values in
    $valuearray = @()

    # Define the starting index to track the current block being read
    $index = 0

    # Loop through each block in the block list
    for ($i = 0; $i -lt $blocklistResult.count; $i++) {
        # Create a byte array object to story the bytes from the block
        $downloadArray = New-Object -TypeName byte[] -ArgumentList $maxvalue

        # Download the data into the ByteArray, starting with the current index, for the number of bytes in the current block. Index is increased by 3 when reading to remove preceding comma.
        write-verbose "`$CloudBlockBlob.DownloadRangeToByteArray(`$downloadArray, 0, $index, $($blockListResult[$i].Length)) `$i:$i"
        [void]$CloudBlockBlob.DownloadRangeToByteArray($downloadArray, 0, $index, $($blockListResult[$i].Length))

        # trim null bytes
        $downloadArray = $downloadArray | Where-Object { $_ -ne 0 }
        # Increment the index by adding the current block length to the previous index
        $index = $index + $blockListResult[$i].Length

        # Retrieve the string from the byte array

        $value = [System.Text.Encoding]::ASCII.GetString($downloadArray)

        # Add the log entry to the value array
        $valuearray += $value
    }
    #Return the Array
    return $valuearray
}

function modify-flowLog() {
    if (!$storageAccountName -and !$logAnalyticsWorkspaceName) {
        Write-Warning "storage account name or log analytics workspace name is required."
        return
    }

    if (!$vnetName) {
        Write-Warning "resource group and vnet name are required."
        return
    }        
    
    write-host "Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName" -ForegroundColor Cyan
    $storageaccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName
    write-host "storageaccount: $($storageaccount | convertto-json -depth 3)" -ForegroundColor Green
    if ($logRetentionInDays -gt 0 -and $storageaccount.kind -ne "StorageV2") {
        write-host "storage account kind must be StorageV2 for log retention or set logRetentionInDays = 0" -ForegroundColor Red
        return
    }
        
    write-host "Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName" -ForegroundColor Cyan
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName
    write-host "vnet: $($vnet | convertto-json -depth 3)" -ForegroundColor Green

    write-host "Get-AzNetworkWatcher -ResourceGroupName $networkWatcherResourceGroupName -Name $networkWatcherName" -ForegroundColor Cyan
    $networkwatcher = Get-AzNetworkWatcher -ResourceGroupName $networkWatcherResourceGroupName -Name $networkWatcherName
    write-host "networkwatcher: $($networkwatcher | convertto-json -depth 3)" -ForegroundColor Green
    
    if ($currentFlowLog) {
        write-host "flow log already exists. updating flow log" -ForegroundColor Yellow
        write-host "current flow log: $($currentFlowLog | convertto-json -depth 3)" -ForegroundColor Yellow
    }
    else {
        write-host "flow log does not exist. creating flow log"
    }

    if ($logAnalyticsWorkspaceName) {
        if (!(Get-AzResourceProvider -ProviderNamespace Microsoft.Insights)) {
            write-host "Register-AzResourceProvider -ProviderNamespace Microsoft.Insights" -ForegroundColor Cyan
            Register-AzResourceProvider -ProviderNamespace Microsoft.Insights
        }

        $error.clear()
        write-host "Get-AzOperationalInsightsWorkspace -Name $logAnalyticsWorkspaceName -ResourceGroupName $resourceGroupName" -ForegroundColor Cyan
        $workspace = Get-AzOperationalInsightsWorkspace -Name $logAnalyticsWorkspaceName -ResourceGroupName $resourceGroupName

        if ($error -and $location) {
            write-host "workspace not found. creating workspace"
            $workspace = New-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName `
                -Name $logAnalyticsWorkspaceName 
            -Location $location
        }
        elseif ($error) {
            write-host "workspace not found. exiting"
            return
        }

        Write-Host "Set-AzNetworkWatcherFlowLog ``
            -Enabled:`$$($enable.IsPresent) ``
            -Name $flowLogName ``
            -NetworkWatcherName $($networkwatcher.Name) ``
            -ResourceGroupName $networkWatcherResourceGroupName ``
            -StorageId $($storageaccount.Id) ``
            -TargetResourceId $($vnet.Id) ``
            -EnableTrafficAnalytics ``
            -TrafficAnalyticsWorkspaceId $($workspace.ResourceId) ``
            -TrafficAnalyticsInterval 10 ``
            -EnableRetention:`$$($logRetentionInDays -gt 0) ``
            -RetentionPolicyDays $logRetentionInDays ``
            -Force:`$$force
        " -ForegroundColor Cyan

        $setFlowLog = Set-AzNetworkWatcherFlowLog -Enabled:$($enable.IsPresent) `
            -Name $flowLogName `
            -NetworkWatcherName $networkwatcher.Name `
            -ResourceGroupName $networkWatcherResourceGroupName `
            -StorageId $storageaccount.Id `
            -TargetResourceId $vnet.Id `
            -EnableTrafficAnalytics `
            -TrafficAnalyticsWorkspaceId $workspace.ResourceId `
            -TrafficAnalyticsInterval 10 `
            -EnableRetention:($logRetentionInDays -gt 0) ``
        -RetentionPolicyDays $logRetentionInDays ``
        -Force:$force
    }
    else {
        Write-Host "Set-AzNetworkWatcherFlowLog ``
            -Enabled:`$$($enable.IsPresent) ``
            -Name $flowLogName ``
            -NetworkWatcherName $($networkwatcher.Name) ``
            -ResourceGroupName $networkWatcherResourceGroupName ``
            -StorageId $($storageaccount.Id) ``
            -TargetResourceId $($vnet.Id) ``
            -EnableRetention:`$$($logRetentionInDays -gt 0) ``
            -RetentionPolicyDays $logRetentionInDays ``
            -Force:`$$force
        " -ForegroundColor Cyan

        $setFlowLog = Set-AzNetworkWatcherFlowLog -Enabled:$enable.IsPresent `
            -Name $flowLogName `
            -NetworkWatcherName $networkwatcher.Name `
            -ResourceGroupName $networkWatcherResourceGroupName `
            -StorageId $storageaccount.Id `
            -TargetResourceId $vnet.Id `
            -EnableRetention:($logRetentionInDays -gt 0) `
            -RetentionPolicyDays $logRetentionInDays `
            -Force:$force
    }

    if ($error -or !$setFlowLog) {
        write-host "error setting flow log $($error | out-string)" -ForegroundColor Red
        return $null
    }
    write-host "setFlowLog: $($setFlowLog | convertto-json -depth 3)" -ForegroundColor Green

    return $setFlowLog
}

function parse-flowTuple([string]$flowTuple, [string]$hostMacAddress) {
    $tuple = $flowTuple.split(',')

    $parsedFlowTuple = [ordered]@{
        TimeStamp                        = ([System.DateTimeOffset]::FromUnixTimeMilliseconds($tuple[0])).toString('o')
        HostMacAddress                   = $hostMacAddress
        SourceIP                         = $tuple[1]
        DestinationIP                    = $tuple[2]
        SourcePort                       = $tuple[3]
        DestinationPort                  = $tuple[4]
        Protocol                         = switch ($tuple[5]) {
            '6' { 'TCP' }
            '17' { 'UDP' }
            default { 'Unknown' }
        }
        FlowDirection                    = switch ($tuple[6]) {
            'I' { 'Inbound' }
            'O' { 'Outbound' }
            default { 'Unknown' }
        }
        FlowState                        = switch ($tuple[7]) {
            'B' { 'Begin' }
            'C' { 'Continuing' }
            'E' { 'End' }
            'D' { 'Denied' }
            default { 'Unknown' }
        }
        FlowEncryption                   = switch ($tuple[8]) {
            'X' { 'Encrypted' }
            'NX' { 'Unencrypted' }
            'NX_HW_NOT_SUPPORTED' { 'Unsupported Hardware' }
            'NX_SW_NOT_READY' { 'Software not ready' }
            'NX_NOT_ACCEPTED' { 'Drop due to no encryption' }
            'NX_NOT_SUPPORTED' { 'Discovery not supported' }
            'NX_LOCAL_DST' { 'Destination on same host' }
            'NX_FALLBACK' { 'Fallback to no encryption' }
            default { 'Unknown' }
        }
        PacketsFromSourceToDestination   = $tuple[9]
        BytesSentFromSourceToDestination = $tuple[10]
        PacketsFromDestinationToSource   = $tuple[11]
        BytesSentFromDestinationToSource = $tuple[12]
    }
    return $parsedFlowTuple
}

function save-flowTuple($flowLogFileName, $parsedFlowTuple) {
    $global:sortedFlowTuple = $parsedFlowTuple | sort-object { $psitem.TimeStamp -as [datetime] }
    write-host "`$global:sortedFlowTuple | export-csv -Path $flowLogFileName.csv -NoTypeInformation" -ForegroundColor Cyan
    $csvFileName = "$flowLogFileName.csv"
    $global:sortedFlowTuple | export-csv -Path $csvFileName -NoTypeInformation
    return $csvFileName
}

function summarize-flowLog($flowLogFileName) {
    write-host "get-content $flowLogFileName | convertfrom-json" -ForegroundColor Cyan
    $parsedFlowTuple = [collections.arrayList]::new()
    $flow = get-content $flowLogFileName | convertfrom-json
    foreach ($record in $flow.records) {
        $hostMacAddress = ''
        if ($record.macAddress -ne $null) {
            $hostMacAddress = $record.macAddress
        }
        foreach ($flowRecord in $record.flowRecords.flows) {
            foreach ($flowGroup in $flowRecord.flowGroups) {
                foreach ($flowTuple in $flowGroup.flowTuples) {
                    write-verbose "flow tuple:$flowTuple"
                    [void]$parsedFlowTuple.Add((parse-flowTuple -flowTuple $flowTuple -hostMacAddress $hostMacAddress))
                    write-verbose "parsed flow tuple:$($parsedFlowTuple | convertto-json -depth 3)"
                }
            }
        }
    }

    return save-flowTuple -flowLogFileName $flowLogFileName -parsedFlowTuple $parsedFlowTuple
    # $global:sortedFlowTuple = $parsedFlowTuple | sort-object { $psitem.TimeStamp -as [datetime]}
    # write-host "`$parsedFlowTuple | export-csv -Path $flowLogFileName.csv -NoTypeInformation" -ForegroundColor Cyan
    # $global:sortedFlowTuple | export-csv -Path "$flowLogFileName.csv" -NoTypeInformation
}

main
