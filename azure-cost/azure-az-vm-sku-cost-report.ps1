<#
.SYNOPSIS
    Generate VM SKU cost analysis using Cost Management Query API (works with standard permissions).

.DESCRIPTION
    Alternative VM SKU analysis that uses Cost Management Query API instead of Usage Details API.
    This works with Owner/Contributor roles without requiring special Cost Management permissions.
    
    Note: Provides cost data but not hour-level usage details. Shows daily costs per SKU.

.PARAMETER SubscriptionId
    Azure subscription ID to analyze.

.PARAMETER StartDate
    Start date for analysis (flexible format: 2024-01-01, 1/1/2024, Jan 1 2024)

.PARAMETER EndDate
    End date for analysis (default: today)

.PARAMETER OutputPath
    Directory for output reports (default: azure-cost-reports)

.PARAMETER MinCost
    Minimum total cost threshold for SKU inclusion (default: $1)

.EXAMPLE
    .\azure-az-vm-sku-cost-report.ps1 -StartDate "2024-01-01"
    
    Analyze VM SKU costs from Jan 1, 2024 to today.

.NOTES
    Author: Cost Analysis System
    Version: 1.0
    Date: 2025-10-07
    
    Uses Cost Management Query API which has ~5 months of historical data.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$SubscriptionId = '',
    
    [Parameter()]
    [string]$StartDate = '',
    
    [Parameter()]
    [string]$EndDate = '',
    
    [Parameter()]
    [string]$OutputPath = 'azure-cost-reports',
    
    [Parameter()]
    [ValidateRange(0, 10000)]
    [double]$MinCost = 1.0
)

$ErrorActionPreference = 'Stop'

