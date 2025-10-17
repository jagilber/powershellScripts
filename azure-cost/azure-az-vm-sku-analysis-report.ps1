<#
.SYNOPSIS
    Generate detailed VM SKU analysis report with 12-month cost and usage trends.

.DESCRIPTION
    Creates a comprehensive Markdown report analyzing VM SKU costs, hours, and trends across 12 months.
    
    Features:
    - Monthly cost breakdown per VM SKU
    - Usage hours tracking for each SKU
    - Cost per hour trends
    - Month-over-month growth analysis
    - SKU utilization patterns
    - Visual Mermaid charts for trends
    - Peak usage identification
    - Cost efficiency metrics

.PARAMETER SubscriptionId
    Azure subscription ID to analyze. Defaults to current context.

.PARAMETER MonthsBack
    Number of months to analyze (default: 12, max: 24)

.PARAMETER OutputPath
    Directory for output reports (default: azure-cost-reports)

.PARAMETER MinCost
    Minimum total cost threshold for SKU inclusion (default: $10)

.EXAMPLE
    .\azure-az-vm-sku-analysis-report.ps1
    
    Generate 12-month VM SKU analysis report for current subscription.

.EXAMPLE
    .\azure-az-vm-sku-analysis-report.ps1 -MonthsBack 24 -MinCost 100
    
    Generate 24-month report including only SKUs with $100+ total cost.

.NOTES
    Author: Cost Analysis System
    Version: 1.0
    Date: 2025-10-07
    
    Requires:
    - Az.Accounts module
    - Azure Cost Management API access
    - Usage Details API access
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$SubscriptionId = '',
    
    [Parameter()]
    [ValidateRange(1, 24)]
    [int]$MonthsBack = 12,
    
    [Parameter()]
    [string]$OutputPath = 'azure-cost-reports',
    
    [Parameter()]
    [ValidateRange(0, 100000)]
    [double]$MinCost = 10
)

$ErrorActionPreference = 'Stop'

# Ensure output directory exists
if(-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "`n=== Azure VM SKU Analysis Report Generator ===" -ForegroundColor Cyan
Write-Host "Analyzing $MonthsBack months of VM usage data...`n" -ForegroundColor Yellow

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
    
    Write-Host "Subscription: $subName ($subId)" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to get Azure context: $($_.Exception.Message)"
    exit 1
}

# Calculate date ranges for each month
$endDate = Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0
$monthRanges = @()

for($i = 0; $i -lt $MonthsBack; $i++) {
    $monthEnd = $endDate.AddMonths(-$i)
    $monthStart = $monthEnd.AddMonths(-1)
    
    $monthRanges += [PSCustomObject]@{
        MonthName = $monthStart.ToString('yyyy-MM')
        StartDate = $monthStart.ToString('yyyy-MM-dd')
        EndDate = $monthEnd.ToString('yyyy-MM-dd')
        MonthIndex = $i
    }
}

Write-Host "`nCollecting VM usage data for $MonthsBack months..." -ForegroundColor Yellow
Write-Host "Date range: $($monthRanges[-1].StartDate) to $($monthRanges[0].EndDate)`n" -ForegroundColor White

# Collect VM usage data for each month
$vmSkuData = @{}
$totalMonths = $monthRanges.Count
$currentMonth = 0

