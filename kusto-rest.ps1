<#
.SYNOPSIS
script to query kusto with AAD authorization or token using kusto rest api
script gives ability to import, export, execute query and commands, and removing empty columns

.DESCRIPTION
this script will setup Microsoft.IdentityModel.Clients Msal for use with powershell 5.1, 6, and 7
KustoObj will be created as $global:kusto to hold properties and run methods from

use the following to save and pass arguments:
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/kusto-rest.ps1" -outFile "$pwd/kusto-rest.ps1";
.\kusto-rest.ps1 -cluster %kusto cluster% -database %kusto database%

.NOTES
Author : jagilber
File Name  : kusto-rest.ps1
Version    : 240521
History    : resolve cluster and database on first run

.EXAMPLE
.\kusto-rest.ps1 -cluster kustocluster -database kustodatabase

.EXAMPLE
.\kusto-rest.ps1 -cluster kustocluster -database kustodatabase
$kusto.Exec('.show tables')

.EXAMPLE
$kusto.viewresults = $true
$kusto.SetTable($table)
$kusto.SetDatabase($database)
$kusto.SetCluster($cluster)
$kusto.parameters = @{'T'= $table}
$kusto.ExecScript("..\KustoFunctions\sflogs\TraceKnownIssueSummary.csl", $kusto.parameters)

.EXAMPLE
$kusto.SetTable("test_$env:USERNAME").Import()

.EXAMPLE
$kusto.SetPipe($true).SetCluster('azure').SetDatabase('azure').Exec("EventEtwTable | where TIMESTAMP > ago(1d) | where TenantName == $tenantId")

.EXAMPLE
.\kusto-rest.ps1 -cluster kustocluster -database kustodatabase
$kusto.Exec('.show tables')
$kusto.ExportCsv("$env:temp\test.csv")
type $env:temp\test.csv

.PARAMETER query
query string or command to execute against a kusto database

.PARAMETER cluster
[string]kusto cluster name. (host name not fqdn)
    example: kustocluster
    example: azurekusto.eastus

.PARAMETER database
[string]kusto database name

.PARAMETER table
[string]optional kusto table for import

.PARAMETER headers
[string]optional kusto table headers for import ['columnname']:columntype,

.PARAMETER resultFile
[string]optional json file name and path to store raw result content

.PARAMETER viewResults
[bool]option if enabled will display results in console output

.PARAMETER token
[string]optional token to connect to kusto. if not provided, script will attempt to authorize user to given cluster and database

.PARAMETER limit
[int]optional result limit. default 10,000

.PARAMETER script
[string]optional path and name of kusto script file (.csl|.kusto) to execute

.PARAMETER clientSecret
[string]optional azure client secret to connect to kusto. if not provided, script will attempt to authorize user to given cluster and database
requires clientId

.PARAMETER clientId
[string]optional azure client id to connect to kusto. if not provided, script will attempt to authorize user to given cluster and database
requires clientSecret

.PARAMETER tenantId
[guid]optional tenantId to use for authorization. default is 'common'

.PARAMETER force
[bool]enable to force authentication regardless if token is valid

.PARAMETER serverTimeout
[timespan]optional override default 4 minute kusto server side timeout. max 60 minutes.

.PARAMETER updateScript
[switch]optional enable to download latest version of script

.PARAMETER parameters
[hashtable]optional hashtable of parameters to pass to kusto script (.csl|kusto) file

.OUTPUTS
KustoObj

.LINK
https://raw.githubusercontent.com/jagilber/powershellScripts/master/kusto-rest.ps1
#>

