# Deployment Assistance Prompt Template

Use this template when requesting AI assistance for Azure deployments and automation.

## Deployment Request

**Deployment Type**: [ARM Template/Bicep/PowerShell Script/Manual]

**Target Environment**: [Development/Staging/Production]

**Azure Resources Involved**:
- [ ] Virtual Machines
- [ ] Storage Accounts  
- [ ] Network Components
- [ ] Databases
- [ ] App Services
- [ ] Key Vault
- [ ] Other: [specify]

**Deployment Context**:
```powershell
# Paste relevant deployment code or template here
```

## Assistance Needed

**Primary Request**: [What specific help do you need?]

**Areas of Focus**:
- [ ] Deployment script creation/review
- [ ] Error troubleshooting and resolution
- [ ] Security and compliance validation
- [ ] Performance optimization
- [ ] Cost optimization
- [ ] Automation and CI/CD integration
- [ ] Documentation and procedures

## Environment Details

**Subscription Information**:
- **Subscription ID**: [Provide if relevant/safe]
- **Resource Group**: [Target resource group name]
- **Region**: [Azure region]
- **Naming Convention**: [Describe your naming standards]

**Authentication Method**:
- [ ] Interactive (development)
- [ ] Service Principal
- [ ] Managed Identity
- [ ] Certificate-based
- [ ] Other: [specify]

**Dependencies**:
- **Required Modules**: [List PowerShell modules needed]
- **External Resources**: [Dependencies on existing resources]
- **Network Requirements**: [VNet, subnet, NSG requirements]

## Security Requirements

**Compliance Needs**:
- [ ] Company security policies
- [ ] Industry regulations (HIPAA, SOX, etc.)
- [ ] Data residency requirements
- [ ] Encryption requirements
- [ ] Network isolation needs

**Access Control**:
- [ ] RBAC configuration needed
- [ ] Key Vault integration
- [ ] Certificate management
- [ ] Secrets handling

## Expected Deliverables

Please provide:

1. **Deployment Solution**: Working PowerShell script or template
2. **Error Handling**: Robust error checking and recovery
3. **Validation Steps**: Pre and post-deployment validation
4. **Documentation**: Comments and usage instructions
5. **Security Review**: Security considerations and recommendations
6. **Testing Guidance**: How to validate the deployment

## Constraints and Considerations

**Technical Constraints**:
- **Budget Limits**: [Any cost constraints]
- **Performance Requirements**: [SLA or performance needs]
- **Compliance Requirements**: [Regulatory or policy constraints]
- **Timeline**: [Deployment deadline if applicable]

**Operational Constraints**:
- **Maintenance Windows**: [When deployments can occur]
- **Rollback Requirements**: [Rollback strategy needs]
- **Monitoring Needs**: [Post-deployment monitoring requirements]

## Example Usage

```
**Deployment Type**: PowerShell Script

**Target Environment**: Production

**Azure Resources Involved**:
- [x] Virtual Machines (2 web servers)
- [x] Storage Accounts (diagnostics)
- [x] Network Components (Load balancer, NSG)

**Deployment Context**:
```powershell
# Need to deploy a web application with load balancing
# Current manual process takes 4 hours
# Want to automate the entire deployment
```

**Primary Request**: Create automated deployment script for web application infrastructure

**Areas of Focus**:
- [x] Deployment script creation/review
- [x] Security and compliance validation
- [x] Automation and CI/CD integration
```
