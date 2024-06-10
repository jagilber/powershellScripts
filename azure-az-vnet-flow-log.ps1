<#
.SYNOPSIS
    powershell script to enable vnet flow logs on azure vnet

.DESCRIPTION

    This script enables flow logs on a virtual network. Flow logs capture information about the IP traffic to and from network interfaces in a virtual network.
    requires az modules to be installed.
    requires at least powershell 7.4.0
    requires storage account or log analytics workspace to store flow logs.
    requires network watcher to be enabled in region.
    requires virtual network to be monitored.

    Feature	Free units included	Price
    Network flow logs collected1	5 GB per month	$0.50 per GB

    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-vnet-flow-log.ps1" -outFile "$pwd\azure-az-vnet-flow-log.ps1"
    .\azure-az-vnet-flow-log.ps1 -examples

    https://learn.microsoft.com/en-us/azure/network-watcher/vnet-flow-logs-overview
    https://learn.microsoft.com/en-us/azure/network-watcher/flow-logs-read?tabs=vnet\

    We recommend disabling network security group flow logs before enabling virtual network flow logs on the same underlying workloads to avoid duplicate traffic recording and additional costs.
    If you enable network security group flow logs on the network security group of a subnet, then you enable virtual network flow logs on the same subnet or parent virtual network,
    you might get duplicate logging (both network security group flow logs and virtual network flow logs generated for all supported workloads in that particular subnet).
    
    Microsoft Privacy Statement: https://privacy.microsoft.com/en-US/privacystatement
    MIT License
    Copyright (c) Microsoft Corporation. All rights reserved.
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE

.NOTES
   File Name  : azure-az-vnet-flow-log.ps1
   Author     : jagilber
   Version    : 240510
   History    :

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-vnet-flow-log.ps1" -outFile "$pwd\azure-az-vnet-flow-log.ps1";
    .\azure-az-vnet-flow-log.ps1 -examples

.EXAMPLE
    .\azure-az-vnet-flow-log.ps1 -resourceGroupName "samoham-eastus2euap-rg" `
        -flowLogName "FLRUNNERSFLOWLOG" `
        -vnetName "flrunnersVnet" `
        -storageAccountName "flrunnersstorage" `
        -location "eastus2euap" `
        -enable
    enable flow log

.EXAMPLE
    .\azure-az-vnet-flow-log.ps1 -resourceGroupName "samoham-eastus2euap-rg" `
        -networkWatcherName "NETWORKWATCHER_EASTUS2EUAP" `
        -flowLogName "FLRUNNERSFLOWLOG" `
        -vnetName "flrunnersVnet" `
        -storageAccountName "flrunnersstorage" `
        -disable
    disable flow log

.EXAMPLE
    .\azure-az-vnet-flow-log.ps1 -resourceGroupName "samoham-eastus2euap-rg" `
        -flowLogName "FLRUNNERSFLOWLOG" `
        -vnetName "flrunnersVnet" `
        -storageAccountName "flrunnersstorage" `
        -get
    get flow log

.EXAMPLE
    .\azure-az-vnet-flow-log.ps1 -resourceGroupName "samoham-eastus2euap-rg" `
        -flowLogName "FLRUNNERSFLOWLOG" `
        -vnetName "flrunnersVnet" `
        -storageAccountName "flrunnersstorage" `
        -location "eastus2euap" `
        -macAddress "6045BD7431F1" `
        -get
    get flow log for mac address

.EXAMPLE
    .\azure-az-vnet-flow-log.ps1 -resourceGroupName "samoham-eastus2euap-rg" `
        -flowLogName "FLRUNNERSFLOWLOG" `
        -vnetName "flrunnersVnet" `
        -storageAccountName "flrunnersstorage" `
        -remove
    remove flow log

