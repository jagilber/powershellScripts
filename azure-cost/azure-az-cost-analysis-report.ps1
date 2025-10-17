<#
.SYNOPSIS
    Generate comprehensive Azure cost analysis report with Mermaid visualizations.

.DESCRIPTION
    This script performs deep analysis of Azure costs over 12 months and generates:
    - Detailed Markdown report with executive summary
    - Mermaid charts (timeseries, pie charts, bar charts)
    - Year-over-year trend analysis
    - Usage quantity analysis
    - Service cost breakdown
    - Recommendations and insights
    
    Output is GitHub-flavored Markdown with embedded Mermaid diagrams.

.PARAMETER SubscriptionId
    Target subscription Id. Defaults to $env:AZURE_SUBSCRIPTION_ID.

.PARAMETER MonthsBack
    Number of months to analyze. Default: 12

.PARAMETER OutputPath
    Output directory for report and data files. Default: .\azure-cost-reports

.PARAMETER ReportName
    Base name for the report file. Default: cost-analysis-report

.PARAMETER IncludeUsageDetails
    Include detailed usage analysis (slower but more comprehensive). Default: $true

.EXAMPLE
    .\azure-az-cost-analysis-report.ps1
    
    Generates 12-month report using environment subscription.

.EXAMPLE
    .\azure-az-cost-analysis-report.ps1 -MonthsBack 6 -OutputPath "C:\Reports"
    
    Generates 6-month report in custom location.

.NOTES
    Requires: azure-az-export-costs.ps1 in same directory
    Output: GitHub-compatible Markdown with Mermaid diagrams
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    
    [Parameter()]
    [ValidateRange(1, 24)]
    [int]$MonthsBack = 12,
    
    [Parameter()]
    [string]$OutputPath = ".\azure-cost-reports",
    
    [Parameter()]
    [string]$ReportName = "cost-analysis-report",
    
    [Parameter()]
    [bool]$IncludeUsageDetails = $true
)

$ErrorActionPreference = 'Stop'

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Warning $Message }

# Validate
if(-not $SubscriptionId) {
    throw "SubscriptionId required. Provide via parameter or set AZURE_SUBSCRIPTION_ID environment variable."
}

$mainScript = Join-Path $PSScriptRoot "azure-az-export-costs.ps1"
if(-not (Test-Path $mainScript)) {
    throw "Required script not found: $mainScript"
}

# Create output directory
if(-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Calculate date range
$endDate = Get-Date
$startDate = $endDate.AddMonths(-$MonthsBack)

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  AZURE COST ANALYSIS & REPORT" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Info "Period: $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))"
Write-Info "Duration: $MonthsBack months"
Write-Info "Output: $OutputPath"
Write-Host ""

# Step 1: Export cost data with trend analysis
Write-Info "Step 1: Collecting cost data..."
$dataPath = Join-Path $OutputPath "data"

$exportParams = @{
    SubscriptionId = $SubscriptionId
    StartDate = $startDate.ToString('yyyy-MM-dd')
    EndDate = $endDate.ToString('yyyy-MM-dd')
    GroupBy = 'ServiceName'
    OutputPath = Join-Path $dataPath "costs"
    ExportFormat = 'Both'
    EnableTrendAnalysis = $true
}

if($IncludeUsageDetails) {
    $exportParams.IncludeUsageDetails = $true
}

& $mainScript @exportParams | Out-Null

# Load the exported data
Write-Info "Step 2: Loading exported data..."

# Files use "costs." prefix (from OutputPath base name)
$costsFile = Join-Path $dataPath "costs.-costs.csv"
$usageFile = Join-Path $dataPath "costs.-usage-details.csv"
$trendFile = Join-Path $dataPath "costs.-trend-analysis.json"

if(-not (Test-Path $costsFile)) {
    throw "Cost data file not found: $costsFile"
}

$costData = Import-Csv $costsFile
$usageData = if(Test-Path $usageFile) { Import-Csv $usageFile } else { @() }
$trendData = if(Test-Path $trendFile) { Get-Content $trendFile -Raw | ConvertFrom-Json } else { $null }

Write-Info "Loaded $($costData.Count) cost records"
if($usageData) {
    Write-Info "Loaded $($usageData.Count) usage records"
}

# Step 3: Perform deep analysis
Write-Info "Step 3: Performing deep analysis..."

