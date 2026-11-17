---
name: power-platform-doctor
description: "Step 2 after Windows prerequisites: check an existing GitHub Copilot CLI or Claude Code host, prepare the official marketplace with approval, then ask which Power Platform plugins the user wants and install only the approved selection through Setup.cmd. No authentication or tenant operations."
---

# Power Platform doctor: choose and install plugins

This is **Step 2** of the
[Windows setup guide](https://github.com/danieag/power-platform-setup/blob/main/README.md).
Use it when the user has completed local prerequisites and wants to choose,
install, or check Power Platform plugins in an **existing Copilot CLI or
Claude Code CLI**. It is not a second installer, a general authentication
doctor, or permission to repair every tool on the computer.

Keep the approved work in the same guided installation chat where possible.
Do the work with terminal tools; do not merely return commands for the user
to run unless permissions or host capabilities genuinely prevent execution.
All installation policy stays in `Setup.ps1`.

## 1. Read the source and check prerequisites

Locate the reviewed, fully extracted
[official setup repository](https://github.com/danieag/power-platform-setup).
Read its `AGENTS.md`, `README.md`, and `Setup.ps1` before execution. If the
folder is not available, ask where it was extracted; do not assume the user's
current project contains the installer or download an isolated launcher.

From that folder, run:

```powershell
.\Setup.cmd -CheckOnly
```

This check is offline, read-only and CLI-free. Exit `1` means missing or
unsupported prerequisites, not installation approval. Stop and use the
Step 1 prerequisite plan/approval process before attempting plugins. Never
install another agent host, modify persistent execution policy, or enable
blanket tool approval to make this step work.

## 2. Confirm one existing CLI host

Use the user's already confirmed host. Otherwise ask **one question**:
"Which command-line agent should receive these plugins: GitHub Copilot CLI
or Claude Code?" If both are installed, do not configure both by default.

| Choice | Existing command | Script value |
|---|---|---|
| GitHub Copilot CLI | `copilot` | `CopilotCli` |
| Claude Code CLI | `claude` | `ClaudeCode` |

Discover only the selected application command with
`Get-Command -CommandType Application`. A PATH entry can be a first-run install
launcher rather than the full CLI. If it asks to install/sign in to a host,
stop and explain; do not accept that prompt, start an AI conversation, or
substitute the other host.
For a missing command, give that host's official installation guide from the
README/`Show-AgentHostInstallHandoff` in `Setup.ps1`. The user completes host
installation independently, reopens the terminal, then resumes this stage.
Do not install the host under any prerequisite, marketplace or plugin approval.
The script's missing-host exit `2` is this handoff, not plugin success.

For **VS Code Copilot without Copilot CLI**, or **Copilot desktop without
Copilot CLI**, use the README's native marketplace/manual route instead.
Neither requires installing an extra CLI. Ordinary Claude chat/Cowork is not
Claude Code. Do not equate any of these surfaces or guess their configuration.

## 3. Prepare the marketplace before asking for plugins

Explain and inspect the chosen CLI's supported
`plugin marketplace list --json` listing. Verify that an existing
`power-platform-skills` source is the official
`microsoft/power-platform-skills` repository; stop on conflicts or unsupported
output. Never overwrite another source.

If it is missing, show the host/source and ask permission to add **only the
marketplace**. Then run one approved example:

```powershell
.\Setup.cmd -NonInteractive -PluginHost CopilotCli -MarketplaceOnly -AcceptPlugins
.\Setup.cmd -NonInteractive -PluginHost ClaudeCode -MarketplaceOnly -AcceptPlugins
```

Use the chosen host only. The script rechecks prerequisites, adds/verifies the
official marketplace, and installs **no plugins**. `-AcceptPlugins` here
approves only this marketplace-only plan, not future plugin installation.
Do not add `-Install -Accept`, `-Plugins`, or `-IncludeDataverse` to this stage.
If the marketplace is already verified, retain it without an unnecessary write.
On refusal/failure, stop this plugin flow rather than silently continuing.

## 4. Ask which Power Platform plugins to install

Ask explicitly; do **not** preselect every plugin. Explain that "Power
Platform Skills" are distributed as plugins, which may contain skills, agents,
hooks, MCP definitions and executable dependencies.

Read `Get-SetupPluginNames` in the current `Setup.ps1` as the authoritative
reviewed catalog. Present its choices with short explanations:

| Plugin ID | What it is for |
|---|---|
| `dataverse` | Dataverse data, schema and solution skills. This is not the separate Dataverse CLI. |
| `model-apps` | Model-driven apps and generative pages. |
| `canvas-apps` | Canvas Apps authoring. |
| `code-apps-preview` | Power Apps Code Apps. |
| `power-pages` | Power Pages sites. |
| `power-automate` | Power Automate flows. |
| `process-intelligence` | Process Intelligence / process mining. |
| `pcf` | Power Apps component framework controls. |
| `mobile-app` | Mobile apps. |
| `power-apps-mobile-extension` | Native mobile extensions for Canvas Apps. |
| `mcp-apps` | MCP apps and widgets. |

Use a multiple-selection control if the host supports it, or accept a list of
names. For example, "Dataverse and Model Apps" means exactly
`dataverse,model-apps`. Confirm an ambiguous workload rather than guessing.
Offer "None / skip" and an explicit all-reviewed-plugins choice. Dataverse
requires explicit selection even when the user chooses the standard all set.
If the user selects none, install no plugins and leave the earlier approved
marketplace intact. Never turn an empty selection into `All`.

Do not pass arbitrary URLs, marketplace suffixes, or names outside the reviewed
catalog. New/renamed upstream plugins need a reviewed setup release.

## 5. Inspect the selected plugins and approve the delta

Explain the local CLI listing checks before running them. Use the selected
host's supported structured listings, as implemented by `Read-PluginJson`,
`Get-PluginInventory`, and `Assert-OfficialMarketplace` in `Setup.ps1`:

```powershell
copilot plugin marketplace list --json
copilot plugin list --json
```

For Claude Code use the same subcommands with `claude` instead of `copilot`.
Use only the chosen host, not both examples. If the installed version does
not support these listings, report it and request a separately approved
host update or use the manual route. Do not parse success-looking log text
as a fallback, expose full private config, or launch servers/authentication.

Show one scoped plan: host, official source `microsoft/power-platform-skills`,
chosen plugin IDs, matching existing plugins to retain, missing plugins to
install, and whether the marketplace needs adding. An existing enabled
`dataverse@dataverse-skills` is reused rather than duplicated.

Stop on a different marketplace source, or a duplicate identity, disabled
plugin, load error, unsupported scope or policy restriction affecting a selected
plugin. Leave unselected plugins, including disabled ones, unchanged. Do not remove
or overwrite sources, force-enable/update plugins, or silently repair these.
Review the selected plugins' current host/runtime requirements; the core
prerequisite check does not prove every workload is build-ready.

Ask for explicit approval of **this host, marketplace and selected plugins**.
Prerequisite approval and selecting checkboxes are not substitutes. Explain
that plugin installation can download executable content and add bundled
definitions, but this step does not authorize sign-in, a live MCP call,
tenant selection, or cloud changes.

## 6. Execute the exact approved selection

Reuse `Setup.cmd -Plugins`, not the broad marketplace `scripts/install.js`
or a second implementation of plugin installation. For an approved example
selection of Dataverse and Model Apps, use **one** of:

```powershell
.\Setup.cmd -NonInteractive -PluginHost CopilotCli -Plugins "dataverse,model-apps" -AcceptPlugins
.\Setup.cmd -NonInteractive -PluginHost ClaudeCode -Plugins "dataverse,model-apps" -AcceptPlugins
```

Replace the example IDs with the actual approved comma-separated selection.
Always pass `-Plugins` explicitly. `-Plugins All` is only for an explicitly
approved standard full set; add `-IncludeDataverse` only when also approved.
An explicit `dataverse` ID in `-Plugins` already opts that plugin in.

Do **not** add `-Install -Accept` just to run Step 2. Without them, a newly
missing prerequisite stops noninteractive setup instead of installing
unapproved software. Optional MCP/connection-skill stages are omitted and
therefore skipped. Combine other stages only after their separate approvals.

Setup adds/verifies the official marketplace, keeps matching plugins, installs
only the selected missing plugins, and verifies their qualified identities,
enabled state and Claude user scope. Respect every exit code; stop on failure
or restart. Earlier successful installations are preserved. No blind retries.

Do not run npm/npx to install Dataverse CLI here. Installing the Dataverse
plugin is not installing that CLI; connection onboarding handles it later
only if selected, missing and separately approved.

## 7. Report what is ready and what remains

Give a short readiness card in chat:

| Layer | State to report |
|---|---|
| Prerequisites | Local inventory ready / blocked, without claiming every binary was executed. |
| Selected CLI | Copilot CLI or Claude Code; plugin management responded / blocked. |
| Marketplace | Official source added / reused and verified. |
| Selected plugins | Installed / retained / failed, naming only this selection. |
| Runtime discovery | Restart/new chat pending until actually confirmed. |
| Authentication | Not checked or changed by this step. |

Ask the user to restart the chosen host or open a fresh chat when needed, then
confirm the selected plugins' skills/tools appear. Do not close the app for
them or claim that a CLI registration proves every bundled tool is live.
Do not write identity/configuration reports into a public repository.

For separately requested sign-in, hand off to
[power-platform-connect](https://github.com/danieag/power-platform-setup/blob/main/skills/power-platform-connect/SKILL.md)
as **Step 3**, confirming account, tenant, environment and approvals there.
When the starting request is the complete guided flow, the setup entry skill
continues with that file in this conversation. Do not require the user to
discover/paste another skill prompt; pause only for a required restart or
capability reload and give the entry skill's resume handoff.
Copilot Studio MCP registration remains a separate optional stage described by
[power-platform-integrations](https://github.com/danieag/power-platform-setup/blob/main/skills/power-platform-integrations/SKILL.md).
