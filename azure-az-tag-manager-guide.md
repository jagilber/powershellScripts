# Azure Tag Manager - Quick Reference Guide

## Overview
`azure-az-tag-manager.ps1` provides complete CRUD operations for Azure resource tags with support for individual resources, resource groups, and bulk operations.

## Operations

### Create
Add new tags without removing existing ones (merge behavior)
```powershell
.\azure-az-tag-manager.ps1 -Operation Create -ResourceGroupName 'myRG' -Tags @{Environment='Production'}
```

### Read
Display current tags
```powershell
.\azure-az-tag-manager.ps1 -Operation Read -ResourceGroupName 'myRG'
```

### Update
Modify existing tag values (same as Create - idempotent)
```powershell
.\azure-az-tag-manager.ps1 -Operation Update -ResourceGroupName 'myRG' -Tags @{Owner='NewOwner'}
```

### Delete
Remove specific tags
```powershell
.\azure-az-tag-manager.ps1 -Operation Delete -ResourceGroupName 'myRG' -TagName 'TempTag' -Force
```

### Merge
Explicitly merge tags (same as Create)
```powershell
.\azure-az-tag-manager.ps1 -Operation Merge -ResourceGroupName 'myRG' -Tags @{NewTag='Value'}
```

### Replace
Remove ALL existing tags and apply new set (destructive)
```powershell
.\azure-az-tag-manager.ps1 -Operation Replace -ResourceGroupName 'myRG' -Tags @{OnlyTag='Value'} -Force
```

## Common Scenarios

### Tag a Specific Resource
```powershell
.\azure-az-tag-manager.ps1 -Operation Create `
    -ResourceGroupName 'myRG' `
    -ResourceName 'myVM' `
    -ResourceType 'Microsoft.Compute/virtualMachines' `
    -Tags @{Owner='TeamA'; CostCenter='123'}
```

### Tag All Resources in Resource Group
```powershell
.\azure-az-tag-manager.ps1 -Operation Create `
    -ResourceGroupName 'myRG' `
    -Tags @{Project='Alpha'; Environment='Prod'} `
    -ApplyToAllResources
```

### Preview Changes (WhatIf)
```powershell
.\azure-az-tag-manager.ps1 -Operation Delete `
    -ResourceGroupName 'myRG' `
    -TagName 'OldTag' `
    -ApplyToAllResources `
    -WhatIf
```

### Export Tags to File
```powershell
.\azure-az-tag-manager.ps1 -Operation Read `
    -ResourceGroupName 'myRG' `
    -ExportPath '.\backup-tags.json'
```

### Import Tags from File
```powershell
.\azure-az-tag-manager.ps1 -Operation Create `
    -ResourceGroupName 'myRG' `
    -ImportPath '.\backup-tags.json' `
    -ApplyToAllResources
```

### Use Environment Variables
1. Create .env file:
```
OWNER_EMAIL=john@company.com
COST_CENTER=IT-12345
```

2. Apply tags with variable substitution:
```powershell
.\azure-az-tag-manager.ps1 -Operation Create `
    -ResourceGroupName 'myRG' `
    -EnvFile '.\.env.tags' `
    -Tags @{Owner='${OWNER_EMAIL}'; CostCenter='${COST_CENTER}'}
