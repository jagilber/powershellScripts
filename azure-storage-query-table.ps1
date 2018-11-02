<#

script to query tables in azure blob storage

(new-object net.webclient).downloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-storage-query-table.ps1","$(get-location)\azure-storage-query-table.ps1")

$sas = "https://sflogsxxxxxxxxxxxxxx.table.core.windows.net/?sv=2017-11-09&ss=bfqt&srt=sco&sp=rwdlacup&se=2018-09-30T09:27:56Z&st=2018-09-30T01:27:56Z&spr=https&sig=4SfN%2Fza0c1CXop6sKQkFf0f8thKDUBYK7xQ%3D"

.\azure-storage-query-table.ps1 -saskeyTable $sas `
    -outputDir f:\cases\0000000000001\tables `
    -noDetail `
    -startTime ((get-date).AddDays(-2)) `
    -endTime ((get-date).AddHours(-12)) `
    -tableName "[^T][^i][^m][^e]$"

.\azure-storage-query-table.ps1 -saskeyTable $sas `
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
    [Parameter(Mandatory = $true)]
    [string]$saskeyTable,
    [switch]$noDetail,
    [switch]$noJson,
    [string]$outputDir, # = (get-location).path,
    [datetime]$startTime = (get-date).AddHours(-24),
    [datetime]$endTime = (get-date),
    [string]$tableName,
    [int]$takecount = 100,
    [string[]]$listColumns
)

$global:allTableResults = $Null
$global:allTableJson = $Null
$global:allTableJsonObject = $Null

if ($outputDir)
{
    new-item -path $outputDir -itemtype directory -erroraction silentlycontinue
}
# Setup storage credentials with SASkey
if ($PSCloudShellUtilityModuleInfo)
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
$storageAccountName = [regex]::Match($accountSASTable.SASToken, "https://(.+?).table.core.windows.net/").Groups[1].Value
$rootTableUrl = "https://$($storageAccountName).table.core.windows.net/"

[microsoft.windowsAzure.storage.table.cloudTableClient]
$cloudTableClient = new-object microsoft.windowsAzure.storage.table.cloudTableClient((new-object Uri($rootTableUrl)), $accountSASTable);
$cloudTableClient

[microsoft.windowsAzure.storage.table.cloudTable]
$cloudTable = new-object microsoft.windowsAzure.storage.table.cloudTable(new-object Uri($saskeyTable));
$cloudTable
$tablesRef = $cloudTable.ServiceClient

[microsoft.windowsAzure.storage.table.queryComparisons]
$queryComparison = [microsoft.windowsAzure.storage.table.queryComparisons]::GreaterThanOrEqual
#$queryFilter = [microsoft.windowsAzure.storage.table.tablequery]::GenerateFilterCondition("PartitionKey", $queryComparison, "x" )
$squeryFilter = [microsoft.windowsAzure.storage.table.tablequery]::GenerateFilterConditionForDate("Timestamp", $queryComparison, ($startTime.ToUniversalTime().ToString("o")) )
$queryComparison = [microsoft.windowsAzure.storage.table.queryComparisons]::LessThanOrEqual
$equeryFilter = [microsoft.windowsAzure.storage.table.tablequery]::GenerateFilterConditionForDate("Timestamp", $queryComparison, ($endTime.ToUniversalTime().ToString("o")) )

$tableOperator = [microsoft.windowsAzure.storage.table.tableOperators]::And
$queryFilter = [microsoft.windowsAzure.storage.table.tablequery]::CombineFilters($squeryFilter, $tableOperator, $equeryFilter)
$global:allTableResults = $null
$global:allTableJson = $null

