<#
.SYNOPSIS
    Complete CRUD management of Azure resource tags at resource and resource group levels.

.DESCRIPTION
    PowerShell script to create, read, update, and delete tags on Azure resources and resource groups.
    Supports individual resource tagging and bulk operations on all resources within a resource group.
    Can load sensitive values from .env file using load-envFile.ps1.
    Operations are idempotent and support -WhatIf for preview.

Microsoft Privacy Statement: https://privacy.microsoft.com/en-US/privacystatement
    MIT License
    Copyright (c) Microsoft Corporation. All rights reserved.
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE

.NOTES
    File Name  : azure-az-tag-manager.ps1
    Author     : jagilber
    Requires   : Az.Accounts, Az.Resources
    Disclaimer : Provided AS-IS without warranty.
    Version    : 1.0
    Changelog  : 1.0 - Initial release with full CRUD operations

.PARAMETER Operation
    Tag operation to perform: Create, Read, Update, Delete, Merge, Replace

.PARAMETER ResourceGroupName
    Target Azure resource group name (mandatory).

.PARAMETER ResourceName
    Specific resource name to tag. If not specified, operations apply to resource group.

.PARAMETER ResourceType
    Azure resource type (e.g., Microsoft.Compute/virtualMachines). Required when ResourceName is specified.

.PARAMETER Tags
    Hashtable of tags to apply. Example: @{Environment='Production'; Owner='TeamA'}

.PARAMETER TagName
    Single tag name for Read or Delete operations.

.PARAMETER ApplyToAllResources
    Apply tag operation to all resources within the resource group.

.PARAMETER EnvFile
    Path to .env file containing tag values or secrets. Uses load-envFile.ps1.

.PARAMETER Force
    Skip confirmation prompts for destructive operations.

.PARAMETER SubscriptionId
    Azure subscription ID. If not specified, uses current context.

.PARAMETER ExportPath
    Export current tags to JSON file at specified path.

.PARAMETER ImportPath
    Import and apply tags from JSON file.

.PARAMETER Diagnostics
    Display diagnostic information about the execution environment.

.EXAMPLE
    .\azure-az-tag-manager.ps1 -Operation Read -ResourceGroupName 'myRG'
    
    Read all tags from resource group 'myRG'.

.EXAMPLE
    .\azure-az-tag-manager.ps1 -Operation Create -ResourceGroupName 'myRG' -Tags @{Environment='Production'; CostCenter='IT'}
    
    Create/add tags to resource group 'myRG'.

.EXAMPLE
    .\azure-az-tag-manager.ps1 -Operation Update -ResourceGroupName 'myRG' -ResourceName 'myVM' -ResourceType 'Microsoft.Compute/virtualMachines' -Tags @{Owner='John'}
    
    Update tags on specific virtual machine resource.

.EXAMPLE
    .\azure-az-tag-manager.ps1 -Operation Create -ResourceGroupName 'myRG' -Tags @{Project='Alpha'} -ApplyToAllResources
    
    Apply tag to all resources within the resource group.

.EXAMPLE
    .\azure-az-tag-manager.ps1 -Operation Delete -ResourceGroupName 'myRG' -TagName 'Temporary' -ApplyToAllResources -WhatIf
    
    Preview deletion of 'Temporary' tag from all resources (WhatIf mode).

.EXAMPLE
    .\azure-az-tag-manager.ps1 -Operation Replace -ResourceGroupName 'myRG' -Tags @{Environment='Dev'} -Force
    
    Replace all existing tags with new set (destructive operation).

.EXAMPLE
    .\azure-az-tag-manager.ps1 -Operation Read -ResourceGroupName 'myRG' -ExportPath '.\tags-backup.json'
    
    Export all resource group and resource tags to JSON file.

.EXAMPLE
    .\azure-az-tag-manager.ps1 -Operation Create -ResourceGroupName 'myRG' -ImportPath '.\tags-backup.json' -WhatIf
    
    Preview import and application of tags from JSON file.

.EXAMPLE
    .\azure-az-tag-manager.ps1 -Operation Create -ResourceGroupName 'myRG' -EnvFile '.\.env.tags' -Tags @{SECRET_TAG='${OWNER_EMAIL}'}
    
    Load values from .env file and apply tags with substitution.

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-tag-manager.ps1" -outFile "$pwd\azure-az-tag-manager.ps1";
    .\azure-az-tag-manager.ps1 -Operation Read -ResourceGroupName 'myRG'
