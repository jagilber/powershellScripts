<#
.SYNOPSIS
    Test harness for azure-az-tag-manager.ps1

.DESCRIPTION
    Validates all major functionality of the tag manager script including:
    - Create, Read, Update, Delete, Merge, Replace operations
    - Resource group and individual resource tagging
    - Bulk operations on all resources
    - Import/Export functionality
    - WhatIf mode validation
    - Error handling scenarios

.NOTES
    Run this after making changes to azure-az-tag-manager.ps1 to ensure functionality
    Requires a test resource group to be specified
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TestResourceGroupName,
    
    [Parameter()]
    [switch]$CleanupOnly
)

$ErrorActionPreference = 'Stop'
$script:testsPassed = 0
$script:testsFailed = 0
$script:testResults = @()

function write-testResult($testName, $passed, $message = '') {
    $result = [PSCustomObject]@{
        Test = $testName
        Status = if($passed) { 'PASS' } else { 'FAIL' }
        Message = $message
        Timestamp = Get-Date
    }
    
    $script:testResults += $result
    
    if ($passed) {
        $script:testsPassed++
        Write-Host "✓ PASS: $testName" -ForegroundColor Green
    }
    else {
        $script:testsFailed++
        Write-Host "✗ FAIL: $testName - $message" -ForegroundColor Red
    }
    
    if ($message) {
        Write-Host "  $message" -ForegroundColor Gray
    }
}

function test-resourceGroupExists() {
    $testName = "Resource Group Exists"
    try {
        $rg = Get-AzResourceGroup -Name $TestResourceGroupName -ErrorAction SilentlyContinue
        if ($rg) {
            write-testResult $testName $true "Resource group '$TestResourceGroupName' found"
            return $true
        }
        else {
            write-testResult $testName $false "Resource group '$TestResourceGroupName' not found. Create it first or specify different resource group."
            return $false
        }
    }
    catch {
        write-testResult $testName $false $_.Exception.Message
        return $false
    }
}

function test-createTagsOnResourceGroup() {
    $testName = "Create Tags on Resource Group"
    try {
        & .\azure-az-tag-manager.ps1 -Operation Create `
                                      -ResourceGroupName $TestResourceGroupName `
                                      -Tags @{TestTag1='Value1'; TestTag2='Value2'} `
                                      -Force `
                                      -ErrorAction Stop
        
        $rg = Get-AzResourceGroup -Name $TestResourceGroupName
        if ($rg.Tags -and $rg.Tags['TestTag1'] -eq 'Value1') {
            write-testResult $testName $true
            return $true
        }
        else {
            write-testResult $testName $false "Tags not applied correctly"
            return $false
        }
    }
    catch {
        write-testResult $testName $false $_.Exception.Message
        return $false
    }
}

function test-readTagsFromResourceGroup() {
    $testName = "Read Tags from Resource Group"
    try {
        $output = & .\azure-az-tag-manager.ps1 -Operation Read `
                                               -ResourceGroupName $TestResourceGroupName `
                                               -ErrorAction Stop 2>&1 | Out-String
        
        if ($output -match 'TestTag1') {
            write-testResult $testName $true
            return $true
        }
        else {
            write-testResult $testName $false "Tags not found in output"
            return $false
        }
    }
    catch {
        write-testResult $testName $false $_.Exception.Message
        return $false
    }
}

function test-updateTagsOnResourceGroup() {
    $testName = "Update Tags on Resource Group"
    try {
        & .\azure-az-tag-manager.ps1 -Operation Update `
                                      -ResourceGroupName $TestResourceGroupName `
                                      -Tags @{TestTag1='UpdatedValue'} `
                                      -Force `
                                      -ErrorAction Stop
        
        $rg = Get-AzResourceGroup -Name $TestResourceGroupName
        if ($rg.Tags['TestTag1'] -eq 'UpdatedValue') {
            write-testResult $testName $true
            return $true
        }
        else {
            write-testResult $testName $false "Tag value not updated"
            return $false
        }
    }
    catch {
        write-testResult $testName $false $_.Exception.Message
        return $false
    }
}

