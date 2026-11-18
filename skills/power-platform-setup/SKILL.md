---
name: power-platform-setup
description: Guide one Windows onboarding conversation: choose your host and Power Platform plugins (or marketplace / full setup) first, install only the required Windows prerequisites, add the approved marketplace/plugins, and continue with separately approved connection onboarding.
---

# Power Platform setup

Use the reviewed public repository
<https://github.com/danieag/power-platform-setup>.
This skill is an instruction wrapper, not another installer. A repository URL
does not automatically register this skill in the desktop app.

## One entry point: plugin-first or full workstation setup

Read this file when the user provides the complete repo/extracted folder and
asks to be guided from setup through connection. Instead of forcing every user
to install all five Windows installers up front ("god mode"), the default
guided flow is **choose host & plugins first > install only their required
prerequisites > add marketplace/plugins > optional connection onboarding**:

1. **Choose host and workload scope** (specific plugins, marketplace only, or
   full 5-tool workstation setup).
2. **Check and install only the required core prerequisites** through
   `Setup.cmd -Prerequisites FromPlugins` (or full `-CheckOnly` / `-Install`
   when the user explicitly chooses the full workstation bundle).
3. **Add the official marketplace and/or selected plugins** for `CopilotCli`,
   `ClaudeCode`, `CopilotApp` confirmation links, or guide VS Code's native UI.
4. **Continue with `power-platform-connect`** when requested, connecting only
   the surfaces relevant to the chosen plugins.

Read the other repo skills when their stage is reached; do not make the user
find and invoke each one separately. Stay in the same conversation where
possible and execute approved work with terminal tools. **One starting prompt
is not blanket approval.** Prerequisite installation, marketplace/plugin
changes, optional personal skill/MCP writes, sign-in and live identity checks
retain their separate approval boundaries. Do not execute the flow for a
documentation-only or explanation request.

### Step 1: choose host and plugins (or full setup) first

Read `AGENTS.md`, `README.md`, and `Setup.ps1` (`Get-SetupPluginCatalog` and
`Resolve-SetupPrerequisites`) from the reviewed full source.

Speak in **plain, everyday language** for non-technical makers—never require the
user to know CLI flags or kebab-case plugin IDs. If the user already stated
what they want in plain English, map it directly instead of re-asking:

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

