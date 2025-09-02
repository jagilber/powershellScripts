# Instructions Directory Overview

This directory contains AI agent instructions organized according to the P1 workspace structure standard.

## Directory Structure

### `.instructions/local/`
**Workspace-specific instructions** that apply only to this PowerShell scripts repository:
- `project-mcp-integration.md` - MCP server integration workflows and tool usage
- `instruction-hierarchy.md` - Local instruction authority and conflict resolution
- `dev-workflows.md` - Development and testing procedures specific to this project

### `.instructions/shared/`
**Content candidates for MCP Index Server promotion** - valuable patterns that could benefit other workspaces:
- `powershell-best-practices.md` - PowerShell coding standards and conventions
- `script-structure-patterns.md` - Reusable script templates and patterns
- `azure-automation-patterns.md` - Common Azure automation approaches

## Content Lifecycle

1. **Local Development**: Create instructions in `local/` directory
2. **Testing**: Validate effectiveness with AI agents in workspace context
3. **Evaluation**: Assess content for broader organizational value
4. **Promotion**: Move valuable content to `shared/` and promote to MCP Index Server

## Integration with Primary Agent Instructions

The primary agent instruction file (`.github/copilot-instructions.md`) references content in this directory and provides the main project context for all AI agents.

## Maintenance

- **Monthly Review**: Assess instruction effectiveness and identify promotion candidates
- **Content Updates**: Keep instructions current with project evolution
- **Agent Feedback**: Incorporate learnings from AI agent interactions

This structure optimizes AI agent effectiveness while enabling knowledge sharing across the organization.
