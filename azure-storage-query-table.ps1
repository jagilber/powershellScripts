<#
script to query tables in azure blob storage

$sas = "https://sflogsho4nnyxerrwe22.table.core.windows.net/?sv=2017-11-09&ss=bfqt&srt=sco&sp=rwdlacup&se=2018-09-30T09:27:56Z&st=2018-09-30T01:27:56Z&spr=https&sig=4SfN%2Fza0c1CXop6sKwmnUaQIJQkFf0f8thKDUBYK7xQ%3D"
$storage = "sflogsho4nnyxerrwe22"
G:\github\jagilber-pr\serviceFabricInternal\powershellScripts\azure-storage-query-table.ps1 -saskeyTable $sas `
    -storageAccountName $storage `
    -outputDir "f:\cases\000000000000001\storageTables" `
    -starttime ((get-date).Touniversaltime().AddHours(-48)) #`
    #-listColumns Timestamp `
    #-takecount 1000
    #-tablename ops 
    
    $events = $global:allTableResults
    $nodes = $events | where-object {$_.Properties.instanceName -ne $Null}
    $nodes | sort Timestamp |% {write-host "$($_.Timestamp),$($_.Properties.instanceName.PropertyAsObject),$($_.Properties.EventType.PropertyAsObject),$($_.Properties.faultDomain.PropertyAsObject)"} 
#>
param(
    [string]$saskeyTable = "https://sflogsho4nnyxerrwe22.table.core.windows.net/?sv=2017-11-09&ss=bfqt&srt=sco&sp=rwdlacup&se=2018-09-29T21:35:00Z&st=2018-09-29T13:35:00Z&spr=https&sig=9e%2FLcoljDisUIDMskKCf0R7bdyQMn61qq4%2FVX8sOabY%3D",
    [string]$storageAccountName = "sflogsho4nnyxerrwe22",
    [switch]$showDetail,
    [switch]$convertOutputToJson,
    [string]$outputDir,
    [datetime]$startTime = (get-date).AddDays(-7),
    [string]$tableName,
    [int]$takecount = 1000,
    [string[]]$listColumns
)

if($outputDir)
{
    new-item -path $outputDir -itemtype directory -erroraction silentlycontinue
}
# Setup storage credentials with SASkey
if($PSCloudShellUtilityModuleInfo)
{
    throw (new-object NotImplementedException)
    #import-module az.storage
}
else
{
    import-module azure.storage
}

[microsoft.windowsazure.storage.auth.storageCredentials]
$accountSASTable = new-object microsoft.windowsazure.storage.auth.storageCredentials($saskeyTable);

$rootTableUrl = "https://$($storageAccountName).table.core.windows.net/"

[Microsoft.WindowsAzure.Storage.Table.CloudTableClient]
$cloudTableClient = new-object microsoft.windowsazure.storage.table.CloudTableClient((new-object Uri($rootTableUrl)), $accountSASTable);
$cloudTableClient

[Microsoft.WindowsAzure.Storage.Table.CloudTable]
$cloudTable = new-object microsoft.windowsazure.storage.table.CloudTable(new-object Uri($saskeyTable));
$cloudTable
$tablesRef = $cloudTable.ServiceClient

[Microsoft.WindowsAzure.Storage.Table.QueryComparisons]
$queryComparison = [Microsoft.WindowsAzure.Storage.Table.QueryComparisons]::GreaterThanOrEqual
#$queryFilter = [microsoft.windowsazure.storage.table.tablequery]::GenerateFilterCondition("PartitionKey", $queryComparison, "x" )
$queryFilter = [microsoft.windowsazure.storage.table.tablequery]::GenerateFilterConditionForDate("Timestamp", $queryComparison, ($startTime.ToUniversalTime().ToString("o")) )
$global:allTableResults = $null
$global:allTableJson = $null

foreach($table in $tablesRef.ListTables())
{
    if($tableName -and (($table.name) -inotmatch $tablename))
    {
        write-host "skipping $($table.name). does not match $($tablename)"
        continue
    }

    write-host "table name:$($table.name)" -ForegroundColor Yellow
    $table
    $tableQuery = new-object microsoft.windowsazure.storage.table.tablequery
    $tableQuery.FilterString = $queryFilter
    $tableQuery.takecount = $takecount

    if($listColumns)
    {
        $tableQuery.SelectColumns = new-object collections.generic.list[string](,$listColumns)
    }

    $tableResults = $table.ExecuteQuery($tableQuery,$null,$null)
    
    if($showDetail -or $outputDir)
    {
        write-host "table results:$(@($tableResults).Count)" -ForegroundColor Cyan

        if(@($tableResults).Count -lt 1)
        {
            continue
        }
        write-host "converting to json"
        $results = (convertto-json $tableResults -Depth 3)
        
        if($outputDir)
        {
            write-host "writing json to file"
            $results | out-file -encoding ascii "$($outputdir)\$($table.name).json"
            write-host "finished writing json to file"
        }
        
        if($showDetail)
        {
            $results
        }
    }

   $global:allTableResults += $tableresults
}

if($convertOutputToJson)
{
    write-host "converting to json..." -ForegroundColor Yellow
    $global:allTableJson = (convertto-json ($global:allTableResults) -Depth 3)
    write-host "`noutput json stored in `$global:allTableJson" -ForegroundColor Magenta
}

write-host "`noutput object[] stored in `$global:allTableResults" -ForegroundColor Magenta
