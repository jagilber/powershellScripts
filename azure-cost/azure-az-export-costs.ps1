<#!
.SYNOPSIS
    Query daily Azure cost for a subscription (current day by default).
.DESCRIPTION
    Uses Cost Management Query REST API to retrieve daily cost aggregated by Resource Group for a provided date or range.
    Handles Azure authentication with options for interactive/device code or managed identity.
.PARAMETER SubscriptionId
    Target subscription Id (mandatory).
.PARAMETER TenantId
    Optional tenant Id; if supplied ensures login context uses this tenant.
.PARAMETER StartDate
    Start date (yyyy-MM-dd). Defaults to today.
.PARAMETER EndDate
    End date (yyyy-MM-dd). Defaults to StartDate.
.PARAMETER GroupBy
    Dimension to group costs by: ResourceGroup (default), ResourceType, ServiceName, ResourceGroupAndType, or All (no grouping).
.PARAMETER UseDeviceCode
    Use device code auth instead of default browser/integrated flow.
.PARAMETER ManagedIdentity
    Use managed identity (for automation in Azure).
.PARAMETER ForceLogin
    Forces a fresh login even if a context exists.
.PARAMETER OutputPath
    Optional path to write results (CSV & JSON). Base filename only; date & extensions appended.
.PARAMETER IncludeUsageDetails
    Fetch detailed usage records including quantities, meters, and units. Note: Can be slower for large date ranges.
.PARAMETER ExportFormat
    Export format: CSV (default), JSON, JSONL (line-delimited for Kusto), or Both (CSV + JSONL).
.PARAMETER EnableTrendAnalysis
    Compare current period with prior year to identify: new services, price changes, quantity changes, and cost trends.
.EXAMPLE
    .\azure-az-export-costs.ps1 -SubscriptionId <subId>
.EXAMPLE
    .\azure-az-export-costs.ps1 -SubscriptionId <subId> -StartDate 2025-09-01 -EndDate 2025-09-15 -OutputPath .\cost
.EXAMPLE
    .\azure-az-export-costs.ps1 -SubscriptionId <subId> -StartDate 2024-10-01 -EndDate 2025-09-30 -EnableTrendAnalysis -IncludeUsageDetails
.EXAMPLE
    .\azure-az-export-costs.ps1 -SubscriptionId <subId> -ManagedIdentity
.NOTES
    Requires Az.Accounts & Az.CostManagement (for token) though token call is generic. API version 2023-03-01.
#>

[CmdletBinding()] 
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,
    [Parameter()]
    [string]$TenantId,
    [Parameter()]
    [string]$StartDate = (Get-Date -Format 'yyyy-MM-dd'),
    [Parameter()]
    [string]$EndDate,
    [Parameter()]
    [ValidateSet('ResourceGroup', 'ResourceType', 'ServiceName', 'ResourceGroupAndType', 'MeterCategory', 'MeterSubcategory', 'ResourceLocation', 'All')]
    [string]$GroupBy = 'ResourceGroup',
    [switch]$UseDeviceCode,
    [switch]$ManagedIdentity,
    [switch]$ForceLogin,
    [string]$OutputPath,
    [switch]$IncludeUsageDetails,
    [ValidateSet('CSV', 'JSON', 'JSONL', 'Both')]
    [string]$ExportFormat = 'CSV',
    [switch]$EnableTrendAnalysis,
    [switch]$DebugAuth
)

if(-not $EndDate) { $EndDate = $StartDate }

$ErrorActionPreference = 'Stop'

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Warning $Message }

Write-Info "Validating Az module(s) availability..."
if(-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    throw 'Az.Accounts module not found. Install with: Install-Module Az -Scope CurrentUser'
}

if($ManagedIdentity -and $UseDeviceCode) { throw 'Specify only one of -ManagedIdentity or -UseDeviceCode.' }

function Invoke-Auth {
    param(
        [string]$SubId,
        [string]$Tid,
        [switch]$Force,
        [switch]$MI,
        [switch]$Device
    )
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if($Force -or -not $ctx -or ($ctx.Subscription.Id -ne $SubId)) {
        Write-Info "Logging in... (Force=$Force MI=$MI Device=$Device)"
        if($MI) {
            Connect-AzAccount -Identity | Out-Null
        } elseif($Device) {
            if($Tid) { Connect-AzAccount -Tenant $Tid -DeviceCode | Out-Null } else { Connect-AzAccount -DeviceCode | Out-Null }
        } else {
            if($Tid) { Connect-AzAccount -Tenant $Tid | Out-Null } else { Connect-AzAccount | Out-Null }
        }
    }
    Set-AzContext -SubscriptionId $SubId | Out-Null
    Write-Info "Context set to subscription $SubId"
}

Invoke-Auth -SubId $SubscriptionId -Tid $TenantId -Force:$ForceLogin -MI:$ManagedIdentity -Device:$UseDeviceCode

# Flexible date parsing and validation
function ConvertTo-IsoDate {
    param([string]$DateString)
    
    $parsedDate = [DateTime]::MinValue
    if(-not [DateTime]::TryParse($DateString, [ref]$parsedDate)) {
        throw "Cannot parse date value '$DateString'. Please use a valid date format (e.g., yyyy-MM-dd, M/d/yyyy, etc.)"
    }
    
    # Convert to ISO format required by API
    return $parsedDate.ToString('yyyy-MM-dd')
}

# Parse and normalize dates
try {
    $StartDate = ConvertTo-IsoDate -DateString $StartDate
    if(-not $EndDate) { 
        $EndDate = $StartDate 
    } else {
        $EndDate = ConvertTo-IsoDate -DateString $EndDate
    }
} catch {
    throw "Date validation failed: $($_.Exception.Message)"
}

Write-Info "Using StartDate=$StartDate EndDate=$EndDate"

# Basic date validation ordering
if([DateTime]::Parse($EndDate) -lt [DateTime]::Parse($StartDate)) { 
    throw 'EndDate cannot be earlier than StartDate.' 
}

# Calculate date range and determine if chunking is needed
$startParsed = [DateTime]::Parse($StartDate)
$endParsed = [DateTime]::Parse($EndDate)
$dateRangeDays = ($endParsed - $startParsed).Days

