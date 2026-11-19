---
name: power-platform-setup
description: Guide one Windows onboarding conversation: choose your host and Power Platform plugins (or marketplace / full setup) first, install only the required Windows prerequisites, add the approved marketplace/plugins, and continue with separately approved connection onboarding.
---

# Power Platform setup

Guided onboarding wrapper for [`Setup.ps1`](../../Setup.ps1) in
<https://github.com/danieag/power-platform-setup>. Stay in one conversation
where possible and execute approved stages with terminal tools—each stage
(prerequisites, marketplace/plugins, optional Copilot Studio MCP, personal
skills, and environment sign-in) requires its own explicit user approval.

## Step 1: choose host and workloads (or full setup)

Read `AGENTS.md`, `README.md`, and `Setup.ps1` (`Get-SetupPluginCatalog` and
`Resolve-SetupPrerequisites`). Speak in **plain, everyday language**—never
require the user to know CLI flags or plugin IDs.

If the user already named their workload(s), map them directly without re-asking:

- "Model-driven apps" / "generative pages" -> `model-apps` (`git, node, dotnet, pac, azure`)
- "Canvas apps" -> `canvas-apps` (`git, dotnet`)
- "Code apps" -> `code-apps-preview` (`git, node`)
- "Power Automate" / "flows" -> `power-automate` (`git, node, azure`)
- "Power Pages" / "website" / "portal" -> `power-pages` (`git, node, dotnet, pac, azure`)
- "Dataverse" -> `dataverse` (`git, node, dotnet, pac, azure`)
- "PCF" / "custom controls" -> `pcf` (`git, node, dotnet, pac, azure`)
- "Process Intelligence" / "process mining" -> `process-intelligence` (`git, node, azure`)
- "Mobile apps" -> `mobile-app` (`git, node, azure`)
- "Mobile extensions" / "wrapped canvas" -> `power-apps-mobile-extension` (`git, node, dotnet, pac`)
- "MCP apps" / "widgets" -> `mcp-apps` (`git, node, dotnet, pac`)
- "Marketplace only" -> `-MarketplaceOnly` (`git` only)
- "Everything" / "full setup" -> `-Prerequisites All` (`git, node, dotnet, pac, azure`)

