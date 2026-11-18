---
name: power-platform-doctor
description: "Choose Power Platform plugins or marketplace-only setup for GitHub Copilot CLI, Claude Code, or the GitHub Copilot app, resolve and check only their required Windows prerequisites through Setup.cmd, and install only what the user approves. No authentication or tenant operations."
---

# Power Platform doctor: choose plugins and required prerequisites

Use this skill when the user wants to choose Power Platform plugins (or add
only the official marketplace), resolve **only the Windows prerequisites their
selection needs**, and configure an **existing Copilot CLI, Claude Code CLI, or
GitHub Copilot desktop app** (or prepare prerequisites for VS Code's native UI).
It is not a second installer, a general authentication doctor, or permission to
install unselected software.

Keep the approved work in the same guided installation chat where possible.
Do the work with terminal tools; do not merely return commands for the user
to run unless permissions or host capabilities genuinely prevent execution.
All installation policy and prerequisite mapping stay in `Setup.ps1`.

## 1. Read the source and confirm one existing host

Locate the reviewed, fully extracted
[official setup repository](https://github.com/danieag/power-platform-setup).
Read its `AGENTS.md`, `README.md`, and `Setup.ps1` (`Get-SetupPluginCatalog` and
`Resolve-SetupPrerequisites`) before execution. If the folder is not available,
ask where it was extracted; do not assume the user's current project contains
the installer or download an isolated launcher.

Use the user's already confirmed host, or ask **one plain-language question**:

| Choice | Existing surface | Script `-PluginHost` |
|---|---|---|
| GitHub Copilot CLI | `copilot` command | `CopilotCli` |
| Claude Code CLI | `claude` command | `ClaudeCode` |
| GitHub Copilot desktop app | Official `ghapp://` confirmation links | `CopilotApp` |
| VS Code Copilot (without CLI) | Native VS Code **Customizations > Browse** UI | Omit / `Skip` (prerequisites only in script) |

If both CLIs are installed, do not configure both by default. For a CLI choice,
discover only the selected application command with
`Get-Command -CommandType Application`. A PATH entry can be a first-run install
launcher rather than the full CLI. If it asks to install/sign in to a host,
stop and explain; do not accept that prompt, start an AI conversation, or
substitute the other host. For a missing CLI command, give that host's official
installation guide from `Show-AgentHostInstallHandoff` in `Setup.ps1`; the user
completes host setup independently, reopens the terminal, and resumes. Never
install an agent host, modify persistent execution policy, or enable blanket
tool approval. Ordinary Claude chat/Cowork is not Claude Code.

## 2. Ask which Power Platform plugins (or marketplace only) they want

If the user already named their workload in plain English (for example
"model-driven apps" -> `model-apps`, "canvas app" -> `canvas-apps`, "Power
Automate" -> `power-automate`), confirm/map it directly rather than making them
repeat themselves. Otherwise ask in everyday language; do **not** preselect
every plugin or install all 5 Windows tools before knowing what they need.

Read `Get-SetupPluginCatalog` in `Setup.ps1` as the authoritative reviewed
catalog and core Windows prerequisite map:

| Plugin ID | Plain-English workload | Core prerequisites resolved by `Setup.ps1` |
|---|---|---|
| `dataverse` | Dataverse data, tables, schema and solutions (not the separate Dataverse CLI). | `git, node, dotnet, pac, azure` |
| `model-apps` | Model-driven apps and generative pages. | `git, node, dotnet, pac, azure` |
| `canvas-apps` | Canvas Apps Studio coauthoring. | `git, dotnet` |
| `code-apps-preview` | Power Apps Code Apps (React/Vite + project-local `pa`). | `git, node` |
| `power-pages` | Power Pages websites and portals. | `git, node, dotnet, pac, azure` |
| `power-automate` | Power Automate cloud and desktop flows. | `git, node, azure` |
| `process-intelligence` | Process Intelligence / process mining. | `git, node, azure` |
| `pcf` | Power Apps component framework custom controls. | `git, node, dotnet, pac, azure` |
| `mobile-app` | Standalone mobile apps (Private Preview). | `git, node, azure` |
| `power-apps-mobile-extension` | Native mobile extensions for wrapped Canvas Apps. | `git, node, dotnet, pac` |
| `mcp-apps` | Codeful MCP server tools and HTML widgets. | `git, node, dotnet, pac` |
| *(Marketplace only)* | Add `microsoft/power-platform-skills` without installing plugins yet. | `git` |

Offer **Marketplace only**, **All reviewed plugins** (confirming explicitly
whether `dataverse` is included), and **None / skip**. Never turn an empty
selection into `All`, and do not pass arbitrary URLs or unreviewed plugin names.

**Multi-select UI rule:** users usually want **several** plugins together, and
`-Plugins "id1,id2,..." -Prerequisites FromPlugins` automatically computes the
union of their required prerequisites. **Never** pass individual plugins as
single-select `choices` in `ask_user` (clicking one immediately submits and
blocks choosing multiple!). Use checkboxes only if the host tool natively
supports `multiSelect: true`; otherwise print the numbered 1–11 catalog and ask
via freeform `ask_user` (no `choices`, e.g. *"Reply with one or more numbers or
names, such as `1, 2, 6` or `dataverse, model-apps, power-automate`"*) or offer
only multi-plugin preset bundles as `choices` alongside the freeform input.

## 3. Check and install only the required prerequisites

Run the offline, read-only, CLI-free check scoped to their selection using
`-Prerequisites FromPlugins`:

```powershell
.\Setup.cmd -CheckOnly -PluginHost CopilotCli -Plugins "canvas-apps,power-automate" -Prerequisites FromPlugins
.\Setup.cmd -CheckOnly -PluginHost CopilotCli -MarketplaceOnly -Prerequisites FromPlugins
```

(Omit `-PluginHost` on `-Plugins ... -Prerequisites FromPlugins` if checking
prerequisites only or using VS Code's manual UI; for a VS Code marketplace-only
prerequisite check without a CLI host, pass `-Prerequisites "git"`.)
Exit `1` means one or more required prerequisites for that selection are missing
or unsupported—it is **not** approval to install them. Explain the exact
missing tools in plain language along with any workload notes printed by
`Setup.ps1`, obtain **explicit prerequisite approval**, and run:

```powershell
.\Setup.cmd -Install -Accept -NonInteractive -Plugins "canvas-apps,power-automate" -Prerequisites FromPlugins
```

(For marketplace-only prerequisite installation, pass `-Prerequisites "git"`.)
Stop on any installer failure (`3`) or Windows restart requirement (`3010`).

## 4. Inspect the selected host and approve marketplace/plugin changes

For `CopilotCli` or `ClaudeCode`, explain the local CLI listing checks before
running them:

```powershell
copilot plugin marketplace list --json
copilot plugin list --json
```

(Use `claude` instead of `copilot` when `ClaudeCode` was chosen; never run both.)
If the user asked to add **only the marketplace**, request marketplace approval
and run one of:

```powershell
.\Setup.cmd -NonInteractive -PluginHost CopilotCli -MarketplaceOnly -Prerequisites FromPlugins -AcceptPlugins
.\Setup.cmd -NonInteractive -PluginHost ClaudeCode -MarketplaceOnly -Prerequisites FromPlugins -AcceptPlugins
.\Setup.cmd -NonInteractive -PluginHost CopilotApp -MarketplaceOnly -Prerequisites FromPlugins -AcceptPlugins
```

`-AcceptPlugins` on `-MarketplaceOnly` approves only adding/printing the
marketplace, not later plugin installation. `CopilotApp` prints the official
marketplace launch link and returns exit `4` (pending user confirmation in the app).

When specific plugins are selected on a CLI host, show one scoped plan: host,
official source `microsoft/power-platform-skills`, chosen plugin IDs, matching
existing plugins to retain, missing plugins to install, and whether the
marketplace needs adding. An existing enabled `dataverse@dataverse-skills` is
reused rather than duplicated. Stop on a different marketplace source, or a
duplicate identity, disabled plugin, load error, unsupported scope or policy
restriction affecting a selected plugin. Leave unselected plugins, including
disabled ones, unchanged. Do not remove or overwrite sources, force-enable/update
plugins, or silently repair these.

Ask for explicit approval of **this host, marketplace and selected plugins**
(separate from prerequisite approval). Explain that plugin installation can
download executable content and add bundled definitions, without authorizing
sign-in, live MCP calls, tenant selection, or cloud changes.

## 5. Execute the exact approved selection

Reuse `Setup.cmd`, not the broad marketplace `scripts/install.js` or a second
plugin installer.

For **`CopilotCli` or `ClaudeCode`**, pass all approved plugin IDs in one
comma-separated `-Plugins` string:

```powershell
.\Setup.cmd -NonInteractive -PluginHost CopilotCli -Plugins "dataverse,model-apps" -Prerequisites FromPlugins -AcceptPlugins
.\Setup.cmd -NonInteractive -PluginHost ClaudeCode -Plugins "dataverse,model-apps" -Prerequisites FromPlugins -AcceptPlugins
```

For **`CopilotApp` (GitHub Copilot desktop app)**, `ghapp://` modals are
asynchronous in-app dialogs (`exit 4`)—**never fire everything and jump ahead to
connection onboarding while modals are still open!** Execute sequentially with
user confirmation at each step:

1. **First add the marketplace & wait:** run
   `.\Setup.cmd -NonInteractive -PluginHost CopilotApp -MarketplaceOnly -Prerequisites FromPlugins -AcceptPlugins`
   and **stop with `ask_user`** until the user confirms clicking **Allow -> Add**
   (`✓ Added power-platform-skills marketplace`) in the Copilot app (skip this
   sub-step if the user confirms the marketplace is already added).
2. **Then trigger each selected plugin one at a time with `-SkipMarketplace` & wait:**
   ```powershell
   .\Setup.cmd -NonInteractive -PluginHost CopilotApp -Plugins "model-apps" -SkipMarketplace -Prerequisites FromPlugins -AcceptPlugins
   ```
   Each call opens `ghapp://plugins/install?source=<id>%40power-platform-skills`
   directly in the Copilot desktop app (also share the printed launch link in
   chat as fallback). **Stop with `ask_user` after each plugin** so the user can
   confirm installing that plugin in the app before the next modal opens—and
   confirm all selected plugins are installed before moving to connection setup!

Always pass `-Plugins` explicitly (`All` only when the standard full set was
explicitly approved; add `-IncludeDataverse` or include `dataverse` in `-Plugins`
only when approved). Keeping `-Prerequisites FromPlugins` verifies only the
prerequisites required by the selected plugins, while omitting `-Install -Accept`
ensures a newly missing prerequisite stops with exit `2` instead of installing
unapproved software.

Do not run npm/npx to install Dataverse CLI here. Installing the Dataverse
plugin is not installing that CLI; connection onboarding handles it later
only if selected, missing and separately approved.

## 6. Report what is ready and what remains

Give a short readiness card in chat:

| Layer | State to report |
|---|---|
| Required prerequisites | Ready / skipped (unselected tools noted) / blocked. |
| Selected host | Copilot CLI, Claude Code, Copilot desktop app links, or VS Code manual UI. |
| Marketplace | Official source added / reused and verified, or app link pending confirmation. |
| Selected plugins | Installed / retained / app links printed (pending confirmation) / failed. |
| Runtime discovery | Restart/reload pending until actually confirmed in the host. |
| Authentication | Not checked or changed by this step. |

Ask the user to reload/restart the chosen host or open a fresh chat when needed,
then confirm the selected plugins' skills/tools appear. Do not close the app for
them or claim that a CLI registration or printed app link proves every bundled
tool is live. Do not write identity/configuration reports into a public repo.

For separately requested sign-in, hand off to
[power-platform-connect](https://github.com/danieag/power-platform-setup/blob/main/skills/power-platform-connect/SKILL.md),
confirming account, tenant, environment and approvals there (and connecting only
surfaces relevant to the user's chosen plugins). When the starting request is
the complete guided flow, the setup entry skill continues with that file in this
conversation; pause only for a required restart or capability reload and give
the entry skill's resume handoff. Copilot Studio MCP registration remains a
separate optional stage described by
[power-platform-integrations](https://github.com/danieag/power-platform-setup/blob/main/skills/power-platform-integrations/SKILL.md).