# Azure Cost Management API supports up to ~13 months (395 days) per query
# We'll chunk any range > 365 days (12 months) to be safe
$needsChunking = $dateRangeDays -gt 365
$chunks = @()

if($needsChunking) {
    Write-Info "Large date range detected ($dateRangeDays days). Splitting into monthly chunks..."
    
    $currentStart = $startParsed
    while($currentStart -lt $endParsed) {
        $currentEnd = $currentStart.AddMonths(1).AddDays(-1)
        if($currentEnd -gt $endParsed) {
            $currentEnd = $endParsed
        }
        
        $chunks += [PSCustomObject]@{
            Start = $currentStart.ToString('yyyy-MM-dd')
            End = $currentEnd.ToString('yyyy-MM-dd')
            Label = $currentStart.ToString('yyyy-MM')
        }
        
        $currentStart = $currentEnd.AddDays(1)
    }
    
    Write-Info "Split into $($chunks.Count) monthly chunks"
} else {
    # Single chunk for date ranges <= 12 months
    $chunks = @([PSCustomObject]@{
        Start = $StartDate
        End = $EndDate
        Label = "Full Range"
    })
}

# Build grouping configuration based on GroupBy parameter
$groupingConfig = @()
switch ($GroupBy) {
    'ResourceGroup' {
        $groupingConfig = @(
            @{ type = "Dimension"; name = "ResourceGroup" }
        )
        Write-Info "Grouping by: Resource Group"
    }
    'ResourceType' {
        $groupingConfig = @(
            @{ type = "Dimension"; name = "ResourceType" }
        )
        Write-Info "Grouping by: Resource Type"
    }
    'ServiceName' {
        $groupingConfig = @(
            @{ type = "Dimension"; name = "ServiceName" }
        )
        Write-Info "Grouping by: Service Name"
    }
    'MeterCategory' {
        $groupingConfig = @(
            @{ type = "Dimension"; name = "MeterCategory" }
        )
        Write-Info "Grouping by: Meter Category (Service Family)"
    }
    'MeterSubcategory' {
        $groupingConfig = @(
            @{ type = "Dimension"; name = "MeterSubcategory" }
        )
        Write-Info "Grouping by: Meter Subcategory (includes VM SKUs, storage types, etc.)"
    }
    'ResourceLocation' {
        $groupingConfig = @(
            @{ type = "Dimension"; name = "ResourceLocation" }
        )
        Write-Info "Grouping by: Resource Location (Azure Region)"
    }
    'ResourceGroupAndType' {
        $groupingConfig = @(
            @{ type = "Dimension"; name = "ResourceGroup" },
            @{ type = "Dimension"; name = "ResourceType" }
        )
        Write-Info "Grouping by: Resource Group and Resource Type"
    }
    'All' {
        $groupingConfig = @()
        Write-Info "No grouping - returning aggregate totals"
    }
}

Write-Info "Acquiring access token..."
$tokenResource = 'https://management.azure.com/'  # trailing slash sometimes required
$AccessToken = $null
try {
    $tokenResponse = Get-AzAccessToken -ResourceUrl $tokenResource -ErrorAction Stop
    $AccessToken = $tokenResponse.Token
} catch {
    Write-Warn "Primary token request failed: $($_.Exception.Message)"
    if(-not $ForceLogin) {
        Write-Info "Forcing re-login and retrying token acquisition..."
        Invoke-Auth -SubId $SubscriptionId -Tid $TenantId -Force -MI:$ManagedIdentity -Device:$UseDeviceCode
        $tokenResponse = Get-AzAccessToken -ResourceUrl $tokenResource -ErrorAction Stop
        $AccessToken = $tokenResponse.Token
    } else { throw }
}

if(-not $AccessToken) { throw 'Failed to acquire access token.' }

if($DebugAuth) {
    Write-Info "Access token acquired. Length=$($AccessToken.Length) ExpiresOn=$($tokenResponse.ExpiresOn)"
    # Decode header & payload (not signature) for debugging without leaking full token structure
    function Decode-Part($seg){
        try { $p=$seg.Replace('-', '+').Replace('_','/'); switch($p.Length %4){0{};2{$p+='=='};3{$p+='='}}; [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) } catch { '<decode-failed>' }
    }
    $parts = $AccessToken.Split('.')
    if($parts.Count -ge 2) {
        $hdr = Decode-Part $parts[0] | ConvertFrom-Json -ErrorAction SilentlyContinue
        $pl  = Decode-Part $parts[1] | ConvertFrom-Json -ErrorAction SilentlyContinue
        Write-Info ("Token header alg={0} kid={1}" -f $hdr.alg, $hdr.kid)
        Write-Info ("Token payload aud={0} appid={1} upn={2} roles={3}" -f $pl.aud, $pl.appid, $pl.upn, ($pl.roles -join ','))
    }
}

# Define endpoint
$CostManagementEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/query?api-version=2023-03-01"

# Process each chunk and accumulate results
$allRows = @()
$chunkNum = 0