#>

#requires -version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Create', 'Read', 'Update', 'Delete', 'Merge', 'Replace')]
    [string]$Operation,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter()]
    [string]$ResourceName,
    
    [Parameter()]
    [string]$ResourceType,
    
    [Parameter()]
    [hashtable]$Tags,
    
    [Parameter()]
    [string]$TagName,
    
    [Parameter()]
    [switch]$ApplyToAllResources,
    
    [Parameter()]
    [string]$EnvFile,
    
    [Parameter()]
    [switch]$Force,
    
    [Parameter()]
    [string]$SubscriptionId,
    
    [Parameter()]
    [string]$ExportPath,
    
    [Parameter()]
    [string]$ImportPath,
    
    [Parameter()]
    [switch]$Diagnostics
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'Stop'
$scriptName = "$psscriptroot\$($MyInvocation.MyCommand.Name)"
$script:processedCount = 0
$script:successCount = 0
$script:failureCount = 0

# Constants
$script:MaxTagsPerResource = 50
$script:MaxTagNameLength = 512
$script:MaxTagValueLength = 256

# always top function
function main() {
    try {
        write-console "Azure Resource Tag Manager v1.0" -foregroundColor Cyan
        write-console "Operation: $Operation | Resource Group: $ResourceGroupName`n" -foregroundColor Gray
        
        if ($Diagnostics) {
            show-diagnostics
            return 0
        }
        
        # Validate prerequisites
        test-prerequisites
        
        # Load environment file if specified
        if ($EnvFile) {
            load-environmentFile
        }
        
        # Import tags from file if specified
        if ($ImportPath) {
            $script:importedTags = import-tagsFromFile
        }
        
        # Validate parameters for operation
        test-operationParameters
        
        # Connect to Azure
        connect-azure
        
        # Execute the requested operation
        switch ($Operation) {
            'Create' { invoke-createTags }
            'Read'   { invoke-readTags }
            'Update' { invoke-updateTags }
            'Delete' { invoke-deleteTags }
            'Merge'  { invoke-mergeTags }
            'Replace' { invoke-replaceTags }
        }
        
        # Export tags if requested
        if ($ExportPath) {
            export-tagsToFile
        }
        
        # Summary
        write-console "`n========================================" -foregroundColor Cyan
        write-console "OPERATION SUMMARY" -foregroundColor Cyan
        write-console "========================================" -foregroundColor Cyan
        write-console "Processed: $script:processedCount" -foregroundColor White
        write-console "Succeeded: $script:successCount" -foregroundColor Green
        write-console "Failed:    $script:failureCount" -foregroundColor $(if($script:failureCount -gt 0){'Red'}else{'White'})
        
        if ($WhatIfPreference) {
            write-console "`n[WhatIf Mode] No changes were made" -foregroundColor Yellow
        }
        
        return 0
    }
    catch {
        write-console "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -foregroundColor Red
        write-verbose "variables:$((get-variable -scope local).value | convertto-json -WarningAction SilentlyContinue -depth 2)"
        return 1
    }
    finally {
        write-console "`nScript completed: $(Get-Date)" -foregroundColor Gray
    }
}

# alphabetical list of functions

function connect-azure() {
    write-console "Checking Azure connection..." -verbose
    
    $context = Get-AzContext -ErrorAction SilentlyContinue
    
    if (-not $context) {
        write-console "No Azure context found. Connecting..." -foregroundColor Yellow
        if ($PSCmdlet.ShouldProcess("Azure", "Connect-AzAccount")) {
            Connect-AzAccount | Out-Null
            $context = Get-AzContext
        }
    }
    
    if ($SubscriptionId) {
        if ($context.Subscription.Id -ne $SubscriptionId) {
            write-console "Switching to subscription: $SubscriptionId" -foregroundColor Yellow
            if ($PSCmdlet.ShouldProcess("Subscription $SubscriptionId", "Set-AzContext")) {
                Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
            }
        }
    }
    
    $context = Get-AzContext
    write-console "Connected to subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -foregroundColor Green
}

