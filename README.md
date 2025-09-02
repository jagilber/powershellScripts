# PowerShell Utility Scripts

Collection of reusable PowerShell scripts for AzAn MCP-based execution environment can provide classification, confirmation for risky operations, and auditing. It is **supporting infrastructure**, not the project's focus. Use it when you want structured execution; otherwise invoke scripts directly. Full details live in `.instructions/local/project-mcp-integration.md`.re operations, diagnostics, performance tracing, file and directory management, RDS administration, networking tests, automation utilities, and assorted developer/system tasks.

The focus of the project is the scripts themselves: clear parameterization, portability, and practical troubleshooting / automation value. Supporting tooling (like an MCP-based execution layer) exists only to make development, testing, and safe reuse easier—it is not the core deliverable.

---

## Goals

* Provide ready-to-run scripts with minimal prerequisites.
* Encourage consistent help metadata (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`).
* Keep scripts idempotent where feasible (safe to re-run).
* Favor native modules (Az, built-in PowerShell) over niche dependencies.
* Optimize for readability first; micro‑optimizations only when needed.

---

## Quick Start

1. Clone repo.
2. Review a script header (`Get-Content .\script.ps1 -TotalCount 40`).
3. Provide required parameters. Example:

   ```powershell
   pwsh ./azure-az-deploy-template.ps1 -resourceGroup demo-rg -templateFile main.json -templateParameterFile main.parameters.json -adminPassword 'P@ssw0rd!123'
   ```
4. Use `-WhatIf` / test flags where available (e.g., `-test`, `-clean`).
5. Log outputs or capture objects for further analysis (e.g., `| Tee-Object`).

Optional safety layer: If you have the companion MCP tools configured, you can run syntax validation and controlled execution there, but this is ancillary—see `.instructions/local/project-mcp-integration.md`.

---

## Script Structure Conventions

Each script strives (work in progress) to include:

* Comment-based help block with synopsis & parameters.
* Parameter attributes for validation / mandatory values where appropriate.
* Clear examples (copy/paste friendly).
* Minimal global state; functions defined at top then executed via a `main` or inline flow.
* Consistent logging using `Write-Host`, `Write-Verbose`, or custom wrappers.

When adding new scripts, please mirror this pattern for consistency.

---

## Categories

| Category                   | Representative Scripts                                                                                                                        | Purpose                                                           |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Azure Deployment           | `azure-az-deploy-template.ps1`, `azure-az-download-deployment-templates.ps1`                                                              | ARM/Bicep deployment automation & template retrieval              |
| Azure Identity & Security  | `azure-az-create-aad-application-spn.ps1`, `azure-msal-logon.ps1`, `azure-az-aad-add-key-vault.ps1`                                     | App registrations, auth flows, identity configuration             |
| Key Vault & Certificates   | `azure-az-create-keyvault-certificate.ps1`, `azure-az-keyvault-manager.ps1`, `convert-pfx-to-pem.ps1`, `create-test-certificates.ps1` | Secret & cert lifecycle management                                |
| Azure Operations / Compute | `azure-az-vm-manager.ps1`, `azure-az-vmss-run-command.ps1`, `azure-az-vmss-snapshot.ps1`                                                | VM / VMSS management, snapshots, remote command                   |
| Data & Storage             | `azure-az-sql-create.ps1`, `azure-sql-query.ps1`, `azure-storage-upload-files.ps1`                                                      | SQL provisioning & queries, file/share/table operations           |
| Diagnostics & Tracing      | `ps-net-trace.ps1`, `perfmon-console-graph.ps1`, `dotnet-trace-collect.ps1`, `process-monitor.ps1`                                    | Performance counters, network & .NET tracing, process diagnostics |
| Logging & Events           | `event-log-manager.ps1`, `enum-eventLog-meta.ps1`, `windows-logon-diagnostics-manager.ps1`                                              | Event log querying, enrichment, troubleshooting                   |
| Networking                 | `net-route-add.ps1`, `test-tcp-listener.ps1`, `test-udp-listener.ps1`                                                                   | Connectivity tests, route adjustments                             |
| File & Directory Ops       | `directory-compare.ps1`, `file-split.ps1`, `remove-BOM-from-files.ps1`                                                                  | File system comparison, large file handling, cleanup              |
| Kusto / Data               | `kusto-rest.ps1`, `kusto-emulator-setup.ps1`                                                                                              | Kusto (ADX) REST queries & local emulator setup                   |
| Automation Utilities       | `schedule-task.ps1`, `regenerate-guids.ps1`, `resolve-envPath.ps1`                                                                      | Job scheduling, GUID regeneration, path resolution                |
| RDS / Remote Desktop       | `rds-lic-per-device-cal-enumerate.ps1`, `rds-upd-mgr.ps1`                                                                                 | Licensing, session & update diagnostics                           |
| AI / Misc                  | `openai.ps1`, `github-billing-monitor.ps1`                                                                                                | AI integration & GitHub cost visibility                           |

---

## Development & Testing Tips

* Use `PSScriptAnalyzer` locally for style and potential issues.
* Prefer splatting for complex parameter sets (`@params = @{}` then call).
* Capture start/stop timestamps for long-running operations.
* Provide a `-test` or `-whatIf` parameter when implementing impactful changes.
* Keep external downloads (e.g., tools) version-pinned or checksum-validated where possible.

---

## Lightweight Safety (Optional MCP Layer)

An MCP-based execution environment can provide classification, confirmation for risky operations, and auditing. It is **supporting infrastructure**, not the project’s focus. Use it when you want structured execution; otherwise invoke scripts directly. Full details live in `WORKSPACE-KNOWLEDGE-INDEX.md`.

---

## Contributing

* Add scripts with meaningful names (`area-action-target.ps1` pattern helpful).
* Include a help block with at least one example.
* Avoid hard-coded secrets; prefer environment variables or interactive secure input.
* Group related helper functions inside the same file unless reused broadly (then consider a module).
* Run a basic functional test before committing (dry-run mode if available).

---

## Roadmap (Selective)

* Normalize help blocks across older scripts.
* Introduce a minimal module for shared logging & utility functions.
* Add CI step for synopsis extraction & auto-regenerated category table.
* Provide sample PSScriptAnalyzer settings.

---

## License

See `LICENSE` for details.

---

<!-- Removed duplicate catalog & sections to keep README concise -->