foreach($chunk in $chunks) {
    $chunkNum++
    Write-Info "Fetching cost summary for chunk $chunkNum/$($chunks.Count): $($chunk.Label) ($($chunk.Start) to $($chunk.End))..."
    
    # Create the query body for this chunk
    $QueryBody = @{
        type = "Usage"
        timeframe = "Custom"
        timePeriod = @{
            from = $chunk.Start
            to = $chunk.End
        }
        dataset = @{
            granularity = "Daily"
            aggregation = @{
                totalCost = @{
                    name = "Cost"
                    function = "Sum"
                }
            }
        }
    }

    # Add grouping if specified
    if ($groupingConfig.Count -gt 0) {
        $QueryBody.dataset.grouping = $groupingConfig
    }

    # Convert to JSON
    $QueryJson = $QueryBody | ConvertTo-Json -Depth 10

    # Make the API request (primary path)
    try {
        $response = Invoke-RestMethod -Uri $CostManagementEndpoint -Method Post -Headers @{
            Authorization = "Bearer $AccessToken"
            "Content-Type" = "application/json"
        } -Body $QueryJson -ErrorAction Stop
    } catch {
        Write-Warn "Primary REST call failed for chunk ${chunkNum}: $($_.Exception.Message)"
        if($_.ErrorDetails -and $_.ErrorDetails.Message -match 'InvalidAuthenticationToken') {
            Write-Info 'Attempting fallback via Invoke-AzRest...'
            # Invoke-AzRestMethod expects string payload, not byte[]
            $azRest = Invoke-AzRestMethod -Method POST -Path "/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/query?api-version=2023-03-01" -Payload $QueryJson -ErrorAction Stop
            if($azRest.StatusCode -ge 200 -and $azRest.StatusCode -lt 300) {
                $response = $azRest.Content | ConvertFrom-Json
            } else {
                Write-Warning "Chunk $chunkNum failed with status $($azRest.StatusCode). Skipping..."
                continue
            }
        } else {
            Write-Warning "Chunk $chunkNum failed - $($_.Exception.Message). Skipping..."
            continue
        }
    }

    if(-not $response.properties) {
        Write-Warning "Chunk $chunkNum returned unexpected format. Skipping..."
        continue
    }

    # Shape rows dynamically if present
    if($response.properties.columns -and $response.properties.rows) {
        # Build column index map
        $colMap = @{}
        for($i=0; $i -lt $response.properties.columns.Count; $i++) {
            $name = $response.properties.columns[$i].name
            if(-not $colMap.ContainsKey($name)) { $colMap[$name] = $i }
        }
        
        # Find date column
        $dateIdx = $colMap['UsageDate']
        if(-not $dateIdx -and $colMap.ContainsKey('Date')) { $dateIdx = $colMap['Date'] }
        
        # Find cost column
        $costIdx = $colMap['Cost']
        if(-not $costIdx -and $colMap.ContainsKey('PreTaxCost')) { $costIdx = $colMap['PreTaxCost'] }
        
        # Identify all dimension columns dynamically
        $dimensionColumns = @('ResourceGroup', 'ResourceType', 'ServiceName', 'ResourceId', 'MeterCategory', 'MeterSubcategory', 'ResourceLocation', 'Meter', 'ProductName', 'PublisherType')
        
        if($chunkNum -eq 1) {
            Write-Verbose "Available columns: $($colMap.Keys -join ', ')"
        }

        $chunkRows = $response.properties.rows | ForEach-Object {
            $rawCost = $null
            if($costIdx -ne $null -and $costIdx -lt $_.Count) { $rawCost = $_[$costIdx] }
            $costVal = $null
            if($rawCost -ne $null -and ($rawCost -as [decimal]) -ne $null) { $costVal = [decimal]$rawCost } else { $costVal = 0 }
            
            # Extract date value
            $dateVal = $null
            if($dateIdx -ne $null -and $dateIdx -lt $_.Count) { $dateVal = $_[$dateIdx] }
            
            # Build object with all available dimension columns dynamically
            $rowObj = [PSCustomObject]@{
                Date = $dateVal
                Cost = $costVal
            }
            
            # Add dimension columns that exist in the response
            foreach($dimCol in $dimensionColumns) {
                if($colMap.ContainsKey($dimCol)) {
                    $idx = $colMap[$dimCol]
                    $val = if($idx -ne $null -and $idx -lt $_.Count) { $_[$idx] } else { $null }
                    $rowObj | Add-Member -NotePropertyName $dimCol -NotePropertyValue $val
                }
            }
            
            $rowObj
        }
        
        $allRows += $chunkRows
        Write-Verbose "Chunk ${chunkNum}: Retrieved $($chunkRows.Count) rows"
    } elseif($response.properties.rows) {
        Write-Warn "Chunk ${chunkNum}: Columns metadata missing; rows cannot be reliably shaped."
    }
}

# Use accumulated rows
$rows = $allRows

Write-Info ("Returned {0} row(s)." -f $rows.Count)

