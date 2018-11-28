<#
.SYNOPSIS
    powershell script to query tables in azure blob storage

.DESCRIPTION
    powershell script to query tables in azure blob storage.
    results are stored in global objects for further analysis.
    see examples and output.

    quickstart:
    (new-object net.webclient).downloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-storage-query-table.ps1","$(get-location)\azure-storage-query-table.ps1")
    $sas = "https://sflogsxxxxxxxxxxxxxx.table.core.windows.net/?sv=2017-11-09&ss=bfqt&srt=sco&sp=rwdlacup&se=2018-09-30T09:27:56Z&st=2018-09-30T01:27:56Z&spr=https&sig=4SfN%2Fza0c1CXop6sKQkFf0f8thKDUBYK7xQ%3D"
    .\azure-storage-query-table.ps1 -saskeyTable $sas
            
    Copyright 2018 Microsoft Corporation
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    
.NOTES
    File Name  : azure-storage-query-table.ps1
    Author     : jagilber
    Version    : 181102 original
    History    : 
    
.EXAMPLE
    .\azure-storage-query-table.ps1 -saskeyTable $sas `
        -outputDir f:\cases\0000000000001\tables `
        -noDetail `
        -startTime ((get-date).AddDays(-2)) `
        -endTime ((get-date).AddHours(-12)) `
        -tableName "[^T][^i][^m][^e]$"

.EXAMPLE
    .\azure-storage-query-table.ps1 -saskeyTable $sas `
        -outputDir "f:\cases\000000000000001\storageTables" `
        -starttime ((get-date).Touniversaltime().AddHours(-48)) #`
        #-listColumns Timestamp `
        #-takecount 1000
        #-tablename ops 
        
        $events = $global:allTableResults
        $nodes = $events | where-object {$_.roleinstance -ne $Null}
        $nodes | sort Timestamp |% {write-host "$($_.Timestamp),$($_.Roleinstance),$($_.EventMessage),$($_.Opcodename)"} 

.PARAMETER saskeyTable
    saskey is mandatory argument for azure storage table to be queried

.PARAMETER noDetail
    disables output of records to console.
    records are still added to global object and output file.

.PARAMETER noJson
    disables output of records to global json object and file.
    this may reduce time to query.

.PARAMETER outputDir
    if specified, is the output location for generated record files and json

.PARAMETER startTime
    utc beginning timestamp for table query
    default is -24 hours

.PARAMETER endTime
    utc end timestamp for table query
    default is now

.PARAMETER excludeTableName
    string / regex name of table to exclude
    default is all

.PARAMETER tableName
    string / regex name of table to query
    default is all

.PARAMETER takeCount
    number of records to return at one time

.PARAMETER listColumns
    names of columns to return
    default is all
.LINK
    https://github.com/jagilber/powershellScripts
    https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-storage-query-table.ps1

.INPUTS
   table saskey string
   Input type  [string]

.OUTPUTS
    optional text / json files
    Output type [$global:object[]]
    $global:allTableResults
    $global:allTableJsonObj

.COMPONENT
    azure.storage

FORWARDHELPTARGETNAME https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-storage-query-table.ps1

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
    [string]$excludeTableName,
    [int]$takecount = 100,
    [string[]]$listColumns
)

$global:allTableResults = $Null
$global:allTableJson = $Null
$global:allTableJsonObject = $Null
$timer = get-date