foreach($range in $monthRanges) {
    $currentMonth++
    $progress = [math]::Round(($currentMonth / $totalMonths) * 100, 0)
    Write-Host "[$currentMonth/$totalMonths] Processing $($range.MonthName)... ($progress%)" -ForegroundColor Cyan
    
    # Query Usage Details API for VM data
    $apiVersion = '2021-10-01'
    $filter = "properties/usageStart ge '$($range.StartDate)' and properties/usageStart lt '$($range.EndDate)' and properties/meterCategory eq 'Virtual Machines'"
    $uri = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.Consumption/usageDetails?api-version=$apiVersion&`$filter=$filter&`$expand=properties/meterDetails"
    
    try {
        $token = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com').Token
        $headers = @{
            'Authorization' = "Bearer $token"
            'Content-Type' = 'application/json'
        }
        
        $allUsage = @()
        $nextLink = $uri
        
        do {
            $response = Invoke-RestMethod -Uri $nextLink -Method Get -Headers $headers
            
            if($response.value) {
                $allUsage += $response.value
            }
            
            $nextLink = $response.nextLink
            
        } while($nextLink)
        
        # Process VM usage data
        foreach($usage in $allUsage) {
            $sku = $usage.properties.meterSubCategory
            if(-not $sku) { $sku = $usage.properties.meterName }
            
            if(-not $vmSkuData.ContainsKey($sku)) {
                $vmSkuData[$sku] = [PSCustomObject]@{
                    SKU = $sku
                    MonthlyData = @{}
                    TotalCost = 0
                    TotalHours = 0
                    FirstSeen = $range.MonthName
                    LastSeen = $range.MonthName
                    ActiveMonths = 0
                }
            }
            
            if(-not $vmSkuData[$sku].MonthlyData.ContainsKey($range.MonthName)) {
                $vmSkuData[$sku].MonthlyData[$range.MonthName] = [PSCustomObject]@{
                    Month = $range.MonthName
                    Cost = 0
                    Hours = 0
                    CostPerHour = 0
                }
            }
            
            $cost = $usage.properties.cost
            $hours = $usage.properties.quantity
            
            $vmSkuData[$sku].MonthlyData[$range.MonthName].Cost += $cost
            $vmSkuData[$sku].MonthlyData[$range.MonthName].Hours += $hours
            $vmSkuData[$sku].TotalCost += $cost
            $vmSkuData[$sku].TotalHours += $hours
            $vmSkuData[$sku].LastSeen = $range.MonthName
        }
        
        # Calculate cost per hour for each SKU/month
        foreach($sku in $vmSkuData.Keys) {
            if($vmSkuData[$sku].MonthlyData.ContainsKey($range.MonthName)) {
                $monthData = $vmSkuData[$sku].MonthlyData[$range.MonthName]
                if($monthData.Hours -gt 0) {
                    $monthData.CostPerHour = $monthData.Cost / $monthData.Hours
                }
            }
        }
        
        Write-Host "  Found $($allUsage.Count) VM usage records" -ForegroundColor Gray
        
    } catch {
        Write-Warning "Failed to retrieve usage data for $($range.MonthName): $($_.Exception.Message)"
        continue
    }
}

# Calculate active months and filter by minimum cost
$skuList = $vmSkuData.Values | Where-Object { $_.TotalCost -ge $MinCost } | ForEach-Object {
    $_.ActiveMonths = ($_.MonthlyData.Values | Where-Object { $_.Hours -gt 0 }).Count
    $_
} | Sort-Object TotalCost -Descending

Write-Host "`nFound $($skuList.Count) VM SKUs meeting criteria (min cost: `$$MinCost)" -ForegroundColor Green
Write-Host "Total VM Cost: `$$([math]::Round(($skuList | Measure-Object -Property TotalCost -Sum).Sum, 2))" -ForegroundColor Green
Write-Host "Total VM Hours: $([math]::Round(($skuList | Measure-Object -Property TotalHours -Sum).Sum, 0))" -ForegroundColor Green

# Generate detailed markdown report
Write-Host "`nGenerating detailed VM SKU analysis report..." -ForegroundColor Yellow

$reportDate = Get-Date -Format 'yyyy-MM-dd'
$reportFile = Join-Path $OutputPath "vm-sku-analysis-$reportDate.md"

$report = @"
# VM SKU Analysis Report

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  
**Subscription:** $subName ($subId)  
**Period:** $($monthRanges[-1].StartDate) to $($monthRanges[0].EndDate) ($MonthsBack months)  
**SKUs Analyzed:** $($skuList.Count) (min cost threshold: `$$MinCost)

---

## Executive Summary

### Overall VM Costs

``````mermaid
graph LR
    Total[Total VM Costs]
    Cost[`$$([math]::Round(($skuList | Measure-Object -Property TotalCost -Sum).Sum, 2))]
    Hours[$([math]::Round(($skuList | Measure-Object -Property TotalHours -Sum).Sum, 0)) Hours]
    SKUs[$($skuList.Count) SKUs]
    
    Total --> Cost
    Total --> Hours
    Total --> SKUs
    
    style Total fill:#339af0,color:#fff
    style Cost fill:#51cf66
    style Hours fill:#74c0fc
    style SKUs fill:#ffd43b