# Fetch usage details if requested
$usageDetails = @()
if($IncludeUsageDetails) {
    Write-Info "Fetching detailed usage records..."
    
    # Reuse the same chunks from cost summary query
    $usageChunkNum = 0
    foreach($chunk in $chunks) {
        $usageChunkNum++
        Write-Info "Processing usage details for chunk $usageChunkNum/$($chunks.Count): $($chunk.Label) ($($chunk.Start) to $($chunk.End))..."
        
        # Use Cost Management API for usage details with daily granularity and resource-level grouping
        $usageQuery = @{
            type = 'Usage'
            timeframe = 'Custom'
            timePeriod = @{ from = $chunk.Start; to = $chunk.End }
            dataset = @{
                granularity = 'None'
                aggregation = @{
                    totalCost = @{ name = 'Cost'; function = 'Sum' }
                    totalQuantity = @{ name = 'UsageQuantity'; function = 'Sum' }
                }
                grouping = @(
                    @{ name = 'ResourceId'; type = 'Dimension' }
                    @{ name = 'MeterCategory'; type = 'Dimension' }
                    @{ name = 'MeterSubCategory'; type = 'Dimension' }
                    @{ name = 'Meter'; type = 'Dimension' }
                    @{ name = 'ResourceLocation'; type = 'Dimension' }
                )
            }
        }
        
        $usageQueryJson = $usageQuery | ConvertTo-Json -Depth 10 -Compress
        Write-Verbose "  API Query: $usageQueryJson"
        
        try {
            # Try primary REST call first
            $usageResult = try {
                Invoke-RestMethod -Uri $CostManagementEndpoint -Method Post -Headers @{
                    Authorization = "Bearer $AccessToken"
                    'Content-Type' = 'application/json'
                } -Body $usageQueryJson -ErrorAction Stop
            } catch {
                Write-Verbose "Primary call failed, using Invoke-AzRest fallback"
                $azRestResult = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/query?api-version=2023-11-01" -Method POST -Payload $usageQueryJson -ErrorAction Stop
                if($azRestResult.StatusCode -ne 200) {
                    throw "Fallback failed with status $($azRestResult.StatusCode)"
                }
                $azRestResult.Content | ConvertFrom-Json
            }
            
            # Parse Cost Management API response (columns + rows format)
            if($usageResult.properties -and $usageResult.properties.rows) {
                $recordCount = $usageResult.properties.rows.Count
                Write-Verbose "  Usage chunk ${usageChunkNum}: Retrieved $recordCount usage detail records"
                
                # Map column indices
                $columns = $usageResult.properties.columns
                $colMap = @{}
                for($i = 0; $i -lt $columns.Count; $i++) {
                    $colMap[$columns[$i].name] = $i
                }
                
                # Parse rows into objects
                $usageDetails += $usageResult.properties.rows | ForEach-Object {
                    $row = $_
                    
                    # Extract resource group from ResourceId
                    $resourceId = if($colMap.ContainsKey('ResourceId')) { $row[$colMap['ResourceId']] } else { '' }
                    $resourceGroup = if($resourceId -match '/resourceGroups/([^/]+)') { $matches[1] } else { 'N/A' }
                    $resourceName = if($resourceId) { ($resourceId -split '/')[-1] } else { 'N/A' }
                    
                    # Extract resource type
                    $resourceType = if($resourceId -match '/providers/([^/]+/[^/]+)') { $matches[1] } else { 'N/A' }
                    
                    $cost = if($colMap.ContainsKey('Cost')) { [decimal]$row[$colMap['Cost']] } else { 0 }
                    $quantity = if($colMap.ContainsKey('UsageQuantity')) { [decimal]$row[$colMap['UsageQuantity']] } else { 0 }
                    
                    [PSCustomObject]@{
                        Date = $chunk.Start  # Since granularity is None, use chunk date
                        ResourceGroup = $resourceGroup
                        ResourceName = $resourceName
                        ResourceId = $resourceId
                        ResourceType = $resourceType
                        MeterCategory = if($colMap.ContainsKey('MeterCategory')) { $row[$colMap['MeterCategory']] } else { '' }
                        MeterSubcategory = if($colMap.ContainsKey('MeterSubCategory')) { $row[$colMap['MeterSubCategory']] } else { '' }
                        MeterName = if($colMap.ContainsKey('Meter')) { $row[$colMap['Meter']] } else { '' }
                        Quantity = $quantity
                        Unit = if($colMap.ContainsKey('UnitOfMeasure')) { $row[$colMap['UnitOfMeasure']] } else { '' }
                        Cost = $cost
                        EffectivePrice = if($quantity -gt 0) { $cost / $quantity } else { 0 }
                        ResourceLocation = if($colMap.ContainsKey('ResourceLocation')) { $row[$colMap['ResourceLocation']] } else { '' }
                        SubscriptionId = $SubscriptionId
                    }
                }
            }
        } catch {
            Write-Warning "Failed to fetch usage details for chunk $usageChunkNum ($($chunk.Label)) - $($_.Exception.Message)"
        }
    }
    
    if($usageDetails.Count -gt 0) {
        Write-Info ("Total usage records retrieved across all chunks: {0}" -f $usageDetails.Count)
    } else {
        Write-Warn "No usage details retrieved. Continuing with cost summary only..."
    }
}

