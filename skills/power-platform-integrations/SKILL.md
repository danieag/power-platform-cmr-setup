---
name: power-platform-integrations
description: After explicit approval, guide Power Platform plugin setup for an existing Claude Code or Copilot host, including optional Dataverse and official Copilot desktop links, and separately register Copilot Studio MCP for the Copilot desktop app.
---

# Power Platform integrations

Use this skill when the user asks to install Power Platform Skills/plugins,
include Dataverse, add Copilot Studio MCP, or finish the integration stage after
the local prerequisites. Perform the approved work with tools; do not merely
give the user commands to copy unless a genuine permission or capability
blocker prevents execution.

This is **stage two**, not a second prerequisite installer. Read the current
`README.md` and `AGENTS.md` in
<https://github.com/danieag/power-platform-setup> first. Do not execute anything
when the user only asks for an explanation or readiness check.

For an existing **Copilot CLI or Claude Code CLI**, README Step 2's
`skills/power-platform-doctor/SKILL.md` is the front door for asking which
plugins the user wants, inspecting that host, and approving the exact selection.
Reuse this skill for native app/IDE routes and separately approved MCP setup.

This stage belongs in the **same guided installation chat** as prerequisite
setup. Use `power-platform-setup`'s combined invocation when those stages are
already approved, or run a scoped follow-up here. Do not send the user to a new
chat to paste a second, broad plugin installer. A new host process/chat is for
loading installed capabilities and separately approved connection onboarding
after installation, not an extra plugin-install requirement. Actual failures,
reboot requirements or a required closure of the current host can interrupt
the flow; explain them rather than silently continuing.

## 1. Inspect, explain, approve

- Run the repository's `.\Setup.cmd -CheckOnly` first. Do not treat its exit 1
  (missing/unsupported tools) as permission to install them; use the prerequisite
  skill only after approval. Keep this check offline and read-only.