.EXAMPLE
    .\azure-az-vnet-flow-log.ps1 `
        -resourceGroupName <cluster resource group> `
        -vnetResourceGroupName SFC_<cluster id> `
        -vnetName <vnet name>`
        -storageAccountName * `
        -logAnalyticsWorkspaceName * `
        -logRetentionInDays 10 `
        -enable 

    enable flow log with new generated storage account and log analytics workspace for service fabric managed cluster

.EXAMPLE
    $global:sortedFlowTuple | ? FlowState -ieq 'denied'
    to review output for denied traffic

.EXAMPLE
    $global:sortedFlowTuple | group SourceIP,DestinationIP
    group and count by ip address

.EXAMPLE
    example steps to enable flow log for capture and analysis with existing / new storage account by name.
    storage account and log analytics workspace names are not removed.

    enable flow log
        .\azure-az-vnet-flow-log.ps1 -resourceGroupName <vnet resource group name> `
            -vnetName <vnet name> `
            -storageAccountName <storage account name> `
            -enable
    reproduce traffic
    download flow log
        .\azure-az-vnet-flow-log.ps1 -resourceGroupName <vnet resource group name> `
            -vnetName <vnet name> `
            -storageAccountName <storage account name> `
            -get `
            -merge
    remove flow log
        .\azure-az-vnet-flow-log.ps1 -resourceGroupName <vnet resource group name> `
            -vnetName <vnet name> `
            -storageAccountName <storage account name> `
            -remove

.EXAMPLE
    example steps to enable flow log for capture and analysis with new generated storage account and new generated log analytics workspace.
    storage account and log analytics workspace names are not removed.
    
    enable flow log
        .\azure-az-vnet-flow-log.ps1 -resourceGroupName <vnet resource group name> `
            -vnetName <vnet name> `
            -storageAccountName * `
            -logAnalyticsWorkspaceName * `
            -enable
    reproduce traffic
    download flow log
        .\azure-az-vnet-flow-log.ps1 -resourceGroupName <vnet resource group name> `
            -vnetName <vnet name> `
            -storageAccountName * `
            -logAnalyticsWorkspaceName * `
            -get `
            -merge
    remove flow log
        .\azure-az-vnet-flow-log.ps1 -resourceGroupName <vnet resource group name> `
            -vnetName <vnet name> `
            -storageAccountName * `
            -logAnalyticsWorkspaceName * `
            -remove

.PARAMETER resourceGroupName
    resource group name

.PARAMETER networkWatcherName
    network watcher name

.PARAMETER networkwatcherResourceGroupName
    network watcher resource group name

.PARAMETER flowLogName
    flow log name

.PARAMETER vnetName
    vnet name

.PARAMETER vnetResourceGroupName
    vnet resource group name

.PARAMETER storageAccountName
    storage account name

.PARAMETER storageResourceGroupName
    storage account resource group name

.PARAMETER logAnalyticsWorkspaceName
    log analytics workspace name

.PARAMETER logAnalyticsResourceGroupName
    log analytics workspace resource group name

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
[CmdletBinding()]
param(
    # [Parameter(Mandatory = $true)]
    [string]$resourceGroupName,
    [string]$vnetName = 'VNet',
    [string]$vnetResourceGroupName = $resourceGroupName,
    # [Parameter(Mandatory = $true)]
    [string]$storageAccountName,
    [string]$storageResourceGroupName = $resourceGroupName,
    [string]$networkwatcherResourceGroupName = 'NetworkWatcherRG', #$resourceGroupName,
    [string]$flowLogName = $vnetName + 'FlowLog',
    [string]$flowLogJson = "$pwd\flowLog.json",
    [string]$subscriptionId, # = (get-azContext).Subscription.Id,
    [string]$location,
    [string]$networkwatcherName = '*', # = 'NetworkWatcher_' + $script:location,
    [string]$logAnalyticsWorkspaceName,
    [string]$logAnalyticsResourceGroupName = $resourceGroupName,
    [string]$macAddress = '*',
    [datetime]$logTime = (get-date),
    [int]$logRetentionInDays = 0, # 0 to disable log retention
    [switch]$enable,
    [switch]$create,
    [switch]$disable,
    [switch]$get,
    [switch]$remove,
    [switch]$examples,
    [switch]$force,
    [switch]$merge
)

