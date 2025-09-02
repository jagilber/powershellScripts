# PowerShell Scripts Repository - AI Agent Instructions

## Project Context
- **Type**: PowerShell utility script collection
- **Tech Stack**: PowerShell Core/5.1, Azure PowerShell (Az module), .NET utilities
- **Environment**: Cross-platform (Windows primary, Linux/macOS compatible where applicable)
- **Domain**: Azure operations, diagnostics, automation, system administration

## Project Philosophy
The focus is on **ready-to-run PowerShell scripts** with practical troubleshooting and automation value. Supporting tooling (like MCP execution layers) exists to enhance development and safety, but scripts themselves are the core deliverable.

## Code Preferences

### PowerShell Standards
- **Help Documentation**: Include comment-based help with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`
- **Parameter Validation**: Use `[Parameter()]` attributes with `Mandatory`, `Position`, validation sets
- **Error Handling**: Implement proper try/catch blocks, use `$ErrorActionPreference` appropriately
- **Output**: Prefer `Write-Output` for pipeline objects, `Write-Host` for user feedback
- **Idempotency**: Design scripts to be safe for re-execution where feasible

### Naming Conventions
- **Scripts**: `area-action-target.ps1` pattern (e.g., `azure-az-vm-manager.ps1`)
- **Functions**: Use approved PowerShell verbs (`Get-`, `Set-`, `New-`, `Remove-`, etc.)
- **Variables**: Use descriptive names, avoid abbreviations, use camelCase
- **Parameters**: Clear, descriptive names matching script purpose

### Architecture Patterns
- **Native Modules First**: Prefer Az module, built-in PowerShell over niche dependencies
- **Portability**: Consider cross-platform compatibility where applicable
- **Readability**: Optimize for clarity first, micro-optimizations only when needed
- **Minimal Global State**: Define functions at top, execute via main flow

## Project-Specific Guidelines

### Script Structure Template
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

### Safety and Testing
- **Test Parameters**: Include `-WhatIf`, `-Test`, or `-DryRun` where appropriate
- **Validation**: Validate inputs before executing destructive operations
- **Logging**: Capture important operations and results
- **Confirmation**: Require confirmation for risky operations

### MCP Integration (Optional Safety Layer)
When MCP tools are available, prefer structured execution:
1. **Syntax Check**: Use `powershell-syntax-check` before execution
2. **Controlled Execution**: Use `powershell-script` or `powershell-file` tools
3. **Risk Assessment**: Leverage threat analysis for security validation
4. **Direct Execution**: Use terminal only when MCP tools don't cover the capability

## Local Instruction References

### Workspace-Specific Context
- **MCP Integration**: See `.instructions/local/project-mcp-integration.md`
- **Instruction Authority**: See `.instructions/local/instruction-hierarchy.md`
- **Development Workflows**: Standard PowerShell development practices
- **Testing Strategy**: Manual testing with `-WhatIf` parameters, PSScriptAnalyzer

### Repository Authority
This repository maintains **instruction authority** - local instructions take precedence over external MCP Index Server instructions. See `.instructions/local/instruction-hierarchy.md` for complete hierarchy.

## Success Indicators
- Scripts execute successfully with clear parameter validation
- Help documentation is complete and accurate
- Code follows PowerShell best practices and conventions
- MCP integration provides safety without compromising script functionality
- Scripts are portable and reusable across environments

## Common Tasks
- **New Script Creation**: Follow naming convention and structure template
- **Script Enhancement**: Add proper help documentation and parameter validation
- **Testing**: Use built-in `-WhatIf` or create test modes
- **Azure Operations**: Leverage Az module consistently, handle authentication properly
- **Diagnostics**: Include verbose output and error handling for troubleshooting