If they asked **only** for prerequisites (e.g. *"install the prereqs for
model-driven apps"*), jump straight to Step 2 for `model-apps`, then politely
offer plugin/connection next steps afterward without forcing them.

Otherwise:
1. Confirm which existing host they use (`CopilotApp`, `CopilotCli`,
   `ClaudeCode`, or VS Code's manual UI). Never install or substitute another
   agent host, and never accept a `Install GitHub Copilot CLI? [y/N]` launcher
   prompt—if a selected CLI is missing, show `Setup.ps1`'s official install URL.
2. **Multi-select UI rule:** users commonly want **multiple** workloads at once.
   **Never** list individual plugins as single-select `choices` in `ask_user`
   (in Copilot, clicking one choice submits immediately and blocks picking
   several). Use checkboxes only if the host natively supports `multiSelect: true`;
   otherwise display the numbered 1–11 catalog in chat and ask via freeform
   `ask_user` (omit `choices`, e.g. *"Reply with one or more numbers or names
   such as `1, 2, 6`, `all`, or `marketplace`"*) or multi-plugin bundle presets.
   Pass all chosen IDs together as `-Plugins "<id1,id2,...>"` so `Setup.ps1`
   computes the combined union of prerequisites.
3. Confirm whether they also want optional **Copilot Studio MCP** registration
   (adds `node` to prerequisites if not already included).

## Step 2: check and install only the required prerequisites

Run an offline, read-only check scoped to their choice:

```powershell
# Selected plugins (CLI, CopilotApp, or omit -PluginHost for VS Code UI):
.\Setup.cmd -CheckOnly -PluginHost CopilotCli -Plugins "canvas-apps,power-automate" -Prerequisites FromPlugins

# Marketplace only (CopilotCli, ClaudeCode, or CopilotApp):
.\Setup.cmd -CheckOnly -PluginHost CopilotCli -MarketplaceOnly -Prerequisites FromPlugins

# Full 5-tool workstation setup:
.\Setup.cmd -CheckOnly
```

Explain what is `[READY]`, what is missing, and any printed workload notes in
plain English. Obtain **explicit prerequisite approval**, then install only the
resolved prerequisites:

```powershell
.\Setup.cmd -Install -Accept -NonInteractive -Plugins "canvas-apps,power-automate" -Prerequisites FromPlugins
```

Stop on installer failure (`3`) or Windows reboot requirement (`3010`).

## Step 3: add the marketplace and selected plugins

Keep `-Prerequisites FromPlugins` on selective reruns and omit `-Install -Accept`
so plugin-only approval never installs unapproved tools. Never run Microsoft's
broad remote `scripts/install.js`.

- **CLI hosts (`CopilotCli` or `ClaudeCode`):**
  Inspect `copilot/claude plugin marketplace list --json` and `plugin list --json`
  on the chosen CLI only, show the delta, obtain plugin approval, and run:
  ```powershell
  .\Setup.cmd -NonInteractive -PluginHost CopilotCli -MarketplaceOnly -Prerequisites FromPlugins -AcceptPlugins
  .\Setup.cmd -NonInteractive -PluginHost CopilotCli -Plugins "dataverse,model-apps" -Prerequisites FromPlugins -AcceptPlugins
  ```
  (Use `ClaudeCode` when Claude Code was chosen.)
- **GitHub Copilot desktop app (`CopilotApp` — confirm each dialog in order):**
  `ghapp://` prompts open asynchronous in-app modals (`exit 4`)—**never jump
  ahead to Step 4 while modals are unconfirmed!** Reuse the exact workloads
  chosen in Step 1:
  1. **Add marketplace first & wait:** after approval, run
     `.\Setup.cmd -NonInteractive -PluginHost CopilotApp -MarketplaceOnly -Prerequisites FromPlugins -AcceptPlugins`
     and **pause with `ask_user`** until the user confirms clicking **Allow -> Add**
     (`✓ Added power-platform-skills marketplace`) in the Copilot app.
  2. **Open each chosen plugin one at a time & wait:** run
     `.\Setup.cmd -NonInteractive -PluginHost CopilotApp -Plugins "<single-id>" -SkipMarketplace -Prerequisites FromPlugins -AcceptPlugins`
     for one plugin at a time (include the printed fallback link in chat) and
     **pause with `ask_user` after each plugin** until the user confirms it is
     installed under **Customize > Installed**.
- **VS Code without CLI:** guide **Customizations > Browse > Configure
  Marketplaces > Add Marketplace... > `microsoft/power-platform-skills`**, and
  wait for confirmation before Step 4.
- **Optional Copilot Studio MCP:** only if separately requested and approved
  (close the host before editing user config), run:
  `.\Setup.cmd -NonInteractive -CopilotStudioHost <host> -AcceptCopilotStudio -Prerequisites "node"`

## Step 4: environment connections & personal router skills (after Step 3!)

**Hard gate:** never ask to connect an environment while Step 3 confirmations
are still pending.

Once Step 3 is complete:
1. Ask whether the user wants to run persistent connection setup now. If yes,
   **always read and follow [`skills/power-platform-connect/SKILL.md`](../power-platform-connect/SKILL.md)**
   end to end—never improvise a bare `pac auth create` one-liner:
   - Connect **PAC CLI** (`pac`) when installed and used by their plugins.
   - Connect **Azure CLI** (`az` with tenant-isolated `AZURE_CONFIG_DIR`) when
     installed and used by their plugins (`model-apps`, `power-pages`,
     `power-automate`, `process-intelligence`, `pcf`, `mobile-app`, `dataverse`).
   - Check whether the **`dataverse` plugin** is installed: if installed, offer
     **Dataverse CLI** (`@microsoft/dataverse`) + **Dataverse MCP**; if not
     installed, let them cleanly **skip** Dataverse CLI/MCP or install the
     `dataverse` plugin first.
   - Save the approved token-free `%LOCALAPPDATA%\PowerPlatformSetup\connections\<alias>.json`
     record (including mapped per-environment MCP server IDs). If an installed
     plugin's `PreToolUse` hook (e.g. `model-apps@power-platform-skills`) fails
     on Windows with `"hook errored"` while writing `mcp-config.json`, ask the
     user to toggle that plugin off temporarily in **Customize > Installed**,
     retry the approved write, and toggle it back on.
2. **Recommend installing the personal user skills** (whether connecting now or
   later, with separate approval):
   ```powershell
   .\Setup.cmd -NonInteractive -ConnectionSkillHost CopilotApp -AcceptConnectionSkill -Prerequisites "git"
   ```
   (Use `CopilotCli` or `ClaudeCode` for those hosts.) This installs both
   `power-platform-connect` and `power-platform-router` into `~/.copilot/skills/`
   (or `~/.claude/skills/`) so future Projects and child sessions automatically
   reuse saved environments and confirm **Environment X and Solution Y**.
3. **Restart handoff when needed:** if `PATH` changed or newly registered
   plugins, personal skills, or MCP servers need a host reload, explain why and
   give a short, PII-free resume prompt listing completed stages, chosen host,
   and plugin IDs. For the **GitHub Copilot desktop app**, remind the user:
   - Closing the window (`X`) may keep background processes alive—if new tools,
     skills, or MCP servers don't appear, open **Windows Task Manager**
     (`Ctrl+Shift+Esc`), choose **End task** on **GitHub Copilot**, and reopen it.
   - Check **Customize > Installed** (under **Skills**) and toggle
     `power-platform-connect`, `power-platform-router`, and plugin skills **on**
     if any appear switched off.
   - During any device-code sign-in in Step 4, always extract the code from
     terminal output and display it **in bold** (`**CODE**`) with
     `[Sign in to your account](https://login.microsoftonline.com/common/oauth2/deviceauth)`
     directly inside the `ask_user` prompt.