# Ensure output directory exists
if(-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "`n=== Azure VM SKU Cost Report (Cost Management API) ===" -ForegroundColor Cyan

# Get subscription context
try {
    $context = Get-AzContext
    if(-not $context) {
        throw "Not logged in to Azure. Run Connect-AzAccount first."
    }
    
    if($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        $context = Get-AzContext
    }
    
    $subId = $context.Subscription.Id
    $subName = $context.Subscription.Name
    
    Write-Host "Subscription: $subName`n" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to get Azure context: $($_.Exception.Message)"
    exit 1
}

# Parse dates
if(-not $StartDate) {
    $StartDate = (Get-Date).AddMonths(-12).ToString('yyyy-MM-01')
}
if(-not $EndDate) {
    $EndDate = (Get-Date).ToString('yyyy-MM-dd')
}

# Parse flexible date formats
$startParsed = [DateTime]::Parse($StartDate)
$endParsed = [DateTime]::Parse($EndDate)

Write-Host "Date Range: $($startParsed.ToString('yyyy-MM-dd')) to $($endParsed.ToString('yyyy-MM-dd'))`n" -ForegroundColor White

# Call the existing export script to get VM SKU data
Write-Host "Collecting VM SKU cost data..." -ForegroundColor Yellow

$tempOutput = Join-Path $env:TEMP "vm-sku-temp-$(Get-Date -Format 'yyyyMMddHHmmss')"

try {
    $null = & "$PSScriptRoot\azure-az-export-costs.ps1" `
        -SubscriptionId $subId `
        -StartDate $startParsed.ToString('yyyy-MM-dd') `
        -EndDate $endParsed.ToString('yyyy-MM-dd') `
        -GroupBy MeterSubcategory `
        -OutputPath $tempOutput `
        -ErrorAction Stop 2>&1
    
    # Read the generated CSV
    $costFile = Get-ChildItem -Path "$tempOutput*.csv" -Filter "*costs.csv" | Select-Object -First 1
    if(-not $costFile) {
        throw "Cost data file not found"
    }
    
    $allCosts = Import-Csv $costFile.FullName
    
    # Filter for VM SKUs
    $vmSkus = $allCosts | Where-Object { 
        $_.MeterSubcategory -like "*Virtual Machines*" 
    } | ForEach-Object {
        [PSCustomObject]@{
            SKU = $_.MeterSubcategory
            TotalCost = [double]$_.Cost
            DaysActive = [int]$_.DaysActive
            AvgDaily = [double]$_.AvgDailyCost
        }
    } | Where-Object { $_.TotalCost -ge $MinCost } | Sort-Object TotalCost -Descending
    
    Write-Host "Found $($vmSkus.Count) VM SKUs (min cost: `$$MinCost)`n" -ForegroundColor Green
    
    if($vmSkus.Count -eq 0) {
        Write-Warning "No VM SKUs found meeting criteria. Try lowering -MinCost or checking date range."
        exit 0
    }
    
    # Get daily breakdown for detailed analysis
    $dailyFile = Get-ChildItem -Path "$tempOutput*.csv" -Filter "*daily.csv" | Select-Object -First 1
    $dailyData = if($dailyFile) { Import-Csv $dailyFile.FullName } else { @() }
    
} catch {
    Write-Error "Failed to collect cost data: $($_.Exception.Message)"
    exit 1
} finally {
    # Cleanup temp files
    if(Test-Path $tempOutput*) {
        Remove-Item "$tempOutput*" -Force -ErrorAction SilentlyContinue
    }
}

# Generate report
Write-Host "Generating VM SKU cost report...`n" -ForegroundColor Yellow

$reportDate = Get-Date -Format 'yyyy-MM-dd'
$reportFile = Join-Path $OutputPath "vm-sku-cost-report-$reportDate.md"

$totalVMCost = ($vmSkus | Measure-Object -Property TotalCost -Sum).Sum
$totalDays = ($endParsed - $startParsed).Days

$report = @"
# VM SKU Cost Report

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  
**Subscription:** $subName ($subId)  
**Period:** $($startParsed.ToString('yyyy-MM-dd')) to $($endParsed.ToString('yyyy-MM-dd')) ($totalDays days)  
**SKUs Found:** $($vmSkus.Count) (min cost threshold: `$$MinCost)

> **Note:** This report uses Cost Management Query API which typically has ~5 months of historical data.  
> For hour-level usage details, use the Usage Details API (requires additional permissions).

---

## Executive Summary

### Total VM Costs

``````mermaid
graph LR
    Total[Total VM Costs]
    Cost[`$$([math]::Round($totalVMCost, 2))]
    SKUs[$($vmSkus.Count) SKUs]
    Days[$totalDays Days Period]
    
    Total --> Cost
    Total --> SKUs
    Total --> Days
    
    style Total fill:#339af0,color:#fff
    style Cost fill:#51cf66
    style SKUs fill:#ffd43b
    style Days fill:#74c0fc
``````

### VM SKUs Ranked by Total Cost

| Rank | VM SKU | Total Cost | Days Active | Avg Cost/Day | % of Total |
|------|--------|------------|-------------|--------------|------------|
$(
    $rank = 1
    foreach($sku in $vmSkus) {
        $pct = if($totalVMCost -gt 0) { ($sku.TotalCost / $totalVMCost) * 100 } else { 0 }
        "| $rank | $($sku.SKU) | `$$([math]::Round($sku.TotalCost, 2)) | $($sku.DaysActive) | `$$([math]::Round($sku.AvgDaily, 2)) | $([math]::Round($pct, 1))% |`n"
        $rank++
    }
)

---

## Detailed SKU Analysis

$(
    foreach($sku in $vmSkus) {
        $pctOfTotal = if($totalVMCost -gt 0) { ($sku.TotalCost / $totalVMCost) * 100 } else { 0 }
        $utilizationPct = if($totalDays -gt 0) { ($sku.DaysActive / $totalDays) * 100 } else { 0 }
        
        # Determine if this is high, medium, or low usage
        $usageLevel = if($utilizationPct -gt 50) { "High" } elseif($utilizationPct -gt 20) { "Medium" } else { "Low" }
        $usageColor = if($utilizationPct -gt 50) { "#ff6b6b" } elseif($utilizationPct -gt 20) { "#ffd43b" } else { "#51cf66" }
        
"
### $($sku.SKU)

**Summary:**
- **Total Cost:** `$$([math]::Round($sku.TotalCost, 2))
- **Days Active:** $($sku.DaysActive) of $totalDays ($([math]::Round($utilizationPct, 1))%)
- **Average Daily Cost:** `$$([math]::Round($sku.AvgDaily, 2))
- **Percentage of Total VM Cost:** $([math]::Round($pctOfTotal, 1))%
- **Usage Level:** $usageLevel utilization

#### Cost Overview

``````mermaid
graph LR
    SKU[`"$($sku.SKU)`"]
    TotalCost[`"Total: `$$([math]::Round($sku.TotalCost, 2))`"]
    DaysActive[`"$($sku.DaysActive) days active`"]
    AvgCost[`"Avg: `$$([math]::Round($sku.AvgDaily, 2))/day`"]
    
    SKU --> TotalCost
    SKU --> DaysActive
    SKU --> AvgCost
    
    style SKU fill:#339af0,color:#fff
    style TotalCost fill:#51cf66
    style DaysActive fill:$usageColor
    style AvgCost fill:#74c0fc
``````

"
        # Add cost efficiency insight
        if($utilizationPct -lt 10) {
            "**💡 Insight:** Very low utilization ($([math]::Round($utilizationPct, 1))%). Consider on-demand usage or decommission if no longer needed.`n`n"
        } elseif($utilizationPct -gt 80) {
            "**💡 Insight:** High utilization ($([math]::Round($utilizationPct, 1))%). Good candidate for Reserved Instances to save costs.`n`n"
        } else {
            "**💡 Insight:** Moderate utilization ($([math]::Round($utilizationPct, 1))%). Monitor usage patterns to optimize.`n`n"
        }
        
"---`n`n"
    }
)

## Cost Analysis

### Total VM Cost Breakdown

``````mermaid
pie title VM Cost Distribution
$(
    $vmSkus | Select-Object -First 8 | ForEach-Object {
        "    `"$($_.SKU)`" : $([math]::Round($_.TotalCost, 2))`n"
    }
    
    $others = ($vmSkus | Select-Object -Skip 8 | Measure-Object -Property TotalCost -Sum).Sum
    if($others -gt 0) {
        "    `"Others`" : $([math]::Round($others, 2))`n"
    }
)
``````

### Utilization Patterns

| Usage Level | SKU Count | Total Cost | % of Total Cost |
|-------------|-----------|------------|-----------------|
$(
    $highUtil = $vmSkus | Where-Object { ($_.DaysActive / $totalDays) -gt 0.5 }
    $medUtil = $vmSkus | Where-Object { ($_.DaysActive / $totalDays) -le 0.5 -and ($_.DaysActive / $totalDays) -gt 0.2 }
    $lowUtil = $vmSkus | Where-Object { ($_.DaysActive / $totalDays) -le 0.2 }
    
    $highCost = ($highUtil | Measure-Object -Property TotalCost -Sum).Sum
    $medCost = ($medUtil | Measure-Object -Property TotalCost -Sum).Sum
    $lowCost = ($lowUtil | Measure-Object -Property TotalCost -Sum).Sum
    
    "| High (>50% days) | $($highUtil.Count) | `$$([math]::Round($highCost, 2)) | $([math]::Round(($highCost / $totalVMCost) * 100, 1))% |`n"
    "| Medium (20-50% days) | $($medUtil.Count) | `$$([math]::Round($medCost, 2)) | $([math]::Round(($medCost / $totalVMCost) * 100, 1))% |`n"
    "| Low (<20% days) | $($lowUtil.Count) | `$$([math]::Round($lowCost, 2)) | $([math]::Round(($lowCost / $totalVMCost) * 100, 1))% |`n"
)

## Recommendations

### Reserved Instance Candidates

$(
    $riCandidates = $vmSkus | Where-Object { ($_.DaysActive / $totalDays) -gt 0.7 -and $_.TotalCost -gt 50 }
    if($riCandidates) {
        "High-utilization SKUs that could benefit from Reserved Instances:`n`n"
        foreach($candidate in $riCandidates) {
            "- **$($candidate.SKU)**: $($candidate.DaysActive)/$totalDays days active, `$$([math]::Round($candidate.TotalCost, 2)) total cost`n"
        }
    } else {
        "No SKUs with consistent high utilization (>70% of days) were found in this period.`n"
    }
)

### Cost Optimization Opportunities

$(
    $optimizationTargets = $vmSkus | Where-Object { ($_.DaysActive / $totalDays) -lt 0.1 -and $_.TotalCost -gt 10 }
    if($optimizationTargets) {
        "Low-utilization SKUs that may be candidates for rightsizing or decommissioning:`n`n"
        foreach($target in $optimizationTargets) {
            "- **$($target.SKU)**: Only $($target.DaysActive)/$totalDays days active ($([math]::Round(($target.DaysActive / $totalDays) * 100, 1))%), `$$([math]::Round($target.TotalCost, 2)) cost`n"
        }
    } else {
        "No obvious low-utilization targets identified.`n"
    }
)

---

## Data Source Notes

**API Used:** Azure Cost Management Query API  
**Data Retention:** Typically ~5 months of historical data  
**Granularity:** Daily cost aggregation (hour-level data requires Usage Details API)

For complete hour-by-hour usage analysis, use `azure-az-vm-sku-analysis-report.ps1` with Usage Details API permissions.

---

**Report End** • Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

# Write report
$report | Out-File -FilePath $reportFile -Encoding UTF8 -Force

Write-Host "✅ Report generated successfully!" -ForegroundColor Green
Write-Host "   Location: $reportFile" -ForegroundColor White
Write-Host "   Size: $([math]::Round((Get-Item $reportFile).Length / 1KB, 2)) KB`n" -ForegroundColor White

Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  • VM SKUs found: $($vmSkus.Count)" -ForegroundColor Cyan
Write-Host "  • Total VM cost: `$$([math]::Round($totalVMCost, 2))" -ForegroundColor Cyan
Write-Host "  • Date range: $totalDays days" -ForegroundColor Cyan
Write-Host "  • Top SKU: $($vmSkus[0].SKU) (`$$([math]::Round($vmSkus[0].TotalCost, 2)))" -ForegroundColor Cyan

Write-Host "`n=== VM SKU Cost Report Complete ===" -ForegroundColor Green
