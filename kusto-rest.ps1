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

.PARAMETER parameters
    [hashtable]optional hashtable of parameters to pass to kusto script (.csl|kusto) file

.PARAMETER updateScript
    [switch]optional enable to download latest version of script

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
     #[string]$resourceUrl, # = "https://{{kusto cluster}}.kusto.windows.net"
     [bool]$force,
     [string]$msalUtility = "https://api.github.com/repos/jagilber/netCore/releases",
     [string]$msalUtilityFileName = "netCoreMsal",
     [switch]$updateScript,
     [hashtable]$parameters = @{ } #@{'clusterName' = $resourceGroup; 'dnsName' = $resourceGroup;}
 )
      
 $ErrorActionPreference = "continue"
 $global:kusto = $null
      
 class KustoObj {
     [object]$adalDll = $null
     [string]$adalDllLocation = $adalDllLocation
     [object]$authenticationResult
     [string]$clientId = $clientID
     hidden [string]$clientSecret = $clientSecret
     [string]$cluster = $cluster
     [string]$database = $database
     [bool]$fixDuplicateColumns = $fixDuplicateColumns
     [bool]$force = $force
     [int]$limit = $limit
     [string]$msalUtility = $msalUtility
     [string]$msalUtilityFileName = $msalUtilityFileName
     [hashtable]$parameters = $parameters
     [bool]$pipeLine = $null
     [string]$query = $query
     hidden [string]$redirectUri = $redirectUri
     [bool]$removeEmptyColumns = $removeEmptyColumns
     [object]$result = $null
     [object]$resultObject = $null
     [object]$resultTable = $null
     [string]$resultFile = $resultFile
     [string]$script = $script
     [string]$table = $table
     [string]$tenantId = $tenantId
     [string]$token = $token
     [bool]$viewResults = $viewResults
     hidden [string]$wellknownClientId = $wellknownClientId
          
     KustoObj() { }
     static KustoObj() { }
      
     hidden [bool] CheckAdal() {
         [object]$kusto = $this
         [string]$packageName = "Microsoft.IdentityModel.Clients.ActiveDirectory"
         [string]$outputDirectory = "$($env:USERPROFILE)\.nuget\packages"
         [string]$nugetSource = "https://api.nuget.org/v3/index.json"
         [string]$nugetDownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
      
         if (!$kusto.force -and $kusto.adalDll) {
             write-warning 'adal already set. use -force to force'
             return $true
         }
      
         [io.directory]::createDirectory($outputDirectory)
         [string]$packageDirectory = "$outputDirectory\$packageName"
         [string]$edition = "net45"
              
         $kusto.adalDllLocation = @(get-childitem -Path $packageDirectory -Recurse | where-object FullName -match "$edition\\$packageName\.dll" | select-object FullName)[-1].FullName
      
         if (!$kusto.adalDllLocation) {
             if (!($env:path.contains(";$pwd;$env:temp"))) { 
                 $env:path += ";$pwd;$env:temp" 
                      
                 if ($PSScriptRoot -and !($env:path.contains(";$psscriptroot"))) {
                     $env:path += ";$psscriptroot" 
                 }
             } 
          
             if (!(test-path nuget)) {
                 (new-object net.webclient).downloadFile($nugetDownloadUrl, "$pwd\nuget.exe")
             }
      
             [string]$localPackages = nuget list -Source $outputDirectory
      
             if ($kusto.force -or !($localPackages -imatch $packageName)) {
                 write-host "nuget install $packageName -Source $nugetSource -outputdirectory $outputDirectory -verbosity detailed"
                 nuget install $packageName -Source $nugetSource -outputdirectory $outputDirectory -verbosity detailed
                 $kusto.adalDllLocation = @(get-childitem -Path $packageDirectory -Recurse | where-object FullName -match "$edition\\$packageName\.dll" | select-object FullName)[-1].FullName
             }
             else {
                 write-host "$packageName already installed" -ForegroundColor green
             }
         }
      
         write-host "adalDll: $($kusto.adalDllLocation)" -ForegroundColor Green
         #import-module $($kusto.adalDll.FullName)
         $kusto.adalDll = [Reflection.Assembly]::LoadFile($kusto.adalDllLocation) 
         $kusto.adalDll
         $kusto.adalDllLocation = $kusto.adalDll.Location
         return $true
     }
      
     [KustoObj] CreateResultTable() {
         [object]$kusto = $this
         $kusto.resultTable = [collections.arraylist]@()
         $columns = @{ }
      
         if (!$kusto.resultObject.tables) {
             write-warning "run query first"
             return $this.Pipe()
         }
      
         foreach ($column in ($kusto.resultObject.tables[0].columns)) {
             try {
                 [void]$columns.Add($column.ColumnName, $null)                 
             }
             catch {
                 write-warning "$($column.ColumnName) already added"
             }
         }
      
         $resultModel = New-Object -TypeName PsObject -Property $columns
         $rowCount = 0
    
         foreach ($row in ($kusto.resultObject.tables[0].rows)) {
             $count = 0
             $resultCopy = $resultModel.PsObject.Copy()
                
             foreach ($column in ($kusto.resultObject.tables[0].columns)) {
                 #write-verbose "createResultTable: procesing column $count"
                 $resultCopy.($column.ColumnName) = $row[$count++]
             }
   
             write-verbose "createResultTable: procesing row $rowCount columns $count"
             $rowCount++
      
             [void]$kusto.resultTable.add($resultCopy)
         }
         $kusto.resultTable = $this.RemoveEmptyResults($kusto.resultTable)
         return $this.Pipe()
     }
      
     [KustoObj] Pipe() {
         if ($this.pipeLine) {
             return $this
         }
         return $null
     }
      
     [KustoObj] Exec([string]$query) {
         $this.query = $query
         $this.Exec()
         $this.query = $null
         return $this.Pipe()
     }
      
     [KustoObj] Exec() {
         [object]$kusto = $this
         $startTime = get-date
         $kusto
      
         if (!$kusto.limit) {
             $kusto.limit = 10000
         }
      
         if (!$kusto.script -and !$kusto.query) {
             Write-Warning "-script and / or -query should be set. exiting"
             return $this.Pipe()
         }
      
         if (!$kusto.cluster -or !$kusto.database) {
             Write-Warning "-cluster and -database have to be set once. exiting"
             return $this.Pipe()
         }
      
         if ($kusto.query) {
             write-host "table:$($kusto.table) query:$($kusto.query.substring(0, [math]::min($kusto.query.length,512)))" -ForegroundColor Cyan
         }
      
         if ($kusto.script) {
             write-host "script:$($kusto.script)" -ForegroundColor Cyan
         }
      
         if ($kusto.table -and $kusto.query.startswith("|")) {
             $kusto.query = $kusto.table + $kusto.query
         }
     
         $kusto.resultObject = $this.Post($null)
     
         if ($kusto.resultObject.Exceptions) {
             write-warning ($kusto.resultObject.Exceptions | out-string)
             $kusto.resultObject.Exceptions = $null
         }
      
         if ($kusto.viewResults) {
             $this.CreateResultTable()
             write-host ($kusto.resultTable | out-string)
         }
      
         if ($kusto.resultFile) {
             out-file -FilePath $kusto.resultFile -InputObject  ($kusto.resultObject | convertto-json -Depth 99)
         }
      
         $primaryResult = $kusto.resultObject | where-object TableKind -eq PrimaryResult
          
         if ($primaryResult) {
             write-host ($primaryResult.columns | out-string)
             write-host ($primaryResult.Rows | out-string)
         }
      
         if ($kusto.resultObject.tables) {
             write-host "results: $($kusto.resultObject.tables[0].rows.count) / $(((get-date) - $startTime).TotalSeconds) seconds to execute" -ForegroundColor DarkCyan
             if ($kusto.resultObject.tables[0].rows.count -eq $kusto.limit) {
                 write-warning "results count equals limit $($kusto.limit). results may be incomplete"
             }
         }
         else {
             write-warning "bad result: error:"#$($error)"
         }
         return $this.Pipe()
     }
      
     [KustoObj] ExecScript([string]$script, [hashtable]$parameters) {
         $this.script = $script
         $this.parameters = $parameters
         $this.ExecScript()
         $this.script = $null
         return $this.Pipe()
     }
      
     [KustoObj] ExecScript([string]$script) {
         $this.script = $script
         $this.ExecScript()
         $this.script = $null
         return $this.Pipe()
     }
      
     [KustoObj] ExecScript() {
         [object]$kusto = $this
         if ($kusto.script.startswith('http')) {
             $destFile = "$pwd\$([io.path]::GetFileName($kusto.script))" -replace '\?.*', ''
              
             if (!(test-path $destFile)) {
                 Write-host "downloading $($kusto.script)" -foregroundcolor green
                 (new-object net.webclient).DownloadFile($kusto.script, $destFile)
             }
             else {
                 Write-host "using cached script $($kusto.script)"
             }
      
             $kusto.script = $destFile
         }
          
         if ((test-path $kusto.script)) {
             $kusto.query = (Get-Content -raw -Path $kusto.script)
         }
         else {
             write-error "unknown script:$($kusto.script)"
             return $this.Pipe()
         }
      
         $this.Exec()
         return $this.Pipe()
     }
      
     [void] ExportCsv([string]$exportFile) {
         $this.CreateResultTable()
         [io.directory]::createDirectory([io.path]::getDirectoryName($exportFile))
         $this.resultTable | export-csv -notypeinformation $exportFile
     }
      
     [void] ExportJson([string]$exportFile) {
         $this.CreateResultTable()
         [io.directory]::createDirectory([io.path]::getDirectoryName($exportFile))
         $this.resultTable | convertto-json -depth 99 | out-file $exportFile
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
         if ($this.table) {
             $this.Import($this.table)
         }
         else {
             write-warning "set table name first"
             return
         }
     }
      
     [KustoObj] Import([string]$table) {
         if (!$this.resultObject.Tables) {
             write-warning 'no results to import'
             return $this.Pipe()
         }
      
         [object]$results = $this.resultObject.Tables[0]
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
      
     [KustoObj] ImportCsv([string]$importFile, [string]$table) {
         [object]$kusto = $this
         $kusto.table = $table
         $this.ImportCsv($importFile)
         return $this.Pipe()
     }
      
     [KustoObj] ImportCsv([string]$importFile) {
         if (!(test-path $importFile) -or !$this.table) {
             write-warning "verify importfile: $importFile and import table: $($this.table)"
             return $this.Pipe()
         }
              
         # not working
         #POST https://help.kusto.windows.net/v1/rest/ingest/Test/Logs?streamFormat=Csv HTTP/1.1
         #[string]$csv = Get-Content -Raw $importFile -encoding utf8
         #$this.Post($csv)
      
         $sr = new-object io.streamreader($importFile) 
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
      
         #$this.Exec(".drop table ['$($this.table)'] ifexists")
         $this.Exec(".create table ['$($this.table)'] $formattedHeaders") 
         $this.Exec(".ingest inline into table ['$($this.table)'] <| $($csv.tostring())")
         return $this.Pipe()
     }
      
     [bool] Logon($resourceUrl) {
         [object]$kusto = $this
         [object]$authenticationContext = $Null
         [string]$ADauthorityURL = "https://login.microsoftonline.com/$($kusto.tenantId)"
      
         if (!$resourceUrl) {
             write-warning "-resourceUrl required. example: https://{{ kusto cluster }}.kusto.windows.net"
             return $false
         }
      
         if (!$kusto.force -and $kusto.AuthenticationResult.expireson -gt (get-date)) {
             write-verbose "token valid: $($kusto.AuthenticationResult.expireson). use -force to force logon"
             return $true
         }
    
         if ($global:PSVersionTable.PSEdition -eq "Core") {
             [string]$utilityFileName = $this.msalUtilityFileName
             [string]$utility = $this.msalUtility
             [string]$filePath = "$env:TEMP\$utilityFileName"
             write-warning ".net core microsoft.identity requires form/webui. checking for $filePath"
               
             if (!(test-path $filePath)) {
                 if ((read-host "is it ok to download .net core Msal utility $utility/$utilityFileName to generate token?`r`n if not, for .net core, you will need to generate and pass token to script.[y|n]") -ilike "y") {
                     write-warning "downloading .net core $utilityFileName from $utility to $filePath"
                     [psobject]$apiResults = convertfrom-json (Invoke-WebRequest $utility -UseBasicParsing)
                     [string]$downloadUrl = @($apiResults.assets.browser_download_url -imatch "/$utilityFileName-")[0]
                     (new-object net.webclient).downloadFile($downloadUrl, "$filePath.zip")
                     Expand-Archive "$filePath.zip" $filePath
                 }
                 else {
                     write-warning "returning"
                     return $false
                 }
             }
    
             [string]$resultJsonText = (. "$filePath\$utilityFileName.exe" --resource "https://$($kusto.cluster).kusto.windows.net")
             write-host "preauth: $resultJsonText" -foregroundcolor green
             $resultJsonText = (. "$filePath\$utilityFileName.exe" --resource "https://$($kusto.cluster).kusto.windows.net" --scope "https://$($kusto.cluster).kusto.windows.net/kusto.read,https://$($kusto.cluster).kusto.windows.net/kusto.write")
             $kusto.authenticationResult = $resultJsonText | convertfrom-json
             $kusto.token = $kusto.authenticationResult.AccessToken
             write-host ($kusto.authenticationResult | convertto-json)
    
             if ($kusto.token) {
                 return $true
             }
             return $false
         }
         elseif (!($this.CheckAdal())) { return $false }
     
         $authenticationContext = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext($ADAuthorityURL)
      
         if ($kusto.clientid -and $kusto.clientSecret) {
             # client id / secret
             $kusto.authenticationResult = $authenticationContext.AcquireTokenAsync($resourceUrl, 
                 (new-object Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential($kusto.clientId, $kusto.clientSecret))).Result
         }
         else {
             # user / pass
             $error.Clear()
             $kusto.authenticationResult = $authenticationContext.AcquireTokenAsync($resourceUrl, 
                 $kusto.wellknownClientId,
                 (new-object Uri($kusto.redirectUri)),
                 (new-object Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters(0))).Result # auto
              
             if ($error) {
                 # MFA
                 $kusto.authenticationResult = $authenticationContext.AcquireTokenAsync($resourceUrl, 
                     $kusto.wellknownClientId,
                     (new-object Uri($kusto.redirectUri)),
                     (new-object Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters(1))).Result # [promptbehavior]::always
             }
         }
      
         if (!($kusto.authenticationResult)) {
             write-error "error authenticating"
             #write-host (Microsoft.IdentityModel.Clients.ActiveDirectory.AdalError)
             return $false
         }
         write-verbose (convertto-json $kusto.authenticationResult -Depth 99)
         $kusto.token = $kusto.authenticationResult.AccessToken;
         $kusto.token
         $kusto.AuthenticationResult
         write-verbose "results saved in `$kusto.authenticationResult and `$kusto.token"
         return $true
     }
      
     hidden [object] Post([string]$body = "") {
         # authorize aad to get token
         [object]$kusto = $this
         [string]$kustoHost = "$($kusto.cluster).kusto.windows.net"
         [string]$kustoResource = "https://$kustoHost"
         [string]$csl = "$($kusto.query)"
          
         $kusto.resultObject = $null
         $kusto.query = $kusto.query.trim()
     
         if ($body -and ($kusto.table)) {
             $uri = "$kustoResource/v1/rest/ingest/$($kusto.database)/$($kusto.table)?streamFormat=Csv&mappingName=CsvMapping"
         }
         elseif ($kusto.query.startswith('.show') -or !$kusto.query.startswith('.')) {
             $uri = "$kustoResource/v1/rest/query"
             $csl = "$($kusto.query) | limit $($kusto.limit)"
         }
         else {
             $uri = "$kustoResource/v1/rest/mgmt"
         }
      
         if (!$kusto.token) {
             if (!($this.Logon($kustoResource))) {
                 write-error "unable to acquire token. exiting"
                 return $error
             }
         }
      
         $requestId = [guid]::NewGuid().ToString()
         write-verbose "request id: $requestId"
      
         $header = @{
             'accept'                 = 'application/json'
             'authorization'          = "Bearer $($kusto.token)"
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
                 db         = $kusto.database
                 csl        = $csl
                 properties = @{
                     Options    = @{
                         queryconsistency = "strongconsistency"
                     }
                     Parameters = $kusto.parameters
                 }
             } | ConvertTo-Json
         }
      
         write-verbose ($header | convertto-json)
         write-verbose $body
      
         $error.clear()
         $kusto.result = Invoke-WebRequest -Method Post -Uri $uri -Headers $header -Body $body
         write-verbose $kusto.result
          
         if ($error) {
             return $error
         }
     
         try {
             return ($this.FixColumns($kusto.result.content) | convertfrom-json)
         }
         catch {
             write-warning "error converting json result to object. unparsed results in `$kusto.result`r`n$error"
                  
             if (!$this.fixDuplicateColumns) {
                 write-warning "$kusto.fixDuplicateColumns = $true may resolve."
             }
             return ($kusto.result.content)
         }
     }
      
     [collections.arrayList] RemoveEmptyResults([collections.arrayList]$sourceContent) {
         if (!$this.removeEmptyColumns -or !$sourceContent -or $sourceContent.count -eq 0) {
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
         $this.cluster = $cluster
         return $this.Pipe()
     }
      
     [KustoObj] SetDatabase([string]$database) {
         $this.database = $database
         return $this.Pipe()
     }
      
     [KustoObj] SetPipe([bool]$enable) {
         $this.pipeLine = $enable
         return $this.Pipe()
     }
      
     [KustoObj] SetTable([string]$table) {
         $this.table = $table
         return $this.Pipe()
     }
 }
      
 $error.Clear()
  
 if ($updateScript) {
     (new-object net.webclient).downloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/kusto-rest.ps1", "$psscriptroot/kusto-rest.ps1");
     write-warning "script updated. restart script"
     return
 }
   
 $global:kusto = [KustoObj]::new()
 $kusto.Exec()
     
 if ($error) {
     write-warning ($error | out-string)
 }
 else {
     $kusto | Get-Member
     write-host "use `$kusto object to set properties and run queries. example: `$kusto.Exec('.show operations')" -ForegroundColor Green
 }
  