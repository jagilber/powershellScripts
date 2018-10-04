<#
script to query tables in azure blob storage

$sas = "https://sflogsxxxxxxxxxxxxxx.table.core.windows.net/?sv=2017-11-09&ss=bfqt&srt=sco&sp=rwdlacup&se=2018-09-30T09:27:56Z&st=2018-09-30T01:27:56Z&spr=https&sig=4SfN%2Fza0c1CXop6sKQkFf0f8thKDUBYK7xQ%3D"
$storage = "sflogsxxxxxxxxxxxxxx"
.\azure-storage-query-table.ps1 -saskeyTable $sas `
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
    [string]$saskeyTable,
    [string]$storageAccountName,
    [switch]$showDetail,
    [switch]$convertOutputToJson,
    [string]$outputDir,
    [datetime]$startTime = (get-date).AddHours(-24),
    [datetime]$endTime = (get-date),
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
$squeryFilter = [microsoft.windowsazure.storage.table.tablequery]::GenerateFilterConditionForDate("Timestamp", $queryComparison, ($startTime.ToUniversalTime().ToString("o")) )
$queryComparison = [Microsoft.WindowsAzure.Storage.Table.QueryComparisons]::LessThanOrEqual
$equeryFilter = [microsoft.windowsazure.storage.table.tablequery]::GenerateFilterConditionForDate("Timestamp", $queryComparison, ($endTime.ToUniversalTime().ToString("o")) )

$tableOperator = [Microsoft.WindowsAzure.Storage.Table.TableOperators]::And
$queryFilter = [microsoft.windowsazure.storage.table.tablequery]::CombineFilters($squeryFilter,$tableOperator,$equeryFilter)
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
    write-host "query: $($queryFilter)"
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

        $outputFile = "$($outputdir)\$($table.name).records.txt"
        remove-item $outputFile -erroraction silentlycontinue

        if($outputDir -or $showDetail)
        {
            [text.stringbuilder]$sb = new-object text.stringbuilder

            foreach($record in ($tableresults)| sort-object Timestamp)
            {
                [void]$sb.AppendLine("----------------------------")
                [void]$sb.AppendLine("$($record.Timestamp):$($record.PartitionKey):$($record.RowKey)")

                foreach($prop in $record.properties.getenumerator())
                {
                    [void]$sb.AppendLine("`t`t$($prop.Key):$($prop.Value.PropertyAsObject)")
                }    

                if($outputdir)
                {
                    out-file -append -inputobject ($sb.tostring()) -encoding ascii -filepath $outputFile
                }

                if($showDetail)
                {
                    write-host ($sb.ToString())
                }

                [void]$sb.Clear()
           }
        }
      
    }

   $global:allTableResults += $tableresults
}

if($convertOutputToJson)
{
    write-host "converting to json..." -ForegroundColor Yellow
    $global:allTableJson = (convertto-json ($global:allTableResults) -Depth 3)
    $outputFile = "$($outputdir)\alltableevents.json"
    $global:allTableJson | out-file -encoding ascii -filepath $outputFile
    write-host "`noutput json stored in `$global:allTableJson and $($outputFile)" -ForegroundColor Magenta
}

write-host "`noutput object[] stored in `$global:allTableResults" -ForegroundColor Magenta
