# Development Workflows

## PowerShell Script Development Process

This document outlines the development, testing, and maintenance workflows specific to this PowerShell scripts repository.

## Script Development Lifecycle

### 1. Planning and Design

**Before creating a new script:**

- **Identify the purpose** - Clear problem statement and use case
- **Check for existing solutions** - Review current scripts to avoid duplication
- **Plan parameters** - Define inputs, outputs, and error conditions
- **Consider safety** - Plan for test modes, validation, and error handling

### 2. Script Creation

**Follow the established template pattern:**

```powershell
<#
.SYNOPSIS
    Brief description of what the script does.

.DESCRIPTION
    Detailed description including use cases and behavior.

.PARAMETER ParameterName
    Description of each parameter.

.EXAMPLE
    ScriptName.ps1 -Parameter "Value"
    
    Description of what this example accomplishes.

.NOTES
    Author: [Author Name]
    Version: 1.0
    Date: [Date]
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RequiredParameter,
    
    [Parameter()]
    [switch]$TestMode
)

# Functions defined at top
function Get-Something {
    # Implementation
}

# Main execution logic
try {
    # Script logic here
} catch {
    Write-Error "Operation failed: $($_.Exception.Message)"
    exit 1
}
```

**Naming convention:** `area-action-target.ps1`

- `area` - Domain (azure, file, network, etc.)
- `action` - Operation (get, set, create, deploy, etc.)
- `target` - Object (vm, storage, certificate, etc.)

### 3. Development Testing

**Local validation process:**

1. **Syntax validation** - Use MCP `powershell-syntax-check` or PowerShell ISE/VS Code
2. **Parameter testing** - Test with various input combinations
3. **Error condition testing** - Verify error handling with invalid inputs
4. **Test mode execution** - Use `-WhatIf`, `-Test`, or custom test parameters
5. **Real execution** - Careful testing with actual operations

**Testing checklist:**

- [ ] Script executes without syntax errors
- [ ] All parameters work as expected
- [ ] Help documentation is complete and accurate
- [ ] Error handling works for common failure scenarios
- [ ] Test mode prevents actual changes when enabled
- [ ] Output is appropriate for pipeline or direct use

### 4. Documentation Standards

**Required documentation elements:**

- **Synopsis** - One-line description of purpose
- **Description** - Detailed explanation including use cases
- **Parameters** - Complete description of each parameter
- **Examples** - At least one practical example
- **Notes** - Author, version, important considerations

**Additional documentation:**

- **README updates** - Add script to appropriate category table
- **Dependencies** - Document required modules or prerequisites
- **Compatibility** - Note PowerShell version or platform requirements

## Code Quality Standards

### PowerShell Best Practices

**Follow these patterns:**

- **Use approved verbs** - `Get-`, `Set-`, `New-`, `Remove-`, etc.
- **Parameter validation** - Use `[Parameter()]` attributes appropriately
- **Error handling** - Implement try/catch blocks for operations that can fail
- **Output consistency** - Use `Write-Output` for objects, `Write-Host` for user messages
- **Variable naming** - Use descriptive names, avoid abbreviations

**Avoid these patterns:**

- **Global variables** - Minimize global state
- **Hard-coded paths** - Use parameters or discoverable defaults
- **Embedded credentials** - Use secure input or environment variables
- **Silent failures** - Always provide feedback on operations

### Security Considerations

**For scripts that make changes:**

- **Confirmation prompts** - For destructive operations
- **Input validation** - Sanitize and validate all user inputs
- **Least privilege** - Don't require more permissions than necessary
- **Audit logging** - Log important operations for compliance

## Testing and Validation

### Manual Testing Process

1. **Syntax check** using VS Code or MCP tools
2. **Parameter validation** with edge cases
3. **Test mode execution** to verify logic without side effects
4. **Small-scale testing** with limited scope
5. **Full execution** in controlled environment

### Automated Validation

**Use PSScriptAnalyzer when available:**

```powershell
# Install if not available
Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck

# Analyze script
Invoke-ScriptAnalyzer -Path .\script-name.ps1
```

**Common issues to check:**

- Parameter validation attributes
- Help documentation completeness
- Error handling patterns
- Security best practices

## Repository Maintenance

### Regular Reviews

**Monthly maintenance tasks:**

- **Update script documentation** - Keep examples and descriptions current
- **Review and update categories** - Maintain README organization
- **Check for deprecated patterns** - Update to current PowerShell practices
- **Test critical scripts** - Verify functionality with current modules

### Version Management

**Version tracking approach:**

- **Git commits** - Primary version history
- **Script headers** - Version notes in `.NOTES` section
- **Change documentation** - Significant changes noted in commit messages

### Dependency Management

**Module dependencies:**

- **Document requirements** - List required modules in script headers
- **Version compatibility** - Note minimum versions where relevant
- **Installation guidance** - Provide installation commands in examples

## Integration with MCP Tools

### Development Workflow with MCP

1. **Create/edit script** in preferred editor
2. **Validate syntax** using `powershell-syntax-check`
3. **Test execution** using `powershell-file` with test parameters
4. **Security analysis** via threat analysis tools
5. **Production execution** with appropriate confirmations

### Safety and Auditing

**Benefits of MCP integration:**

- **Structured logging** - All operations tracked
- **Risk assessment** - Automatic threat analysis
- **Controlled execution** - Confirmation requirements for risky operations
- **Audit trail** - Complete history of script executions

This workflow ensures consistent quality while maintaining the repository's core principle of practical, ready-to-run PowerShell scripts.