If the user asked **only** for prerequisites (for example, *"install the prereqs
for model-driven apps"*), run `-CheckOnly -Plugins "model-apps" -Prerequisites
FromPlugins` right away, explain the plan in plain English, and ask approval to
install only those missing tools; afterward, politely offer (without forcing)
to add the matching plugin and/or connect their environment.

Otherwise confirm which existing host the user wants (`CopilotCli`, `ClaudeCode`,
`CopilotApp`, or VS Code manual marketplace UI) if not already clear from
context. Check passive host availability as needed; if a selected CLI is
missing, provide its official installation handoff rather than installing or
substituting a host.

Ask what they want to build/install, presenting the choices in friendly plain
language with the tools each choice needs:

- **CRITICAL multi-select UI rule:** users frequently want **multiple** workloads
  at once (for example *Model-driven apps + Dataverse + Power Automate*), and
  `Setup.ps1` (`-Plugins "id1,id2,..." -Prerequisites FromPlugins`) automatically
  combines the union of all prerequisites they need. **Never** put individual
  plugins as single-select `choices` in `ask_user`! In GitHub Copilot's
  `ask_user` tool, `choices` is single-select (clicking one option submits
  immediately and prevents picking multiple). Only use clickable plugin options
  if your host's question tool explicitly supports `multiSelect: true`.
  Otherwise show the numbered 1–11 workload table in your message and either
  call `ask_user` **without `choices`** (freeform: *"Reply with one or more
  numbers or workload names separated by commas, such as `1, 2, 6` or
  `Model-driven apps, Power Automate`, `all` for all 11, or `marketplace` for
  marketplace only"*) **or** offer only multi-plugin preset bundles as `choices`
  (such as `"Core Maker bundle (Dataverse + Model-driven + Canvas + Power Automate)"`,
  `"All 11 Power Platform plugins"`, `"Marketplace only"`) while reminding them
  to type any custom multi-plugin combination in the text box.
- **Selected plugins** (pass all chosen IDs together in `-Plugins "<id1,id2,...>"`:
  `canvas-apps` -> `git, dotnet`; `code-apps-preview` -> `git, node`;
  `power-automate` or `process-intelligence` or `mobile-app` -> `git, node, azure`;
  `mcp-apps` or `power-apps-mobile-extension` -> `git, node, dotnet, pac`;
  `dataverse`, `model-apps`, `power-pages`, or `pcf` -> all 5 core tools).
- **Official marketplace only** (`-MarketplaceOnly` on `CopilotCli`,
  `ClaudeCode`, or `CopilotApp` link -> requires `git` only).
- **Full workstation setup** (all 5 core tools: `git, node, dotnet, pac, azure`).

Also confirm whether they want optional **Copilot Studio MCP** registration
(which adds `node` to resolved prerequisites if not already included).

### Step 2: check and install only the required prerequisites

Run an offline, read-only, CLI-free check matching the user's scope:

```powershell
# Specific plugins (CLI, Copilot desktop app, or omit -PluginHost for VS Code UI):
.\Setup.cmd -CheckOnly -PluginHost CopilotCli -Plugins "canvas-apps,power-automate" -Prerequisites FromPlugins

# Marketplace only (CopilotCli, ClaudeCode, or CopilotApp):
.\Setup.cmd -CheckOnly -PluginHost CopilotCli -MarketplaceOnly -Prerequisites FromPlugins

# Explicit prerequisite subset, when requested directly:
.\Setup.cmd -CheckOnly -Prerequisites "git,node,azure"

# Full workstation setup (all 5 core tools):
.\Setup.cmd -CheckOnly
```

Explain the resolved core prerequisites, what is already `[READY]`, what needs
installing, and any workload notes printed by the script (such as Dataverse CLI
and optional Python SDK being deferred to connection onboarding, Mobile
Extensions needing JDK 17+/Android SDK 35 or macOS Xcode for native builds, or
Canvas Apps needing coauthoring enabled in Power Apps Studio).

Obtain **explicit approval** for the prerequisite plan, then install **only**
those resolved prerequisites:

```powershell
.\Setup.cmd -Install -Accept -NonInteractive -Plugins "canvas-apps,power-automate" -Prerequisites FromPlugins
```

(Omit `-Plugins ... -Prerequisites FromPlugins` for full workstation setup, or
pass `-Prerequisites "git"` for marketplace-only prerequisite setup. Omit
`-AcceptPlugins` here unless the user already separately approved the plugin or
marketplace stage as well.) Compatible installed tools are skipped.

If Windows reports a reboot requirement (`3010`) or an installer fails (`3`),
stop; no later stage may run. If PATH changed, arrange the required
host/terminal restart before connection work. Approved CLI marketplace/plugin
commands can run first when no Windows reboot is required because the script
refreshes its own process PATH without rewriting the parent host's environment.

### Step 3: add the marketplace and/or selected plugins

Read and follow `skills/power-platform-doctor/SKILL.md` in this same
conversation. Keep `-Prerequisites FromPlugins` on selective reruns so
intentionally skipped tools (such as `.NET`/`PAC` for Power Automate or `Node`/
`Azure` for Canvas Apps) never block plugin setup:

- **CLI hosts (`CopilotCli` or `ClaudeCode`)**:
  - Marketplace-only, after marketplace approval:
    `.\Setup.cmd -NonInteractive -PluginHost <host> -MarketplaceOnly -Prerequisites FromPlugins -AcceptPlugins`
  - Selected plugins, after inspecting CLI state and obtaining plugin approval:
    `.\Setup.cmd -NonInteractive -PluginHost <host> -Plugins "<id,id>" -Prerequisites FromPlugins -AcceptPlugins`
- **GitHub Copilot desktop app (`CopilotApp` — MANDATORY step-by-step confirmation!):**
  Because `ghapp://` prompts open asynchronous in-app dialogs and exit `4`
  immediately while the user is still clicking in the UI, **never jump ahead to
  environment connection while marketplace or plugin dialogs are unconfirmed!**
  Execute in strict confirmed steps:
  1. **Add marketplace first & WAIT:** after user approval, run
     `.\Setup.cmd -NonInteractive -PluginHost CopilotApp -MarketplaceOnly -Prerequisites FromPlugins -AcceptPlugins`
     (triggers `ghapp://plugins/marketplace/add?source=microsoft%2Fpower-platform-skills`).
     **Immediately pause with `ask_user`** asking the user to click **Allow -> Add**
     in the Copilot app until `✓ Added power-platform-skills marketplace` appears
     (or let them say the marketplace was already added).
  2. **Open each selected plugin prompt one by one & WAIT:** only AFTER the user
     confirms the marketplace is added, if plugins were selected, trigger **one
     plugin at a time** with `-SkipMarketplace`:
     `.\Setup.cmd -NonInteractive -PluginHost CopilotApp -Plugins "<single-id>" -SkipMarketplace -Prerequisites FromPlugins -AcceptPlugins`
     (triggers `ghapp://plugins/install?source=<single-id>%40power-platform-skills`
     directly in the Copilot app, and include the clickable launch link in chat
     as fallback). **Pause with `ask_user` after each plugin** so the user confirms
     installing that plugin in the Copilot app before you open the next plugin's
     modal—and confirm all selected plugins appear under **Customize > Installed**
     before moving to Step 4!
- **VS Code without CLI**: guide the user through **Customizations > Browse >
  Configure Marketplaces > Add Marketplace... > `microsoft/power-platform-skills`**
  to install their chosen plugins, and wait for their confirmation before Step 4.

Never choose every plugin by default, configure an unselected CLI, install an
agent host, or run the broad remote `install.js` installer.

### Step 4: continue with the connection skill (ONLY after Step 3 is confirmed!)

**Hard gate:** do **not** ask *"Do you want to connect to a Power Platform
environment now?"* or initiate `power-platform-connect` until the marketplace
and all approved plugins from Step 3 have finished installing (for `CopilotApp`
or VS Code UI, until the user explicitly confirms they completed the in-app
plugin installations or chose to skip them).

When Step 3 is complete and the request includes connection onboarding, read
`skills/power-platform-connect/SKILL.md` from this same repo and follow it;
the user need not paste a second setup prompt. If the user asked only for
installation, ask whether they want to connect before initiating this stage.
The skill file can be read directly; a personal copy is optional and still
requires its own installation approval.

Connect **only the surfaces relevant to the user's chosen plugins**. If their
selective setup intentionally omitted `pac` (for example `power-automate`,
`process-intelligence`, `canvas-apps`, or `code-apps-preview`), do **not** run
`pac` commands or assume PAC is installed: guide the relevant surface instead
(such as scoped `az login` for Azure-backed plugins, Studio coauthoring for
Canvas Apps, or `pa` sign-in during Code Apps work), or obtain separate
prerequisite install approval first if they want PAC environment discovery.
When PAC is part of their setup, confirm the host, sign-in identity and tenant,
let the connection skill reuse/sign in to PAC in an approved exact environment
context, run `pac env list`, present returned environment names/URLs, and keep
manual entry of another existing URL available. Discovery approval is not
approval to configure all returned environments. Confirm each selected target,
nickname and tools as the connection skill requires. Reuse supplied details
without asking again, but never infer a tenant from the active profile.
Ask before additional software, profile changes, private binding records,
authentication, MCP registration/startup and bounded live identity checks.
Do not install Dataverse CLI just because its plugin was selected; check first
and ask only when the selected connection needs it and it is missing.

Read the installed `dv-overview` / `dv-connect` resources through their supported
locations when needed. If an installed plugin's `PreToolUse` file-write hook
(such as `model-apps@power-platform-skills`) fails on Windows with `"hook
errored"` when saving `%USERPROFILE%\.copilot\mcp-config.json` or the private
connection record, do not silently work around it: tell the user which plugin's
hook errored so they can temporarily toggle that plugin off under **Customize >
Installed**, retry the approved write, and toggle the plugin back on afterward.
If freshly installed plugin resources or callable MCP
tools are not available in the current host, use the pause/resume procedure
below. Reading an instruction file is not proof that its MCP tools are loaded.
Do not duplicate the connection skill's auth implementation or invent tokens,
OAuth flows, client IDs, server commands or host configuration locations.

### Restart and resume only at a real boundary

Do not require a separate chat merely to move from tools to marketplace to
plugin selection. However, **do not promise zero restarts**: changed PATH,
new plugin discovery, new MCP registration, a host-close requirement or a
Windows reboot can require a pause. A new chat alone may not reload MCP servers;
use the actual selected host's documented reload/restart mechanism.

Before any required pause, list completed stages, the chosen host, selected
plugin IDs and the next pending action. For multiple connection targets,
include their local nicknames and per-target pending/verified state, not their
private identity/URL details. Do not close the app for the user.
Give a copyable, filled-in resume prompt shaped like:

> Continue guided Power Platform onboarding from the same extracted repo.
> Read `AGENTS.md` and `skills/power-platform-setup/SKILL.md`.
> My chosen host is Copilot CLI. Prerequisites and the official marketplace
> are ready; the selected plugins are dataverse and model-apps.
> I have restarted the host. Verify what is present without reinstalling
> working components, then continue with power-platform-connect.
> Confirm the target and ask before sign-in, configuration changes or live checks.

Replace the example host/plugins/stage with the actual situation. Include
no email, tenant/environment IDs or URLs, local cache paths, tokens or passwords
in a generic handoff. Do not claim that earlier approvals authorize new actions
after a resume. Once MCP is loaded, complete the connection skill's approved
post-restart identity verification rather than stopping at "definition saved."

Ask which existing host the user wants if it is not already clear:

| Chosen host | Script host value | Plugin route |
|---|---|---|
| Claude Code, including a supported local desktop Code tab | `ClaudeCode` | Existing `claude` command; install for the user. Ordinary Claude chat/Cowork is not this host. |
| Copilot CLI | `CopilotCli` | Existing `copilot` command; install for that host. |
| Copilot desktop app without a CLI command | `CopilotApp` | Official app links; guide the user through marketplace/plugin confirmations. This part is not unattended. |

Use the **chosen host**, not whichever CLI happens to be found first. If both
CLIs exist, do not configure both unless the user separately requests both.
Never install a CLI/another host as a shortcut for the desktop app.

The official quick installer's CLI dependency is **not a requirement to use
skills/plugins in an IDE or app**. If the user means **VS Code Copilot agent
mode**, do not label it Copilot CLI or pass an invented `VSCode` host flag.
The current script's plugin host values cover the three routes above; use the
integration skill's documented native VS Code marketplace path for that IDE
instead. Copilot desktop confirmation links do not install plugins in VS Code.

**A command on PATH can be an install launcher, not the full CLI.** The
`Install GitHub Copilot CLI? [y/N]` message means it is not ready for plugin
management yet. Do not silently answer `y`, start an AI session, or infer
readiness from `Get-Command` alone. Inspect supported local installation
metadata first; if readiness is uncertain, explain that before invoking the
script's CLI plugin route. A listing/verification failure must not be reported
as a successful installation.
The script's interactive host summary is passive: CLI commands and the `ghapp`
URL registration are candidates, not runtime proof. If the selected command is
missing, exit `2` prints the official host-installation handoff. Let the user
complete that separate step, reopen, and resume; do not install another host.

If the user has only Copilot desktop, explain the two choices before plugin
setup: proceed with **CopilotApp** confirmation links (no additional host
needed), or pause while the user independently installs the optional CLI using
[GitHub's official instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli).
Do not install that host for them under prerequisite/plugin approval. If they
choose to install it themselves, explain its current requirements and policy,
then recheck readiness before proposing **CopilotCli**. If they decline, continue
with approved **CopilotApp** links rather than abandoning installation or
pretending the terminal route is available. If no suitable desktop app is
available either, report that prerequisite and keep the remaining setup pending.

CLI download/installation and plugin-management subcommands do not themselves
submit an AI prompt. Using the CLI's agent/model features and this guiding
chat can consume the user's AI allowance and requires the appropriate
plan/authentication and organizational policy. Do not open a CLI AI session
just to install plugins, promise unlimited/free AI usage, or purchase credits.

Collect separate approvals one decision at a time, then run only the approved
flags. Pass `-Prerequisites FromPlugins` when the user chose specific plugins
or marketplace-only preparation so unselected core installers are skipped; use
default `-Prerequisites All` only when they chose the full 5-tool workstation
setup. `All` for `-Plugins` is only for an explicitly approved standard full
set; Dataverse requires an explicit `dataverse` ID in `-Plugins` or requested
`-IncludeDataverse`. For a plugin-only follow-up with ready prerequisites, omit
`-Install -Accept`; `-NonInteractive -PluginHost <host> -Plugins "id,id"
-Prerequisites FromPlugins -AcceptPlugins` checks only the tools those plugins
require and stops if one is missing instead of installing unapproved software.

Omit an optional stage's host and
acceptance flags when not requested; noninteractive setup skips it. If the
user approves stages later, run another scoped invocation **in this same chat**;
the script rechecks/skips compatible existing tools. Never invent consent just
to make a combined command possible.

Stop on an actual failure or restart requirement. An app-close requirement may
also need a handoff: do not close the app hosting the current chat without
explaining that it ends the session. If necessary, give the reviewed approved
setup command to run in a separate terminal while that app is closed, then
resume after reopening. Do not promise zero interruptions from Windows/UAC.

When installation is complete, explain pending desktop confirmations and host
discovery. Continue to Step 4 if requested and the necessary capabilities are
available; otherwise give the restart/resume handoff. Never run authentication
under installation approvals.

## Checks and separate approval gates

1. Read the repository's `AGENTS.md`, `README.md`, and `Setup.ps1`. Obtain the full
   source if it is not already available locally. Do not run unreviewed downloads.
2. Confirm the intended host and whether the user wants specific Power Platform
   plugins, marketplace-only preparation, or the full 5-tool workstation setup.
   Run `.\Setup.cmd -CheckOnly` with `-Plugins "<id,id>" -Prerequisites FromPlugins`
   (or `-MarketplaceOnly -Prerequisites FromPlugins`, or plain `-CheckOnly` for
   the full bundle). Use `-SkipAzureCli` only when the user explicitly opts out
   of Azure CLI. This mode is offline, read-only and CLI-free.
   Use the same launcher on x64 and ARM64 Windows 11; it detects native Windows
   architecture even in an emulated terminal. Explain any existing emulated
   tools and x64 Azure CLI emulation shown in the plan. Do not replace
   the script with ad hoc architecture-specific installation commands.
3. Summarize the resolved prerequisite plan and ask the user to explicitly
   approve installing the missing/unsupported tools and accepting their licenses.
4. After approval, run `.\Setup.cmd -Install -Accept -NonInteractive` with the
   same approved `-Plugins` / `-Prerequisites` / `-SkipAzureCli` scope. This
   still permits Windows UAC to require human action.
5. Respect exit codes, stop on failure/restart requirement, and explain any
   terminal/Copilot restart needed. Report binaries, desktop plugins, and
   authentication separately.
6. For Power Platform plugins or marketplace preparation, use the doctor flow.
   Obtain separate approval for `ClaudeCode`, `CopilotCli`, or `CopilotApp` and
   the actual selection, then run with `-PluginHost <host>` plus
   `-Plugins "id,id" -Prerequisites FromPlugins -AcceptPlugins` (or
   `-MarketplaceOnly -Prerequisites FromPlugins -AcceptPlugins`). Dataverse is
   opt-in by explicit ID or `-IncludeDataverse`. CLI hosts must already be on
   PATH; no new host is installed. The `CopilotApp` route prints official
   confirmation links for only the requested marketplace/plugins and returns
   `4`, meaning pending user action, not verified installation. Do not retry
   installations solely because the app handoff returns that code.
7. For Copilot Studio MCP, obtain independent approval for the chosen host and
   append `-CopilotStudioHost <host> -AcceptCopilotStudio`. The script saves the
   launch command but does not start the server; the package downloads/caches
   at the host's first launch. Do not run `npx` standalone or claim runtime/auth
   readiness from a saved JSON entry.
8. Use `skills/power-platform-doctor/SKILL.md` for CLI plugin choices and
   `skills/power-platform-integrations/SKILL.md` for manual/native routes or
   agent-guided MCP setup. Reuse existing registrations.
   Stop on configuration conflicts; keep any local backup private.
9. For connection onboarding requested in the starting prompt or afterward,
   continue with `skills/power-platform-connect/SKILL.md` as a separately
   approval-gated stage. Installation approval never authorizes authenticating, selecting a
   tenant, or inspecting that tenant's data.
   To make that skill available locally first, obtain approval for
   `-ConnectionSkillHost <host> -AcceptConnectionSkill` in the final setup stage.
   This copies instructions only. It is not required to read the bundled file
   and does not authorize onboarding; use the independently requested Step 3
   flow and its target/approval checks.

## The official quick-install command is an alternative, not another stage

On Windows, `curl.exe` is the native curl program; plain `curl` can resolve to
PowerShell's `Invoke-WebRequest` alias. For a reviewed PowerShell download,
`Invoke-WebRequest -UseBasicParsing` avoids HTML-parsing prompts. Neither
download command installs a plugin by itself.

The official remote `install.js` command targets existing Claude Code/Copilot
CLI installations; it is not a universal Copilot desktop installer. It can
configure both detected CLIs, install/update prerequisites, and enable plugin
auto-updates. This skill uses Setup.cmd's scoped host commands instead.
Do not append `curl.exe ... | node ...` or the downloaded installer as another
required step: that can repeat/broaden changes already approved for Setup.cmd.
If the user explicitly chooses the official broad installer as an alternative,
follow the integration skill's review/approval rules before execution.

Never install Copilot CLI/another agent host, enable auto-approval, change
persistent execution policy, blindly run the broad marketplace installer, sign
in or select a profile without the confirmed target and separate approval,
or create cloud resources. The integration skill can
use supported commands on an already available CLI or documented shared MCP
configuration; it must not install another host. Never infer plugin or auth
readiness from the presence of executables.