function main()
{
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

    [microsoft.windowsAzure.storage.auth.storageCredentials]
    $accountSASTable = new-object microsoft.windowsAzure.storage.auth.storageCredentials($saskeyTable);
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
    #$queryFilter = [microsoft.windowsAzure.storage.table.tableQuery]::GenerateFilterCondition("PartitionKey", $queryComparison, "x" )
    $squeryFilter = [microsoft.windowsAzure.storage.table.tableQuery]::GenerateFilterConditionForDate("Timestamp", $queryComparison, ($startTime.ToUniversalTime().ToString("o")) )
    $queryComparison = [microsoft.windowsAzure.storage.table.queryComparisons]::LessThanOrEqual
    $equeryFilter = [microsoft.windowsAzure.storage.table.tableQuery]::GenerateFilterConditionForDate("Timestamp", $queryComparison, ($endTime.ToUniversalTime().ToString("o")) )

    $tableOperator = [microsoft.windowsAzure.storage.table.tableOperators]::And
    $queryFilter = [microsoft.windowsAzure.storage.table.tableQuery]::CombineFilters($squeryFilter, $tableOperator, $equeryFilter)
    $global:allTableResults = $null
    $global:allTableJson = $null

    foreach ($table in $tablesRef.ListTables())
    {
        if ($tableName -and (($table.name) -inotmatch $tablename))
        {
            write-host "skipping $($table.name). does not match $($tablename)"
            continue
        }
        
        if ($excludeTableName -and (($table.name) -imatch $excludTablename))
        {
            write-host "skipping excluded $($table.name). matches $($excludedTablename)"
            continue
        }
        
        write-host "table name:$($table.name)" -ForegroundColor Yellow
        write-host "query: $($queryFilter)"
        $table
        $tableQuery = new-object microsoft.windowsAzure.storage.table.tableQuery
        $tableQuery.FilterString = $queryFilter
        $tableQuery.takecount = $takecount

        if ($listColumns)
        {
            $tableQuery.SelectColumns = new-object collections.generic.list[string](, $listColumns)
        }

        [microsoft.windowsAzure.storage.table.tableContinuationToken]
        $token = new-object microsoft.windowsAzure.storage.table.tableContinuationToken
        $outputFile = "$($outputdir)\$($table.name).records.txt"
        remove-item $outputFile -erroraction silentlycontinue

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

            $global:allTableResults += $recordObjs
        }
    }

    if (!$noJson -and $global:allTableJson)
    {
        # final format
        $global:allTableJson = "[`r`n$($global:allTableJson.TrimEnd("`r`n,"))`r`n]"

        if ($outputDir)
        {
            $outputFile = "$($outputdir)\alltableevents.json"
            $global:allTableJson | out-file -encoding ascii -filepath $outputFile
            write-host "output json stored in `$global:allTableJson and $($outputFile)" -ForegroundColor Magenta
        }

        $global:allTableJsonObject = convertfrom-json $global:allTableJson
        $global:allTableJsonObject = $global:allTableJsonObject | sort eventtimestamp
        
        write-host "output json object stored in `$global:allTableJsonObject" -ForegroundColor Magenta
        write-host "example queries:"
        write-host "`$global:allTableJsonObject | select table,eventtimestamp,level,eventmessage | ? level -lt 4" -ForegroundColor Cyan
        write-host "`$global:allTableJsonObject | ? taskname -imatch `"FM`" | ft" -ForegroundColor Cyan
        write-host "`$global:allTableJsonObject | ? eventmessage -imatch `"upgrade`" | out-gridview" -ForegroundColor Cyan
        write-host "`$global:allTableJsonObject | select table,eventtimestamp,level,eventmessage | ? eventmessage -imatch `"upgrade`"" -ForegroundColor Cyan
        write-host "`$global:allTableJsonObject | select table,eventtimestamp,level,eventmessage | ? eventmessage -imatch `"fail`"" -ForegroundColor Cyan
        write-host "`$global:allTableJsonObject | select table,eventtimestamp,level,eventmessage -ExpandProperty eventmessage | ? { `$_.eventmessage.tolower().contains(`"upgrade`") -and `$_.level -lt 4 }" -ForegroundColor Cyan
        write-host
        write-host "`$q = `$global:allTableJsonObject | select table,eventtimestamp,level,eventmessage -ExpandProperty eventmessage | ? eventmessage" -ForegroundColor Cyan
        write-host "`$q -imatch `"fail|error`"" -ForegroundColor Cyan
    }

    $global:allTableResults = $global:allTableResults | sort eventtimestamp
    write-host "`noutput table object[] stored in `$global:allTableResults" -ForegroundColor Magenta

    if ($outputDir)
    {
        write-host "output files stored in dir $outputDir\*records.txt" -ForegroundColor Magenta
    }
    else
    {
        write-host "use -outputDir to write output to files" -ForegroundColor Gray
    }

    write-host "use -starttime and -endtime to adjust time range" -ForegroundColor Gray
    write-host "type 'help $($MyInvocation.ScriptName) -full' for additional information" -ForegroundColor Gray
    write-host "finished searching tables in $rootTableUrl. total minutes: $(((get-date) - $timer).TotalMinutes.tostring("F2"))"
    write-host "$($global:allTableResults.count) events total between $starttime and $endtime" -ForegroundColor Yellow

}

main
