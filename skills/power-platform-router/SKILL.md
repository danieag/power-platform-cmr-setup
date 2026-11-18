---
name: power-platform-router
description: "Load FIRST or ALONGSIDE any Power Platform build, create, edit, deploy, or data request—including when the user names create-code-app, code app, model-apps, genpage, app-builder, canvas-app, power-automate, create-flow, power-pages, create-site, pcf, mobile-app, mcp-apps, or dataverse, and in Project coordinators before spawning child sessions. Reads saved connections in %LOCALAPPDATA%\\PowerPlatformSetup\\connections\\*.json so you never re-ask for Environment URL, Environment ID, Tenant ID, or sign-in email: confirm saved Environment X and Solution Y with the user, activate PAC/Dataverse/AZURE_CONFIG_DIR/MCP bindings, and hand off the verified target."
---

# Power Platform environment & solution router

Load this skill **before or alongside** any Power Platform product skill
(`create-code-app`, `model-apps`, `genpage`, `app-builder`, `canvas-app`,
`power-automate`, `create-flow`, `power-pages`, `create-site`, `pcf`,
`mobile-app`, `power-apps-mobile-extension`, `mcp-apps`, or `dataverse`),
including when the user's prompt explicitly names a product skill or runs in a
Project coordinator that spawns child sessions.

Its job is simple: **read the user's saved local connection registry first so
you never ask them to look up Environment URLs, Environment IDs, Tenant IDs, or
sign-in emails they already configured**. Instead, ask them to confirm
**Environment X** (from their saved connections, unless they specify another)
and **Solution Y** (when applicable), activate the matching authentication
bindings, and pass that verified target straight to the specialist skill.

---

## 1. Read the local connection registry first