function export-tagsToFile() {
    write-console "`nExporting tags to: $ExportPath" -foregroundColor Cyan
    
    if ($PSCmdlet.ShouldProcess($ExportPath, "Export tags")) {
        $exportData = @{
            ExportDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            SubscriptionId = (Get-AzContext).Subscription.Id
            ResourceGroupName = $ResourceGroupName
            ResourceGroupTags = @{}
            Resources = @()
        }
        
        # Get resource group tags
        $rg = Get-AzResourceGroup -Name $ResourceGroupName
        $exportData.ResourceGroupTags = $rg.Tags
        
        # Get all resource tags
        $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
        foreach ($resource in $resources) {
            $exportData.Resources += @{
                ResourceName = $resource.Name
                ResourceType = $resource.ResourceType
                Tags = $resource.Tags
            }
        }
        
        $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $ExportPath -Encoding utf8
        write-console "Tags exported successfully to $ExportPath" -foregroundColor Green
    }
}

function format-tagOutput($tagObject, $resourceInfo = $null) {
    if ($null -eq $tagObject -or $tagObject.Count -eq 0) {
        write-console "  No tags found" -foregroundColor Gray
        return
    }
    
    if ($resourceInfo) {
        write-console "`n  Resource: $($resourceInfo.Name)" -foregroundColor White
        write-console "  Type: $($resourceInfo.ResourceType)" -foregroundColor Gray
    }
    
    $tagObject.GetEnumerator() | Sort-Object Name | ForEach-Object {
        write-console "    $($_.Key) = $($_.Value)" -foregroundColor Cyan
    }
}

