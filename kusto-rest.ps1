<#
.SYNOPSIS
    script to query kusto with AAD authorization or token using kusto rest api
    script gives ability to import, export, execute query and commands, and removing empty columns

.DESCRIPTION
    this script will setup Microsoft.IdentityModel.Clients.ActiveDirectory Adal for powershell 5.1 
        or Microsoft.IdentityModel.Clients Msal using https://github.com/jagilber/netCore/tree/master/netCoreMsal 
        for .net core 3 verified single executable package for powershell 6+
    
    KustoObj will be created as $global:kusto to hold properties and run methods from
    
    use the following to save and pass arguments:
    (new-object net.webclient).downloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/kusto-rest.ps1","$pwd/kusto-rest.ps1");
    .\kusto-rest.ps1 -cluster %kusto cluster% -database %kusto database%

.NOTES
    Author : jagilber
    File Name  : kusto-rest.ps1
    Version    : 191205
    History    : 

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
    $kusto.ExecScript("..\docs\kustoqueries\sflogs-table-info.csl", $kusto.parameters)

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

.PARAMETER clean
    [switch]optional clean msal logon utility for .net core and nuget for .net

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
    [string]$query = '.show tables',
    [string]$cluster,
    [string]$database,
    [bool]$fixDuplicateColumns,
    [bool]$removeEmptyColumns,
    [string]$table,
    [string]$adalDllLocation,
    [string]$resultFile, # = ".\result.json",
    [bool]$viewResults = $true,
    [string]$token,
    [int]$limit,
    [string]$script,
    [string]$clientSecret,
    [string]$clientId,
    [string]$tenantId = "common",
    [bool]$pipeLine,
    [string]$wellknownClientId = "1950a258-227b-4e31-a9cf-717495945fc2", 
    [string]$redirectUri = "urn:ietf:wg:oauth:2.0:oob",
    [bool]$force,
    [string]$msalUtility = "https://api.github.com/repos/jagilber/netCore/releases",
    [string]$msalUtilityFileName = "netCoreMsal",
    [timespan]$serverTimeout = (new-Object timespan (0, 4, 0)),
    [switch]$updateScript,
    [switch]$clean,
    [hashtable]$parameters = @{ } #@{'clusterName' = $resourceGroup; 'dnsName' = $resourceGroup;}
)
      
$ErrorActionPreference = "continue"
$global:kusto = $null
      
class KustoObj {
    hidden [object]$adalDll = $null
    hidden [string]$adalDllLocation = $adalDllLocation
    hidden [object]$authenticationResult
    [string]$clientId = $clientID
    hidden [string]$clientSecret = $clientSecret
    [string]$Cluster = $cluster
    [string]$Database = $database
    [bool]$FixDuplicateColumns = $fixDuplicateColumns
    [bool]$Force = $force
    [int]$Limit = $limit
    hidden [string]$msalUtility = $msalUtility
    hidden [string]$msalUtilityFileName = $msalUtilityFileName
    [hashtable]$parameters = $parameters
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
    [bool]$ViewResults = $viewResults
    hidden [string]$wellknownClientId = $wellknownClientId
          
    KustoObj() { }
    static KustoObj() { }
      