# Overall statistics
$totalCost = ($costData | Measure-Object -Property Cost -Sum).Sum
$avgDailyCost = $totalCost / $MonthsBack / 30
$uniqueDays = ($costData | Select-Object -ExpandProperty Date -Unique | Measure-Object).Count

# Monthly aggregation
$monthlyCosts = $costData | Group-Object { 
    # Handle date format - could be yyyyMMdd or yyyy-MM-dd
    $dateStr = $_.Date
    if($dateStr -match '^\d{8}$') {
        # Format: 20250707
        $dateStr.Substring(0,4) + '-' + $dateStr.Substring(4,2)
    } else {
        ([DateTime]::Parse($dateStr)).ToString('yyyy-MM')
    }
} | ForEach-Object {
    [PSCustomObject]@{
        Month = $_.Name
        TotalCost = ($_.Group | Measure-Object -Property Cost -Sum).Sum
        RecordCount = $_.Count
    }
} | Sort-Object Month

# Service breakdown
$serviceCosts = $costData | Group-Object ServiceName | ForEach-Object {
    $totalCost = ($_.Group | Measure-Object -Property Cost -Sum).Sum
    [PSCustomObject]@{
        Service = $_.Name
        TotalCost = $totalCost
        AvgDailyCost = $totalCost / $uniqueDays
        Percentage = 0  # Will calculate after
    }
} | Sort-Object TotalCost -Descending

# Calculate percentages
$totalServiceCost = ($serviceCosts | Measure-Object -Property TotalCost -Sum).Sum
$serviceCosts | ForEach-Object {
    $_.Percentage = if($totalServiceCost -gt 0) { ($_.TotalCost / $totalServiceCost) * 100 } else { 0 }
}

# Daily trend
$dailyCosts = $costData | Group-Object Date | ForEach-Object {
    # Parse date to ensure proper sorting
    $dateStr = $_.Name
    $parsedDate = if($dateStr -match '^\d{8}$') {
        # Format: 20250707 -> 2025-07-07
        "$($dateStr.Substring(0,4))-$($dateStr.Substring(4,2))-$($dateStr.Substring(6,2))"
    } else {
        $dateStr
    }
    
    [PSCustomObject]@{
        Date = $parsedDate
        TotalCost = ($_.Group | Measure-Object -Property Cost -Sum).Sum
    }
} | Sort-Object Date

# Growth rate analysis
if($monthlyCosts.Count -gt 1) {
    for($i = 1; $i -lt $monthlyCosts.Count; $i++) {
        $current = $monthlyCosts[$i].TotalCost
        $previous = $monthlyCosts[$i-1].TotalCost
        $growth = if($previous -gt 0) { (($current - $previous) / $previous) * 100 } else { 0 }
        $monthlyCosts[$i] | Add-Member -NotePropertyName 'GrowthPercent' -NotePropertyValue $growth
    }
    $monthlyCosts[0] | Add-Member -NotePropertyName 'GrowthPercent' -NotePropertyValue 0
}

# VM usage analysis (if available)
$vmAnalysis = $null
if($usageData) {
    $vmUsage = $usageData | Where-Object { $_.MeterCategory -eq 'Virtual Machines' }
    if($vmUsage) {
        $vmAnalysis = $vmUsage | Group-Object MeterSubcategory | ForEach-Object {
            [PSCustomObject]@{
                SKU = $_.Name
                TotalHours = ($_.Group | Measure-Object -Property Quantity -Sum).Sum
                TotalCost = ($_.Group | Measure-Object -Property Cost -Sum).Sum
                AvgHourlyRate = if(($_.Group | Measure-Object -Property Quantity -Sum).Sum -gt 0) {
                    ($_.Group | Measure-Object -Property Cost -Sum).Sum / ($_.Group | Measure-Object -Property Quantity -Sum).Sum
                } else { 0 }
            }
        } | Sort-Object TotalCost -Descending
    }
}

# Top cost drivers
$topDrivers = $serviceCosts | Select-Object -First 5

# Identify cost anomalies (days with >150% of average)
$avgCost = ($dailyCosts | Measure-Object -Property TotalCost -Average).Average
$anomalies = $dailyCosts | Where-Object { $_.TotalCost -gt ($avgCost * 1.5) } | Sort-Object TotalCost -Descending | Select-Object -First 5