function get-resourceId() {
    if ($ResourceName) {
        if (-not $ResourceType) {
            throw "ResourceType is required when ResourceName is specified"
        }
        
        $resource = Get-AzResource -ResourceGroupName $ResourceGroupName `
                                   -ResourceName $ResourceName `
                                   -ResourceType $ResourceType `
                                   -ErrorAction SilentlyContinue
        
        if (-not $resource) {
            throw "Resource '$ResourceName' of type '$ResourceType' not found in resource group '$ResourceGroupName'"
        }
        
        return $resource.ResourceId
    }
    
    return $null
}

function get-resourcesInGroup() {
    write-console "Retrieving resources in resource group: $ResourceGroupName" -verbose
    
    $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
    
    if ($resources.Count -eq 0) {
        write-console "No resources found in resource group" -foregroundColor Yellow
    }
    else {
        write-console "Found $($resources.Count) resource(s)" -foregroundColor Green
    }
    
    return $resources
}

function import-tagsFromFile() {
    write-console "Importing tags from: $ImportPath" -foregroundColor Cyan
    
    if (-not (Test-Path $ImportPath)) {
        throw "Import file not found: $ImportPath"
    }
    
    $importData = Get-Content -Path $ImportPath -Raw | ConvertFrom-Json
    write-console "Tags imported from file (exported on $($importData.ExportDate))" -foregroundColor Green
    
    return $importData
}

function invoke-createTags() {
    write-console "`n=== CREATE TAGS ===" -foregroundColor Cyan
    
    $tagsToApply = if ($ImportPath) { 
        $script:importedTags.ResourceGroupTags 
    } else { 
        resolve-tagVariables -tags $Tags 
    }
    
    if (-not $tagsToApply -or $tagsToApply.Count -eq 0) {
        throw "No tags specified for Create operation"
    }
    
    validate-tags -tags $tagsToApply
    
    if ($ResourceName) {
        # Apply to specific resource
        $resourceId = get-resourceId
        write-console "Creating tags on resource: $ResourceName" -foregroundColor Yellow
        
        $script:processedCount++
        if ($PSCmdlet.ShouldProcess("Resource: $ResourceName", "Create tags: $($tagsToApply.Keys -join ', ')")) {
            $existingTags = (Get-AzResource -ResourceId $resourceId).Tags
            if ($null -eq $existingTags) { $existingTags = @{} }
            
            # Merge new tags with existing
            foreach ($key in $tagsToApply.Keys) {
                $existingTags[$key] = $tagsToApply[$key]
            }
            
            Set-AzResource -ResourceId $resourceId -Tag $existingTags -Force | Out-Null
            $script:successCount++
            write-console "✓ Tags created successfully" -foregroundColor Green
        }
    }
    elseif ($ApplyToAllResources) {
        # Apply to all resources in group
        $resources = get-resourcesInGroup
        
        foreach ($resource in $resources) {
            $script:processedCount++
            write-console "`nProcessing: $($resource.Name)" -foregroundColor White
            
            if ($PSCmdlet.ShouldProcess("Resource: $($resource.Name)", "Create tags: $($tagsToApply.Keys -join ', ')")) {
                try {
                    $existingTags = $resource.Tags
                    if ($null -eq $existingTags) { $existingTags = @{} }
                    
                    foreach ($key in $tagsToApply.Keys) {
                        $existingTags[$key] = $tagsToApply[$key]
                    }
                    
                    Set-AzResource -ResourceId $resource.ResourceId -Tag $existingTags -Force | Out-Null
                    $script:successCount++
                    write-console "  ✓ Success" -foregroundColor Green
                }
                catch {
                    $script:failureCount++
                    write-console "  ✗ Failed: $($_.Exception.Message)" -foregroundColor Red
                }
            }
        }
        
        # Also apply to resource group
        $script:processedCount++
        write-console "`nApplying to resource group: $ResourceGroupName" -foregroundColor White
        if ($PSCmdlet.ShouldProcess("ResourceGroup: $ResourceGroupName", "Create tags")) {
            $rg = Get-AzResourceGroup -Name $ResourceGroupName
            $existingTags = $rg.Tags
            if ($null -eq $existingTags) { $existingTags = @{} }
            
            foreach ($key in $tagsToApply.Keys) {
                $existingTags[$key] = $tagsToApply[$key]
            }
            
            Set-AzResourceGroup -Name $ResourceGroupName -Tag $existingTags | Out-Null
            $script:successCount++
            write-console "  ✓ Success" -foregroundColor Green
        }
    }
    else {
        # Apply to resource group only
        write-console "Creating tags on resource group: $ResourceGroupName" -foregroundColor Yellow
        
        $script:processedCount++
        if ($PSCmdlet.ShouldProcess("ResourceGroup: $ResourceGroupName", "Create tags: $($tagsToApply.Keys -join ', ')")) {
            $rg = Get-AzResourceGroup -Name $ResourceGroupName
            $existingTags = $rg.Tags
            if ($null -eq $existingTags) { $existingTags = @{} }
            
            foreach ($key in $tagsToApply.Keys) {
                $existingTags[$key] = $tagsToApply[$key]
            }
            
            Set-AzResourceGroup -Name $ResourceGroupName -Tag $existingTags | Out-Null
            $script:successCount++
            write-console "✓ Tags created successfully" -foregroundColor Green
        }
    }
}

function invoke-deleteTags() {
    write-console "`n=== DELETE TAGS ===" -foregroundColor Cyan
    
    if (-not $TagName -and -not $Tags) {
        throw "TagName or Tags parameter required for Delete operation"
    }
    
    $tagNamesToDelete = if ($Tags) { $Tags.Keys } else { @($TagName) }
    
    if (-not $Force) {
        $confirmation = Read-Host "WARNING: This will delete tag(s): $($tagNamesToDelete -join ', '). Continue? (y/n)"
        if ($confirmation -ne 'y') {
            write-console "Operation cancelled by user" -foregroundColor Yellow
            return
        }
    }
    
    if ($ResourceName) {
        # Delete from specific resource
        $resourceId = get-resourceId
        write-console "Deleting tags from resource: $ResourceName" -foregroundColor Yellow
        
        $script:processedCount++
        if ($PSCmdlet.ShouldProcess("Resource: $ResourceName", "Delete tags: $($tagNamesToDelete -join ', ')")) {
            $resource = Get-AzResource -ResourceId $resourceId
            $existingTags = $resource.Tags
            
            if ($existingTags) {
                foreach ($tagKey in $tagNamesToDelete) {
                    $existingTags.Remove($tagKey)
                }
                
                Set-AzResource -ResourceId $resourceId -Tag $existingTags -Force | Out-Null
                $script:successCount++
                write-console "✓ Tags deleted successfully" -foregroundColor Green
            }
            else {
                write-console "No tags to delete" -foregroundColor Gray
            }
        }
    }
    elseif ($ApplyToAllResources) {
        # Delete from all resources
        $resources = get-resourcesInGroup
        
        foreach ($resource in $resources) {
            $script:processedCount++
            write-console "`nProcessing: $($resource.Name)" -foregroundColor White
            
            if ($PSCmdlet.ShouldProcess("Resource: $($resource.Name)", "Delete tags: $($tagNamesToDelete -join ', ')")) {
                try {
                    $existingTags = $resource.Tags
                    
                    if ($existingTags) {
                        foreach ($tagKey in $tagNamesToDelete) {
                            $existingTags.Remove($tagKey)
                        }
                        
                        Set-AzResource -ResourceId $resource.ResourceId -Tag $existingTags -Force | Out-Null
                        $script:successCount++
                        write-console "  ✓ Success" -foregroundColor Green
                    }
                    else {
                        write-console "  No tags to delete" -foregroundColor Gray
                    }
                }
                catch {
                    $script:failureCount++
                    write-console "  ✗ Failed: $($_.Exception.Message)" -foregroundColor Red
                }
            }
        }
        
        # Also delete from resource group
        $script:processedCount++
        write-console "`nDeleting from resource group: $ResourceGroupName" -foregroundColor White
        if ($PSCmdlet.ShouldProcess("ResourceGroup: $ResourceGroupName", "Delete tags")) {
            $rg = Get-AzResourceGroup -Name $ResourceGroupName
            $existingTags = $rg.Tags
            
            if ($existingTags) {
                foreach ($tagKey in $tagNamesToDelete) {
                    $existingTags.Remove($tagKey)
                }
                
                Set-AzResourceGroup -Name $ResourceGroupName -Tag $existingTags | Out-Null
                $script:successCount++
                write-console "  ✓ Success" -foregroundColor Green
            }
        }
    }
    else {
        # Delete from resource group only
        write-console "Deleting tags from resource group: $ResourceGroupName" -foregroundColor Yellow
        
        $script:processedCount++
        if ($PSCmdlet.ShouldProcess("ResourceGroup: $ResourceGroupName", "Delete tags: $($tagNamesToDelete -join ', ')")) {
            $rg = Get-AzResourceGroup -Name $ResourceGroupName
            $existingTags = $rg.Tags
            
            if ($existingTags) {
                foreach ($tagKey in $tagNamesToDelete) {
                    $existingTags.Remove($tagKey)
                }
                
                Set-AzResourceGroup -Name $ResourceGroupName -Tag $existingTags | Out-Null
                $script:successCount++
                write-console "✓ Tags deleted successfully" -foregroundColor Green
            }
            else {
                write-console "No tags to delete" -foregroundColor Gray
            }
        }
    }
}

function invoke-mergeTags() {
    write-console "`n=== MERGE TAGS ===" -foregroundColor Cyan
    write-console "Note: Merge combines existing tags with new tags, preserving existing values unless overwritten" -foregroundColor Gray
    
    # Merge is essentially the same as Create (adds to existing)
    invoke-createTags
}

function invoke-readTags() {
    write-console "`n=== READ TAGS ===" -foregroundColor Cyan
    
    if ($ResourceName) {
        # Read from specific resource
        $resourceId = get-resourceId
        $resource = Get-AzResource -ResourceId $resourceId
        
        write-console "`nResource Group: $ResourceGroupName" -foregroundColor Yellow
        format-tagOutput -tagObject $resource.Tags -resourceInfo $resource
        
        $script:processedCount++
        $script:successCount++
    }
    elseif ($ApplyToAllResources) {
        # Read from all resources
        $resources = get-resourcesInGroup
        
        write-console "`nResource Group: $ResourceGroupName" -foregroundColor Yellow
        $rg = Get-AzResourceGroup -Name $ResourceGroupName
        write-console "Resource Group Tags:" -foregroundColor Cyan
        format-tagOutput -tagObject $rg.Tags
        
        write-console "`n--- Individual Resources ---" -foregroundColor Yellow
        foreach ($resource in $resources) {
            format-tagOutput -tagObject $resource.Tags -resourceInfo $resource
            $script:processedCount++
            $script:successCount++
        }
    }
    else {
        # Read from resource group only
        write-console "`nResource Group: $ResourceGroupName" -foregroundColor Yellow
        $rg = Get-AzResourceGroup -Name $ResourceGroupName
        format-tagOutput -tagObject $rg.Tags
        
        $script:processedCount++
        $script:successCount++
    }
}

function invoke-replaceTags() {
    write-console "`n=== REPLACE TAGS ===" -foregroundColor Cyan
    write-console "WARNING: This will remove ALL existing tags and replace with new tags" -foregroundColor Red
    
    if (-not $Tags -and -not $ImportPath) {
        throw "Tags parameter required for Replace operation"
    }
    
    if (-not $Force) {
        $confirmation = Read-Host "This will DELETE all existing tags and replace them. Continue? (y/n)"
        if ($confirmation -ne 'y') {
            write-console "Operation cancelled by user" -foregroundColor Yellow
            return
        }
    }
    
    $tagsToApply = if ($ImportPath) { 
        $script:importedTags.ResourceGroupTags 
    } else { 
        resolve-tagVariables -tags $Tags 
    }
    
    validate-tags -tags $tagsToApply
    
    if ($ResourceName) {
        # Replace on specific resource
        $resourceId = get-resourceId
        write-console "Replacing tags on resource: $ResourceName" -foregroundColor Yellow
        
        $script:processedCount++
        if ($PSCmdlet.ShouldProcess("Resource: $ResourceName", "Replace all tags")) {
            Set-AzResource -ResourceId $resourceId -Tag $tagsToApply -Force | Out-Null
            $script:successCount++
            write-console "✓ Tags replaced successfully" -foregroundColor Green
        }
    }
    elseif ($ApplyToAllResources) {
        # Replace on all resources
        $resources = get-resourcesInGroup
        
        foreach ($resource in $resources) {
            $script:processedCount++
            write-console "`nProcessing: $($resource.Name)" -foregroundColor White
            
            if ($PSCmdlet.ShouldProcess("Resource: $($resource.Name)", "Replace all tags")) {
                try {
                    Set-AzResource -ResourceId $resource.ResourceId -Tag $tagsToApply -Force | Out-Null
                    $script:successCount++
                    write-console "  ✓ Success" -foregroundColor Green
                }
                catch {
                    $script:failureCount++
                    write-console "  ✗ Failed: $($_.Exception.Message)" -foregroundColor Red
                }
            }
        }
        
        # Also replace on resource group
        $script:processedCount++
        write-console "`nReplacing on resource group: $ResourceGroupName" -foregroundColor White
        if ($PSCmdlet.ShouldProcess("ResourceGroup: $ResourceGroupName", "Replace all tags")) {
            Set-AzResourceGroup -Name $ResourceGroupName -Tag $tagsToApply | Out-Null
            $script:successCount++
            write-console "  ✓ Success" -foregroundColor Green
        }
    }
    else {
        # Replace on resource group only
        write-console "Replacing tags on resource group: $ResourceGroupName" -foregroundColor Yellow
        
        $script:processedCount++
        if ($PSCmdlet.ShouldProcess("ResourceGroup: $ResourceGroupName", "Replace all tags")) {
            Set-AzResourceGroup -Name $ResourceGroupName -Tag $tagsToApply | Out-Null
            $script:successCount++
            write-console "✓ Tags replaced successfully" -foregroundColor Green
        }
    }
}

function invoke-updateTags() {
    write-console "`n=== UPDATE TAGS ===" -foregroundColor Cyan
    write-console "Note: Update modifies existing tag values (creates if not exist)" -foregroundColor Gray
    
    # Update is essentially the same as Create/Merge
    invoke-createTags
}

function load-environmentFile() {
    write-console "Loading environment file: $EnvFile" -foregroundColor Cyan
    
    if (-not (Test-Path $EnvFile)) {
        throw "Environment file not found: $EnvFile"
    }
    
    $loadEnvScript = Join-Path $PSScriptRoot "load-envFile.ps1"
    if (-not (Test-Path $loadEnvScript)) {
        throw "load-envFile.ps1 not found in script directory"
    }
    
    & $loadEnvScript -Path $EnvFile
    write-console "Environment variables loaded" -foregroundColor Green
}

function resolve-tagVariables($tags) {
    if (-not $tags) { return $tags }
    
    $resolvedTags = @{}
    
    foreach ($key in $tags.Keys) {
        $value = $tags[$key]
        
        # Replace ${VAR_NAME} with environment variable value
        if ($value -match '\$\{([^}]+)\}') {
            $varName = $matches[1]
            $envValue = [System.Environment]::GetEnvironmentVariable($varName)
            
            if ($envValue) {
                $value = $value -replace '\$\{[^}]+\}', $envValue
                write-console "Resolved variable: $varName" -verbose
            }
            else {
                write-console "Warning: Environment variable '$varName' not found" -foregroundColor Yellow
            }
        }
        
        $resolvedTags[$key] = $value
    }
    
    return $resolvedTags
}

function show-diagnostics() {
    write-console "`n=== DIAGNOSTICS ===" -foregroundColor Cyan
    write-console "PowerShell Version: $($PSVersionTable.PSVersion)" -foregroundColor White
    write-console "OS: $($PSVersionTable.OS)" -foregroundColor White
    write-console "Script Path: $scriptName" -foregroundColor White
    write-console "Current User: $env:USERNAME" -foregroundColor White
    
    write-console "`nAz Module Versions:" -foregroundColor Cyan
    $azModules = Get-Module Az.* -ListAvailable | Select-Object Name, Version -Unique
    $azModules | ForEach-Object { write-console "  $($_.Name): $($_.Version)" -foregroundColor Gray }
    
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if ($context) {
        write-console "`nAzure Context:" -foregroundColor Cyan
        write-console "  Account: $($context.Account.Id)" -foregroundColor White
        write-console "  Subscription: $($context.Subscription.Name)" -foregroundColor White
        write-console "  Tenant: $($context.Tenant.Id)" -foregroundColor White
    }
    else {
        write-console "`nNo Azure context found" -foregroundColor Yellow
    }
    
    write-console "`nParameters:" -foregroundColor Cyan
    write-console "  Operation: $Operation" -foregroundColor White
    write-console "  ResourceGroupName: $ResourceGroupName" -foregroundColor White
    write-console "  ResourceName: $ResourceName" -foregroundColor White
    write-console "  ApplyToAllResources: $ApplyToAllResources" -foregroundColor White
}

function test-operationParameters() {
    write-console "Validating operation parameters..." -verbose
    
    switch ($Operation) {
        'Create' {
            if (-not $Tags -and -not $ImportPath) {
                throw "Tags or ImportPath parameter required for Create operation"
            }
        }
        'Update' {
            if (-not $Tags) {
                throw "Tags parameter required for Update operation"
            }
        }
        'Delete' {
            if (-not $TagName -and -not $Tags) {
                throw "TagName or Tags parameter required for Delete operation"
            }
        }
        'Merge' {
            if (-not $Tags -and -not $ImportPath) {
                throw "Tags or ImportPath parameter required for Merge operation"
            }
        }
        'Replace' {
            if (-not $Tags -and -not $ImportPath) {
                throw "Tags or ImportPath parameter required for Replace operation"
            }
        }
    }
    
    if ($ResourceName -and -not $ResourceType) {
        throw "ResourceType is required when ResourceName is specified"
    }
    
    if ($ResourceName -and $ApplyToAllResources) {
        throw "Cannot specify both ResourceName and ApplyToAllResources"
    }
}

function test-prerequisites() {
    write-console "Checking prerequisites..." -verbose
    
    # Check for required modules
    $requiredModules = @('Az.Accounts', 'Az.Resources')
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "Required module '$module' not found. Install with: Install-Module $module -Scope CurrentUser"
        }
    }
    
    write-console "All prerequisites met" -foregroundColor Green
}

