# Code Review Prompt Template

Use this template when requesting AI assistance for PowerShell code reviews.

## Code Review Request

**Script/Function Name**: [Name of the script or function]

**Purpose**: [Brief description of what the code is supposed to do]

**Code to Review**:
```powershell
[Paste your PowerShell code here]
```

**Specific Areas of Concern**:
- [ ] Parameter validation and error handling
- [ ] Performance optimization
- [ ] Security considerations
- [ ] PowerShell best practices compliance
- [ ] Cross-platform compatibility
- [ ] Documentation completeness
- [ ] Other: [specify]

**Context**:
- **Environment**: [Windows/Linux/macOS/All]
- **PowerShell Version**: [5.1/7.x/Any]
- **Dependencies**: [List required modules]
- **Execution Context**: [Interactive/Automation/Service]

## Review Checklist

Please review the code against these criteria:

### Functionality
- [ ] Code achieves its stated purpose
- [ ] Logic flow is correct and efficient
- [ ] Edge cases are handled appropriately
- [ ] Output is appropriate for intended use

### PowerShell Standards
- [ ] Uses approved PowerShell verbs
- [ ] Follows proper parameter design patterns
- [ ] Implements appropriate error handling
- [ ] Uses correct output methods (Write-Output vs Write-Host)
- [ ] Includes proper help documentation

### Security
- [ ] Input validation is implemented
- [ ] No hard-coded credentials or sensitive data
- [ ] Appropriate permission requirements
- [ ] Safe handling of external resources

### Performance
- [ ] Efficient collection handling
- [ ] Appropriate use of pipeline processing
- [ ] Memory usage considerations
- [ ] Resource cleanup where needed

### Maintainability
- [ ] Code is readable and well-structured
- [ ] Functions are appropriately sized
- [ ] Variables have descriptive names
- [ ] Comments explain complex logic

## Expected Output

Please provide:
1. **Overall Assessment**: Brief summary of code quality
2. **Issues Found**: List of problems with severity levels
3. **Recommendations**: Specific improvements with code examples
4. **Best Practice Suggestions**: General improvements for maintainability
5. **Security Considerations**: Any security-related recommendations

## Example Usage

```
**Script/Function Name**: Get-SystemHealth.ps1

**Purpose**: Collect system health metrics including CPU, memory, and disk usage

**Code to Review**:
```powershell
function Get-SystemHealth {
    $cpu = Get-Counter "\Processor(_Total)\% Processor Time"
    $memory = Get-CimInstance Win32_OperatingSystem
    return "CPU: $($cpu.CounterSamples.CookedValue)%, Memory: $($memory.FreePhysicalMemory)"
}
```

**Specific Areas of Concern**:
- [x] Parameter validation and error handling
- [x] Performance optimization
- [x] Cross-platform compatibility

**Context**:
- **Environment**: All
- **PowerShell Version**: 7.x
- **Dependencies**: None
- **Execution Context**: Interactive and Automation
```