# Year-over-Year Trend Analysis
$trendAnalysis = $null
if($EnableTrendAnalysis) {
    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "  TREND ANALYSIS (YoY Comparison)" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    
    Write-Info "Fetching prior year data for comparison..."
    
    # Calculate prior year dates
    $priorStartDate = ([DateTime]::Parse($StartDate)).AddYears(-1).ToString('yyyy-MM-dd')
    $priorEndDate = ([DateTime]::Parse($EndDate)).AddYears(-1).ToString('yyyy-MM-dd')
    
    Write-Info "Prior Period: $priorStartDate to $priorEndDate"
    
    # Build query for prior year (using same grouping)
    $priorDimensions = switch ($GroupBy) {
        'ResourceGroup' { @(@{name='ResourceGroupName'; type='Dimension'}) }
        'ResourceType' { @(@{name='ResourceType'; type='Dimension'}) }
        'ServiceName' { @(@{name='ServiceName'; type='Dimension'}) }
        'MeterCategory' { @(@{name='MeterCategory'; type='Dimension'}) }
        'MeterSubcategory' { @(@{name='MeterSubCategory'; type='Dimension'}) }
        'ResourceLocation' { @(@{name='ResourceLocation'; type='Dimension'}) }
        'ResourceGroupAndType' { @(@{name='ResourceGroupName'; type='Dimension'}, @{name='ResourceType'; type='Dimension'}) }
        'All' { @() }
    }
    
    $priorQuery = @{
        type = 'ActualCost'
        timeframe = 'Custom'
        timePeriod = @{ from = $priorStartDate; to = $priorEndDate }
        dataset = @{
            granularity = 'Daily'
            aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }
        }
    }
    if($priorDimensions.Count -gt 0) { $priorQuery.dataset.grouping = $priorDimensions }
    
    $priorQueryJson = $priorQuery | ConvertTo-Json -Depth 10
    
    try {
        $priorResponse = Invoke-RestMethod -Uri $CostManagementEndpoint -Method Post -Headers @{
            Authorization = "Bearer $AccessToken"
            "Content-Type" = "application/json"
        } -Body $priorQueryJson -ErrorAction Stop
        
        # Parse prior year rows
        $priorRows = @()
        if($priorResponse.properties.columns -and $priorResponse.properties.rows) {
            $priorColMap = @{}
            for($i=0; $i -lt $priorResponse.properties.columns.Count; $i++) {
                $name = $priorResponse.properties.columns[$i].name
                if(-not $priorColMap.ContainsKey($name)) { $priorColMap[$name] = $i }
            }
            
            $priorDateIdx = $priorColMap['UsageDate']
            if(-not $priorDateIdx -and $priorColMap.ContainsKey('Date')) { $priorDateIdx = $priorColMap['Date'] }
            $priorCostIdx = $priorColMap['Cost']
            if(-not $priorCostIdx -and $priorColMap.ContainsKey('PreTaxCost')) { $priorCostIdx = $priorColMap['PreTaxCost'] }
            
            $dimensionColumns = @('ResourceGroup', 'ResourceType', 'ServiceName', 'MeterCategory', 'MeterSubcategory', 'ResourceLocation')
            
            $priorRows = $priorResponse.properties.rows | ForEach-Object {
                $rawCost = $null
                if($priorCostIdx -ne $null -and $priorCostIdx -lt $_.Count) { $rawCost = $_[$priorCostIdx] }
                $costVal = if($rawCost -ne $null -and ($rawCost -as [decimal]) -ne $null) { [decimal]$rawCost } else { 0 }
                
                $dateVal = $null
                if($priorDateIdx -ne $null -and $priorDateIdx -lt $_.Count) { $dateVal = $_[$priorDateIdx] }
                
                $rowObj = [PSCustomObject]@{
                    Date = $dateVal
                    Cost = $costVal
                }
                
                foreach($dimCol in $dimensionColumns) {
                    if($priorColMap.ContainsKey($dimCol)) {
                        $idx = $priorColMap[$dimCol]
                        $val = if($idx -ne $null -and $idx -lt $_.Count) { $_[$idx] } else { $null }
                        $rowObj | Add-Member -NotePropertyName $dimCol -NotePropertyValue $val
                    }
                }
                
                $rowObj
            }
        }
        
        Write-Info ("Retrieved {0} prior year row(s)." -f $priorRows.Count)
        
        # Perform trend analysis
        if($priorRows.Count -gt 0) {
            $currentTotal = ($rows | Measure-Object -Property Cost -Sum).Sum
            $priorTotal = ($priorRows | Measure-Object -Property Cost -Sum).Sum
            $yoyChange = $currentTotal - $priorTotal
            $yoyPercent = if($priorTotal -gt 0) { ($yoyChange / $priorTotal) * 100 } else { 0 }
            
            Write-Host "`nOVERALL YoY COMPARISON" -ForegroundColor Yellow
            Write-Host ("  Prior Year Total:    `${0:N2}" -f $priorTotal) -ForegroundColor White
            Write-Host ("  Current Year Total:  `${0:N2}" -f $currentTotal) -ForegroundColor White
            Write-Host ("  Change:              `${0:N2} ({1:N1}%)" -f $yoyChange, $yoyPercent) -ForegroundColor $(if($yoyChange -gt 0) { 'Red' } else { 'Green' })
            
            # Identify new services (in current but not in prior)
            if($primaryGroupColumn) {
                $currentServices = $rows | Where-Object { $_.$primaryGroupColumn } | Select-Object -ExpandProperty $primaryGroupColumn -Unique
                $priorServices = $priorRows | Where-Object { $_.$primaryGroupColumn } | Select-Object -ExpandProperty $primaryGroupColumn -Unique
                
                $newServices = $currentServices | Where-Object { $_ -notin $priorServices }
                $removedServices = $priorServices | Where-Object { $_ -notin $currentServices }
                
                if($newServices) {
                    Write-Host "`nNEW SERVICES (Not in Prior Year)" -ForegroundColor Yellow
                    foreach($svc in $newServices) {
                        $cost = ($rows | Where-Object { $_.$primaryGroupColumn -eq $svc } | Measure-Object -Property Cost -Sum).Sum
                        Write-Host ("  • {0,-40} `${1:N2}" -f $svc, $cost) -ForegroundColor Cyan
                    }
                }
                
                if($removedServices) {
                    Write-Host "`nREMOVED SERVICES (Were in Prior Year)" -ForegroundColor Yellow
                    foreach($svc in $removedServices) {
                        $cost = ($priorRows | Where-Object { $_.$primaryGroupColumn -eq $svc } | Measure-Object -Property Cost -Sum).Sum
                        Write-Host ("  • {0,-40} `${1:N2}" -f $svc, $cost) -ForegroundColor Gray
                    }
                }
                
                # Compare costs for common services
                $commonServices = $currentServices | Where-Object { $_ -in $priorServices }
                if($commonServices) {
                    Write-Host "`nSERVICE COST CHANGES (YoY)" -ForegroundColor Yellow
                    
                    $serviceComparison = $commonServices | ForEach-Object {
                        $svcName = $_
                        $currentCost = ($rows | Where-Object { $_.$primaryGroupColumn -eq $svcName } | Measure-Object -Property Cost -Sum).Sum
                        $priorCost = ($priorRows | Where-Object { $_.$primaryGroupColumn -eq $svcName } | Measure-Object -Property Cost -Sum).Sum
                        $change = $currentCost - $priorCost
                        $changePercent = if($priorCost -gt 0) { ($change / $priorCost) * 100 } else { 0 }
                        
                        [PSCustomObject]@{
                            Service = $svcName
                            PriorCost = $priorCost
                            CurrentCost = $currentCost
                            Change = $change
                            ChangePercent = $changePercent
                        }
                    } | Sort-Object Change -Descending
                    
                    # Top 10 increases
                    Write-Host "`n  Top Cost Increases:" -ForegroundColor Cyan
                    $serviceComparison | Where-Object { $_.Change -gt 0 } | Select-Object -First 10 | ForEach-Object {
                        Write-Host ("    {0,-40} `${1,8:N2} → `${2,8:N2} ({3,6:N1}%)" -f $_.Service, $_.PriorCost, $_.CurrentCost, $_.ChangePercent) -ForegroundColor Red
                    }
                    
                    # Top 10 decreases
                    $decreases = $serviceComparison | Where-Object { $_.Change -lt 0 } | Select-Object -First 10
                    if($decreases) {
                        Write-Host "`n  Top Cost Decreases:" -ForegroundColor Cyan
                        $decreases | ForEach-Object {
                            Write-Host ("    {0,-40} `${1,8:N2} → `${2,8:N2} ({3,6:N1}%)" -f $_.Service, $_.PriorCost, $_.CurrentCost, $_.ChangePercent) -ForegroundColor Green
                        }
                    }
                }
            }
            
            # Quantity/Usage Analysis (if usage details available)
            if($usageDetails.Count -gt 0) {
                Write-Host "`n========================================" -ForegroundColor Magenta
                Write-Host "  USAGE QUANTITY ANALYSIS" -ForegroundColor Magenta
                Write-Host "========================================" -ForegroundColor Magenta
                
                # Group by MeterCategory and aggregate quantities
                $currentUsage = $usageDetails | Group-Object MeterCategory | ForEach-Object {
                    $category = $_.Name
                    $totalQuantity = ($_.Group | Measure-Object -Property Quantity -Sum).Sum
                    $totalCost = ($_.Group | Measure-Object -Property Cost -Sum).Sum
                    $avgPrice = if($totalQuantity -gt 0) { $totalCost / $totalQuantity } else { 0 }
                    
                    [PSCustomObject]@{
                        Category = $category
                        Quantity = $totalQuantity
                        Cost = $totalCost
                        AvgPrice = $avgPrice
                        Unit = ($_.Group | Select-Object -First 1).Unit
                    }
                } | Sort-Object Cost -Descending
                
                Write-Host "`nUSAGE BY CATEGORY" -ForegroundColor Yellow
                $currentUsage | Select-Object -First 15 | Format-Table @{
                    Label = "Category"
                    Expression = { $_.Category }
                }, @{
                    Label = "Quantity"
                    Expression = { "{0:N2}" -f $_.Quantity }
                    Alignment = "Right"
                }, @{
                    Label = "Unit"
                    Expression = { $_.Unit }
                }, @{
                    Label = "Total Cost"
                    Expression = { "`${0:N2}" -f $_.Cost }
                    Alignment = "Right"
                }, @{
                    Label = "Avg Price"
                    Expression = { "`${0:N4}" -f $_.AvgPrice }
                    Alignment = "Right"
                } -AutoSize
                
                # VM Hours analysis if Virtual Machines category exists
                $vmUsage = $usageDetails | Where-Object { $_.MeterCategory -eq 'Virtual Machines' }
                if($vmUsage) {
                    Write-Host "`nVIRTUAL MACHINE USAGE (Hours)" -ForegroundColor Yellow
                    $vmBySubcategory = $vmUsage | Group-Object MeterSubcategory | ForEach-Object {
                        [PSCustomObject]@{
                            SKU = $_.Name
                            Hours = ($_.Group | Measure-Object -Property Quantity -Sum).Sum
                            Cost = ($_.Group | Measure-Object -Property Cost -Sum).Sum
                            AvgHourlyCost = if(($_.Group | Measure-Object -Property Quantity -Sum).Sum -gt 0) { 
                                ($_.Group | Measure-Object -Property Cost -Sum).Sum / ($_.Group | Measure-Object -Property Quantity -Sum).Sum 
                            } else { 0 }
                        }
                    } | Sort-Object Cost -Descending
                    
                    $vmBySubcategory | Select-Object -First 10 | Format-Table @{
                        Label = "VM SKU"
                        Expression = { $_.SKU }
                    }, @{
                        Label = "Total Hours"
                        Expression = { "{0:N2}" -f $_.Hours }
                        Alignment = "Right"
                    }, @{
                        Label = "Total Cost"
                        Expression = { "`${0:N2}" -f $_.Cost }
                        Alignment = "Right"
                    }, @{
                        Label = "Avg $/Hour"
                        Expression = { "`${0:N4}" -f $_.AvgHourlyCost }
                        Alignment = "Right"
                    } -AutoSize
                    
                    Write-Host ("  Total VM Hours: {0:N2}" -f ($vmUsage | Measure-Object -Property Quantity -Sum).Sum) -ForegroundColor White
                    Write-Host ("  Total VM Cost:  `${0:N2}" -f ($vmUsage | Measure-Object -Property Cost -Sum).Sum) -ForegroundColor White
                }
                
                Write-Host "`nKEY INSIGHTS:" -ForegroundColor Yellow
                Write-Host "  • Compare quantity changes between periods to identify usage increases" -ForegroundColor Cyan
                Write-Host "  • Compare avg prices between periods to identify rate increases" -ForegroundColor Cyan
                Write-Host "  • Export to Kusto for detailed correlation analysis" -ForegroundColor Cyan
            }
            
            # Store analysis for export
            $trendAnalysis = [PSCustomObject]@{
                PriorPeriod = "$priorStartDate to $priorEndDate"
                CurrentPeriod = "$StartDate to $EndDate"
                PriorTotal = $priorTotal
                CurrentTotal = $currentTotal
                ChangeAmount = $yoyChange
                ChangePercent = $yoyPercent
                NewServices = if($newServices) { $newServices -join '; ' } else { 'None' }
                RemovedServices = if($removedServices) { $removedServices -join '; ' } else { 'None' }
            }
        }
        
    } catch {
        Write-Warn "Failed to fetch prior year data: $($_.Exception.Message)"
        Write-Info "Continuing without trend analysis..."
    }
    
    Write-Host ""
}

