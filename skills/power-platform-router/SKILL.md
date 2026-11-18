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
        $mcpMap = if ($rec.PSObject.Properties['mcpServers']) { $rec.mcpServers } else { $null }
        [pscustomobject]@{
            Alias = $rec.alias
            EnvironmentUrl = $rec.environmentUrl
            EnvironmentId = $rec.environmentId
            OrganizationId = $rec.organizationId
            TenantId = $rec.tenantId
            Account = $rec.account
            DefaultSolution = if ($rec.PSObject.Properties['defaultSolution']) { $rec.defaultSolution } else { $null }
            PacProfile = $rec.pacProfile
            DataverseProfile = $rec.dataverseProfile
            AzureConfigDir = $rec.azureConfigDir
            DataverseMcpServer = $rec.dataverseMcpServer
            PowerAutomateMcpServer = if ($rec.PSObject.Properties['powerAutomateMcpServer']) { $rec.powerAutomateMcpServer } elseif ($mcpMap -and $mcpMap.PSObject.Properties['powerAutomate']) { $mcpMap.powerAutomate } else { $null }
            CopilotStudioMcpServer = if ($rec.PSObject.Properties['copilotStudioMcpServer']) { $rec.copilotStudioMcpServer } elseif ($mcpMap -and $mcpMap.PSObject.Properties['copilotStudio']) { $mcpMap.copilotStudio } else { $null }
            McpServers = $mcpMap
        }
    }
}
```

Do not read raw MSAL/DPAPI token caches or print raw JSON files verbatim.

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
- **Multi-environment MCP mapping & strict server isolation:**
  A user with multiple environments can have **multiple MCP servers registered
  simultaneously** (for example `dataverse-dev` vs `dataverse-prod`,
  `flowagent-dev` vs `flowagent-prod`, plus `copilot-studio`). **Never** guess
  an MCP tool prefix by name alone or invoke an MCP server mapped to a sibling
  environment alias! Enforce exact environment matching for every MCP family:
  1. **Dataverse MCP (`$target.DataverseMcpServer`):** each Dataverse MCP server
     process is launched against **one specific `EnvironmentUrl`**. Call **only**
     MCP tools belonging to `$target.DataverseMcpServer`; never fall back to
     another `dataverse-*` server registered for a different environment.
  2. **Power Automate MCP (`$target.PowerAutomateMcpServer`, e.g. `flowagent` or
     `flowagent-<alias>`):** call **only** tools under `$target.PowerAutomateMcpServer`.
     Because FlowAgent also tracks an active environment at runtime, **always
     verify** `whoami` matches `$target.Account` / `$target.TenantId` and check
     `get_current_env` before listing or modifying flows—calling `set_current_env`
     with `$target.EnvironmentId` (after user confirmation if switching active
     context) so flows are never created or edited in the wrong environment!
  3. **Copilot Studio MCP (`$target.CopilotStudioMcpServer`, e.g. `copilot-studio`):**
     Copilot Studio MCP holds **one active Power Platform environment session at
     a time**. Before reading or authoring agents, inspect `copilot_studio_status`
     to verify the signed-in account/tenant and selected environment match
     `$target.EnvironmentId`; if it points to another environment, use
     `copilot_studio_select_environment` for `$target.EnvironmentId` with user
     confirmation rather than operating on the stale environment!
  4. **When an MCP slot is unmapped (`null` / absent) in `<alias>.json` — ask,
     don't hard-block or silently guess:** users often add MCP servers later
     outside `power-platform-connect` (for example manually adding a new
     `flowagent` or `dataverse-*` entry in **Customize** or `mcp-config.json`).
     - When an MCP **is** mapped in `<alias>.json`, use it **automatically**
       ("just works" with no extra MCP picker).
     - When an MCP needed by the task is **not** mapped in `<alias>.json`, never
       silently pick another environment's server on your own, and **do not
       rigidly block the user** either: list any candidate MCP servers currently
       available in the host and let the user **explicitly choose** which MCP to
       use for `<alias>` (or add a new MCP / continue without MCP). Once they
       choose one, verify its identity/environment matches `<alias>` and offer
       to save that MCP server ID into `<alias>.json` so next time it works
       automatically!
  5. **Concrete multi-environment example (`Env X` = 3 MCPs vs `Env Y` = 2 MCPs):**
     - `env-x.json` maps: `dataverseMcpServer = "dataverse-env-x"`,
       `powerAutomateMcpServer = "flowagent-env-x"`,
       `copilotStudioMcpServer = "copilot-studio"`.
     - `env-y.json` maps: `dataverseMcpServer = "dataverse-env-y"`,
       `powerAutomateMcpServer = null`,
       `copilotStudioMcpServer = "copilot-studio"`.
     - When the user confirms **Env X**: `dataverse-env-x`, `flowagent-env-x`
       (aligned to Env X's `environmentId`), and `copilot-studio` (switched to
       Env X's `environmentId`) all work automatically.
     - When the user confirms **Env Y**: `dataverse-env-y` and `copilot-studio`
       (switched to Env Y's `environmentId`) work automatically. If the user asks
       to build a Power Automate flow in **Env Y**, tell them no Power Automate
       MCP is mapped to `env-y.json` yet and let them **choose** an available
       FlowAgent MCP server (for example one they added manually later—verifying
       its account/environment matches Env Y and offering to save it to
       `env-y.json`), set up a new one, or proceed without MCP—never silently
       writing into Env X's `flowagent-env-x` unasked!
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
   - Bound MCP servers for this environment ONLY:
     `dataverseMcpServer=<DataverseMcpServer>`,
     `powerAutomateMcpServer=<PowerAutomateMcpServer>`,
     `copilotStudioMcpServer=<CopilotStudioMcpServer>`,
     `mcpServers=<McpServers JSON or N/A>`
   - Explicit instruction: *"Target environment and solution are already
     confirmed by the user from `%LOCALAPPDATA%\PowerPlatformSetup\connections\<Alias>.json`.
     Reuse these exact values and bindings: mapped MCP servers for `<Alias>`
     work automatically (verify `get_current_env`/`set_current_env` on FlowAgent
     and `copilot_studio_status` on Copilot Studio MCP against `<EnvironmentId>`);
     if an MCP slot is unmapped (`null`), do not silently use another
     environment's MCP—ask the user to choose an available MCP (verifying it
     matches `<Alias>`) or add a new one. Do NOT ask the user for Environment
     URL, Environment ID, Tenant ID, or sign-in email again. Preserve normal
     approvals before creating/modifying cloud tables, flows, apps, or deployments."*

Confirming an environment from the registry selects **where** to work; it does
**not** bypass explicit user approval before live Dataverse schema writes, bulk
data changes, app/flow deployment, publishing, sharing, or deletion.