Before asking the user for an environment URL, Environment ID, `make.powerapps.com`
link, Tenant ID, or work email, inspect their token-free binding records under
`%LOCALAPPDATA%\PowerPlatformSetup\connections\`:

```powershell
$registryDir = Join-Path $env:LOCALAPPDATA 'PowerPlatformSetup\connections'
if (Test-Path -LiteralPath $registryDir -PathType Container) {
    Get-ChildItem -LiteralPath $registryDir -Filter '*.json' -File | Sort-Object Name | ForEach-Object {
        $rec = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
        $mcp = [ordered]@{}
        if ($rec.PSObject.Properties['mcpServers'] -and $null -ne $rec.mcpServers) {
            foreach ($p in $rec.mcpServers.PSObject.Properties) {
                if (-not [string]::IsNullOrWhiteSpace($p.Value)) { $mcp[$p.Name] = [string]$p.Value }
            }
        }
        foreach ($legacy in @(
            @{ Prop = 'dataverseMcpServer'; Key = 'dataverse' },
            @{ Prop = 'powerAutomateMcpServer'; Key = 'powerAutomate' },
            @{ Prop = 'copilotStudioMcpServer'; Key = 'copilotStudio' })) {
            if (-not $mcp.Contains($legacy.Key) -and $rec.PSObject.Properties[$legacy.Prop] -and -not [string]::IsNullOrWhiteSpace($rec.($legacy.Prop))) {
                $mcp[$legacy.Key] = [string]$rec.($legacy.Prop)
            }
        }
        [pscustomobject]@{
            Alias = $rec.alias
            EnvironmentUrl = $rec.environmentUrl
            EnvironmentId = $rec.environmentId
            OrganizationId = $rec.organizationId
            TenantId = $rec.tenantId
            Account = $rec.account
            DefaultSolution = if ($rec.PSObject.Properties['defaultSolution'] -and -not [string]::IsNullOrWhiteSpace($rec.defaultSolution)) { $rec.defaultSolution } else { $null }
            PacProfile = if ($rec.PSObject.Properties['pacProfile']) { $rec.pacProfile } else { $null }
            DataverseProfile = if ($rec.PSObject.Properties['dataverseProfile']) { $rec.dataverseProfile } else { $null }
            AzureConfigDir = if ($rec.PSObject.Properties['azureConfigDir']) { $rec.azureConfigDir } else { $null }
            McpServers = [pscustomobject]$mcp
        }
    }
}
```

Do not read raw MSAL/DPAPI token caches, print raw JSON files verbatim, or
rewrite an older `<alias>.json` file merely to add optional/`null` keys.

- **1 saved connection found:** propose it directly for confirmation—for example:
  *"Should I build this in your saved environment **`<Alias>`** (`<EnvironmentUrl>`, `<Account>`)?"*
  Always allow choosing/adding a different environment if they want one.
- **Multiple saved connections found:** present the saved aliases (`<Alias>` —
  `<EnvironmentUrl>`, `<Account>`) so the user picks **Environment X** in one
  step (plus an option to use a different environment).
- **User already named the target in their prompt:** if their prompt names an
  alias or URL matching one saved record, reuse its stored `EnvironmentUrl`,
  `EnvironmentId`, `OrganizationId`, `TenantId`, `Account`, profiles, MCP server,
  and `AzureConfigDir` without asking for any of those fields again; still keep
  normal write/deploy/publish approvals.
- **0 saved connections found (or user wants an unlisted environment):** use the
  `power-platform-connect` skill
  ([public reference](https://github.com/danieag/power-platform-setup/blob/main/skills/power-platform-connect/SKILL.md))
  to connect and save the binding record first so future builds remember it too.

---

## 2. Confirm Solution Y (when the build uses Dataverse / solutions)

Once **Environment X** is selected:

- **Workloads that use a Dataverse solution (`Solution Y`):** Dataverse tables,
  columns, views, or forms (`dataverse`), Model-driven apps and generative pages
  (`model-apps`), Power Automate flows (`power-automate`), Power Pages
  (`power-pages`), PCF controls (`pcf`), solution-aware Canvas or Mobile apps,
  and **Power Apps Code Apps whenever the request creates or modifies custom
  Dataverse tables** (note: Code App frontend hosting via `pa` is separate from
  Dataverse solution membership, while custom Dataverse tables created for the
  app belong in **Solution Y**).
- **Workloads without Dataverse metadata/solution writes** (for example a purely
  local or non-Dataverse connector Code App): confirm **Environment X** only;
  do not force an unnecessary Dataverse solution question.

When **Solution Y** is needed and the user did not already name it in their prompt:

1. After activating/scoping read access to **Environment X** (Step 3), list
   existing visible unmanaged solutions (excluding `Default`, `Active`, `Basic`,
   and `Cr*` system containers)—using the bound `<DataverseMcpServer>`
   `read_query` tool (`SELECT uniquename, friendlyname, version FROM solution WHERE ismanaged = 0 AND isvisible = 1`),
   `dataverse` CLI, or `pac solution list`.
2. If the connection record includes a `DefaultSolution`, highlight it first.
3. Ask the user to confirm **Solution Y** (pick an existing unmanaged solution
   or give a name + publisher prefix for a new solution). Never silently drop
   components into the Default Solution.

---

## 3. Activate and verify the saved bindings for Environment X

Use only the surfaces installed and recorded on **Environment X**'s binding:

- **PAC CLI** (when `PacProfile` is populated and the task uses `pac`):
  ```powershell
  pac auth select --name $target.PacProfile
  pac env who --environment $target.EnvironmentUrl --json
  ```
- **Dataverse CLI** (when `DataverseProfile` is populated and the task uses `dataverse`):
  ```powershell
  dataverse auth select --name $target.DataverseProfile
  dataverse auth who
  ```
- **Azure CLI** (when `AzureConfigDir` is populated and the task uses `az`—for
  example `model-apps`, `power-automate`, `power-pages`, `pcf`, or `mobile-app`):
  scope `AZURE_CONFIG_DIR` per shell invocation without `setx`:
  ```powershell
  $previousAzureConfigDir = $env:AZURE_CONFIG_DIR
  try {
      $env:AZURE_CONFIG_DIR = $target.AzureConfigDir
      az account show --query "{tenant:tenantId,user:user.name}" --output json
  } finally {
      $env:AZURE_CONFIG_DIR = $previousAzureConfigDir
  }
  ```
- **Open, task-driven MCP selection (`$target.McpServers`):**
  `$target.McpServers` is an open map of **any** MCP servers linked to
  **Environment X** (for example `dataverse`, `flowagent`, `copilotStudio`,
  `canvas`, `powerPages`, `erp`, or any future/custom MCP—no fixed 3-server
  limit and no `null` placeholders needed):
  1. **When a matching MCP is mapped in `$target.McpServers` — use it automatically:**
     pick whichever server ID in `$target.McpServers` exposes the tools needed
     for the current task (for example Dataverse schema/query tools, FlowAgent
     flow tools, Copilot Studio authoring tools, Canvas coauthoring tools, etc.).
     If that MCP holds a switchable active environment at runtime (such as
     FlowAgent's `get_current_env`/`set_current_env` or Copilot Studio's
     `copilot_studio_status`/`copilot_studio_select_environment`), verify its
     active environment matches `$target.EnvironmentId` before acting.
  2. **When no MCP for this task is mapped on Environment X yet — ask, don't
     block or silently guess:** users may add new MCP servers outside
     `power-platform-connect` at any time. Never silently call an MCP server
     mapped to a different saved environment, and do not block the user either:
     list any candidate MCP servers visible in the host and let the user
     **choose** which MCP to use for `<Alias>` (verifying it matches `<Alias>`
     and offering to save `"<label>": "<server-id>"` into `<Alias>.json`'s
     `mcpServers` map so next time it works automatically), add a new MCP, or
     proceed with CLI/SDK tools instead.
- **Power Apps Code Apps (`create-code-app` / `pa` CLI):** supply the confirmed
  `EnvironmentId` and `EnvironmentUrl` from the binding record directly into
  `power.config.json` / `pa` commands so `create-code-app` does not prompt the
  user to look up their Environment ID or paste a `make.powerapps.com` link.

Check that the active tool identity matches `$target.Account`, `$target.TenantId`,
and `$target.EnvironmentUrl` / `$target.OrganizationId`. If a cached token
genuinely expired and needs interactive renewal, tell the user which single CLI
needs re-authentication (keeping the saved binding metadata) rather than asking
them to re-enter URLs or Tenant IDs. Never run `auth clear` or `az logout` on
working profiles.

---

## 4. Hand off the confirmed target to product skills and child sessions

Pass the confirmed target directly into the relevant installed product skill
(`create-code-app`, `app-builder`, `genpage`, `canvas-app`, `create-flow`,
`create-site`, `pcf`, `create-mobile-app`, `dv-metadata`, `dv-data`,
`dv-solution`, etc.) so that specialist owns all product-specific architecture,
scaffolding, and validation without re-asking target questions.

**CRITICAL for Project coordinators, child sessions (`create_session`), and
sub-agents (`task`):**
A newly spawned child session starts with a fresh conversation and will
otherwise ask *"Which existing Power Platform environment should this app use?
Please provide its Dataverse URL and environment ID"*! Therefore:

1. **Resolve and confirm Environment X (and Solution Y, when needed) BEFORE
   spawning the child session**, or instruct the child explicitly where to read
   the registry.
2. **Include the confirmed target handoff block in the child's kickoff prompt:**
   - Confirmed alias: `<Alias>`
   - `environmentUrl`: `<EnvironmentUrl>`
   - `environmentId`: `<EnvironmentId>`
   - `organizationId`: `<OrganizationId>`
   - `tenantId`: `<TenantId>`
   - `account`: `<Account>`
   - `selectedSolution`: `<SolutionUniqueName or N/A>`
   - Bound CLIs: `pacProfile=<PacProfile>`, `dataverseProfile=<DataverseProfile>`,
     `azureConfigDir=<AzureConfigDir>`
   - Mapped MCP servers for `<Alias>`: `mcpServers=<McpServers JSON>`
   - Explicit instruction: *"Target environment and solution are already
     confirmed by the user from `%LOCALAPPDATA%\PowerPlatformSetup\connections\<Alias>.json`.
     Reuse these exact values and bindings: automatically use the MCP server IDs
     in `mcpServers` that match your task (verifying active `environmentId` on
     stateful servers like FlowAgent or Copilot Studio MCP); if a needed MCP is
     not in `mcpServers`, ask the user to choose an available MCP rather than
     silently using another environment's server. Do NOT ask the user for
     Environment URL, Environment ID, Tenant ID, or sign-in email again.
     Preserve normal approvals before creating/modifying cloud resources."*

Confirming an environment from the registry selects **where** to work; it does
**not** bypass explicit user approval before live Dataverse schema writes, bulk
data changes, app/flow deployment, publishing, sharing, or deletion.