# Step 4: Generate Markdown report
Write-Info "Step 4: Generating Markdown report..."

$reportFile = Join-Path $OutputPath "$ReportName-$(Get-Date -Format 'yyyy-MM-dd').md"

$report = @"
# Azure Cost Analysis Report

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  
**Subscription:** $SubscriptionId  
**Analysis Period:** $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd')) ($MonthsBack months)

---

## Executive Summary

### Key Metrics

| Metric | Value |
|--------|-------|
| **Total Cost** | `$$([math]::Round($totalCost, 2)) |
| **Average Daily Cost** | `$$([math]::Round($avgDailyCost, 2)) |
| **Days Analyzed** | $uniqueDays |
| **Services Tracked** | $($serviceCosts.Count) |
| **Cost Records** | $($costData.Count) |
$(if($usageData) { "| **Usage Records** | $($usageData.Count) |" })

"@

# Add YoY comparison if available
if($trendData) {
    $report += @"

### Year-over-Year Comparison

| Metric | Prior Year | Current Year | Change |
|--------|------------|--------------|--------|
| **Total Cost** | `$$([math]::Round($trendData.PriorTotal, 2)) | `$$([math]::Round($trendData.CurrentTotal, 2)) | `$$([math]::Round($trendData.ChangeAmount, 2)) ($([math]::Round($trendData.ChangePercent, 1))%) |

"@

    if($trendData.NewServices -and $trendData.NewServices -ne 'None') {
        $report += "**🆕 New Services Added:**  `n$($trendData.NewServices)`n`n"
    }
    
    if($trendData.RemovedServices -and $trendData.RemovedServices -ne 'None') {
        $report += "**🗑️ Services Removed:**  `n$($trendData.RemovedServices)`n`n"
    }
}

$report += @"

---

## Cost Trends

### Monthly Cost Overview

``````mermaid
graph LR
    subgraph "Monthly Costs (Last $MonthsBack Months)"
$(
    for($i = 0; $i -lt [Math]::Min($monthlyCosts.Count, 12); $i++) {
        $month = $monthlyCosts[$i]
        $monthLabel = ([DateTime]::ParseExact($month.Month, 'yyyy-MM', $null)).ToString('MMM yy')
        $cost = [math]::Round($month.TotalCost, 0)
        "        M$i[`"$monthLabel<br/>`$$cost`"]`n"
        if($i -lt $monthlyCosts.Count - 1) {
            "        M$i --> M$($i+1)`n"
        }
    }
)
    end
    
$(
    # Add styling
    for($i = 0; $i -lt [Math]::Min($monthlyCosts.Count, 12); $i++) {
        "    style M$i fill:#e3f2fd,stroke:#1976d2`n"
    }
)
``````

### Cost Trend Analysis

The following chart shows daily cost patterns over the analysis period:

``````mermaid
graph TB
    subgraph "Daily Cost Pattern (First 30 days shown)"
$(
    # Show first 30 days only for clarity
    $first30 = $dailyCosts | Select-Object -First 30
    for($i = 0; $i -lt $first30.Count; $i++) {
        $day = $first30[$i]
        $dateLabel = ([DateTime]::Parse($day.Date)).ToString('M/d')
        $cost = [math]::Round($day.TotalCost, 0)
        "        D$i[`"$dateLabel<br/>`$$cost`"]`n"
        if($i -lt $first30.Count - 1) {
            "        D$i --> D$($i+1)`n"
        }
    }
    
    # Color code based on cost relative to average
    $avgCost = ($first30 | Measure-Object -Property TotalCost -Average).Average
    for($i = 0; $i -lt $first30.Count; $i++) {
        $cost = $first30[$i].TotalCost
        if($cost -gt ($avgCost * 1.5)) {
            "    style D$i fill:#ef5350,color:#fff`n"
        } elseif($cost -lt ($avgCost * 0.5)) {
            "    style D$i fill:#66bb6a,color:#fff`n"
        } else {
            "    style D$i fill:#e3f2fd`n"
        }
    }
)
    end
``````

> **Legend:** 🔴 Red = High cost (>150% avg) | 🔵 Blue = Normal | 🟢 Green = Low cost (<50% avg)

### Growth Rate Analysis

``````mermaid
graph LR
    subgraph "Month-over-Month Growth Rate"
