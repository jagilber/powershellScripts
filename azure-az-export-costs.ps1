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
.EXAMPLE
    .\azure-az-export-costs.ps1 -SubscriptionId <subId>
.EXAMPLE
    .\azure-az-export-costs.ps1 -SubscriptionId <subId> -StartDate 2025-09-01 -EndDate 2025-09-15 -OutputPath .\cost
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
    [ValidateSet('ResourceGroup', 'ResourceType', 'ServiceName', 'ResourceGroupAndType', 'All')]
    [string]$GroupBy = 'ResourceGroup',
    [switch]$UseDeviceCode,
    [switch]$ManagedIdentity,
    [switch]$ForceLogin,
    [string]$OutputPath,
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

# Create the query body
$QueryBody = @{
    type = "Usage"
    timeframe = "Custom"
    timePeriod = @{
        from = $StartDate
        to = $EndDate
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

# Make the API request (primary path)
try {
    $response = Invoke-RestMethod -Uri $CostManagementEndpoint -Method Post -Headers @{
        Authorization = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    } -Body $QueryJson -ErrorAction Stop
} catch {
    Write-Warn "Primary REST call failed: $($_.Exception.Message)"
    if($_.ErrorDetails -and $_.ErrorDetails.Message -match 'InvalidAuthenticationToken') {
        Write-Info 'Attempting fallback via Invoke-AzRest...'
    # Invoke-AzRestMethod expects string payload, not byte[]
    $azRest = Invoke-AzRestMethod -Method POST -Path "/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/query?api-version=2023-03-01" -Payload $QueryJson -ErrorAction Stop
        if($azRest.StatusCode -ge 200 -and $azRest.StatusCode -lt 300) {
            $response = $azRest.Content | ConvertFrom-Json
        } else {
            throw "Invoke-AzRest fallback failed with status $($azRest.StatusCode)"
        }
    } else { throw }
}

if(-not $response.properties) { throw 'Unexpected response format: no properties node.' }

# Shape rows dynamically if present
$rows = @()
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
    $dimensionColumns = @('ResourceGroup', 'ResourceType', 'ServiceName', 'ResourceId', 'MeterCategory', 'MeterSubCategory')
    
    Write-Verbose "Available columns: $($colMap.Keys -join ', ')"

    $rows = $response.properties.rows | ForEach-Object {
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
} elseif($response.properties.rows) {
    Write-Warn 'Columns metadata missing; rows cannot be reliably shaped.'
}

Write-Info ("Returned {0} row(s)." -f $rows.Count)

# Determine the primary grouping column for reporting
$primaryGroupColumn = switch ($GroupBy) {
    'ResourceType' { 'ResourceType' }
    'ServiceName' { 'ServiceName' }
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
    
    # Save raw data
    $jsonFile = "$base-raw.json"
    $csvFile =  "$base-rows.csv"
    $response | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 $jsonFile
    $rows | Export-Csv -NoTypeInformation -Path $csvFile
    
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
    
    # Export additional CSV reports
    $dailyCosts | Export-Csv -NoTypeInformation -Path $dailyFile
    if($dimCosts) {
        $dimCosts | Export-Csv -NoTypeInformation -Path $rgFile
    }
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  FILES SAVED" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Info "Raw JSON:         $jsonFile"
    Write-Info "All Rows CSV:     $csvFile"
    Write-Info "Summary Report:   $summaryFile"
    Write-Info "Daily Costs CSV:  $dailyFile"
    Write-Info "By RG CSV:        $rgFile"
    Write-Host ""
}

# Display all rows if no output path (for piping/debugging)
if(-not $OutputPath -and $rows.Count) { 
    $rows | Sort-Object Date, ResourceGroup | Format-Table -AutoSize 
} elseif(-not $rows.Count) {
    Write-Warn "No cost data returned for the specified period."
    $response | ConvertTo-Json -Depth 10
}