function test-mergeTagsOnResourceGroup() {
    $testName = "Merge Tags on Resource Group"
    try {
        & .\azure-az-tag-manager.ps1 -Operation Merge `
                                      -ResourceGroupName $TestResourceGroupName `
                                      -Tags @{TestTag3='Value3'} `
                                      -Force `
                                      -ErrorAction Stop
        
        $rg = Get-AzResourceGroup -Name $TestResourceGroupName
        if ($rg.Tags['TestTag3'] -eq 'Value3' -and $rg.Tags['TestTag1'] -eq 'UpdatedValue') {
            write-testResult $testName $true
            return $true
        }
        else {
            write-testResult $testName $false "Tags not merged correctly"
            return $false
        }
    }
    catch {
        write-testResult $testName $false $_.Exception.Message
        return $false
    }
}

function test-deleteTagFromResourceGroup() {
    $testName = "Delete Tag from Resource Group"
    try {
        & .\azure-az-tag-manager.ps1 -Operation Delete `
                                      -ResourceGroupName $TestResourceGroupName `
                                      -TagName 'TestTag3' `
                                      -Force `
                                      -ErrorAction Stop
        
        $rg = Get-AzResourceGroup -Name $TestResourceGroupName
        if (-not $rg.Tags.ContainsKey('TestTag3')) {
            write-testResult $testName $true
            return $true
        }
        else {
            write-testResult $testName $false "Tag not deleted"
            return $false
        }
    }
    catch {
        write-testResult $testName $false $_.Exception.Message
        return $false
    }
}

function test-exportTags() {
    $testName = "Export Tags to JSON"
    $exportPath = "$PSScriptRoot\test-tags-export.json"
    
    try {
        & .\azure-az-tag-manager.ps1 -Operation Read `
                                      -ResourceGroupName $TestResourceGroupName `
                                      -ExportPath $exportPath `
                                      -ErrorAction Stop
        
        if (Test-Path $exportPath) {
            $content = Get-Content $exportPath -Raw | ConvertFrom-Json
            if ($content.ResourceGroupName -eq $TestResourceGroupName) {
                write-testResult $testName $true
                return $true
            }
        }
        
        write-testResult $testName $false "Export file not created or invalid"
        return $false
    }
    catch {
        write-testResult $testName $false $_.Exception.Message
        return $false
    }
}

function test-whatIfMode() {
    $testName = "WhatIf Mode (no changes made)"
    try {
        $rg = Get-AzResourceGroup -Name $TestResourceGroupName
        $tagCountBefore = if ($rg.Tags) { $rg.Tags.Count } else { 0 }
        
        & .\azure-az-tag-manager.ps1 -Operation Create `
                                      -ResourceGroupName $TestResourceGroupName `
                                      -Tags @{WhatIfTest='ShouldNotApply'} `
                                      -WhatIf `
                                      -ErrorAction Stop
        
        $rg = Get-AzResourceGroup -Name $TestResourceGroupName
        $tagCountAfter = if ($rg.Tags) { $rg.Tags.Count } else { 0 }
        
        if ($tagCountBefore -eq $tagCountAfter -and -not $rg.Tags.ContainsKey('WhatIfTest')) {
            write-testResult $testName $true
            return $true
        }
        else {
            write-testResult $testName $false "WhatIf mode applied changes"
            return $false
        }
    }
    catch {
        write-testResult $testName $false $_.Exception.Message
        return $false
    }
}

function test-replaceTagsOnResourceGroup() {
    $testName = "Replace All Tags on Resource Group"
    try {
        & .\azure-az-tag-manager.ps1 -Operation Replace `
                                      -ResourceGroupName $TestResourceGroupName `
                                      -Tags @{FinalTag='FinalValue'} `
                                      -Force `
                                      -ErrorAction Stop
        
        $rg = Get-AzResourceGroup -Name $TestResourceGroupName
        if ($rg.Tags.Count -eq 1 -and $rg.Tags['FinalTag'] -eq 'FinalValue') {
            write-testResult $testName $true
            return $true
        }
        else {
            write-testResult $testName $false "Tags not replaced correctly"
            return $false
        }
    }
    catch {
        write-testResult $testName $false $_.Exception.Message
        return $false
    }
}

function test-applyToAllResources() {
    $testName = "Apply Tags to All Resources"
    try {
        $resources = Get-AzResource -ResourceGroupName $TestResourceGroupName
        
        if ($resources.Count -eq 0) {
            write-testResult $testName $true "Skipped - No resources in group"
            return $true
        }
        
        & .\azure-az-tag-manager.ps1 -Operation Create `
                                      -ResourceGroupName $TestResourceGroupName `
                                      -Tags @{BulkTag='BulkValue'} `
                                      -ApplyToAllResources `
                                      -Force `
                                      -ErrorAction Stop
        
        $resources = Get-AzResource -ResourceGroupName $TestResourceGroupName
        $allHaveTag = $true
        foreach ($resource in $resources) {
            if (-not $resource.Tags -or $resource.Tags['BulkTag'] -ne 'BulkValue') {
                $allHaveTag = $false
                break
            }
        }
        
        if ($allHaveTag) {
            write-testResult $testName $true
            return $true
        }
        else {
            write-testResult $testName $false "Not all resources have the tag"
            return $false
        }
    }
    catch {
        write-testResult $testName $false $_.Exception.Message
        return $false
    }
}