``````

### Top 10 VM SKUs by Total Cost

| Rank | VM SKU | Total Cost | Total Hours | Avg Cost/Hour | Active Months | First Seen | Last Seen |
|------|--------|------------|-------------|---------------|---------------|------------|-----------|
$(
    $rank = 1
    $skuList | Select-Object -First 10 | ForEach-Object {
        $avgCostPerHour = if($_.TotalHours -gt 0) { $_.TotalCost / $_.TotalHours } else { 0 }
        "| $rank | $($_.SKU) | `$$([math]::Round($_.TotalCost, 2)) | $([math]::Round($_.TotalHours, 0)) | `$$([math]::Round($avgCostPerHour, 4)) | $($_.ActiveMonths) | $($_.FirstSeen) | $($_.LastSeen) |`n"
        $rank++
    }
)

---

## Detailed SKU Analysis

$(
    foreach($sku in $skuList) {
        $avgCostPerHour = if($sku.TotalHours -gt 0) { $sku.TotalCost / $sku.TotalHours } else { 0 }
        
        # Build monthly data table
        $monthlyTable = "| Month | Cost | Hours | Cost/Hour | MoM Change |`n"
        $monthlyTable += "|-------|------|-------|-----------|------------|`n"
        
        $previousCost = 0
        foreach($month in ($monthRanges | Sort-Object MonthIndex -Descending)) {
            $monthData = $sku.MonthlyData[$month.MonthName]
            
            if($monthData -and $monthData.Hours -gt 0) {
                $cost = [math]::Round($monthData.Cost, 2)
                $hours = [math]::Round($monthData.Hours, 0)
                $costPerHour = [math]::Round($monthData.CostPerHour, 4)
                
                $momChange = ''
                if($previousCost -gt 0) {
                    $changePercent = (($cost - $previousCost) / $previousCost) * 100
                    $momChange = "$([math]::Round($changePercent, 1))%"
                    
                    if($changePercent -gt 10) {
                        $momChange = "📈 $momChange"
                    } elseif($changePercent -lt -10) {
                        $momChange = "📉 $momChange"
                    } else {
                        $momChange = "→ $momChange"
                    }
                } else {
                    $momChange = "🆕 New"
                }
                
                $monthlyTable += "| $($month.MonthName) | `$$cost | $hours | `$$costPerHour | $momChange |`n"
                $previousCost = $cost
            } else {
                $monthlyTable += "| $($month.MonthName) | `$0.00 | 0 | `$0.00 | - |`n"
            }
        }
        
        # Calculate trend
        $activeMonthsData = $sku.MonthlyData.Values | Where-Object { $_.Hours -gt 0 } | Sort-Object Month
        $trendDirection = "→ Stable"
        $trendColor = "#74c0fc"
        
        if($activeMonthsData.Count -ge 3) {
            $firstThirdAvg = ($activeMonthsData | Select-Object -First ([math]::Ceiling($activeMonthsData.Count / 3)) | Measure-Object -Property Cost -Average).Average
            $lastThirdAvg = ($activeMonthsData | Select-Object -Last ([math]::Ceiling($activeMonthsData.Count / 3)) | Measure-Object -Property Cost -Average).Average
            
            if($firstThirdAvg -gt 0) {
                $trendChange = (($lastThirdAvg - $firstThirdAvg) / $firstThirdAvg) * 100
                
                if($trendChange -gt 20) {
                    $trendDirection = "📈 Growing ($([math]::Round($trendChange, 1))%)"
                    $trendColor = "#ff6b6b"
                } elseif($trendChange -lt -20) {
                    $trendDirection = "📉 Declining ($([math]::Round($trendChange, 1))%)"
                    $trendColor = "#51cf66"
                } else {
                    $trendDirection = "→ Stable ($([math]::Round($trendChange, 1))%)"
                }
            }
        }
        
        # Build cost trend chart (monthly costs)
        $chartData = ""
        $monthIndex = 0
        foreach($month in ($monthRanges | Sort-Object MonthIndex -Descending)) {
            $monthData = $sku.MonthlyData[$month.MonthName]
            $cost = if($monthData) { [math]::Round($monthData.Cost, 2) } else { 0 }
            
            if($cost -gt 0) {
                $monthLabel = $month.MonthName.Substring(5, 2)  # Just MM
                $chartData += "    M$monthIndex[$monthLabel<br>`$$cost]`n"
                $monthIndex++
            }
        }
        
        # Determine peak month
        $peakMonth = $sku.MonthlyData.Values | Sort-Object Cost -Descending | Select-Object -First 1
        $peakMonthName = if($peakMonth) { $peakMonth.Month } else { 'N/A' }
        $peakCost = if($peakMonth) { [math]::Round($peakMonth.Cost, 2) } else { 0 }

"
### $($sku.SKU)

**Summary:**
- **Total Cost:** `$$([math]::Round($sku.TotalCost, 2))
- **Total Hours:** $([math]::Round($sku.TotalHours, 0))
- **Average Cost/Hour:** `$$([math]::Round($avgCostPerHour, 4))
- **Active Months:** $($sku.ActiveMonths) of $MonthsBack
- **Lifecycle:** $($sku.FirstSeen) to $($sku.LastSeen)
- **Peak Month:** $peakMonthName (`$$peakCost)
- **Trend:** $trendDirection

#### Monthly Cost Trend

``````mermaid
graph LR
$chartData
    
$(
    # Add styling based on cost levels
    $maxCost = ($sku.MonthlyData.Values | Measure-Object -Property Cost -Maximum).Maximum
    $i = 0
    foreach($month in ($monthRanges | Sort-Object MonthIndex -Descending)) {
        $monthData = $sku.MonthlyData[$month.MonthName]
        if($monthData -and $monthData.Cost -gt 0) {
            $pct = if($maxCost -gt 0) { ($monthData.Cost / $maxCost) * 100 } else { 0 }
            
            if($pct -ge 80) {
                "    style M$i fill:#ff6b6b`n"
            } elseif($pct -ge 50) {
                "    style M$i fill:#ffd43b`n"
            } else {
                "    style M$i fill:#51cf66`n"
            }
            $i++
        }
    }
)
``````