$(
    for($i = 0; $i -lt $monthlyCosts.Count; $i++) {
        $month = $monthlyCosts[$i]
        $monthName = ([DateTime]::ParseExact($month.Month, 'yyyy-MM', $null)).ToString('MMM')
        $growth = [math]::Round($month.GrowthPercent, 1)
        $growthSign = if($growth -gt 0) { "+" } else { "" }
        "        MG$i[`"$monthName<br/>$growthSign$growth%`"]`n"
        if($i -lt $monthlyCosts.Count - 1) {
            "        MG$i --> MG$($i+1)`n"
        }
    }
    
    # Color code by growth rate
    for($i = 0; $i -lt $monthlyCosts.Count; $i++) {
        $growth = $monthlyCosts[$i].GrowthPercent
        if($growth -gt 20) {
            "    style MG$i fill:#ef5350,color:#fff`n"
        } elseif($growth -lt -10) {
            "    style MG$i fill:#66bb6a,color:#fff`n"
        } elseif($growth -gt 5) {
            "    style MG$i fill:#ffb74d`n"
        } else {
            "    style MG$i fill:#e3f2fd`n"
        }
    }
)
    end
``````

> **Legend:** 🔴 High growth (>20%) | 🟠 Moderate growth (5-20%) | 🔵 Stable | 🟢 Declining (< -10%)

---

## Service Breakdown

### Top Services by Cost

The following services represent the highest costs in the analysis period:

| Rank | Service | Total Cost | Avg Daily | % of Total |
|------|---------|------------|-----------|------------|
$(
    for($i = 0; $i -lt [Math]::Min($topDrivers.Count, 10); $i++) {
        $svc = $topDrivers[$i]
        "| $($i + 1) | $($svc.Service) | `$$([math]::Round($svc.TotalCost, 2)) | `$$([math]::Round($svc.AvgDailyCost, 2)) | $([math]::Round($svc.Percentage, 1))% |`n"
    }
)

### Service Cost Distribution

``````mermaid
pie title Cost Distribution by Service
$(
    # Top 10 services + "Others"
    $top10 = $serviceCosts | Select-Object -First 10
    $othersTotal = ($serviceCosts | Select-Object -Skip 10 | Measure-Object -Property TotalCost -Sum).Sum
    
    $top10 | ForEach-Object {
        "    `"$($_.Service)`" : $([math]::Round($_.TotalCost, 2))`n"
    }
    
    if($othersTotal -gt 0) {
        "    `"Others`" : $([math]::Round($othersTotal, 2))`n"
    }
)
``````

### Service Cost Flow

``````mermaid
graph TD
    Total["Total Cost<br/>`$$([math]::Round($totalCost, 2))"] --> Top5["Top 5 Services<br/>`$$([math]::Round(($topDrivers | Measure-Object -Property TotalCost -Sum).Sum, 2))"]
    
$(
    $topDrivers | ForEach-Object {
        $safeName = $_.Service -replace '[^a-zA-Z0-9]', ''
        "    Top5 --> $safeName[`"$($_.Service)<br/>`$$([math]::Round($_.TotalCost, 2))`"]`n"
    }
)
    
$(
    if($serviceCosts.Count -gt 5) {
        $othersSum = ($serviceCosts | Select-Object -Skip 5 | Measure-Object -Property TotalCost -Sum).Sum
        "    Total --> Others[`"Other Services ($($serviceCosts.Count - 5))<br/>`$$([math]::Round($othersSum, 2))`"]`n"
    }
)
    
    style Total fill:#e1f5fe,stroke:#01579b,stroke-width:3px
    style Top5 fill:#f3e5f5,stroke:#4a148c
``````

---

"@

# Add VM analysis if available
if($vmAnalysis) {
    $report += @"
## Virtual Machine Usage Analysis

### VM Hours by SKU

The following table shows Virtual Machine usage broken down by SKU:

| SKU | Total Hours | Total Cost | Avg `$/Hour | % of VM Cost |
|-----|-------------|------------|-----------|--------------|
$(
    $totalVMCost = ($vmAnalysis | Measure-Object -Property TotalCost -Sum).Sum
    $vmAnalysis | Select-Object -First 10 | ForEach-Object {
        $pct = if($totalVMCost -gt 0) { ($_.TotalCost / $totalVMCost) * 100 } else { 0 }
        "| $($_.SKU) | $([math]::Round($_.TotalHours, 2)) | `$$([math]::Round($_.TotalCost, 2)) | `$$([math]::Round($_.AvgHourlyRate, 4)) | $([math]::Round($pct, 1))% |`n"
    }
)