Set-StrictMode -Version Latest
$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'continue'
$scriptName = "$psscriptroot\$($MyInvocation.MyCommand.Name)"
$global:sortedFlowTuple = $null
$script:storageResourceGroup = $storageResourceGroupName
$script:laResourceGroup = $logAnalyticsResourceGroupName
$script:networkwatcherName = $networkwatcherName
$script:nwResourceGroup = $networkwatcherResourceGroupName
$script:location = $location
$script:logAnalyticsWorkspaceName = $logAnalyticsWorkspaceName
$script:storageAccountName = $storageAccountName
$script:subscriptionId = $subscriptionId
$script:vnetResourceGroup = $vnetResourceGroupName

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

        if ($create -or $enable -or $disable) {
            if (!(modify-flowLog)) {
                return
            }
            $currentFlowLog = get-flowLog
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
                write-host "merged flow log saved to $csvFileName" -ForegroundColor Magenta
            }
            write-host "finished. results in:`$global:sortedFlowTuple" -ForegroundColor Green
        }
        elseif ($get) {
            write-host "flow log not found" -ForegroundColor Yellow
        }

        if ($remove -and $currentFlowLog) {
            # $script:flowLogResourceGroup = get-resourceGroup -ResourceName $script:networkwatcherName -ResourceType 'Microsoft.Network/networkWatchers'
            write-host "Remove-AzNetworkWatcherFlowLog -Name $flowLogName -NetworkWatcherName $($script:networkwatcherName) -ResourceGroupName $script:nwResourceGroup" -ForegroundColor Yellow
            Remove-AzNetworkWatcherFlowLog -Name $flowLogName -NetworkWatcherName $script:networkwatcherName -ResourceGroupName $script:nwResourceGroup
            $currentFlowLog = get-flowLog
        }
        elseif ($remove) {
            write-host "flow log not found" -ForegroundColor Yellow
        }
    }
    catch {
        write-verbose "variables:$((get-variable -scope local).value | convertto-json -WarningAction SilentlyContinue -depth 2)"
        write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
        return 1
    }
    finally {
        if ($currentFlowLog) {
            if ($currentFlowLog.enabled) {
                write-warning "flow log enabled. to prevent unnecessary charges, disable flow log when not in use using -disable switch"
            }
        }
    }
}