```

## Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| Operation | Create, Read, Update, Delete, Merge, Replace | Yes | - |
| ResourceGroupName | Target resource group | Yes | - |
| ResourceName | Specific resource name | No | - |
| ResourceType | Resource type (required if ResourceName set) | No | - |
| Tags | Hashtable of tags to apply | No* | - |
| TagName | Single tag name for Read/Delete | No | - |
| ApplyToAllResources | Apply to all resources in group | No | false |
| EnvFile | Path to .env file | No | - |
| Force | Skip confirmations | No | false |
| SubscriptionId | Azure subscription ID | No | Current |
| ExportPath | Export tags to JSON | No | - |
| ImportPath | Import tags from JSON | No | - |
| WhatIf | Preview changes | No | false |
| Diagnostics | Show environment info | No | false |

*Required for Create, Update, Merge, Replace unless using ImportPath

## Tag Constraints

- Maximum 50 tags per resource
- Tag name max length: 512 characters
- Tag value max length: 256 characters
- Invalid characters in names: `< > % & \ ? /`

## Safety Features

1. **WhatIf Support**: Preview all changes before applying
2. **Confirmation Prompts**: Destructive operations require confirmation (unless -Force)
3. **Idempotent**: Safe to run multiple times
4. **Error Aggregation**: Continues processing on individual failures
5. **Secret Masking**: Sensitive env vars masked in output

## Testing

Run the test harness to validate functionality:
```powershell
.\azure-az-tag-manager.tests.ps1 -TestResourceGroupName 'myTestRG'
```

Cleanup test tags only:
```powershell
.\azure-az-tag-manager.tests.ps1 -TestResourceGroupName 'myTestRG' -CleanupOnly
```

## Troubleshooting

### View Diagnostics
```powershell
.\azure-az-tag-manager.ps1 -Operation Read -ResourceGroupName 'myRG' -Diagnostics
```

### Enable Verbose Output
```powershell
.\azure-az-tag-manager.ps1 -Operation Create -ResourceGroupName 'myRG' -Tags @{Test='Value'} -Verbose
```

### Common Issues

**"ResourceType required"**: When specifying ResourceName, must also specify ResourceType
```powershell
# Wrong
-ResourceName 'myVM'

# Correct
-ResourceName 'myVM' -ResourceType 'Microsoft.Compute/virtualMachines'
```

**"Cannot specify both ResourceName and ApplyToAllResources"**: These are mutually exclusive
```powershell
# Use either:
-ResourceName 'myVM' -ResourceType '...'
# Or:
-ApplyToAllResources
```

## Best Practices

1. **Always use -WhatIf first** for destructive operations (Delete, Replace)
2. **Backup tags** before bulk operations: Use -ExportPath
3. **Use consistent naming**: Standardize tag names across organization
4. **Leverage environment files**: Store common tag values in .env files
5. **Test in dev first**: Use test harness to validate changes
6. **Use -Force in automation**: Skip prompts for CI/CD pipelines

## Examples

### Daily Operations
```powershell
# Add owner tag to all resources
.\azure-az-tag-manager.ps1 -Operation Create -ResourceGroupName 'prod-rg' `
    -Tags @{Owner='ops-team@company.com'} -ApplyToAllResources

# Read all tags for compliance audit
.\azure-az-tag-manager.ps1 -Operation Read -ResourceGroupName 'prod-rg' `
    -ExportPath '.\audit-tags.json'

# Remove temporary tags after testing
.\azure-az-tag-manager.ps1 -Operation Delete -ResourceGroupName 'dev-rg' `
    -Tags @{Temporary=''; TestRun=''} -ApplyToAllResources -Force
```

### Governance & Compliance
```powershell
# Apply required governance tags
.\azure-az-tag-manager.ps1 -Operation Create -ResourceGroupName 'new-rg' `
    -Tags @{
        CostCenter='IT-12345'
        Environment='Production'
        DataClassification='Internal'
        Compliance='SOC2'
        Owner='platform-team@company.com'
    } -ApplyToAllResources

# Standardize environment tags across all resources
.\azure-az-tag-manager.ps1 -Operation Update -ResourceGroupName 'app-rg' `
    -Tags @{Environment='Production'} -ApplyToAllResources -WhatIf
```

### Cost Management
```powershell
# Tag resources by project for cost allocation
.\azure-az-tag-manager.ps1 -Operation Merge -ResourceGroupName 'shared-rg' `
    -ResourceName 'sql-server-01' `
    -ResourceType 'Microsoft.Sql/servers' `
    -Tags @{Project='ProjectAlpha'; BillingCode='PROJ-001'}
```

## See Also

- Azure Tags Documentation: https://docs.microsoft.com/azure/azure-resource-manager/management/tag-resources
- load-envFile.ps1: Environment variable loader
- template.ps1: Script template used as basis