### VM Cost Distribution

``````mermaid
pie title VM Costs by SKU
$(
    $vmAnalysis | Select-Object -First 8 | ForEach-Object {
        "    `"$($_.SKU)`" : $([math]::Round($_.TotalCost, 2))`n"
    }
    
    $vmOthers = ($vmAnalysis | Select-Object -Skip 8 | Measure-Object -Property TotalCost -Sum).Sum
    if($vmOthers -gt 0) {
        "    `"Others`" : $([math]::Round($vmOthers, 2))`n"
    }
)
``````

---

"@
}

# Add anomaly detection
if($anomalies) {
    $report += @"
## Cost Anomalies

The following days had significantly higher costs than average (>150% of daily average):

| Date | Cost | % Above Average | Potential Cause |
|------|------|-----------------|-----------------|
$(
    $anomalies | ForEach-Object {
        $pctAbove = (($_.TotalCost / $avgCost) - 1) * 100
        "| $($_.Date) | `$$([math]::Round($_.TotalCost, 2)) | +$([math]::Round($pctAbove, 1))% | 🔍 Investigate |`n"
    }
)

> **Note:** Review these dates for unusual activity, resource scaling events, or data processing jobs.

---

"@
}

# Add insights and recommendations
$report += @"
## Key Insights

### Cost Drivers

``````mermaid
graph TB
    Root[Cost Analysis]
    TopSvc[Top Services]
    Trends[Trends]
$(
    if($anomalies) {
        "    Anomalies[Anomalies]`n"
    }
)
$(
    if($trendData -and $trendData.NewServices -ne 'None') {
        "    NewSvc[New Services]`n"
    }
)
    
    Root --> TopSvc
    Root --> Trends
$(
    if($anomalies) {
        "    Root --> Anomalies`n"
    }
)
$(
    if($trendData -and $trendData.NewServices -ne 'None') {
        "    Root --> NewSvc`n"
    }
)
$(
    $i = 1
    $topDrivers | Select-Object -First 5 | ForEach-Object {
        "    Svc$i[`"$($_.Service): `$$([math]::Round($_.TotalCost, 0))`"]`n"
        "    TopSvc --> Svc$i`n"
        $i++
    }
)
$(
    if($monthlyCosts.Count -gt 1) {
        $lastGrowth = $monthlyCosts[-1].GrowthPercent
        if($lastGrowth -gt 5) {
            "    TrendStatus[Growing: $([math]::Round($lastGrowth, 1))% MoM]`n"
            "    Trends --> TrendStatus`n"
            "    style TrendStatus fill:#ff6b6b`n"
        } elseif($lastGrowth -lt -5) {
            "    TrendStatus[Declining: $([math]::Round($lastGrowth, 1))% MoM]`n"
            "    Trends --> TrendStatus`n"
            "    style TrendStatus fill:#51cf66`n"
        } else {
            "    TrendStatus[Stable: $([math]::Round($lastGrowth, 1))% MoM]`n"
            "    Trends --> TrendStatus`n"
            "    style TrendStatus fill:#74c0fc`n"
        }
    }
)
$(
    if($anomalies) {
        "    AnomalyCount[`"$($anomalies.Count) days identified`"]`n"
        "    Anomalies --> AnomalyCount`n"
        "    style AnomalyCount fill:#ffd43b`n"
    }
)
$(
    if($trendData -and $trendData.NewServices -ne 'None') {
        "    NewSvcInfo[Added this period]`n"
        "    NewSvc --> NewSvcInfo`n"
        "    style NewSvcInfo fill:#a9e34b`n"
    }
)
    
    style Root fill:#339af0,color:#fff
    style TopSvc fill:#748ffc
    style Trends fill:#748ffc
$(
    if($anomalies) {
        "    style Anomalies fill:#748ffc`n"
    }
)
$(
    if($trendData -and $trendData.NewServices -ne 'None') {
        "    style NewSvc fill:#748ffc`n"
    }
)
``````

### Recommendations

Based on the analysis, consider the following actions:

$(
    $recommendations = @()
    
    # High growth rate
    if($monthlyCosts.Count -gt 1 -and $monthlyCosts[-1].GrowthPercent -gt 10) {
        $recommendations += "1. **🔴 High Growth Alert**: Month-over-month cost increase of $([math]::Round($monthlyCosts[-1].GrowthPercent, 1))%. Review resource scaling and new deployments."
    }
    
    # Top service consuming >50%
    if($topDrivers[0].Percentage -gt 50) {
        $recommendations += "2. **⚠️ Single Service Dominance**: $($topDrivers[0].Service) accounts for $([math]::Round($topDrivers[0].Percentage, 1))% of total costs. Consider optimization opportunities."
    }
    
    # Anomalies detected
    if($anomalies) {
        $recommendations += "3. **🔍 Cost Spikes Detected**: $($anomalies.Count) days with abnormal costs. Investigate resource usage patterns on these dates."
    }
    
    # New services
    if($trendData -and $trendData.NewServices -ne 'None') {
        $recommendations += "4. **🆕 New Service Costs**: Recently added services may require budget adjustment: $($trendData.NewServices)"
    }
    
    # VM optimization
    if($vmAnalysis -and $vmAnalysis.Count -gt 0) {
        $recommendations += "5. **💻 VM Optimization**: Review VM SKU usage for right-sizing opportunities. Consider reserved instances for predictable workloads."
    }
    
    # General recommendations
    $recommendations += "6. **📊 Continuous Monitoring**: Set up budget alerts and cost anomaly detection in Azure Cost Management."
    $recommendations += "7. **🏷️ Resource Tagging**: Implement consistent tagging strategy for better cost allocation and chargeback."
    
    $recommendations -join "`n"
)

---

## Detailed Data

### Monthly Cost Breakdown

| Month | Total Cost | Growth % | Records |
|-------|------------|----------|---------|
$(
    $monthlyCosts | ForEach-Object {
        $monthName = ([DateTime]::ParseExact($_.Month, 'yyyy-MM', $null)).ToString('MMMM yyyy')
        $growthStr = if($_.GrowthPercent) { "$([math]::Round($_.GrowthPercent, 1))%" } else { "N/A" }
        "| $monthName | `$$([math]::Round($_.TotalCost, 2)) | $growthStr | $($_.RecordCount) |`n"
    }
)

### All Services

<details>
<summary>Click to expand complete service list</summary>

| Service | Total Cost | % of Total |
|---------|------------|------------|
$(
    $serviceCosts | ForEach-Object {
        "| $($_.Service) | `$$([math]::Round($_.TotalCost, 2)) | $([math]::Round($_.Percentage, 1))% |`n"
    }
)

</details>

---

## Appendix

### Data Sources

- **Cost Data:** $costsFile
- **Usage Data:** $(if($usageData) { $usageFile } else { "Not collected" })
- **Trend Analysis:** $(if($trendData) { $trendFile } else { "Not performed" })

### Analysis Methodology

1. **Data Collection**: Azure Cost Management Query API (2023-03-01)
2. **Grouping**: By Service Name for high-level insights
3. **Aggregation**: Daily and monthly summaries
4. **Trend Analysis**: Year-over-year comparison when available
5. **Anomaly Detection**: Statistical outlier identification (>150% of average)

### Report Generation

- **Generated by:** azure-az-cost-analysis-report.ps1
- **Report Format:** GitHub-flavored Markdown with Mermaid diagrams
- **Mermaid Version:** Compatible with GitHub (v10.6+)

---

**📌 Next Steps:**

1. Review recommendations and prioritize optimization efforts
2. Set up automated cost alerts in Azure portal
3. Schedule monthly reports for ongoing monitoring
4. Share this report with stakeholders and finance teams

*Report End*
"@

# Write report to file
$report | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  REPORT GENERATION COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Info "Report saved to: $reportFile"
Write-Info "Data files in: $dataPath"
Write-Host ""
Write-Host "📊 View the report:" -ForegroundColor Yellow
Write-Host "   - Open in VS Code or any Markdown viewer" -ForegroundColor White
Write-Host "   - Push to GitHub to see Mermaid diagrams rendered" -ForegroundColor White
Write-Host "   - Use GitHub Pages for web hosting" -ForegroundColor White
Write-Host ""

# Open report if possible
if(Get-Command code -ErrorAction SilentlyContinue) {
    Write-Host "Opening report in VS Code..." -ForegroundColor Cyan
    code $reportFile
}

return $reportFile
