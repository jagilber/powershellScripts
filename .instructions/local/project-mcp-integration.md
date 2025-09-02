# Project MCP Integration Workflows

## MCP Server Integration Overview

This PowerShell scripts repository integrates with MCP (Model Context Protocol) servers to provide structured execution, safety validation, and operational auditing for PowerShell scripts.

## Priority: CRITICAL

**Always prefer executing PowerShell operations via MCP Server tools** instead of raw terminal commands when available.

## Preferred Tool Chain

1. **powershell-syntax-check** – Validate content (inline or file) before execution
2. **powershell-script / powershell-file** – Perform the actual work with structured logging
3. **powershell-command** – Single safe read-only commands
4. **threat-analysis** – Observe cumulative risk posture and security implications
5. **ai-agent-test** – Regression and environment validation after adding tools or security rules

## Fallback Policy

Use integrated terminal (pwsh) only when:
- Required capability not yet exposed as MCP tool
- Interactive authentication flow blocks automation
- Experimental binary/CLI not covered by existing tools

**After fallback usage**: Propose or implement a new MCP tool wrapper so future runs are structured and auditable.

## Security Classification Framework

### SAFE Operations
- **Read-only commands**: `Get-*`, `Select-*`, `Format-*`, `Show-*`
- **Information gathering**: System queries, configuration reads
- **Safe analysis**: Content parsing, data transformation

### RISKY Operations (Require Confirmation)
- **File system mutations**: `Remove-Item`, `Move-Item`, file modifications
- **Process management**: `Stop-Process`, service control
- **Network operations**: Downloads, remote connections
- **Registry modifications**: Non-critical registry changes

### BLOCKED Operations (DANGEROUS/CRITICAL)
- **System shutdown/restart**: `Restart-Computer`, `Stop-Computer`
- **Encoded/obfuscated content**: Base64 scripts, compressed payloads
- **System file mutations**: Windows system directories, critical files
- **Remote system modifications**: Changes to remote machines
- **Suspicious patterns**: Download-and-execute, privilege escalation

## Command Submission Guidelines

### Best Practices
- **Minimal commands**: Avoid chaining destructive operations with unrelated reads
- **Logical grouping**: Use single `powershell-script` invocation for related steps
- **Syntax validation**: Always syntax-check new or edited scripts before first run
- **Clear intent**: Provide context and rationale for operations

### Error Handling Pattern

1. **BLOCKED** → Explain to user; do not re-issue without code change
2. **RISKY missing confirmation** → Re-run with `confirmed:true` only after justification
3. **Timeout** → Refactor or increase timeout (bounded); consider streaming enhancement
4. **Execution errors** → Analyze, provide remediation suggestions

## Integration with Repository Workflows

### Script Development
1. Create/edit script using standard editor
2. Validate syntax using `powershell-syntax-check`
3. Test execution using `powershell-file` with appropriate risk level
4. Iterate based on results and security feedback

### Production Execution
1. Review script purpose and risk level
2. Use MCP tools for structured execution
3. Monitor security classifications and confirmations
4. Capture results for auditing and future reference

### Safety Enhancements
- **Pre-execution validation**: Syntax and security analysis
- **Structured logging**: All operations logged through MCP layer
- **Risk assessment**: Automatic threat analysis for complex operations
- **Audit trail**: Complete execution history for compliance

## Tool-Specific Usage

### powershell-syntax-check
```json
{
  "content": "Get-Process | Where-Object CPU -gt 100",
  "type": "inline"
}
```

### powershell-script
```json
{
  "script": "param($Path) Get-ChildItem $Path | Sort-Object Length -Descending",
  "parameters": {"Path": "C:\\Scripts"},
  "confirmed": true
}
```

### powershell-file
```json
{
  "filePath": "C:\\Scripts\\azure-az-vm-manager.ps1",
  "parameters": {"-resourceGroup": "demo-rg", "-whatIf": true},
  "confirmed": false
}
```

This MCP integration provides a safety layer while maintaining the core principle that scripts should be executable directly when needed.