# Determine the primary grouping column for reporting
$primaryGroupColumn = switch ($GroupBy) {
    'ResourceType' { 'ResourceType' }
    'ServiceName' { 'ServiceName' }
    'MeterCategory' { 'MeterCategory' }
    'MeterSubcategory' { 'MeterSubcategory' }
    'ResourceLocation' { 'ResourceLocation' }
    'ResourceGroupAndType' { 'ResourceGroup' }
    'All' { $null }
    default { 'ResourceGroup' }
}

# Generate comprehensive cost reports
if($rows.Count -gt 0) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  COST ANALYSIS REPORT" -ForegroundColor Cyan
    Write-Host "  Period: $StartDate to $EndDate" -ForegroundColor Cyan
    Write-Host "  Grouped By: $GroupBy" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Overall Summary
    $totalCost = ($rows | Measure-Object -Property Cost -Sum).Sum
    $avgDailyCost = ($rows | Group-Object Date | ForEach-Object { ($_.Group | Measure-Object -Property Cost -Sum).Sum } | Measure-Object -Average).Average
    $uniqueDays = ($rows | Select-Object -ExpandProperty Date -Unique | Measure-Object).Count
    
    Write-Host "OVERALL SUMMARY" -ForegroundColor Yellow
    Write-Host ("  Total Cost:          `${0:N2}" -f $totalCost) -ForegroundColor White
    Write-Host ("  Days in Period:      {0}" -f $uniqueDays) -ForegroundColor White
    Write-Host ("  Avg Cost per Day:    `${0:N2}" -f $avgDailyCost) -ForegroundColor White
    
    # Show unique count for the grouping dimension
    if($primaryGroupColumn -and ($rows[0].PSObject.Properties.Name -contains $primaryGroupColumn)) {
        $uniqueCount = ($rows | Where-Object { $_.$primaryGroupColumn } | Select-Object -ExpandProperty $primaryGroupColumn -Unique | Measure-Object).Count
        # Convert camelCase to "Camel Case" format
        $label = $primaryGroupColumn -creplace '([A-Z])', ' $1'
        $label = $label.Trim()
        Write-Host ("  Unique {0}s: {1}" -f $label, $uniqueCount) -ForegroundColor White
    }
    Write-Host ""
    
    # Daily Cost Summary
    Write-Host "DAILY COST BREAKDOWN" -ForegroundColor Yellow
    $dailyCosts = $rows | Group-Object Date | ForEach-Object {
        [PSCustomObject]@{
            Date = $_.Name
            TotalCost = ($_.Group | Measure-Object -Property Cost -Sum).Sum
            ResourceGroups = ($_.Group | Where-Object { $_.ResourceGroup } | Select-Object -ExpandProperty ResourceGroup -Unique | Measure-Object).Count
        }
    } | Sort-Object Date
    
    $dailyCosts | Format-Table @{
        Label = "Date"
        Expression = { $_.Date }
    }, @{
        Label = "Total Cost"
        Expression = { "`${0:N2}" -f $_.TotalCost }
        Alignment = "Right"
    }, @{
        Label = "Resource Groups"
        Expression = { $_.ResourceGroups }
        Alignment = "Right"
    } -AutoSize
    
    # Top items by grouping dimension
    if($primaryGroupColumn -and ($rows[0].PSObject.Properties.Name -contains $primaryGroupColumn)) {
        # Convert camelCase to "Camel Case" format
        $label = $primaryGroupColumn -creplace '([A-Z])', ' $1'
        $labelTrimmed = $label.Trim()
        
        Write-Host "TOP 10 $($labelTrimmed.ToUpper())S BY TOTAL COST" -ForegroundColor Yellow
        $groupCosts = $rows | Where-Object { $_.$primaryGroupColumn } | Group-Object $primaryGroupColumn | ForEach-Object {
            $obj = [PSCustomObject]@{
                Name = $_.Name
                TotalCost = ($_.Group | Measure-Object -Property Cost -Sum).Sum
                Days = ($_.Group | Select-Object -ExpandProperty Date -Unique | Measure-Object).Count
                AvgDailyCost = ($_.Group | Measure-Object -Property Cost -Average).Average
            }
            # If ResourceGroupAndType, add ResourceType info
            if($GroupBy -eq 'ResourceGroupAndType' -and $_.Group[0].ResourceType) {
                $obj | Add-Member -NotePropertyName 'ResourceType' -NotePropertyValue $_.Group[0].ResourceType
            }
            $obj
        } | Sort-Object TotalCost -Descending | Select-Object -First 10
        
        $groupCosts | Format-Table @{
            Label = $labelTrimmed
            Expression = { $_.Name }
        }, @{
            Label = "Total Cost"
            Expression = { "`${0:N2}" -f $_.TotalCost }
            Alignment = "Right"
        }, @{
            Label = "Days Active"
            Expression = { $_.Days }
            Alignment = "Right"
        }, @{
            Label = "Avg Daily"
            Expression = { "`${0:N2}" -f $_.AvgDailyCost }
            Alignment = "Right"
        } -AutoSize
        
        # By Average Daily Cost
        Write-Host "TOP 10 $($labelTrimmed.ToUpper())S BY AVG DAILY COST" -ForegroundColor Yellow
        $groupAvgCosts = $rows | Where-Object { $_.$primaryGroupColumn } | Group-Object $primaryGroupColumn | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                AvgDailyCost = ($_.Group | Measure-Object -Property Cost -Average).Average
                TotalCost = ($_.Group | Measure-Object -Property Cost -Sum).Sum
                Days = ($_.Group | Select-Object -ExpandProperty Date -Unique | Measure-Object).Count
            }
        } | Sort-Object AvgDailyCost -Descending | Select-Object -First 10
        
        $groupAvgCosts | Format-Table @{
            Label = $labelTrimmed
            Expression = { $_.Name }
        }, @{
            Label = "Avg Daily Cost"
            Expression = { "`${0:N2}" -f $_.AvgDailyCost }
            Alignment = "Right"
        }, @{
            Label = "Total Cost"
            Expression = { "`${0:N2}" -f $_.TotalCost }
            Alignment = "Right"
        }, @{
            Label = "Days"
            Expression = { $_.Days }
            Alignment = "Right"
        } -AutoSize
        
        # Unallocated/Untagged items
        $unallocatedCost = ($rows | Where-Object { -not $_.$primaryGroupColumn } | Measure-Object -Property Cost -Sum).Sum
        if($unallocatedCost -gt 0) {
            Write-Host "UNALLOCATED/SHARED COSTS" -ForegroundColor Yellow
            Write-Host ("  Total Unallocated:   `${0:N2}" -f $unallocatedCost) -ForegroundColor White
            Write-Host ("  Percentage of Total: {0:N1}%" -f (($unallocatedCost / $totalCost) * 100)) -ForegroundColor White
            Write-Host ""
        }
        
        # Save dimension-specific costs for file export
        $dimCosts = $groupCosts
    }
    
    # Cost Trend Analysis
    Write-Host "COST TREND ANALYSIS" -ForegroundColor Yellow
    if($dailyCosts.Count -gt 1) {
        $firstDayCost = $dailyCosts[0].TotalCost
        $lastDayCost = $dailyCosts[-1].TotalCost
        $trendChange = $lastDayCost - $firstDayCost
        $trendPercent = if($firstDayCost -gt 0) { ($trendChange / $firstDayCost) * 100 } else { 0 }
        
        Write-Host ("  First Day ({0}):   `${1:N2}" -f $dailyCosts[0].Date, $firstDayCost) -ForegroundColor White
        Write-Host ("  Last Day ({0}):    `${1:N2}" -f $dailyCosts[-1].Date, $lastDayCost) -ForegroundColor White
        
        if($trendChange -gt 0) {
            Write-Host ("  Trend:                 ↑ `${0:N2} ({1:N1}% increase)" -f $trendChange, $trendPercent) -ForegroundColor Red
        } elseif($trendChange -lt 0) {
            Write-Host ("  Trend:                 ↓ `${0:N2} ({1:N1}% decrease)" -f ([Math]::Abs($trendChange)), ([Math]::Abs($trendPercent))) -ForegroundColor Green
        } else {
            Write-Host "  Trend:                 → No change" -ForegroundColor Gray
        }
        Write-Host ""
        
        # Peak cost day
        $peakDay = $dailyCosts | Sort-Object TotalCost -Descending | Select-Object -First 1
        Write-Host ("  Peak Cost Day:       {0} (`${1:N2})" -f $peakDay.Date, $peakDay.TotalCost) -ForegroundColor White
        
        $lowDay = $dailyCosts | Sort-Object TotalCost | Select-Object -First 1
        Write-Host ("  Lowest Cost Day:     {0} (`${1:N2})" -f $lowDay.Date, $lowDay.TotalCost) -ForegroundColor White
        Write-Host ""
    }
}