function validate-tags($tags) {
    if ($tags.Count -gt $script:MaxTagsPerResource) {
        throw "Cannot apply more than $script:MaxTagsPerResource tags per resource"
    }
    
    foreach ($key in $tags.Keys) {
        if ($key.Length -gt $script:MaxTagNameLength) {
            throw "Tag name '$key' exceeds maximum length of $script:MaxTagNameLength characters"
        }
        
        $value = $tags[$key]
        if ($value.Length -gt $script:MaxTagValueLength) {
            throw "Tag value for '$key' exceeds maximum length of $script:MaxTagValueLength characters"
        }
        
        # Azure tag name restrictions
        if ($key -match '[<>%&\\?/]') {
            throw "Tag name '$key' contains invalid characters. Cannot use: < > % & \ ? /"
        }
    }
    
    write-console "Tag validation passed" -verbose
}

function write-console($message, [consoleColor]$foregroundColor = 'White', [switch]$verbose, [switch]$err, [switch]$warn) {
    if (!$message) { return }
    if ($message.gettype().name -ine 'string') {
        $message = $message | convertto-json -Depth 10
    }

    if ($verbose) {
        write-verbose($message)
    }
    else {
        write-host($message) -ForegroundColor $foregroundColor
    }

    if ($warn) {
        write-warning($message)
    }
    elseif ($err) {
        write-error($message)
        throw
    }
}

main