function check-arguments() {


    if (!$resourceGroupName) {
        write-warning "resource group name is required."
        return $false
    }

    if (!$vnetName) {
        write-warning "vnet name is required."
        return $false
    }

    if (!(check-module)) {
        return $false
    }

    if (!$script:subscriptionId) {
        $script:subscriptionId = (get-azContext).Subscription.Id

        if (!$script:subscriptionId) {
            write-warning "subscription id is required."
            return $false
        }
        write-host "setting subscription id: $script:subscriptionId" -ForegroundColor Cyan
    }

    if (!$script:location) {
        $script:location = (Get-AzResourceGroup -Name $resourceGroupName).Location
        write-host "setting location: $script:location" -ForegroundColor Cyan
    }
    if (!$script:location) {
        write-warning "location is required."
        return $false
    }

    if (!$flowLogName) {
        write-warning "flow log name is required with -flowLogName argument. To create a new flow log, use -flowLogName with name of new flow log."
        return $false
    }

    if (!$script:storageAccountName) {
        write-warning "storage account name is required. To create a new storage account, use -storageAccountName with name of new storage account or use '*' to generate."
        return
    }

    if ($enable -and $disable) {
        write-warning "enable and disable switches are mutually exclusive."
        return $false
    }

    if ($get -and $remove) {
        write-warning "get and remove switches are mutually exclusive."
        return $false
    }

    if (($enable -or $disable) -and ($get -or $remove)) {
        write-warning "enable/disable and get/remove switches are mutually exclusive."
        return $false
    }

    if (!(check-logAnalytics)) {
        Write-Warning "log analytics workspace not configured/found. To create a new log analytics workspace, use -logAnalyticsWorkspaceName with name of new workspace or use '*' to generate."
        # return $false
    }

    if (!(check-storage)) {
        return $false
    }

    if (!(check-networkWatcher)) {
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

function check-logAnalytics() {
    if (!$script:logAnalyticsWorkspaceName -and $script:logAnalyticsWorkspaceName -ne "*") {
        write-warning "log analytics workspace not provided."
        return $false
    }
    if ($script:logAnalyticsWorkspaceName -eq "*") {
        $script:logAnalyticsWorkspaceName = 'flow' + $resourceGroupName
        write-warning "generated log analytics workspace name: $script:logAnalyticsWorkspaceName"
    }
    $laResourceGroup = get-resourceGroup -ResourceName $script:logAnalyticsWorkspaceName -ResourceType 'Microsoft.OperationalInsights/workspaces' -resourceGroup $script:laResourceGroup
    if (!$laResourceGroup) {
        write-warning "log analytics workspace resource group not found for $script:logAnalyticsWorkspaceName. getting log analytics workspace resource group."
        $continue = read-host "do you want to create a new log analytics workspace named $script:logAnalyticsWorkspaceName in $script:laResourceGroup in $($script:location)?[y|n]"
        if ($continue -imatch "y") {
            $error.clear()
            write-host "New-AzOperationalInsightsWorkspace -ResourceGroupName $script:laResourceGroup -Name $script:logAnalyticsWorkspaceName -Location $script:location" -ForegroundColor Cyan
            $logAnalyticsWorkspace = New-AzOperationalInsightsWorkspace -ResourceGroupName $script:laResourceGroup -Name $script:logAnalyticsWorkspaceName -Location $script:location
            # $script:laResourceGroup = $resourceGroupName
            if ($error -or !$logAnalyticsWorkspace) {
                Write-Error "error creating log analytics workspace:$($error | out-string)"
                return $false
            }
            else {
                write-host "log analytics workspace created" -ForegroundColor Green
            }
        }
        else {
            write-host "log analytics workspace resource group not found. exiting" -ForegroundColor Red
            return $false
        }
    }
    else {
        write-host "log analytics workspace resource group found" -ForegroundColor Green
        $script:laResourceGroup = $laResourceGroup
    }
    return $true
}

function check-networkWatcher() {
    if (!$script:networkwatcherName -and $script:networkwatcherName -ne "*") {
        write-warning "network watcher name not provided."
        return $false
    }
    if ($script:networkwatcherName -eq "*") {
        $script:networkwatcherName = 'NetworkWatcher_' + $script:location
        write-warning "generated network watcher name: $script:networkwatcherName"
    }
    $nwResourceGroup = get-resourceGroup -ResourceName $script:networkwatcherName -ResourceType 'Microsoft.Network/networkWatchers'
    if (!$nwResourceGroup) {
        if(!(Get-AzResourceGroup -ResourceGroupName $script:nwResourceGroup)) {
            write-warning "network watcher resource group not found. creating"
            write-host "New-AzResourceGroup -Name $script:nwResourceGroup -Location $script:location" -ForegroundColor Cyan
            New-AzResourceGroup -Name $script:nwResourceGroup -Location $script:location
        }
        write-warning "network watcher resource group not found for $($script:networkwatcherName). getting network watcher resource group."
        $continue = read-host "do you want to create a new network watcher named $($script:networkwatcherName) in $script:nwResourceGroup in $($script:location)?[y|n]"
        if ($continue -imatch "y") {
            $error.clear()
            write-host "New-AzNetworkWatcher -ResourceGroupName $script:nwResourceGroup -Name $script:networkwatcherName -Location $script:location" -ForegroundColor Cyan
            $networkwatcher = New-AzNetworkWatcher -ResourceGroupName $script:nwResourceGroup -Name $script:networkwatcherName -Location $script:location
            # $script:flowLogResourceGroup = $resourceGroupName
            if ($error -or !$networkwatcher) {
                write-error "error creating network watcher:$($error | out-string)"
                return $false
            }
            else {
                write-host "network watcher created" -ForegroundColor Green
            }
        }
        else {
            write-host "network watcher resource group not found. exiting" -ForegroundColor Red
            return $false
        }
    }
    else {
        write-host "network watcher resource group found" -ForegroundColor Green
        $script:nwResourceGroup = $nwResourceGroup
    }
    return $true
}

function check-storage() {
    if (!$script:storageAccountName -and $script:storageAccountName -ne "*") {
        write-warning "storage account name not provided."
        return $false
    }
    if ($script:storageAccountName -eq "*") {
        $base64String = [convert]::toBase64String([text.encoding]::UTF8.GetBytes($resourceGroupName)).tolower().substring(0, 20) -replace '[^a-z0-9]', ''
        $script:storageAccountName = [string]::join('', @('flow', $base64String))
        write-warning "generated storage account name: $script:storageAccountName"
    }
    $storageResourceGroup = get-resourceGroup -ResourceName $script:storageAccountName -ResourceType 'Microsoft.Storage/storageAccounts' -resourceGroup $script:storageResourceGroup
    if (!$storageResourceGroup) {
        write-warning "storage account resource group not found for $script:storageAccountName. getting storage account resource group."
        $continue = read-host "do you want to create a new storage account named $script:storageAccountName in $script:storageResourceGroup in $($script:location)?[y|n]"
        if ($continue -imatch "y") {
            $error.clear()
            write-host "New-AzStorageAccount -ResourceGroupName $script:storageResourceGroup -Name $script:storageAccountName -Location $script:location -SkuName Standard_LRS -Kind StorageV2" -ForegroundColor Cyan
            $storageaccount = New-AzStorageAccount -ResourceGroupName $script:storageResourceGroup -Name $script:storageAccountName -Location $script:location -SkuName Standard_LRS -Kind StorageV2
            # $script:storageResourceGroup = $resourceGroupName
            if ($error -or !$storageaccount) {
                write-error "error creating storage account:$($error | out-string)"
                return $false
            }
            else {
                write-host "storage account created" -ForegroundColor Green
            }
        }
        else {
            write-host "storage account resource group not found. exiting" -ForegroundColor Red
            return $false
        }
    }
    return $true
}


function download-flowLog($currentFlowLog) {
    $flowLog = $currentFlowLog
    $flowLogFileNames = @()

    if ($flowLog) {
        write-host "flow log stored in global variable: `$flowLog" -ForegroundColor Magenta
        $global:blockBlobs = @(Get-VNetFlowLogCloudBlockBlob -subscriptionId $script:subscriptionId `
                -region $script:location `
                -VNetFlowLogName $flowLogName `
                -storageAccountName $script:storageAccountName `
                -storageAccountResourceGroup $script:storageResourceGroup `
                -macAddress $macAddress `
                -logTime $universalTime)

        foreach ($blockBlob in $global:blockBlobs) {
            write-verbose "blockBlob: $($blockBlob | convertto-json -WarningAction SilentlyContinue -depth 3)"

            $global:blockList = @(Get-VNetFlowLogBlockList -CloudBlockBlob $blockBlob)
            Write-Verbose "blockList: $($global:blockList | convertto-json -WarningAction SilentlyContinue -depth 3)"

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

function generate-fileName($fileName, $identifier = "") {
    $flowLogFileName = [io.path]::GetFileNameWithoutExtension($fileName)
    $flowLogFilePath = [io.path]::GetDirectoryName($fileName)
    $flowLogFileNameExt = [io.path]::GetExtension($fileName)

    if ($identifier) {
        $name = "$($flowLogFilePath)/$($flowLogFileName)_$($identifier)_$($universalTime.ToString("yyyyMMddHHmm"))$flowLogFileNameExt"
    }
    else {
        $name = "$($flowLogFilePath)/$($flowLogFileName)_$($universalTime.ToString("yyyyMMddHHmm"))$flowLogFileNameExt"
    }

    $name = $name.replace('\','/')
    return $name
}

function get-flowLog() {
    write-host "Get-AzNetworkWatcherFlowLog -Name $flowLogName -NetworkWatcherName $script:networkwatcherName -ResourceGroupName $script:nwResourceGroup -ErrorAction SilentlyContinue" -ForegroundColor Cyan
    $currentFlowLog = Get-AzNetworkWatcherFlowLog -Name $flowLogName -NetworkWatcherName $script:networkwatcherName -ResourceGroupName $script:nwResourceGroup -ErrorAction SilentlyContinue
    if ($currentFlowLog) {
        write-host "current flow log: $($currentFlowLog | convertto-json -WarningAction SilentlyContinue -depth 3)" -ForegroundColor Yellow
    }
    else {
        write-host "flow log not found" -ForegroundColor Yellow
    }
    return $currentFlowLog
}

function get-vnet() {
    $script:vnetResourceGroup = get-resourceGroup -ResourceName $vnetName -ResourceType 'Microsoft.Network/virtualNetworks' -resourceGroup $script:vnetResourceGroup
    if (!$script:vnetResourceGroup) {
        write-host "vnet resource group not found. exiting" -ForegroundColor Red
        return $false
    }
    write-host "Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $script:vnetResourceGroup -ErrorAction SilentlyContinue" -ForegroundColor Cyan
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $script:vnetResourceGroup -ErrorAction SilentlyContinue
    if ($vnet) {
        write-host "vnet found: $($vnet | convertto-json -WarningAction SilentlyContinue -depth 3)" -ForegroundColor Yellow
    }
    else {
        write-host "vnet not found" -ForegroundColor Yellow
    }
    return $vnet

}

function get-resourceGroup($resourceName, $resourceType, $resourceGroupName = $null) {
    write-host "get-azresource -ResourceName $resourceName -ResourceType '$resourceType' -ResourceGroupName $resourceGroupName" -ForegroundColor Cyan
    $resourceGroup = $null
    if ($resourceGroupName) {
        $resourceGroups = @(get-azresource -ResourceName $resourceName -ResourceType $resourceType -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue)
    }
    else {
        $resourceGroups = @(get-azresource -ResourceName $resourceName -ResourceType $resourceType -ErrorAction SilentlyContinue)
    }

    if (!$resourceGroups -and $resourceGroupName) {
        write-host "resource not found in resource group $resourceGroupName. searching without resource group" -ForegroundColor Red
        $resourceGroup = get-resourceGroup -ResourceName $resourceName -ResourceType $resourceType
    }
    
    if ($resourceGroups -and $resourceGroups.Count -eq 1) {
        $resourceGroup = $resourceGroups[0].ResourceGroupName
    }
    else {
        write-host "resource group not found" -ForegroundColor Red
    }
    write-host "returning resourceGroup: $resourceGroup"
    return $resourceGroup
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

    # Gets the storage blog
    write-host "Get-AzStorageBlob -Context $ctx -Container $ContainerName -Blob $BlobName" -ForegroundColor Cyan
    $Blob = Get-AzStorageBlob -Context $ctx -Container $ContainerName -Blob $BlobName
    write-verbose "blob: $($Blob | convertto-json -WarningAction SilentlyContinue)"
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

    $vnet = get-vnet
    write-host "Get-AzNetworkWatcher -Name $script:networkwatcherName" -ForegroundColor Cyan
    $networkwatcher = Get-AzNetworkWatcher -Name $script:networkwatcherName
    write-host "networkwatcher: $($networkwatcher | convertto-json -WarningAction SilentlyContinue -depth 3)" -ForegroundColor Green

    if ($currentFlowLog) {
        write-host "flow log already exists. updating flow log" -ForegroundColor Yellow
        write-host "current flow log: $($currentFlowLog | convertto-json -WarningAction SilentlyContinue -depth 3)" -ForegroundColor Yellow
    }
    else {
        write-host "flow log does not exist. creating flow log"
    }

    write-host "Get-AzStorageAccount -Name $script:storageAccountName -ResourceGroupName $script:storageResourceGroup" -ForegroundColor Cyan
    $storageaccount = Get-AzStorageAccount -Name $script:storageAccountName -ResourceGroupName $script:storageResourceGroup
    write-host "storageaccount: $($storageaccount | convertto-json -WarningAction SilentlyContinue -depth 3)" -ForegroundColor Green
    if ($logRetentionInDays -gt 0 -and $storageaccount.kind -ne "StorageV2") {
        write-host "storage account kind must be StorageV2 for log retention or set logRetentionInDays = 0" -ForegroundColor Red
        return
    }

    if ($script:logAnalyticsWorkspaceName) {
        if (!(Get-AzResourceProvider -ProviderNamespace Microsoft.Insights)) {
            write-host "Register-AzResourceProvider -ProviderNamespace Microsoft.Insights" -ForegroundColor Cyan
            Register-AzResourceProvider -ProviderNamespace Microsoft.Insights
        }

        $error.clear()
        write-host "Get-AzOperationalInsightsWorkspace -Name $script:logAnalyticsWorkspaceName -ResourceGroupName $script:laResourceGroup" -ForegroundColor Cyan
        $workspace = Get-AzOperationalInsightsWorkspace -Name $script:logAnalyticsWorkspaceName -ResourceGroupName $script:laResourceGroup

        if ($error -and $script:location) {
            write-host "workspace not found. creating workspace"
            $workspace = New-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName `
                -Name $script:logAnalyticsWorkspaceName `
                -Location $script:location
        }
        elseif ($error) {
            write-host "workspace not found. exiting"
            return
        }

        Write-Host "Set-AzNetworkWatcherFlowLog ``
            -Enabled:`$$($enable.IsPresent) ``
            -Name $flowLogName ``
            -NetworkWatcherName $($networkwatcher.Name) ``
            -ResourceGroupName $script:nwResourceGroup ``
            -StorageId $($storageaccount.Id) ``
            -TargetResourceId $($vnet.Id) ``
            -EnableTrafficAnalytics:`$$($enable.IsPresent) ``
            -TrafficAnalyticsWorkspaceId $($workspace.ResourceId) ``
            -TrafficAnalyticsInterval 10 ``
            -EnableRetention:`$$($logRetentionInDays -gt 0) ``
            -RetentionPolicyDays $logRetentionInDays ``
            -Force:`$$force
        " -ForegroundColor Cyan

        $setFlowLog = Set-AzNetworkWatcherFlowLog -Enabled:$($enable.IsPresent) `
            -Name $flowLogName `
            -NetworkWatcherName $networkwatcher.Name `
            -ResourceGroupName $script:nwResourceGroup `
            -StorageId $storageaccount.Id `
            -TargetResourceId $vnet.Id `
            -EnableTrafficAnalytics:$($enable.IsPresent) `
            -TrafficAnalyticsWorkspaceId $workspace.ResourceId `
            -TrafficAnalyticsInterval 10 `
            -EnableRetention:($logRetentionInDays -gt 0) `
            -RetentionPolicyDays $logRetentionInDays `
            -Force:$force
    }

    else {
        Write-Host "Set-AzNetworkWatcherFlowLog ``
            -Enabled:`$$($enable.IsPresent) ``
            -Name $flowLogName ``
            -NetworkWatcherName $($networkwatcher.Name) ``
            -ResourceGroupName $script:nwResourceGroup ``
            -StorageId $($storageaccount.Id) ``
            -TargetResourceId $($vnet.Id) ``
            -EnableRetention:`$$($logRetentionInDays -gt 0) ``
            -RetentionPolicyDays $logRetentionInDays ``
            -Force:`$$force
        " -ForegroundColor Cyan

        $setFlowLog = Set-AzNetworkWatcherFlowLog -Enabled:$enable.IsPresent `
            -Name $flowLogName `
            -NetworkWatcherName $networkwatcher.Name `
            -ResourceGroupName $script:nwResourceGroup `
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
    write-host "setFlowLog: $($setFlowLog | convertto-json -WarningAction SilentlyContinue -depth 3)" -ForegroundColor Green

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
                    write-verbose "parsed flow tuple:$($parsedFlowTuple | convertto-json -WarningAction SilentlyContinue -depth 3)"
                }
            }
        }
    }

    return save-flowTuple -flowLogFileName $flowLogFileName -parsedFlowTuple $parsedFlowTuple
}

main