[cmdletbinding()]
param(
    [string]$cluster,
    [string]$database,
    [string]$query = '.show tables',
    [bool]$fixDuplicateColumns,
    [bool]$removeEmptyColumns = $true,
    [string]$table,
    [string]$headers,
    [string]$identityPackageLocation,
    [string]$resultFile, # = ".\result.json",
    [bool]$createResults = $true,
    [bool]$viewResults = $true,
    [string]$token,
    [int]$limit,
    [string]$script,
    [string]$clientSecret,
    [string]$clientId = "1950a258-227b-4e31-a9cf-717495945fc2",
    [string]$tenantId = "common",
    [bool]$pipeLine,
    [string]$redirectUri = "http://localhost", # "urn:ietf:wg:oauth:2.0:oob", #$null
    [bool]$force,
    [timespan]$serverTimeout = (new-Object timespan (0, 4, 0)),
    [switch]$updateScript,
    [hashtable]$parameters = @{ } #@{'clusterName' = $resourceGroup; 'dnsName' = $resourceGroup;}
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = "continue"
$global:kusto = $null
$global:identityPackageLocation
$packageVersion = "4.28.0"

if ($updateScript) {
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/kusto-rest.ps1" -outFile  "$psscriptroot/kusto-rest.ps1";
    write-warning "script updated. restart script"
    return
}

function main() {
    try {
        $error.Clear()
        $global:kusto = [KustoObj]::new()
        $kusto.SetTables()
        $kusto.SetFunctions()
        $kusto.Exec()
        $kusto.ClearResults()

        write-host ($PSBoundParameters | out-string)

        if ($error) {
            write-warning ($error | out-string)
        }
        else {
            write-host ($kusto | Get-Member | out-string)
            write-host "use `$kusto object to set properties and run queries. example: `$kusto.Exec('.show operations')" -ForegroundColor Green
            write-host "set `$kusto.viewresults=`$true to see results." -ForegroundColor Green
        }
    }
    catch {
        write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
    }
}

function AddIdentityPackageType([string]$packageName, [string] $edition) {
    # support ps core on linux
    if ($IsLinux) {
        $env:USERPROFILE = $env:HOME
    }
    [string]$nugetPackageDirectory = "$($env:USERPROFILE)/.nuget/packages"
    [string]$nugetSource = "https://api.nuget.org/v3/index.json"
    [string]$nugetDownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    [io.directory]::createDirectory($nugetPackageDirectory)
    [string]$packageDirectory = "$nugetPackageDirectory/$packageName"

    $global:identityPackageLocation = get-identityPackageLocation $packageDirectory

    if (!$global:identityPackageLocation) {
        if ($psedition -ieq 'core') {
            $tempProjectFile = './temp.csproj'

            #dotnet new console
            $csproj = "<Project Sdk=`"Microsoft.NET.Sdk`">
                    <PropertyGroup>
                        <OutputType>Exe</OutputType>
                        <TargetFramework>$edition</TargetFramework>
                    </PropertyGroup>
                    <ItemGroup>
                        <PackageReference Include=`"$packageName`" Version=`"$packageVersion`" />
                    </ItemGroup>
                </Project>
            "

            out-file -InputObject $csproj -FilePath $tempProjectFile
            write-host "dotnet restore --packages $packageDirectory --no-cache --no-dependencies $tempProjectFile"
            dotnet restore --packages $packageDirectory --no-cache --no-dependencies $tempProjectFile

            remove-item "$pwd/obj" -re -fo
            remove-item -path $tempProjectFile
        }
        else {
            $nuget = "nuget.exe"
            if (!(test-path $nuget)) {
                $nuget = "$env:temp/nuget.exe"
                if (!(test-path $nuget)) {
                    [net.webclient]::new().DownloadFile($nugetDownloadUrl, $nuget)
                }
            }
            [string]$localPackages = . $nuget list -Source $nugetPackageDirectory

            if ($force -or !($localPackages -imatch "$edition.$packageName")) {
                write-host "$nuget install $packageName -Source $nugetSource -outputdirectory $nugetPackageDirectory -verbosity detailed"
                . $nuget install $packageName -Source $nugetSource -outputdirectory $nugetPackageDirectory -verbosity detailed
            }
            else {
                write-host "$packageName already installed" -ForegroundColor green
            }
        }
    }

    $global:identityPackageLocation = get-identityPackageLocation $packageDirectory
    write-host "identityDll: $($global:identityPackageLocation)" -ForegroundColor Green
    add-type -literalPath $global:identityPackageLocation
    return $true
}

function get-identityPackageLocation($packageDirectory) {
    $pv = [version]::new($packageVersion)
    $pv = [version]::new($pv.Major, $pv.Minor)

    $versions = @{}
    $files = @(get-childitem -Path $packageDirectory -Recurse | where-object FullName -imatch "lib.$edition.$packageName\.dll")
    write-host "existing identity dlls $($files|out-string)"

    foreach ($file in @($files.fullname)) {
        $versionString = [regex]::match($file, ".$packageName.([0-9.]+?).lib.$edition", [text.regularexpressions.regexoptions]::IgnoreCase).Groups[1].Value
        if (!$versionString) { continue }

        $version = [version]::new($versionString)
        [void]$versions.add($file, [version]::new($version.Major, $version.Minor))
    }

    foreach ($version in $versions.GetEnumerator()) {
        write-host "comparing file version:$($version.value) to configured version:$($pv)"
        if ($version.value -ge $pv) {
            return $version.Key
        }
    }
    return $null
}

function get-msalLibrary() {
    # Install latest AD client library
    try {
        if (([Microsoft.Identity.Client.ConfidentialClientApplication]) -and !$force) {
            write-host "[Microsoft.Identity.Client.AzureCloudInstance] already loaded. skipping" -ForegroundColor Cyan
            return
        }
    }
    catch {
        write-verbose "exception checking for identity client:$($error|out-string)"
        $error.Clear()
    }

    if ($global:PSVersionTable.PSEdition -eq "Core") {
        write-host "setting up microsoft.identity.client for .net core"
        if (!(AddIdentityPackageType -packageName "Microsoft.Identity.Client" -edition "net6.0")) {
            write-error "unable to add package"
            return $false
        }
        if (!(AddIdentityPackageType -packageName "Microsoft.IdentityModel.Abstractions" -edition "net6.0")) {
            write-error "unable to add package"
            return $false
        }
    }
    else {
        write-host "setting up microsoft.identity.client for .net framework"
        if (!(AddIdentityPackageType -packageName "Microsoft.Identity.Client" -edition "net461")) {
            write-error "unable to add package"
            return $false
        }
        if (!(AddIdentityPackageType -packageName "Microsoft.IdentityModel.Abstractions" -edition "net6.0")) {
            write-error "unable to add package"
            return $false
        }
    }
}

get-msalLibrary

# comment next line after microsoft.identity.client type has been imported into powershell session to troubleshoot 1 of 2
invoke-expression @'

class KustoObj {
    hidden [string]$identityPackageLocation = $identityPackageLocation
    hidden [object]$authenticationResult
    hidden [Microsoft.Identity.Client.ConfidentialClientApplication] $confidentialClientApplication = $null
    [string]$clientId = $clientId
    hidden [string]$clientSecret = $clientSecret
    [string]$Cluster = $cluster
    [bool]$ClusterResolved = $false
    [string]$Database = $database
    [bool]$FixDuplicateColumns = $fixDuplicateColumns
    [bool]$Force = $force
    [string]$Headers = $headers
    [int]$Limit = $limit
    [hashtable]$parameters = $parameters
    hidden [Microsoft.Identity.Client.PublicClientApplication] $publicClientApplication = $null
    [bool]$PipeLine = $null
    [string]$Query = $query
    hidden [string]$redirectUri = $redirectUri
    [bool]$RemoveEmptyColumns = $removeEmptyColumns
    hidden [object]$Result = $null
    [object]$ResultObject = $null
    [object]$ResultTable = $null
    [string]$ResultFile = $resultFile
    [string]$Script = $script
    [string]$Table = $table
    [string]$tenantId = $tenantId
    [timespan]$ServerTimeout = $serverTimeout
    hidden [string]$token = $token
    [bool]$CreateResults = $createResults
    [bool]$ViewResults = $viewResults
    [hashtable]$Tables = @{}
    [hashtable]$Functions = @{}
    hidden [hashtable]$FunctionObjs = @{}

    KustoObj() { }
    static KustoObj() { }

    [void] ClearResults() {
        $this.ResultObject = $null
        $this.ResultTable = $null
    }

    [KustoObj] CreateResultTable() {
        $this.ResultTable = [collections.arraylist]@()
        $columns = @{ }

        if (!$this.ResultObject.tables) {
            write-warning "run query first"
            return $this.Pipe()
        }

        foreach ($column in ($this.ResultObject.tables[0].columns)) {
            try {
                [void]$columns.Add($column.ColumnName, $null)
            }
            catch {
                write-warning "$($column.ColumnName) already added"
            }
        }

        $resultModel = New-Object -TypeName PsObject -Property $columns
        $rowCount = 0

        foreach ($row in ($this.ResultObject.tables[0].rows)) {
            $count = 0
            $resultCopy = $resultModel.PsObject.Copy()

            foreach ($column in ($this.ResultObject.tables[0].columns)) {
                #write-verbose "createResultTable: procesing column $count"
                $resultCopy.($column.ColumnName) = $row[$count++]
            }

            write-verbose "createResultTable: processing row $rowCount columns $count"
            $rowCount++

            [void]$this.ResultTable.add($resultCopy)
        }
        $this.ResultTable = $this.RemoveEmptyResults($this.ResultTable)
        return $this.Pipe()
    }

    [KustoObj] Exec([string]$query) {
        $this.Query = $query
        $this.Exec()
        $this.Query = $null
        return $this.Pipe()
    }

    [KustoObj] Exec() {
        $startTime = get-date
        $this

        if (!$this.Limit) {
            $this.Limit = 10000
        }

        if (!$this.Script -and !$this.Query) {
            Write-Warning "-script and / or -query should be set. exiting"
            return $this.Pipe()
        }

        if (!$this.Cluster -or !$this.Database) {
            Write-Warning "-cluster and -database have to be set once. exiting"
            return $this.Pipe()
        }

        if ($this.Query) {
            write-host "table:$($this.Table) query:$($this.Query.substring(0, [math]::min($this.Query.length,512)))" -ForegroundColor Cyan
        }

        if ($this.Script) {
            write-host "script:$($this.Script)" -ForegroundColor Cyan
        }

        if ($this.Table -and $this.Query.startswith("|")) {
            $this.Query = $this.Table + $this.Query
        }

        $this.ResultObject = $this.Post($null)

        if ($this.ResultObject.Exceptions) {
            write-warning ($this.ResultObject.Exceptions | out-string)
            $this.ResultObject.Exceptions = $null
        }

        if ($this.ViewResults -or $this.CreateResults) {
            $this.CreateResultTable()
            if ($this.ViewResults) {
                write-host ($this.ResultTable | out-string)
            }
        }

        if ($this.ResultFile) {
            out-file -FilePath $this.ResultFile -InputObject  ($this.ResultObject | convertto-json -Depth 99)
        }

        $primaryResult = $this.ResultObject | where-object TableKind -eq PrimaryResult

        if ($primaryResult) {
            write-host ($primaryResult.columns | out-string)
            write-host ($primaryResult.Rows | out-string)
        }

        if ($this.ResultObject.tables) {
            write-host "results: $($this.ResultObject.tables[0].rows.count) / $(((get-date) - $startTime).TotalSeconds) seconds to execute" -ForegroundColor DarkCyan
            if ($this.ResultObject.tables[0].rows.count -eq $this.limit) {
                write-warning "results count equals limit $($this.limit). results may be incomplete"
            }
        }
        else {
            write-warning "bad result: error:"#$($error)"
        }
        return $this.Pipe()
    }

    [KustoObj] ExecFunctionWithTableName([string]$function) {
        $functionObj = ($this.FunctionObjs.getEnumerator() | where-object Name -imatch $function).Value

        if (!$function -or !$functionObj -or $functionObj.parameters.length -lt 1) {
            write-warning "verify function '$function' and number of parameters '$($functionObj.parameters)'"
        }
        else {
            write-host "function:$function$($functionObj.parameters)" -foregroundcolor cyan
        }

        if ($this.Table) {
            $this.Exec([string]::Format("{0}('{1}')", $function, $this.Table))
        }
        else {
            write-warning "table not set"
        }
        return $this.Pipe()
    }

    [KustoObj] ExecFunction([string]$function, [array]$parameters) {
        if ($parameters) {
            $this.Exec([string]::Format("{0}('{1}')", $function, $parameters -join "','"))
        }
        else {
            $this.Exec([string]::Format("{0}()", $function))
        }
        return $this.Pipe()
    }

    [KustoObj] ExecScript([string]$script, [hashtable]$parameters) {
        $this.Script = $script
        $this.parameters = $parameters
        $this.ExecScript()
        $this.Script = $null
        return $this.Pipe()
    }

    [KustoObj] ExecScript([string]$script) {
        $this.Script = $script
        $this.ExecScript()
        $this.Script = $null
        return $this.Pipe()
    }

    [KustoObj] ExecScript() {
        if ($this.Script.startswith('http')) {
            $destFile = "$pwd\$([io.path]::GetFileName($this.Script))" -replace '\?.*', ''

            if (!(test-path $destFile)) {
                Write-host "downloading $($this.Script)" -foregroundcolor green
                invoke-webRequest $this.Script -outFile  $destFile
            }
            else {
                Write-host "using cached script $($this.Script)"
            }

            $this.Script = $destFile
        }

        if ((test-path $this.Script)) {
            $this.Query = (Get-Content -raw -Path $this.Script)
        }
        else {
            write-error "unknown script:$($this.Script)"
            return $this.Pipe()
        }

        $this.Exec()
        return $this.Pipe()
    }

    [void] ExportCsv([string]$exportFile) {
        $this.CreateResultTable()
        [io.directory]::createDirectory([io.path]::getDirectoryName($exportFile))
        $this.ResultTable | export-csv -notypeinformation $exportFile
    }

    [void] ExportJson([string]$exportFile) {
        $this.CreateResultTable()
        [io.directory]::createDirectory([io.path]::getDirectoryName($exportFile))
        $this.ResultTable | convertto-json -depth 99 | out-file $exportFile
    }

    [string] FixColumns([string]$sourceContent) {
        if (!($this.fixDuplicateColumns)) {
            return $sourceContent
        }

        [hashtable]$tempTable = @{ }
        $matches = [regex]::Matches($sourceContent, '"ColumnName":"(?<columnName>.+?)"', 1)

        foreach ($match in $matches) {
            $matchInfo = $match.Captures[0].Groups['columnName']
            $column = $match.Captures[0].Groups['columnName'].Value
            $newColumn = $column
            $increment = $true
            $count = 0

            while ($increment) {
                try {
                    [void]$tempTable.Add($newColumn, $null)
                    $increment = $false

                    if ($newColumn -ne $column) {
                        write-warning "replacing $column with $newColumn"
                        return $this.FixColumns($sourceContent.Substring(0, $matchInfo.index) `
                                + $newColumn `
                                + $sourceContent.Substring($matchInfo.index + $matchinfo.Length))
                    }

                }
                catch {
                    $count++
                    $newColumn = "$($column)_$($count)"
                    $error.Clear()
                }
            }
        }
        return $sourceContent
    }

    [void] Import() {
        if ($this.Table) {
            $this.Import($this.Table)
        }
        else {
            write-warning "set table name first"
            return
        }
    }

    [KustoObj] Import([string]$table) {
        if (!$this.ResultObject.Tables) {
            write-warning 'no results to import'
            return $this.Pipe()
        }

        [object]$results = $this.ResultObject.Tables[0]
        [string]$formattedHeaders = "("

        foreach ($column in ($results.Columns)) {
            $formattedHeaders += "['$($column.ColumnName)']:$($column.DataType.tolower()), "
        }

        $formattedHeaders = $formattedHeaders.trimend(', ')
        $formattedHeaders += ")"

        [text.StringBuilder]$csv = New-Object text.StringBuilder

        foreach ($row in ($results.rows)) {
            $csv.AppendLine($row -join ',')
        }

        $this.Exec(".drop table ['$table'] ifexists")
        $this.Exec(".create table ['$table'] $formattedHeaders")
        $this.Exec(".ingest inline into table ['$table'] <| $($csv.tostring())")
        return $this.Pipe()
    }

    [KustoObj] ImportCsv([string]$csvFile, [string]$table, [string]$headers) {
        $this.Headers = $headers
        $this.Table = $table
        $this.ImportCsv($csvFile)
        return $this.Pipe()
    }

    [KustoObj] ImportCsv([string]$csvFile, [string]$table) {
        $this.Table = $table
        $this.ImportCsv($csvFile)
        return $this.Pipe()
    }

    [KustoObj] ImportCsv([string]$csvFile) {
        if (!(test-path $csvFile) -or !$this.Table) {
            write-warning "verify importfile: $csvFile and import table: $($this.Table)"
            return $this.Pipe()
        }

        # not working
        #POST https://help.kusto.windows.net/v1/rest/ingest/Test/Logs?streamFormat=Csv HTTP/1.1
        #[string]$csv = Get-Content -Raw $csvFile -encoding utf8
        #$this.Post($csv)

        $sr = new-object io.streamreader($csvFile)
        [string]$tempHeaders = $sr.ReadLine()
        [text.StringBuilder]$csv = New-Object text.StringBuilder

        while ($sr.peek() -ge 0) {
            $csv.AppendLine($sr.ReadLine())
        }

        $sr.close()
        $formattedHeaderList = @{ }
        [string]$formattedHeaders = "("

        foreach ($header in ($tempHeaders.Split(',').trim())) {
            $columnCount = 0
            if (!$header) { $header = 'column' }
            [string]$normalizedHeader = $header.trim('`"').Replace(" ", "_")
            $normalizedHeader = [regex]::Replace($normalizedHeader, "\W", "")
            $uniqueHeader = $normalizedHeader

            while ($formattedHeaderList.ContainsKey($uniqueHeader)) {
                $uniqueHeader = $normalizedHeader + ++$columnCount
            }

            $formattedHeaderList.Add($uniqueHeader, "")
            $formattedHeaders += "['$($uniqueHeader)']:string, "
        }

        $this.Headers = $formattedHeaders
        $formattedHeaders = $formattedHeaders.trimend(', ')
        $formattedHeaders += ")"

        #$this.Exec(".drop table ['$($this.Table)'] ifexists")
        $this.Exec(".create table ['$($this.Table)'] $formattedHeaders")
        $this.Exec(".ingest inline into table ['$($this.Table)'] <| $($csv.tostring())")
        return $this.Pipe()
    }

    [KustoObj] ImportJson([string]$jsonFile) {
        [string]$csvFile = [io.path]::GetTempFileName()
        try {
            ((Get-Content -Path $jsonFile) | ConvertFrom-Json) | Export-CSV $csvFile -NoTypeInformation
            write-host "using $csvFile"

            if (!(test-path $jsonFile) -or !$this.Table) {
                write-warning "verify importfile: $csvFile and import table: $($this.Table)"
                return $this.Pipe()
            }
            $this.ImportCsv($csvFile)
            return $this.Pipe()
        }
        finally {
            write-host "deleting $csvFile"
            [io.file]::Delete($csvFile)
        }
    }

    [KustoObj] ImportJson([string]$jsonFile, [string]$table) {
        $this.Table = $table
        $this.ImportJson($jsonFile)
        return $this.Pipe()
    }

    [bool] Logon([string]$resourceUrl) {
        [int]$expirationRefreshMinutes = 15
        [int]$expirationMinutes = 0
        write-host "logon($resourceUrl)" -foregroundcolor green

        if (!$resourceUrl) {
            write-warning "-resourceUrl required. example: https://{{ kusto cluster }}.kusto.windows.net"
            return $false
        }

        if ($this.authenticationResult) {
            $expirationMinutes = $this.authenticationResult.ExpiresOn.Subtract((get-date)).TotalMinutes
        }
        write-verbose "token expires in: $expirationMinutes minutes"

        if (!$this.Force -and ($expirationMinutes -gt $expirationRefreshMinutes)) {
            write-verbose "token valid: $($this.authenticationResult.ExpiresOn). use -force to force logon"
            return $true
        }
        #return $this.LogonMsal($resourceUrl, @("$resourceUrl/kusto.read", "$resourceUrl/kusto.write"))
        return $this.LogonMsal($resourceUrl, @("$resourceUrl/user_impersonation"))
    }

    hidden [bool] LogonMsal([string]$resourceUrl, [string[]]$scopes) {
        try {
            $error.Clear()
            [string[]]$defaultScope = @(".default")
            write-host "logonMsal($resourceUrl,$($scopes | out-string))" -foregroundcolor green

            if ($this.clientId -and $this.clientSecret) {
                [string[]]$defaultScope = @("$resourceUrl/.default")
                [Microsoft.Identity.Client.ConfidentialClientApplicationOptions] $cAppOptions = new-Object Microsoft.Identity.Client.ConfidentialClientApplicationOptions
                $cAppOptions.ClientId = $this.clientId
                $cAppOptions.RedirectUri = $this.redirectUri
                $cAppOptions.ClientSecret = $this.clientSecret
                $cAppOptions.TenantId = $this.tenantId

                [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]$cAppBuilder = [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]::CreateWithApplicationOptions($cAppOptions)
                $cAppBuilder = $cAppBuilder.WithAuthority([microsoft.identity.client.azureCloudInstance]::AzurePublic, $this.tenantId)

                if ($global:PSVersionTable.PSEdition -eq "Core") {
                    $cAppBuilder = $cAppBuilder.WithLogging($this.MsalLoggingCallback, [Microsoft.Identity.Client.LogLevel]::Verbose, $true, $true )
                }

                $this.confidentialClientApplication = $cAppBuilder.Build()
                write-verbose ($this.confidentialClientApplication | convertto-json)

                try {
                    write-host "acquire token for client" -foregroundcolor green
                    $this.authenticationResult = $this.confidentialClientApplication.AcquireTokenForClient($defaultScope).ExecuteAsync().Result
                }
                catch [Exception] {
                    write-host "error client acquire error: $_`r`n$($error | out-string)" -foregroundColor red
                    $error.clear()
                }
            }
            else {
                # user creds
                [Microsoft.Identity.Client.PublicClientApplicationBuilder]$pAppBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($this.clientId)
                $pAppBuilder = $pAppBuilder.WithAuthority([microsoft.identity.client.azureCloudInstance]::AzurePublic, $this.tenantId)

                if (!($this.publicClientApplication)) {
                    if ($global:PSVersionTable.PSEdition -eq "Core") {
                        $pAppBuilder = $pAppBuilder.WithDefaultRedirectUri()
                        $pAppBuilder = $pAppBuilder.WithLogging($this.MsalLoggingCallback, [Microsoft.Identity.Client.LogLevel]::Verbose, $true, $true )
                    }
                    else {
                        $pAppBuilder = $pAppBuilder.WithRedirectUri($this.redirectUri)
                    }
                    $this.publicClientApplication = $pAppBuilder.Build()
                }

                write-verbose ($this.publicClientApplication | convertto-json)

                [Microsoft.Identity.Client.IAccount]$account = $this.publicClientApplication.GetAccountsAsync().Result[0]
                #preauth with .default scope
                try {
                    write-host "preauth acquire token silent for account: $account" -foregroundcolor green
                    $this.authenticationResult = $this.publicClientApplication.AcquireTokenSilent($defaultScope, $account).ExecuteAsync().Result
                    if (!$this.authenticationResult) { throw }
                }
                catch [Exception] {
                    write-host "preauth acquire error: $_`r`n$($error | out-string)" -foregroundColor yellow
                    $error.clear()
                    try {
                        write-host "preauth acquire token interactive" -foregroundcolor yellow
                        $this.authenticationResult = $this.publicClientApplication.AcquireTokenInteractive($defaultScope).ExecuteAsync().Result
                        if (!$this.authenticationResult) { throw }
                    }
                    catch [Exception] {
                        write-host "preauth acquire token device" -foregroundcolor yellow
                        $this.authenticationResult = $this.publicClientApplication.AcquireTokenWithDeviceCode($defaultScope, $this.MsalDeviceCodeCallback).ExecuteAsync().Result
                        if (!$this.authenticationResult) { throw }
                    }
                }

                write-host "authentication result: $($this.authenticationResult)"
                $account = $this.publicClientApplication.GetAccountsAsync().Result[0]

                #add kusto scopes after preauth
                if ($scopes) {
                    try {
                        write-host "kusto acquire token silent" -foregroundcolor green
                        $this.authenticationResult = $this.publicClientApplication.AcquireTokenSilent($scopes, $account).ExecuteAsync().Result
                    }
                    catch [Exception] {
                        write-host "kusto acquire error: $_`r`n$($error | out-string)" -foregroundColor red
                        $error.clear()
                    }
                }
            }

            if ($this.authenticationResult) {
                write-host "authenticationResult:$($this.authenticationResult | convertto-json)"
                $this.Token = $this.authenticationResult.AccessToken
                return $true
            }
            return $false
        }
        catch {
            Write-Error "$($error | out-string)"
            return $false
        }
    }

    [Threading.Tasks.Task] MsalDeviceCodeCallback([Microsoft.Identity.Client.DeviceCodeResult] $result) {
        write-host "MSAL Device code result: $($result | convertto-json)"
        return [threading.tasks.task]::FromResult(0)
    }

    [void] MsalLoggingCallback([Microsoft.Identity.Client.LogLevel] $level, [string]$message, [bool]$containsPII) {
        write-verbose "MSAL: $level $containsPII $message"
    }

    [KustoObj] Pipe() {
        if ($this.pipeLine) {
            return $this
        }
        return $null
    }

    hidden [object] Post([string]$body = "") {
        # authorize aad to get token
        if(!($this.ClusterResolved)){
            $this.ClusterResolved = $this.ResolveCluster()
        }

        [string]$kustoHost = $this.cluster
        [string]$kustoResource = 'https://' + $kustoHost
        [string]$csl = "$($this.Query)"

        $this.Result = $null
        $this.ResultObject = $null
        $this.ResultTable = $null
        $this.Query = $this.Query.trim()

        if ($body -and ($this.Table)) {
            $uri = "$kustoResource/v1/rest/ingest/$($this.Database)/$($this.Table)?streamFormat=Csv&mappingName=CsvMapping"
        }
        elseif ($this.Query.startswith('.show') -or !$this.Query.startswith('.')) {
            $uri = "$kustoResource/v1/rest/query"
            $csl = "$($this.Query) | limit $($this.Limit)"
        }
        else {
            $uri = "$kustoResource/v1/rest/mgmt"
        }

        if (!$this.Token -or $this.authenticationResult) {
            if (!($this.Logon($kustoResource))) {
                write-error "unable to acquire token."
                return $error
            }
        }

        $requestId = [guid]::NewGuid().ToString()
        write-verbose "request id: $requestId"

        $header = @{
            'accept'                 = 'application/json'
            'authorization'          = "Bearer $($this.Token)"
            'content-type'           = 'application/json'
            'host'                   = $kustoHost
            'x-ms-app'               = 'kusto-rest.ps1'
            'x-ms-user'              = $env:USERNAME
            'x-ms-client-request-id' = $requestId
        }

        if ($body) {
            $header.Add("content-length", $body.Length)
        }
        else {
            $body = @{
                db         = $this.database
                csl        = $csl
                properties = @{
                    Options    = @{
                        queryconsistency = "strongconsistency"
                        servertimeout    = $this.ServerTimeout.ToString()
                    }
                    Parameters = $this.parameters
                }
            } | ConvertTo-Json
        }

        write-verbose ($header | convertto-json)
        write-verbose $body

        $error.clear()
        $this.Result = Invoke-WebRequest -Method Post -Uri $uri -Headers $header -Body $body
        write-verbose $this.Result

        if ($error) {
            return $error
        }

        try {
            return ($this.FixColumns($this.Result.content) | convertfrom-json)
        }
        catch {
            write-warning "error converting json result to object. unparsed results in `$this.Result`r`n$error"

            if (!$this.FixDuplicateColumns) {
                write-warning "$this.fixDuplicateColumns = $true may resolve."
            }
            return ($this.Result.content)
        }
    }

    [collections.arrayList] RemoveEmptyResults([collections.arrayList]$sourceContent) {
        if (!$this.RemoveEmptyColumns -or !$sourceContent -or $sourceContent.count -eq 0) {
            return $sourceContent
        }
        $columnList = (Get-Member -InputObject $sourceContent[0] -View Extended).Name
        write-verbose "checking column list $columnList"
        $populatedColumnList = [collections.arraylist]@()

        foreach ($column in $columnList) {
            if (@($sourceContent | where-object $column -ne "").Count -gt 0) {
                $populatedColumnList += $column
            }
        }
        return [collections.arrayList]@($sourceContent | select-object $populatedColumnList)
    }

    [bool] ResolveCluster() {
        if($this.cluster.startswith('https://')) {
            $this.cluster = $this.cluster.trimstart('https://')
        }

        if(!(test-netConnection $this.cluster -p 443).TcpTestSucceeded) {
            write-warning "cluster not reachable:$($this.cluster)"
            if((test-netConnection "$($this.cluster).kusto.windows.net" -p 443).TcpTestSucceeded) {
                $this.cluster += '.kusto.windows.net'
                write-host "cluster reachable:$($this.cluster)" -foregroundcolor green
            }
            else {
                write-warning "cluster not reachable:$($this.cluster)"
                return $false
            }
        }
        return $true
    }

    [KustoObj] SetCluster([string]$cluster) {
        $this.Cluster = $cluster
        return $this.Pipe()
    }

    [KustoObj] SetDatabase([string]$database) {
        $this.Database = $database
        $this.SetTables()
        $this.SetFunctions()
        return $this.Pipe()
    }

    [KustoObj] SetPipe([bool]$enable) {
        $this.PipeLine = $enable
        return $this.Pipe()
    }

    [KustoObj] SetTable([string]$table) {
        $this.Table = $table
        return $this.Pipe()
    }

    [KustoObj] SetFunctions() {
        $this.Functions.Clear()
        $this.FunctionObjs.Clear()
        $this.exec('.show functions')
        $this.CreateResultTable()

        foreach ($function in $this.ResultTable) {
            $this.Functions.Add($function.Name, $function.Name)
            $this.FunctionObjs.Add($function.Name, $function)
        }
        return $this.Pipe()
    }

    [KustoObj] SetTables() {
        $this.Tables.Clear()
        $this.exec('.show tables | project TableName')
        $this.CreateResultTable()

        foreach ($table in $this.ResultTable) {
            $this.Tables.Add($table.TableName, $table.TableName)
        }
        return $this.Pipe()
    }
}

# comment next line after microsoft.identity.client type has been imported into powershell session to troubleshoot 2 of 2
'@

main