- Setup preserves compatible **Node 22.18+ (22.x), 24 or 26** with npm 10+;
  new installations still use **Node 24 LTS**. Read the
  [current package instructions](https://www.npmjs.com/package/@microsoft/copilot-studio-mcp)
  before configuring Copilot Studio MCP; bootstrap compatibility does not
  guarantee that every package version supports every accepted Node version.
- Confirm which integrations the user wants: selected Power Platform plugins,
  Dataverse (explicit opt-in), Copilot Studio MCP, or the combination.
  Explain downloads, user configuration changes, and later app reload/sign-in.
  Obtain approval for the actual plan, separately from prerequisite approval.
- Determine the configuration scope and discover an **already available**
  `claude` or `copilot` executable for the user's chosen host with
  `Get-Command -CommandType Application`. Ordinary Claude chat/Cowork is not
  Claude Code. Do not silently configure both hosts if both are found. Do not
  install Copilot CLI, start a different agent host, search private app internals
  for undocumented binaries, or modify PATH to make one appear.
  `Get-Command` is discovery only: a command can be a first-run install launcher.
  If it offers to install the CLI, do not answer for the user or call it ready.
  Follow the setup skill's optional user-installed-CLI/desktop-link decision
  before running a CLI installation stage.
- Inspect only the relevant existing plugin/server definitions. Do not print,
  upload, commit, or log full user configuration: other entries can hold tokens.
  Preserve unrelated definitions and organization policies. Do not start a
  server, authenticate, or query a tenant to check whether a definition exists.

GitHub documents that skills and MCP servers configured for repositories or
Copilot CLI are available in the desktop app. This does **not** make every
CLI-installed plugin component desktop-compatible. Verify desktop visibility
separately before calling the integration ready.

## 2. Install Power Platform plugins

The official marketplace is
<https://github.com/microsoft/power-platform-skills>.

**Copilot in VS Code is not Copilot CLI.** Its agent mode can use compatible
skills/plugins without a `copilot` terminal program. When VS Code is the user's
intended host, use its native, separately approved marketplace flow rather than
the script's Copilot desktop links or an invented `-PluginHost VSCode`:
**Chat: Manage Plugin Marketplaces > Add Marketplace...**, enter
`microsoft/power-platform-skills`, then **Customize > Browse > Install** for the
selected plugins. Use supported UI tools if available; otherwise guide the user.
See [GitHub's VS Code instructions](https://docs.github.com/en/copilot/how-tos/copilot-in-your-ide/customize-copilot/extend-copilot-with-tools-and-context/using-plugins).
Do not install another agent host just to drive that marketplace. Plugin
components/policies can differ by surface, so verify the actual IDE capabilities.
An equivalent user-verified route is **Customizations > Browse > All Sources
dropdown > Configure Marketplaces > Add Marketplace...**; enter the repository,
press **Enter**, then select **power-platform-skills** and install the chosen
plugins. Refer to the README screenshots when helpful. Adding the source only
exposes the catalog; it does not install every plugin.
If the IDE reports missing Git, distinguish an absent installation from stale
inherited PATH before suggesting installation. A successful absolute-path
`git.exe --version` proves the binary exists; if reloading saved Windows PATH
fixes command resolution, relaunch the IDE from that refreshed environment.
Do not delete/reinstall working Git or change installation directories as a
substitute for refreshing the app's environment.

Setup.cmd now offers the reviewed plugin set after prerequisites are ready.
For that set, prefer its shared implementation after approval, choosing **one**
host rather than duplicating the installation logic in an agent:

```powershell
.\Setup.cmd -Install -Accept -NonInteractive -PluginHost ClaudeCode -AcceptPlugins
.\Setup.cmd -Install -Accept -NonInteractive -PluginHost CopilotCli -AcceptPlugins
.\Setup.cmd -Install -Accept -NonInteractive -PluginHost CopilotApp -AcceptPlugins
```

These examples select the standard full set. For the doctor's individual
choices use `-Plugins "id,id"` instead, as below. Dataverse requires an explicit
`dataverse` ID or `-IncludeDataverse`, only when approved. `-Accept` and `-AcceptPlugins` are
separate decisions. If prerequisites are already ready, they are skipped.
If optional MCP and connection-skill installation were also approved, append
`-CopilotStudioHost <host> -AcceptCopilotStudio` and
`-ConnectionSkillHost <host> -AcceptConnectionSkill` to the same invocation.
Ask before selecting a different host for a stage; no host is inferred from
the presence of another installed CLI.
`CopilotApp` prints official marketplace/plugin links; exit `4` requires the
user to open/confirm them in the desktop app. It is not a failed prerequisite
install or proof that any plugin was installed. Do not automatically launch
browser sign-in or claim app availability from a link.

For **custom subsets**, prefer the same script implementation after approval.
When prerequisites are ready, choose **one** plugin-only example and replace
its IDs with the actual approved choices:

```powershell
.\Setup.cmd -NonInteractive -PluginHost CopilotCli -Plugins "dataverse,model-apps" -AcceptPlugins
.\Setup.cmd -NonInteractive -PluginHost ClaudeCode -Plugins "dataverse,model-apps" -AcceptPlugins
```

Omitting `-Install -Accept` prevents a missing prerequisite from being installed
under plugin-only approval. Empty/unknown selections fail rather than falling
back to all plugins. Do not run both host commands or a second broad installer.
`Setup.ps1` verifies the official marketplace and plugin identities, preserves
an existing enabled external Dataverse installation, and uses Claude's explicit
user scope. Do not launch an agent conversation just for management commands.

Read command help when the installed version differs from the documented
interface. Check every exit code. Skip an existing matching marketplace/plugin
after inspecting it; an error containing "already" is not sufficient proof of
success. Do not uninstall, overwrite a different source, or force-update a
working plugin without approval. Do not enable auto-approval or auto-update as
an unrequested side effect.

The official quick installer (`node install.js --include-dataverse`, or the
remote download piped into `node - --include-dataverse`) is an **alternative**
for supported CLI hosts, not something to run after Setup.cmd's plugin stage.

It is a **different, broad installer**: it detects Copilot CLI/Claude Code, can
configure both if present, installs the marketplace's selected plugin set, may
install/update PAC, attempts Azure CLI installation when absent, and enables
auto-update. It is not a desktop-only installer.
Do not run it blindly or delete a pre-existing `install.js`. Prefer scoped
commands above so the approved host, plugins, and settings are explicit.
If the user specifically requests that broad installer, explain its current
effects, inspect the downloaded code in a new temporary directory, and get
approval for those effects; do not silently substitute it for this plan.
On Windows use `curl.exe` rather than the ambiguous `curl` alias, or
`Invoke-WebRequest -UseBasicParsing`, to download for review. Do not overwrite
or delete a pre-existing file, pipe unseen code into Node, or assume successful
execution proves plugin/runtime readiness. `--include-dataverse` adds the
plugin, not a guaranteed global installation of the separate Dataverse CLI.

If no supported plugin-management executable is available, **do not install
another host as a workaround**. Use documented desktop controls, or guide the
user through them if UI automation is unavailable:

For the Copilot app, prefer the official marketplace/plugin confirmation links
printed by `-PluginHost CopilotApp` or listed in the marketplace README.
Those links do not install a CLI or bypass app approval. The manual fallback is:

1. **Customize** > marketplace settings beside the marketplace dropdown:
   add `microsoft/power-platform-skills`.
2. Find each approved plugin in **Customize**, then **Install**.
3. Confirm it appears under **Installed**.

Do not copy only skill folders and claim a full plugin was installed: plugins
can also contain agents, hooks, and MCP configuration.

## 3. Register Copilot Studio MCP

The package is <https://www.npmjs.com/package/@microsoft/copilot-studio-mcp>.
Its launch command is `npx -y @microsoft/copilot-studio-mcp@latest`.
The MCP host starts it over stdio when needed. Running that command alone in a
terminal is **not** registration, and can leave an unused long-running process.

The normal setup path is now the script's **separately approved** MCP stage:

```powershell
.\Setup.cmd -Install -Accept -NonInteractive -CopilotStudioHost CopilotApp -AcceptCopilotStudio
```

Choose `CopilotCli` or `ClaudeCode` instead when appropriate. Approve only the
intended host, not all three. The script rechecks prerequisites, reuses matching
user definitions, rejects conflicts, and verifies the saved configuration
without launching a server or invoking tenant tools. Copilot hosts share the
documented user config; Claude Code uses its existing user-scope MCP command.
Keep local config backups private; never commit them or attach them to a report.
Custom host config directories require explicit manual review rather than
guessing their location. Prerequisite/plugin approval is not MCP approval.

The script does not pre-download or start the npm server: its output must say
**configured, not runtime-verified**. The first launch by the selected host
downloads/caches `@latest` and may request trust/sign-in separately.
Do not invoke `/mcp auth` in a desktop-hosted conversation.

For a separately approved custom setup outside the normal script path, these
documented command/configuration details are reference only; do not bypass the
script's conflict detection by overwriting a definition it refused to change:

```powershell
copilot mcp add copilot-studio -- npx -y @microsoft/copilot-studio-mcp@latest
```

**No CLI executable is required for the documented configuration-file route.**
With explicit approval for user scope, merge this single server definition
into `%USERPROFILE%\.copilot\mcp-config.json`:

```json
{
  "mcpServers": {
    "copilot-studio": {
      "type": "local",
      "command": "npx",
      "args": ["-y", "@microsoft/copilot-studio-mcp@latest"],
      "tools": ["*"]
    }
  }
}
```

This is the desired **entry shape**, not permission to replace the whole file.
If editing:

- Stop on invalid/unsupported JSON; never replace it with an empty default.
- Read the live file, preserve all unrelated keys/entries and existing access
  controls, and keep a protected local recovery copy if a file already exists.
  Never print that copy or include it in a repository or release ZIP.
- Re-read before writing; if another process changed the file, merge from the
  new live content rather than overwriting it. Write atomically and confirm the
  target entry without exposing other configuration.
- If safe merging or permissions cannot be established, stop and use the app's
  **Customize > MCP > add a custom server** flow instead. Report the exact
  remaining step; do not claim registration succeeded.

Use **user scope** for this general developer setup. A requested project-only
setup needs that app version's documented repository-customization flow; do
not invent a repository config schema or turn a local setting into a committed
change without explicit approval.

`tools: ["*"]` exposes the server's advertised tools; it does **not** authorize
executing them or enable agent auto-approval. Using `@latest` means the first
launch can download/cache the current package and future launches can receive
new versions. Explain that behavior before approval; an organization can instead
approve a specific published version after checking its requirements.

## 4. Verify registration, then hand off sign-in

- Confirm only the intended marketplace/plugins and MCP definition changed.
  Treat package download, registration, tool discovery, authentication, and
  environment access as distinct states.
- Refresh/restart the desktop session if necessary. Check **Customize >
  Installed** and the actual available skills/tools. A CLI plugin listing or
  JSON entry alone proves configuration, not desktop runtime readiness.
- Launching the configured MCP server may require user trust/permission. Do
  not run cloud tools as a smoke test, initiate sign-in, select an environment,
  or access tenant data under installation approval.
- When the user is ready to authenticate, follow the desktop app's sign-in
  action for this server. Account/environment/connector setup is separate and
  may require additional permissions. For reusable CLI profiles and coordinated
  authentication, hand off to
  [power-platform-connect](../power-platform-connect/SKILL.md) after separate
  target/sign-in approval. Do not start that workflow merely because installation
  completed. Never collect credentials or log tokens.
- Report completed actions and precise blockers. If visibility/launch has not
  been confirmed, say **configured, not runtime-verified** rather than "ready".
  Do not retry an uncertain installation/write without inspecting its result.

## Verified documentation

Recheck these contracts when the app or package changes:

- [Desktop customization and shared skill/MCP configuration](https://docs.github.com/en/copilot/how-tos/github-copilot-app/customize-github-copilot-app)
- [MCP terminal commands and configuration-file format](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers)
- [Power Platform marketplace and installer source](https://github.com/microsoft/power-platform-skills)
- [Copilot Studio MCP package](https://www.npmjs.com/package/@microsoft/copilot-studio-mcp)