function cleanup-testTags() {
    Write-Host "`nCleaning up test tags..." -ForegroundColor Cyan
    
    try {
        # Remove all tags from resource group
        & .\azure-az-tag-manager.ps1 -Operation Replace `
                                      -ResourceGroupName $TestResourceGroupName `
                                      -Tags @{} `
                                      -Force `
                                      -ErrorAction SilentlyContinue
        
        # Remove test export file
        $exportPath = "$PSScriptRoot\test-tags-export.json"
        if (Test-Path $exportPath) {
            Remove-Item $exportPath -Force
        }
        
        Write-Host "✓ Cleanup completed" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Cleanup encountered errors: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Main test execution
function main() {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Azure Tag Manager Test Harness" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Host "Test Resource Group: $TestResourceGroupName`n" -ForegroundColor Yellow
    
    if ($CleanupOnly) {
        cleanup-testTags
        return 0
    }
    
    # Prerequisites
    if (-not (test-resourceGroupExists)) {
        Write-Host "`nTests cannot proceed without valid resource group" -ForegroundColor Red
        return 1
    }
    
    # Run tests
    Write-Host "`nRunning tests...`n" -ForegroundColor Cyan
    
    test-createTagsOnResourceGroup
    test-readTagsFromResourceGroup
    test-updateTagsOnResourceGroup
    test-mergeTagsOnResourceGroup
    test-deleteTagFromResourceGroup
    test-exportTags
    test-whatIfMode
    test-replaceTagsOnResourceGroup
    test-applyToAllResources
    
    # Results
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "TEST RESULTS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total Tests: $($script:testsPassed + $script:testsFailed)" -ForegroundColor White
    Write-Host "Passed:      $script:testsPassed" -ForegroundColor Green
    Write-Host "Failed:      $script:testsFailed" -ForegroundColor $(if($script:testsFailed -gt 0){'Red'}else{'White'})
    
    # Detailed results
    Write-Host "`nDetailed Results:" -ForegroundColor Cyan
    $script:testResults | Format-Table -AutoSize
    
    # Cleanup
    $cleanup = Read-Host "`nCleanup test tags? (y/n)"
    if ($cleanup -eq 'y') {
        cleanup-testTags
    }
    
    # Exit code
    if ($script:testsFailed -gt 0) {
        Write-Host "`nTests FAILED" -ForegroundColor Red
        return 1
    }
    else {
        Write-Host "`nAll tests PASSED" -ForegroundColor Green
        return 0
    }
}

$exitCode = main
exit $exitCode