    hidden [bool] CheckAdal() {
        [string]$packageName = "Microsoft.IdentityModel.Clients.ActiveDirectory"
        [string]$outputDirectory = "$($env:USERPROFILE)\.nuget\packages"
        [string]$nugetSource = "https://api.nuget.org/v3/index.json"
        [string]$nugetDownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
      
        if (!$this.force -and $this.adalDll) {
            write-warning 'adal already set. use -force to force'
            return $true
        }
      
        [io.directory]::createDirectory($outputDirectory)
        [string]$packageDirectory = "$outputDirectory\$packageName"
        [string]$edition = "net45"
              
        $this.adalDllLocation = @(get-childitem -Path $packageDirectory -Recurse | where-object FullName -match "$edition\\$packageName\.dll" | select-object FullName)[-1].FullName
      
        if (!$this.adalDllLocation) {
            if ($psscriptroot -and !($env:path.contains(";$psscriptroot"))) {
                $env:path += ";$psscriptroot" 
            }
          
            if (!(test-path nuget)) {
                (new-object net.webclient).downloadFile($nugetDownloadUrl, "$psscriptroot\nuget.exe")
            }
      
            [string]$localPackages = nuget list -Source $outputDirectory
      
            if ($this.force -or !($localPackages -imatch $packageName)) {
                write-host "nuget install $packageName -Source $nugetSource -outputdirectory $outputDirectory -verbosity detailed"
                nuget install $packageName -Source $nugetSource -outputdirectory $outputDirectory -verbosity detailed
                $this.adalDllLocation = @(get-childitem -Path $packageDirectory -Recurse | where-object FullName -match "$edition\\$packageName\.dll" | select-object FullName)[-1].FullName
            }
            else {
                write-host "$packageName already installed" -ForegroundColor green
            }
        }
      
        write-host "adalDll: $($this.adalDllLocation)" -ForegroundColor Green
        #import-module $($this.adalDll.FullName)
        $this.adalDll = [Reflection.Assembly]::LoadFile($this.adalDllLocation) 
        $this.adalDll
        $this.adalDllLocation = $this.adalDll.Location
        return $true
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
      
        if ($this.ViewResults) {
            $this.CreateResultTable()
            write-host ($this.ResultTable | out-string)
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
                (new-object net.webclient).DownloadFile($this.Script, $destFile)
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
        [string]$headers = $sr.ReadLine()
        [text.StringBuilder]$csv = New-Object text.StringBuilder
      
        while ($sr.peek() -ge 0) {
            $csv.AppendLine($sr.ReadLine())
        }
      
        $sr.close()
        $formattedHeaderList = @{ }
        [string]$formattedHeaders = "("
      
        foreach ($header in ($headers.Split(',').trim())) {
            $normalizedHeader = $header.trim('`"').Replace(" ", "_")
            $normalizedHeader = [regex]::Replace($normalizedHeader, "\W", "")
            $columnCount = 0
            $uniqueHeader = $normalizedHeader
    
            while ($formattedHeaderList.ContainsKey($uniqueHeader)) {
                $uniqueHeader = $normalizedHeader + ++$columnCount
            }
                
            $formattedHeaderList.Add($uniqueHeader, "")
            $formattedHeaders += "['$($uniqueHeader)']:string, "
        }
              
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

    [bool] Logon($resourceUrl) {
        [object]$authenticationContext = $Null
        [string]$ADauthorityURL = "https://login.microsoftonline.com/$($this.TenantId)"
      
        if (!$resourceUrl) {
            write-warning "-resourceUrl required. example: https://{{ kusto cluster }}.kusto.windows.net"
            return $false
        }
      
        if (!$this.force -and $this.AuthenticationResult.expireson -gt (get-date)) {
            write-verbose "token valid: $($this.AuthenticationResult.expireson). use -force to force logon"
            return $true
        }
    
        if ($global:PSVersionTable.PSEdition -eq "Core") {
            [string]$utilityFileName = $this.msalUtilityFileName
            [string]$utility = $this.msalUtility
            [string]$filePath = "$env:TEMP\$utilityFileName"
            [string]$fileName = "$filePath.zip"
            write-warning ".net core microsoft.identity requires form/webui. checking for $filePath"
               
            if (!(test-path $filePath)) {
                # .net core 3.0 singleexe may clean up extracted dir
                if (!(test-path $fileName)) {
                    if ((read-host "is it ok to download .net core Msal utility $utility/$utilityFileName to generate token?[y|n]`r`n" `
                                "(if not, for .net core, you will need to generate and pass token to script.)") -ilike "y") {
                        write-warning "downloading .net core $utilityFileName from $utility to $filePath"
                        [psobject]$apiResults = convertfrom-json (Invoke-WebRequest $utility -UseBasicParsing)
                        [string]$downloadUrl = @($apiResults.assets.browser_download_url -imatch "/$utilityFileName-")[0]
                        
                        (new-object net.webclient).downloadFile($downloadUrl, $fileName)
                        Expand-Archive $fileName $filePath
                    }
                    else {
                        write-warning "returning"
                        return $false
                    }
                }
                else {
                    Expand-Archive $fileName $filePath
                }
            }
    
            [string]$resultJsonText = (. "$filePath\$utilityFileName.exe" --resource "https://$($this.cluster).kusto.windows.net")
            write-host "preauth: $resultJsonText" -foregroundcolor green
            $resultJsonText = (. "$filePath\$utilityFileName.exe" --resource "https://$($this.cluster).kusto.windows.net" --scope "https://$($this.cluster).kusto.windows.net/kusto.read,https://$($this.cluster).kusto.windows.net/kusto.write")
            $this.authenticationResult = $resultJsonText | convertfrom-json
            $this.Token = $this.authenticationResult.AccessToken
            write-host ($this.authenticationResult | convertto-json)
    
            if ($this.Token) {
                return $true
            }
            return $false
        }
        elseif (!($this.CheckAdal())) { 
            return $false 
        }
     
        $authenticationContext = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext($ADAuthorityURL)
      
        if ($this.clientid -and $this.clientSecret) {
            # client id / secret
            $this.authenticationResult = $authenticationContext.AcquireTokenAsync($resourceUrl, 
                (new-object Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential($this.clientId, $this.clientSecret))).Result
        }
        else {
            # user / pass
            $error.Clear()
            $this.authenticationResult = $authenticationContext.AcquireTokenAsync($resourceUrl, 
                $this.wellknownClientId,
                (new-object Uri($this.RedirectUri)),
                (new-object Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters(0))).Result # auto
              
            if ($error) {
                # MFA
                $this.authenticationResult = $authenticationContext.AcquireTokenAsync($resourceUrl, 
                    $this.wellknownClientId,
                    (new-object Uri($this.RedirectUri)),
                    (new-object Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters(1))).Result # [promptbehavior]::always
            }
        }
      
        if (!($this.authenticationResult)) {
            write-error "error authenticating"
            #write-host (Microsoft.IdentityModel.Clients.ActiveDirectory.AdalError)
            return $false
        }
        write-verbose (convertto-json $this.authenticationResult -Depth 99)
        $this.Token = $this.authenticationResult.AccessToken;
        $this.Token
        $this.AuthenticationResult
        write-verbose "results saved in `$this.authenticationResult and `$this.Token"
        return $true
    }

    [KustoObj] Pipe() {
        if ($this.pipeLine) {
            return $this
        }
        return $null
    }

    hidden [object] Post([string]$body = "") {
        # authorize aad to get token
        [string]$kustoHost = "$($this.cluster).kusto.windows.net"
        [string]$kustoResource = "https://$kustoHost"
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
                write-error "unable to acquire token. exiting"
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
     
    [KustoObj] SetCluster([string]$cluster) {
        $this.Cluster = $cluster
        return $this.Pipe()
    }
      
    [KustoObj] SetDatabase([string]$database) {
        $this.Database = $database
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
}
      
$error.Clear()
  
if ($updateScript) {
    (new-object net.webclient).downloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/kusto-rest.ps1", "$psscriptroot/kusto-rest.ps1");
    write-warning "script updated. restart script"
    return
}

if ($clean) {
    $paths = @("$env:temp\$msalUtilityFileName", "$env:temp\.net\$msalUtilityFileName", "$env:temp\$msalUtilityFileName.zip", "$psscriptroot\nuget.exe")
    foreach ($path in $paths) {    
        if ((test-path $path)) {
            Write-Warning "deleting $path"
            remove-item -Path $path -Recurse -Force
        }
    }
    return
}

$global:kusto = [KustoObj]::new()
$kusto.Exec()
     
if ($error) {
    write-warning ($error | out-string)
}
else {
    $kusto | Get-Member
    write-host "use `$kusto object to set properties and run queries. example: `$this.Exec('.show operations')" -ForegroundColor Green
}
