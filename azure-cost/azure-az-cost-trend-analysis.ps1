<#
.SYNOPSIS
    Analyze Azure cost trends over the last 12 months with year-over-year comparison.

.DESCRIPTION
    Convenience wrapper for azure-az-export-costs.ps1 that automatically:
    - Queries last 12 months of cost data
    - Performs year-over-year trend analysis
    - Fetches detailed usage records
    - Exports data in Kusto-ready JSONL format
    - Answers: Why are costs increasing? Usage? Prices? New services?

.PARAMETER SubscriptionId
    Target subscription Id. Defaults to $env:AZURE_SUBSCRIPTION_ID if available.

.PARAMETER GroupBy
    How to group costs: ResourceGroup, ResourceType, ServiceName, MeterCategory, MeterSubcategory (for VM SKUs), etc.
    Default: ServiceName (shows services like Virtual Machines, Defender, Storage, etc.)

.PARAMETER MonthsBack
    Number of months to analyze. Default: 12 (one year)

.PARAMETER OutputPath
    Base path for exported files. Default: .\azure-cost-analysis\cost-analysis

.PARAMETER ExportFormat
    Export format: CSV, JSON, JSONL (recommended for Kusto), or Both (CSV + JSONL). Default: JSONL

.PARAMETER SkipUsageDetails
    Skip fetching detailed usage records (faster but less detailed analysis).

.EXAMPLE
    .\azure-az-cost-trend-analysis.ps1
    
    Uses environment variable subscription, analyzes last 12 months by ServiceName.

.EXAMPLE
    .\azure-az-cost-trend-analysis.ps1 -GroupBy MeterSubcategory
    
    Analyzes costs by VM SKU and meter subcategory for detailed usage breakdown.

.EXAMPLE
    .\azure-az-cost-trend-analysis.ps1 -MonthsBack 6 -GroupBy ResourceGroup
    
    Analyzes last 6 months grouped by resource group.

.EXAMPLE
    .\azure-az-cost-trend-analysis.ps1 -SubscriptionId "xxx-xxx" -OutputPath "C:\Reports\Azure"
    
    Custom subscription and output location.

.NOTES
    This script answers the key questions:
    1. Are costs increasing due to MORE USAGE? (quantity analysis)
    2. Are costs increasing due to HIGHER PRICES? (rate analysis)
    3. Are costs increasing due to NEW SERVICES? (service additions)
    4. Which specific services/SKUs are driving the increase?
    
    Requires: Az.Accounts module, azure-az-export-costs.ps1 in same directory
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    
    [Parameter()]
    [ValidateSet('ResourceGroup', 'ResourceType', 'ServiceName', 'MeterCategory', 'MeterSubcategory', 'ResourceLocation', 'ResourceGroupAndType', 'All')]
    [string]$GroupBy = 'ServiceName',
    
    [Parameter()]
    [ValidateRange(1, 24)]
    [int]$MonthsBack = 12,
    
    [Parameter()]
    [string]$OutputPath = ".\azure-cost-analysis\cost-analysis",
    
    [Parameter()]
    [ValidateSet('CSV', 'JSON', 'JSONL', 'Both')]
    [string]$ExportFormat = 'JSONL',
    
    [switch]$SkipUsageDetails
)

$ErrorActionPreference = 'Stop'

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Warning $Message }

# Validate subscription ID
if(-not $SubscriptionId) {
    throw "SubscriptionId is required. Provide via parameter or set AZURE_SUBSCRIPTION_ID environment variable."
}

# Calculate date range
$endDate = Get-Date
$startDate = $endDate.AddMonths(-$MonthsBack)

Write-Host "========================================" -ForegroundColor Green
Write-Host "  AZURE COST TREND ANALYSIS" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Info "Subscription:     $SubscriptionId"
Write-Info "Analysis Period:  $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))"
Write-Info "Duration:         $MonthsBack months"
Write-Info "Grouping:         $GroupBy"
Write-Info "Export Format:    $ExportFormat"
Write-Info "Output Path:      $OutputPath"
Write-Host ""

# Verify the main script exists
$mainScript = Join-Path $PSScriptRoot "azure-az-export-costs.ps1"
if(-not (Test-Path $mainScript)) {
    throw "Required script not found: $mainScript"
}

Write-Info "Executing cost analysis with trend comparison..."
Write-Host ""

# Build parameters for main script
$scriptParams = @{
    SubscriptionId = $SubscriptionId
    StartDate = $startDate.ToString('yyyy-MM-dd')
    EndDate = $endDate.ToString('yyyy-MM-dd')
    GroupBy = $GroupBy
    OutputPath = $OutputPath
    ExportFormat = $ExportFormat
    EnableTrendAnalysis = $true
}

if(-not $SkipUsageDetails) {
    $scriptParams.IncludeUsageDetails = $true
}

# Execute the analysis
& $mainScript @scriptParams

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ANALYSIS COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS FOR KUSTO ANALYSIS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Ingest the JSONL files into Kusto:" -ForegroundColor White
Write-Host "   .ingest inline into table CostData <| $(Resolve-Path $OutputPath)-costs.jsonl" -ForegroundColor Gray
Write-Host "   .ingest inline into table UsageData <| $(Resolve-Path $OutputPath)-usage-details.jsonl" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Example Kusto queries:" -ForegroundColor White
Write-Host "   // Price increase analysis" -ForegroundColor Gray
Write-Host "   UsageData" -ForegroundColor Gray
Write-Host "   | summarize AvgPrice=avg(EffectivePrice) by MeterCategory, bin(Date, 30d)" -ForegroundColor Gray
Write-Host "   | order by Date asc" -ForegroundColor Gray
Write-Host ""
Write-Host "   // Usage quantity trends" -ForegroundColor Gray
Write-Host "   UsageData" -ForegroundColor Gray
Write-Host "   | summarize TotalQuantity=sum(Quantity) by MeterCategory, bin(Date, 30d)" -ForegroundColor Gray
Write-Host "   | order by Date asc" -ForegroundColor Gray
Write-Host ""
Write-Host "   // Cost vs Quantity correlation" -ForegroundColor Gray
Write-Host "   UsageData" -ForegroundColor Gray
Write-Host "   | summarize TotalCost=sum(Cost), TotalQuantity=sum(Quantity) by Month=startofmonth(Date)" -ForegroundColor Gray
Write-Host "   | extend CostChange=TotalCost-prev(TotalCost), QuantityChange=TotalQuantity-prev(TotalQuantity)" -ForegroundColor Gray
Write-Host ""