# Save outputs
if($OutputPath) {
    $base = [IO.Path]::ChangeExtension($OutputPath, $null)
    if(-not (Test-Path (Split-Path $base -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $base -Parent) -Force | Out-Null
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  EXPORTING DATA" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Save raw API response
    $jsonFile = "$base-raw.json"
    $response | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 $jsonFile
    Write-Info "Raw API Response: $jsonFile"
    
    # Export cost summary rows in requested format(s)
    $csvFile = "$base-costs.csv"
    $jsonlFile = "$base-costs.jsonl"
    $jsonArrayFile = "$base-costs.json"
    
    if($ExportFormat -in @('CSV', 'Both')) {
        $rows | Export-Csv -NoTypeInformation -Path $csvFile
        Write-Info "Cost Summary CSV: $csvFile"
    }
    
    if($ExportFormat -in @('JSON', 'Both')) {
        $rows | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $jsonArrayFile
        Write-Info "Cost Summary JSON: $jsonArrayFile"
    }
    
    if($ExportFormat -in @('JSONL', 'Both')) {
        # Line-delimited JSON for Kusto ingestion
        $rows | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 5 } | Out-File -Encoding utf8 $jsonlFile
        Write-Info "Cost Summary JSONL (Kusto-ready): $jsonlFile"
    }
    
    # Export usage details if collected
    if($usageDetails.Count -gt 0) {
        $usageCsvFile = "$base-usage-details.csv"
        $usageJsonlFile = "$base-usage-details.jsonl"
        $usageJsonFile = "$base-usage-details.json"
        
        if($ExportFormat -in @('CSV', 'Both')) {
            $usageDetails | Export-Csv -NoTypeInformation -Path $usageCsvFile
            Write-Info "Usage Details CSV: $usageCsvFile"
        }
        
        if($ExportFormat -in @('JSON', 'Both')) {
            $usageDetails | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $usageJsonFile
            Write-Info "Usage Details JSON: $usageJsonFile"
        }
        
        if($ExportFormat -in @('JSONL', 'Both')) {
            # Line-delimited JSON for Kusto ingestion
            $usageDetails | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 5 } | Out-File -Encoding utf8 $usageJsonlFile
            Write-Info "Usage Details JSONL (Kusto-ready): $usageJsonlFile"
        }
    }
    
    # Export trend analysis if performed
    if($trendAnalysis) {
        $trendFile = "$base-trend-analysis.json"
        $trendAnalysis | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $trendFile
        Write-Info "Trend Analysis: $trendFile"
    }
    
    # Save summary reports
    $summaryFile = "$base-summary.txt"
    $dailyFile = "$base-daily.csv"
    $rgFile = "$base-by-resourcegroup.csv"
    
    # Summary report
    @"
AZURE COST ANALYSIS REPORT
Period: $StartDate to $EndDate
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

OVERALL SUMMARY
  Total Cost:          `$$($totalCost.ToString('N2'))
  Days in Period:      $uniqueDays
  Avg Cost per Day:    `$$($avgDailyCost.ToString('N2'))
  Resource Groups:     $uniqueRGs

TOP RESOURCE GROUPS BY TOTAL COST
$($rgCosts | ForEach-Object { "  {0,-40} `${1,10:N2}" -f $_.ResourceGroup, $_.TotalCost } | Out-String)

DAILY COSTS
$($dailyCosts | ForEach-Object { "  {0}  `${1,10:N2}" -f $_.Date, $_.TotalCost } | Out-String)
"@ | Out-File -Encoding utf8 $summaryFile
    
    # Export additional analysis reports
    $dailyCosts | Export-Csv -NoTypeInformation -Path $dailyFile
    Write-Info "Daily Analysis:   $dailyFile"
    
    if($dimCosts) {
        $dimCosts | Export-Csv -NoTypeInformation -Path $rgFile
        Write-Info "Dimension Analysis: $rgFile"
    }
    
    Write-Info "Text Summary:     $summaryFile"
    
    Write-Host "`n" -NoNewline
    Write-Host "✓ Export complete! " -ForegroundColor Green -NoNewline
    Write-Host "Files saved to: $(Split-Path $base -Parent)" -ForegroundColor White
    Write-Host ""
}

# Display all rows if no output path (for piping/debugging)
if(-not $OutputPath -and $rows.Count) { 
    $rows | Sort-Object Date, ResourceGroup | Format-Table -AutoSize 
} elseif(-not $rows.Count) {
    Write-Warn "No cost data returned for the specified period."
    $response | ConvertTo-Json -Depth 10
}