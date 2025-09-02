# Troubleshooting Assistance Prompt Template

Use this template when requesting AI assistance for PowerShell script or Azure resource troubleshooting.

## Troubleshooting Request

**Issue Type**: [Script Error/Azure Resource Issue/Performance Problem/Configuration Issue]

**Priority Level**: [Low/Medium/High/Critical]

**Brief Problem Description**: [One-line summary of the issue]

## Problem Details

**What You're Trying to Accomplish**:
[Describe the intended goal or task]

**What's Actually Happening**:
[Describe the current behavior or error]

**Error Messages** (if any):
```
[Paste exact error messages here, including error codes]
```

**Relevant Code/Configuration**:
```powershell
# Paste the relevant PowerShell code or configuration
```

## Environment Information

**System Details**:
- **Operating System**: [Windows 10/11, Server 2019/2022, Linux, macOS]
- **PowerShell Version**: [Use `$PSVersionTable.PSVersion`]
- **Execution Policy**: [Use `Get-ExecutionPolicy`]
- **PowerShell Edition**: [Desktop/Core]

**Azure Context** (if applicable):
- **Subscription**: [Subscription name or ID if relevant]
- **Resource Group**: [Target resource group]
- **Region**: [Azure region]
- **Authentication Method**: [How you're authenticating to Azure]

**Modules and Dependencies**:
- **Installed Modules**: [List relevant PowerShell modules and versions]
- **Required Permissions**: [What permissions the script/operation needs]
- **External Dependencies**: [APIs, services, files the script depends on]

## Reproduction Steps

**Steps to Reproduce**:
1. [First step]
2. [Second step]
3. [Continue with exact steps]

**Expected Result**: [What should happen]

**Actual Result**: [What actually happens]

**Frequency**: [Always/Sometimes/Rarely occurs]

## Troubleshooting Already Attempted

**What You've Already Tried**:
- [ ] Verified PowerShell syntax
- [ ] Checked module versions and dependencies
- [ ] Reviewed Azure permissions and RBAC
- [ ] Tested with different parameters/inputs
- [ ] Checked network connectivity
- [ ] Reviewed Azure resource status
- [ ] Examined logs (specify which logs)
- [ ] Other: [describe other attempts]

**Results of Previous Attempts**:
[Describe what happened when you tried the above]

## Additional Context

**Recent Changes**:
- [ ] No recent changes
- [ ] Updated PowerShell modules
- [ ] Changed Azure subscriptions/tenants
- [ ] Modified scripts or configurations
- [ ] System updates or patches
- [ ] Network or firewall changes
- [ ] Other: [describe changes]

**Working Previously**: 
- [ ] Yes, this worked before
- [ ] No, this is new functionality
- [ ] Unknown

**Urgency and Impact**:
- **Business Impact**: [How this affects operations]
- **Deadline**: [Any time constraints]
- **Workaround Available**: [Any temporary solutions in use]

## Requested Assistance

**Specific Help Needed**:
- [ ] Error diagnosis and resolution
- [ ] Code review and improvement suggestions
- [ ] Alternative approaches or solutions
- [ ] Performance optimization
- [ ] Best practices guidance
- [ ] Documentation or learning resources

**Preferred Solution Type**:
- [ ] Quick fix for immediate resolution
- [ ] Comprehensive solution with explanation
- [ ] Multiple options to choose from
- [ ] Long-term architectural guidance

## Expected Output

Please provide:
1. **Root Cause Analysis**: What's causing the issue
2. **Solution Steps**: Clear steps to resolve the problem
3. **Code Examples**: Working code if applicable
4. **Prevention Tips**: How to avoid this issue in the future
5. **Additional Resources**: Links or documentation for further learning

## Example Usage

```
**Issue Type**: Script Error

**Priority Level**: High

**Brief Problem Description**: Azure VM deployment script fails with authentication error

**What You're Trying to Accomplish**:
Deploy a Windows VM using PowerShell script for development environment

**What's Actually Happening**:
Script fails during Connect-AzAccount with "AADSTS50076: Due to a configuration change"

**Error Messages**:
```
Connect-AzAccount: AADSTS50076: Due to a configuration change made by your administrator, 
or because you moved to a new location, you must use multi-factor authentication to access
```

**Environment Details**:
- **Operating System**: Windows 11
- **PowerShell Version**: 7.3.0
- **Execution Policy**: RemoteSigned
- **PowerShell Edition**: Core

**Troubleshooting Already Attempted**:
- [x] Verified PowerShell syntax
- [x] Checked module versions and dependencies  
- [x] Reviewed Azure permissions and RBAC
- [ ] Tested with different authentication methods
```