foreach ($table in $tablesRef.ListTables())
{
    if ($tableName -and (($table.name) -inotmatch $tablename))
    {
        write-host "skipping $($table.name). does not match $($tablename)"
        continue
    }

    write-host "table name:$($table.name)" -ForegroundColor Yellow
    write-host "query: $($queryFilter)"
    $table
    $tableQuery = new-object microsoft.windowsAzure.storage.table.tablequery
    $tableQuery.FilterString = $queryFilter
    $tableQuery.takecount = $takecount

    if ($listColumns)
    {
        $tableQuery.SelectColumns = new-object collections.generic.list[string](, $listColumns)
    }

    [microsoft.windowsAzure.storage.table.tableContinuationToken]
    $token = New-Object microsoft.windowsAzure.storage.table.tableContinuationToken

    while ($token)
    {
    
        $tableResults = $table.ExecuteQuerySegmented($tableQuery, $token, $null, $null)
        $token = $tableResults.continuationtoken
        $recordObjs = new-object collections.arraylist 

        if (!$noDetail -or $outputDir -or !$noJson)
        {
            write-host "table results:$(@($tableResults).Count)" -ForegroundColor Cyan

            if (@($tableResults).Count -lt 1)
            {
                continue
            }

            $outputFile = "$($outputdir)\$($table.name).records.txt"
            remove-item $outputFile -erroraction silentlycontinue

            if ($outputDir -or !$noDetail -or !$noJson)
            {
                [text.stringbuilder]$sb = new-object text.stringbuilder

                foreach ($record in ($tableresults)| sort-object Timestamp)
                {
                    $recordObj = @{}    
                    [void]$sb.AppendLine("$($record.Timestamp):$($record.PartitionKey):$($record.RowKey)")
                    [void]$recordObj.Add("Table", $table.name)
                    [void]$recordObj.Add("EventTimeStamp", $record.Timestamp.ToString())
                    [void]$recordObj.Add("PartitionKey", $record.PartitionKey)
                    [void]$recordObj.Add("RowKey", $record.RowKey)

                    foreach ($prop in $record.properties.getenumerator())
                    {
                        [void]$sb.AppendLine("`t`t$($prop.Key):$($prop.Value.PropertyAsObject)")
                        [void]$recordObj.Add($prop.Key, $prop.Value.PropertyAsObject.ToString().Replace("`"", "\`""))
                    }    

                    if ($outputdir)
                    {
                        out-file -append -inputobject ($sb.tostring()) -encoding ascii -filepath $outputFile
                    }

                    if (!$noDetail)
                    {
                        write-host "----------------------------"
                        write-host ($sb.ToString())
                    }

                    [void]$sb.Clear()

                    if (!$noJson)
                    {
                        $global:allTableJson += "$(ConvertTo-Json -InputObject $recordObj | foreach { [text.regularExpressions.regex]::Unescape($_) }),`r`n"
                    }
                
                    [void]$recordObjs.Add($recordObj)
                }
            }
      
        }

        #$global:allTableResults += $tableresults
        $global:allTableResults += $recordObjs
    }
}

if (!$noJson)
{
    
    # format
    $global:allTableJson = "[`r`n$($global:allTableJson.TrimEnd("`r`n,"))`r`n]"

    if ($outputDir)
    {
        $outputFile = "$($outputdir)\alltableevents.json"
        $global:allTableJson | out-file -encoding ascii -filepath $outputFile
        write-host "output json stored in `$global:allTableJson and $($outputFile)" -ForegroundColor Magenta
    }

    $global:allTableJsonObject = convertfrom-json $global:allTableJson
    write-host "output json object stored in `$global:allTableJsonObject" -ForegroundColor Magenta
    write-host "example queries:"
    write-host "`$global:allTableJsonObject | select table,eventtimestamp,level,message | ? level -lt 4" -ForegroundColor Green
    write-host "`$global:allTableJsonObject | select table,eventtimestamp,level,message | ? message -imatch `"upgrade`"" -ForegroundColor Green
    write-host "`$global:allTableJsonObject | select table,eventtimestamp,level,message | ? message -imatch `"fail`"" -ForegroundColor Green
    write-host "`$global:allTableJsonObject | select table,eventtimestamp,level,message -ExpandProperty message | ? { `$_.message.tolower().contains(`"upgrade`") -and `$_.level -lt 4 }" -ForegroundColor Green
    write-host
    write-host "`$q = `$global:allTableJsonObject | select table,eventtimestamp,level,message -ExpandProperty message | ? message" -ForegroundColor Green
    write-host "`$q -imatch `"fail|error`"" -ForegroundColor Green

}

write-host "`noutput table object[] stored in `$global:allTableResults" -ForegroundColor Magenta

if ($outputDir)
{
    write-host "output files stored in dir $outputDir\*records.txt" -ForegroundColor Magenta
}
else
{
    write-host "use -outputDir to write output to files"
}