#### Monthly Breakdown

$monthlyTable

---

"
    }
)

## Cost Trends Analysis

### SKU Lifecycle Patterns

$(
    $newSkus = $skuList | Where-Object { $_.FirstSeen -eq $monthRanges[0].MonthName } | Measure-Object
    $retiredSkus = $skuList | Where-Object { $_.LastSeen -ne $monthRanges[0].MonthName -and $_.ActiveMonths -ge 3 } | Measure-Object
    $growingSkus = $skuList | Where-Object { 
        $activeData = $_.MonthlyData.Values | Where-Object { $_.Hours -gt 0 } | Sort-Object Month
        if($activeData.Count -ge 3) {
            $firstThird = ($activeData | Select-Object -First ([math]::Ceiling($activeData.Count / 3)) | Measure-Object -Property Cost -Average).Average
            $lastThird = ($activeData | Select-Object -Last ([math]::Ceiling($activeData.Count / 3)) | Measure-Object -Property Cost -Average).Average
            $firstThird -gt 0 -and (($lastThird - $firstThird) / $firstThird) -gt 0.2
        } else {
            $false
        }
    } | Measure-Object
)

- **New SKUs** (first seen this month): $($newSkus.Count)
- **Retired/Inactive SKUs** (not seen recently): $($retiredSkus.Count)
- **Growing SKUs** (20%+ cost increase): $($growingSkus.Count)

### Monthly Aggregate Trends

``````mermaid
graph TB
    Start[VM Cost Analysis]
    
$(
    foreach($month in ($monthRanges | Select-Object -First 6 | Sort-Object MonthIndex -Descending)) {
        $monthTotal = ($skuList | ForEach-Object { 
            if($_.MonthlyData.ContainsKey($month.MonthName)) { 
                $_.MonthlyData[$month.MonthName].Cost 
            } else { 
                0 
            }
        } | Measure-Object -Sum).Sum
        
        $monthHours = ($skuList | ForEach-Object { 
            if($_.MonthlyData.ContainsKey($month.MonthName)) { 
                $_.MonthlyData[$month.MonthName].Hours 
            } else { 
                0 
            }
        } | Measure-Object -Sum).Sum
        
        $monthName = $month.MonthName
        "    M$monthName[`"$monthName<br>`$$([math]::Round($monthTotal, 2))<br>$([math]::Round($monthHours, 0))h`"]`n"
    }
)
    
    Start --> M$($monthRanges[5].MonthName)
$(
    for($i = 5; $i -gt 0; $i--) {
        "    M$($monthRanges[$i].MonthName) --> M$($monthRanges[$i-1].MonthName)`n"
    }
)
    
    style Start fill:#339af0,color:#fff
$(
    foreach($month in ($monthRanges | Select-Object -First 6)) {
        "    style M$($month.MonthName) fill:#74c0fc`n"
    }
)
``````

## Recommendations

### Cost Optimization Opportunities

$(
    # Identify high-cost SKUs with declining usage
    $optimizationTargets = $skuList | Where-Object {
        $activeData = $_.MonthlyData.Values | Where-Object { $_.Hours -gt 0 } | Sort-Object Month
        if($activeData.Count -ge 3) {
            $firstHalf = ($activeData | Select-Object -First ([math]::Ceiling($activeData.Count / 2)) | Measure-Object -Property Hours -Average).Average
            $lastHalf = ($activeData | Select-Object -Last ([math]::Ceiling($activeData.Count / 2)) | Measure-Object -Property Hours -Average).Average
            $_.TotalCost -gt 100 -and $firstHalf -gt 0 -and (($lastHalf - $firstHalf) / $firstHalf) -lt -0.1
        } else {
            $false
        }
    } | Select-Object -First 5
    
    if($optimizationTargets) {
        foreach($target in $optimizationTargets) {
            "- **$($target.SKU)**: Total cost `$$([math]::Round($target.TotalCost, 2)) with declining usage hours. Consider rightsizing or decommissioning.`n"
        }
    } else {
        "- No obvious optimization targets identified based on usage trends.`n"
    }
)

### Growth Monitoring

$(
    $highGrowthSkus = $skuList | Where-Object { 
        $activeData = $_.MonthlyData.Values | Where-Object { $_.Hours -gt 0 } | Sort-Object Month
        if($activeData.Count -ge 3) {
            $firstThird = ($activeData | Select-Object -First ([math]::Ceiling($activeData.Count / 3)) | Measure-Object -Property Cost -Average).Average
            $lastThird = ($activeData | Select-Object -Last ([math]::Ceiling($activeData.Count / 3)) | Measure-Object -Property Cost -Average).Average
            $firstThird -gt 0 -and (($lastThird - $firstThird) / $firstThird) -gt 0.3
        } else {
            $false
        }
    } | Select-Object -First 5
    
    if($highGrowthSkus) {
        foreach($sku in $highGrowthSkus) {
            "- **$($sku.SKU)**: Rapid cost growth detected. Monitor for unexpected scaling or review Reserved Instance opportunities.`n"
        }
    } else {
        "- No SKUs showing exceptional growth patterns.`n"
    }
)

---

**Report End**

*For detailed raw data, use azure-az-export-costs.ps1 with -IncludeUsageDetails parameter.*
"@

# Write report to file
$report | Out-File -FilePath $reportFile -Encoding UTF8 -Force

Write-Host "`n✅ Report generated successfully!" -ForegroundColor Green
Write-Host "   Location: $reportFile" -ForegroundColor White
Write-Host "   Size: $([math]::Round((Get-Item $reportFile).Length / 1KB, 2)) KB" -ForegroundColor White
Write-Host "`nKey Statistics:" -ForegroundColor Yellow
Write-Host "  • Total SKUs analyzed: $($skuList.Count)" -ForegroundColor Cyan
Write-Host "  • Total VM cost: `$$([math]::Round(($skuList | Measure-Object -Property TotalCost -Sum).Sum, 2))" -ForegroundColor Cyan
Write-Host "  • Total VM hours: $([math]::Round(($skuList | Measure-Object -Property TotalHours -Sum).Sum, 0))" -ForegroundColor Cyan
Write-Host "  • Date range: $MonthsBack months" -ForegroundColor Cyan

Write-Host "`n=== VM SKU Analysis Complete ===" -ForegroundColor Green
