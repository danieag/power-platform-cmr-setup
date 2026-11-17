# Detailed setup guide

[Back to the simple guide and screenshots](../README.md)

This reference covers the install policy, all command-line options,
authentication boundaries, troubleshooting, and contributor tests.
Run commands below **from the extracted repository root**, not this `docs` folder.

- [Supported PCs](#supported-pcs-and-current-limitations)
- [Tool installation and sources](#what-gets-installed)
- [Power Platform plugins](#step-2-choose-power-platform-plugins)
- [Copilot Studio MCP](#step-3-optional-copilot-studio-mcp-registration)
- [Connection skill installation](#step-4-install-the-optional-connection-skill)
- [Sign-in and persistent connections](#step-5-connect-and-remember-sign-in-optional-skill)
- [Exit codes and troubleshooting](#exit-codes-and-troubleshooting)
- [Tests and packaging](#validate-and-create-a-shareable-zip)

### Supported PCs and current limitations

> **Initial release status:** syntax and non-installing regression tests are
> automated. A complete installation on a pristine Windows Sandbox has **not**
> been verified. The same script supports **x64 Windows 11 / Windows 10 22H2**
> and **ARM64 Windows 11**, with 64-bit Windows PowerShell 5.1 or PowerShell 7.
> ARM64 Windows 10 and 32-bit Windows/processes are rejected. Use a
> vendor-supported Windows version; Windows 10 support/security servicing is
> your responsibility.

**User-reported ARM64 Sandbox acceptance:** Git, Node.js/npm, .NET 10 SDK and
PAC were installed/verified as ARM64; Azure CLI was installed/verified as x64
under emulation. The desktop plugin stage printed links (exit `4`, no plugins
installed). Copilot Studio MCP and the connection skill were saved, but app
discovery and live sign-in were not verified. That run cleared an explicitly
default `COPILOT_HOME` to work around an older setup bug; the corrected script
now accepts the default without requiring that workaround. This is evidence
for those reported stages, not full acceptance of every current feature.

**Intel/AMD x64 or ARM64: use the same Setup.cmd.** No separate ARM script,
architecture flag, or special skill is needed. Setup reads the native Windows
architecture from the machine registry, even if the terminal is running under
emulation, and prints the selected architecture before approval.

| Tool | New install on x64 | New install on ARM64 Windows 11 |
|---|---|---|
| Git | Official x64 installer | Official native ARM64 installer |
| Node.js/npm | Official Node 24 x64 MSI | Official Node 24 native ARM64 MSI |
| .NET 10 SDK | Official x64 SDK installer | Official native ARM64 SDK installer |
| PAC | .NET global tool using the selected SDK host | Same package; native ARM64 shim when using the native SDK |
| Azure CLI | Official x64 MSI | Official **x64 MSI under Windows 11 emulation**, not a native ARM64 package |

Compatible existing x64/x86 tools are preserved on ARM64 and run using
[Windows 11's built-in emulation](https://learn.microsoft.com/en-us/windows/arm/apps-on-arm-x86-emulation).
Executable architectures are read from file headers without running the tools.
PAC's shim must match the selected .NET host; a mixed ARM64/x64 installation
must not be treated as ready just because both version numbers look correct.
An emulated x64 SDK/PAC pair can remain in place; a fresh installation uses the
native SDK and PAC shim. No emulation software or Windows feature is installed.

The Azure CLI emulation path is explicitly shown in the default ARM64 plan.
A user-reported ARM64 Sandbox run verified installation and `az version` under
emulation. Other Windows images and current vendor versions still require
their own acceptance; setup verifies `az version` after installation and stops on failure.
Native package availability does not guarantee every Power Platform plugin or
workflow supports ARM64.

### Step 1: download, extract, and run Setup.cmd

1. On [this repository](https://github.com/danieag/power-platform-setup), choose
   **Code > Download ZIP**. Extract **all** files to a folder you can find.
   Do not run `Setup.cmd` from inside the ZIP or download just the launcher.
2. Read this page and review `Setup.ps1`, then double-click **Setup.cmd**.
   Start as your normal user, **not** "Run as administrator".
3. Setup checks local files and shows what is missing. Type **INSTALL** only
   if you approve the displayed plan and the vendors' software licenses.
   Anything else cancels without downloading or installing anything.
4. Approve Windows administrator prompts only for the expected Node.js,
   Microsoft .NET SDK, or Microsoft Azure CLI installer.
   If setup requests a restart, save your work, restart yourself, and run it again.
5. After prerequisites succeed, the same window offers
   [step 2: Power Platform plugins](#step-2-choose-power-platform-plugins).
   Choose your existing host, review the separate plan, and type `PLUGINS` to
   approve, or press Enter to skip. Restart your host/terminals afterward.
   The next optional stage offers Copilot Studio MCP registration; it needs
   separate `MCP` approval. Sign-in remains separate and is not started by setup.

Internet access is needed **only after installation approval**. Setup does not
need `winget`, Git, npm, or .NET to start. This is important in Windows Sandbox,
where `winget` is often absent. Enabling or creating Sandbox is outside scope;
its filesystem is normally discarded when you close it.

The launcher and an agent both use the same `Setup.ps1`; there is no second
installation implementation.

### Check without changing anything

Open PowerShell in the extracted folder:

```powershell
.\Setup.cmd -CheckOnly
```

Or, when your execution policy permits local scripts:

```powershell
.\Setup.ps1 -CheckOnly
```

Check-only reads native Windows architecture, local executable version metadata
and PE architecture headers, npm's package manifest, SDK directories, and
Azure CLI's Windows uninstall registration and bundled Python
architecture.
It **does not execute any CLI** (including plugin commands), open app links,
download files, write diagnostics, alter PATH,
change Windows features/policies, sign in, or contact a tenant. It reports
**local installation readiness**, not a guarantee that every installed binary,
plugin, network connection, or account works. Output includes local paths;
review/redact these before posting it publicly.

### Let an agent use the repository

Open the extracted repository in the Copilot desktop app, or point an agent to
this public repository and ask it to download/review it first:

> Read AGENTS.md in https://github.com/danieag/power-platform-setup. Run the
> check-only setup, explain the plan, and ask me before installing anything.
> Do not install Copilot CLI, configure auto-approval, or sign in to a tenant.

After the user has explicitly approved the actual plan, an agent can use:

```powershell
.\Setup.cmd -Install -Accept -NonInteractive
```

`-Accept` accepts the selected installers and their licenses; it is **not**
authorization to change plugin settings, sign in, or access an environment.
`-NonInteractive` suppresses the script's approval prompt, **not Windows UAC**.
An unattended process without a usable UAC session will fail rather than bypass
Windows security. Agents must not add `-Accept` without user approval.

### One starting prompt for guided onboarding

The [README Alternative B prompt](../README.md#alternative-b-use-your-coding-agent)
loads the bundled [setup entry skill](../skills/power-platform-setup/SKILL.md).
It coordinates the existing script, doctor and connection skill:
**prerequisites > approved marketplace registration > plugin choices and
approval > separately approved connection onboarding**. Do not require the
user to manually find/invoke each skill. One starting prompt is not one
approval, and no new agent host is installed.

The setup and integration skills should **execute the approved stages in the
same installation chat**, not stop at prerequisites and send the user elsewhere
to paste a plugin-installer one-liner. Only the chosen host is configured:
`ClaudeCode` uses an existing `claude` command, `CopilotCli` uses an existing
`copilot` command, and `CopilotApp` prints official app confirmation links.
Ordinary Claude chat/Cowork is not Claude Code, and the presence of a CLI does
not mean the user chose that host.

`Get-Command copilot` alone is not proof of a usable CLI: some systems have an
install launcher that displays `Install GitHub Copilot CLI? [y/N]`. The setup
skill must not accept that prompt, call it a ready CLI, or start a model session.
Use approved local installation metadata to assess readiness; an ambiguous or
failed command is not permission to install another host. A desktop user can
choose app links immediately or independently install the optional CLI from
[GitHub's official instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli)
before readiness is checked again. If they decline the optional CLI, the skill
can continue with separately approved desktop links instead. This is agent
guidance, not a new automatic CLI installer inside Setup.ps1.

CLI binaries and plugin-management commands do not themselves submit AI prompts.
AI agent use, including a chat guiding setup, can consume the user's allowance
and requires the applicable plan/authentication/policy. Do not promise unlimited
AI usage, buy credits, or open a model session as an installation check.

After each relevant approval, flags can be combined in one invocation. For
example, when the user has approved all four installation stages for the
Copilot desktop app:

```powershell
.\Setup.cmd -Install -Accept -NonInteractive `
    -PluginHost CopilotApp -AcceptPlugins `
    -CopilotStudioHost CopilotApp -AcceptCopilotStudio `
    -ConnectionSkillHost CopilotApp -AcceptConnectionSkill
```

Use `ClaudeCode` or `CopilotCli` consistently instead for that selected host.
Add `-IncludeDataverse` only when requested. An omitted optional stage is skipped
in noninteractive mode; if approved later, a scoped rerun in the same chat is
fine. No flag grants sign-in/tenant access. Exit `4` still means desktop plugin
confirmations are pending even if MCP/skill files were saved.

This is not a promise that Windows can never interrupt the session. Stop on
installer errors/restart requirements, and explain if the selected host must
be closed for a configuration change. Do not close the app hosting the active
agent conversation without a handoff; an approved external-terminal step may
be necessary. After PATH changes, reopen the host before connection work.
Otherwise continue the requested flow in the same conversation when its
required capabilities are available. If newly installed plugins/MCP tools need
a reload, give a filled-in resume prompt with completed stages and selected
host/plugin IDs, not emails, tenant/environment IDs, URLs or token/cache data.
A new chat alone may not restart MCP processes. Do not claim runtime discovery
or reuse across a restart until actually verified in the intended host.

**Azure CLI is included by default, after PAC CLI.** The full plugin set includes
Azure-dependent workflows (Power Automate, Process Intelligence, and PCF
verification/inventory), so no extra Azure flag is needed. It still requires
approval as part of the displayed prerequisite plan and never runs `az login`.

For an intentionally minimal setup without those workflows, use `-SkipAzureCli`
on **both** the check and install commands:

```powershell
.\Setup.cmd -CheckOnly -SkipAzureCli
.\Setup.cmd -Install -Accept -NonInteractive -SkipAzureCli
```

Skipping Azure can leave Azure-dependent plugins without a required runtime
tool even if their plugin installation succeeds. The old `-IncludeAzureCli`
flag remains accepted for compatibility but is no longer necessary; do not
combine it with `-SkipAzureCli`.

The optional [prerequisite skill](../skills/power-platform-setup/SKILL.md) contains
these same instructions. Noninteractive runs do not silently opt into the new
plugin stage: use the separate flags below only after approval. The
[integration skill](../skills/power-platform-integrations/SKILL.md) can guide
plugin setup or register Copilot Studio MCP. Skills instruct the agent to
execute approved work; they are not just command lists for the user to copy.

A GitHub URL does not itself install a skill. Load/copy the skills only using a
mechanism supported by your app version, or let the agent read them directly.
No personalized skills, MCP endpoints, or account settings are bundled.

## What gets installed

Compatible tools are left alone. Missing/unsupported tools are handled in this
order; Azure CLI is included by default and comes after PAC:

| Order | Tool | Preserved when | If setup is needed |
|---|---|---|---|
| 1 | Git for Windows | Version 2.40+ with a compatible executable architecture | Current stable native x64/ARM64 Git installer, current-user program directory |
| 2 | Node.js and npm | Node **22.18+ (22.x), 24 or 26**, bundled npm 10+, compatible executable architecture | Current **24 LTS** native x64/ARM64 MSI, machine-wide |
| 3 | .NET **SDK** | Stable **10.0** SDK files and a compatible SDK host present | Current stable .NET 10 native x64/ARM64 SDK installer, machine-wide |
| 4 | Power Platform CLI (PAC) | Recognized PAC executable version 1.0+ with a shim matching the selected SDK host architecture | Current stable `Microsoft.PowerApps.CLI.Tool`, global .NET tool for the current user |
| 5 | Azure CLI | Recognized MSI installation 2.60+, launcher, and compatible bundled Python present | Official x64 Azure CLI MSI, machine-wide; uses emulation on ARM64 |

These are this bootstrap's compatibility baselines, not a guarantee that every
Power Platform plugin supports every accepted version. Only the reviewed Node
majors listed above are accepted; compatible existing installations are left
unchanged rather than replaced. New installs still select Node 24
LTS. Check the selected plugins' current runtime requirements separately; this
setup deliberately does not treat an arbitrary newer Node major as compatible.
The .NET runtime alone is insufficient. Newer .NET SDK
majors do not replace the required 10.0 SDK. Compatible tools are not automatically
updated to the latest patch; keep them patched using your normal maintenance
process.

Nonstandard/portable installations, version-manager shims, stale PATH entries,
unknown file versions, and non-MSI Azure CLI installs may need manual repair.
The first executable on PATH is authoritative; setup does not delete or
reorder competing installations or overwrite version-manager configuration.
For a different unsupported newer Node major, Windows can reject installing
the older Node 24 MSI. Review the vendor/version-manager options before changing
that installation; do not uninstall a working runtime blindly. Setup stops if
it cannot verify the result.
For upgrades of older machine-wide Git, use the vendor installer manually if
the new per-user copy is shadowed by the old PATH entry.
On ARM64, Microsoft installs native .NET under `%ProgramFiles%\dotnet` and
x64 .NET under `%ProgramFiles%\dotnet\x64`. If an older x64 host comes first on
PATH, it can shadow a newly installed native SDK. Setup preserves that order
and stops if verification fails; it does not delete the other architecture,
rewrite `DOTNET_ROOT`, or silently switch your existing projects to a new host.
An existing PAC shim with the wrong architecture may require intentional
manual repair if the .NET tool update does not recreate it.

### Downloads, verification, and privilege

No arbitrary installer URL parameter exists. Direct official downloads are the
normal path, **not** an unverified fallback when `winget` fails:

| Tool | Built-in source and integrity check |
|---|---|
| Git | [`git-for-windows/git` official GitHub release](https://github.com/git-for-windows/git/releases/latest), GitHub asset SHA256 digest **and** valid Windows Authenticode signature |
| Node | [nodejs.org distribution metadata](https://nodejs.org/dist/index.json), matching official `SHASUMS256.txt` **and** valid OpenJS/Node.js Foundation Authenticode signature |
| .NET | [Microsoft .NET 10 release metadata](https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/10.0/releases.json), matching SHA512 **and** valid Microsoft Authenticode signature |
| PAC | [Microsoft's documented .NET global tool](https://learn.microsoft.com/en-us/power-platform/developer/howto/install-cli-net-tool), from NuGet.org using an isolated package-source configuration |
| Azure | [Microsoft's x64 MSI link](https://aka.ms/installazurecliwindowsx64), valid Microsoft Authenticode signature (no separate published hash used here) |

If metadata, checksums, certificate trust, or signer verification fails, setup
stops. It never falls back to running an unverified file. Official HTTPS
endpoints can redirect to their distribution CDNs; payload verification still
applies. Metadata and installers are resolved at approval time, so new installs
receive the then-current stable patch, not a permanently pinned version.
"Deterministic" means one ordered, fixed-policy workflow, not byte-identical
packages forever.

Downloaded installers and the temporary NuGet configuration are removed after
use. No diagnostic file or credential log is created by this project; approved
vendor installers/CLIs may maintain their own normal caches, telemetry, and logs.
No installer is run during this repository's tests.

Git is directed to `%LOCALAPPDATA%\Programs\Git`; when run unelevated its
registration is per-user. An already-elevated session can cause Git's vendor
installer to write machine registration, so start unelevated. PAC is installed
for the **invoking user** under `%USERPROFILE%\.dotnet\tools`.
Only installers requiring machine-wide access request UAC. Do not start the
entire setup with a different administrator account.
The script refreshes **only its process PATH**, retaining inherited entries,
and does not rewrite your persistent PATH itself (vendor installers do their
normal registration). Existing Copilot/terminal processes must be restarted.
Approved CLI marketplace/plugin stages also refresh their script process PATH
before spawning the CLI, so they can use newly installed Git/Node without
rewriting the parent agent's environment.

### PowerShell and downloaded-file security

Use **`Setup.cmd`**, even from an agent terminal. It is expected that directly
running `Setup.ps1` can be blocked by Windows PowerShell execution policy in
a fresh Sandbox. This is not a failed prerequisite installation and does not
require changing policy permanently. The launcher forwards flags/exit codes
and uses the same script; it is not a different installation path.

`Setup.cmd` starts Windows PowerShell with `-NoProfile -ExecutionPolicy Bypass`
**for that child process only** so a downloaded, unsigned script can run after
you review it. It does not call `Set-ExecutionPolicy` or change persistent policy.
This exception is deliberate, not proof that downloaded code is safe.
Do not run files you do not trust.

SmartScreen, Mark of the Web, enterprise Group Policy, AppLocker, WDAC, proxy
policy, and certificate restrictions can still block setup. Follow your
organization's approved process; do not disable those protections. For example,
an organization's signed-script requirement needs an approved/signed copy,
not a machine-wide policy relaxation. No automatic reboot is requested.

## Step 2: choose Power Platform plugins

For **existing Copilot CLI or Claude Code CLI** users, the beginner README's
Step 2 starts with the bundled
[power-platform-doctor skill](../skills/power-platform-doctor/SKILL.md).
Ask the agent in the extracted setup folder to read that file. It confirms one
host, prepares the official marketplace with approval, then asks for the desired
plugins, checks existing registrations, presents the
delta, and executes the approved selection through `Setup.cmd -Plugins`.
The skill is included in source/runtime downloads, not automatically installed
into a personal skill directory. It does not authenticate or install an agent
host, Dataverse CLI, or additional tools.

To use this individual-selection route after a double-click Step 1, press
Enter to skip its optional full-set plugin host chooser. Continue with the
doctor in the chosen CLI. In a guided agent setup, keep these stages in the
same installation chat. The existing console full-set route below remains
available for users who choose it.

This stage runs **only after all selected prerequisites are ready**, never after
an installer failure or restart requirement. An interactive launch, including a
rerun on an already prepared PC, offers a host chooser. No selection is guessed
from the presence of a different application.

Before that interactive chooser, passive discovery looks for the selected
products' `claude`/`copilot` application commands and the `ghapp` URL-protocol
registration under the merged Windows classes registry. It does not execute
either CLI, inspect private app directories, start the app, or verify sign-in.
Commands can be first-run install launchers; protocol registrations can be
stale. Status is therefore **candidate detected**, not installed/working proof.
Registry access failures are reported, not silently turned into "not installed."

Selecting a missing CLI prints its fixed official installation guide and
returns exit `2` before plugin prompts/changes or later MCP/skill stages.
No other host is installed or substituted. Finish the chosen host's official
setup independently, reopen the terminal/host, then rerun or resume onboarding.
For an undetected desktop app, the interactive chooser asks for `APP` to confirm
it is already installed; otherwise it prints the official app page and stops.
That confirmation never replaces `PLUGINS` approval, and desktop links still
return `4` until their in-app confirmations/verification are completed.

An explicit noninteractive host does not inventory/configure the other hosts.
Its CLI command is still checked; a missing command receives the same handoff.
An explicitly selected desktop-link route remains a user-confirmed handoff,
not a claim based on registry detection. Check-only skips host discovery.

**Installed binaries do not mean plugins or authentication are configured.**
The prerequisite summary deliberately does not claim plugin readiness.

| Host choice | What setup does |
|---|---|
| `ClaudeCode` | Uses the existing `claude` command to register the official marketplace and install plugins at **user scope**. This applies to Claude Code, including supported local Code-tab/IDE setups, not ordinary Claude chat or Cowork. |
| `CopilotCli` | Uses the existing `copilot` command for marketplace registration and plugin installation. It does not start an agent conversation or install Copilot CLI. |
| `CopilotApp` | Prints the official **add marketplace** link first, followed by each plugin's **install in app** link. Open them yourself and confirm each step in the Copilot desktop app. No CLI is required or installed. |
| `Skip` / Enter | Leaves plugins unchanged. You can rerun later or use the integration skill. |

The reviewed set is Power Pages, model-driven apps, Canvas apps, Code apps,
mobile apps, Power Apps mobile extensions, Power Automate, Process Intelligence,
PCF, and MCP Apps. **Dataverse is separate opt-in**, as in the official installer.
An explicit `dataverse` ID in `-Plugins` also opts that plugin in.
Future additions to Microsoft's catalog require a reviewed setup release.
Plugins can contain executable hooks, agents, MCP servers, and dependencies;
review the displayed plan and the host's permissions before approving.

The CLI route requires versions supporting JSON-array output from
`plugin list --json` and `plugin marketplace list --json`. Setup verifies each
installed plugin's qualified identity and enabled status; text mentioning a
plugin or exit code `0` alone is not enough. Unsupported CLI output, marketplace
source conflicts, disabled plugins, and load errors stop setup explicitly.
Existing compatible registrations are skipped, not force-updated or re-enabled.
An existing enabled Dataverse plugin from `dataverse-skills` is reused rather
than duplicated. CLI listings can still differ from actual desktop/runtime
readiness: restart the host and verify its skills/tools separately.

**Copilot app route: exit `4` means action required, not installation success.**
The printed links match those in
[Microsoft's marketplace README](https://github.com/microsoft/power-platform-skills#install-one-plugin-with-a-click).
Printing links does not install plugins or verify that the app is present.
The app must be installed locally and handle its confirmation links. No browser
is opened automatically and no account or browser profile is selected.

### Agent/noninteractive usage

To prepare **only the official marketplace**, before plugin selection:

```powershell
.\Setup.cmd -NonInteractive -PluginHost CopilotCli -MarketplaceOnly -AcceptPlugins
```

Use `ClaudeCode` instead when selected. This mode requires an explicit CLI host
and cannot be combined with a plugin selection or Dataverse opt-in. It verifies
or adds the marketplace without listing/installing plugins, configuring another
host, or signing in. `-AcceptPlugins` approves only this marketplace-only plan;
request separate approval after the user subsequently chooses plugins.

For an approved **individual selection**, after prerequisites are ready:

```powershell
.\Setup.cmd -NonInteractive -PluginHost CopilotCli -Plugins "dataverse,model-apps" -AcceptPlugins
```

Use `ClaudeCode` instead for that host, not both. `-Plugins` is one
comma-separated string so it passes safely through the Windows launcher.
Names are checked against the reviewed catalog, normalized and deduplicated.
Empty entries, unknown names, URLs and marketplace suffixes fail before
prerequisite changes. The selected plugins are the entire plan, not additions
to the full set. The official marketplace is added/verified even when matching
selected plugins already exist; an external Dataverse plugin is not duplicated.

Do not pass `-Install -Accept` for a plugin-only approval: if a prerequisite is
missing at rerun time, this command stops without installing it. Omitted
MCP-registration and connection-skill stages are skipped.

Prerequisite approval and plugin approval are distinct. After the user approves
both plans, for example:

```powershell
.\Setup.cmd -Install -Accept -NonInteractive -PluginHost ClaudeCode -AcceptPlugins
.\Setup.cmd -Install -Accept -NonInteractive -PluginHost CopilotCli -AcceptPlugins -IncludeDataverse
.\Setup.cmd -Install -Accept -NonInteractive -PluginHost CopilotApp -AcceptPlugins -IncludeDataverse
```

These examples use the backward-compatible `-Plugins All` default: the standard
reviewed set, excluding Dataverse unless explicitly opted in. The doctor always
passes the user's selected IDs, and never turns "none" into `All`.
Choose **one** command for the intended host; do not run all three.
`-Accept` approves prerequisites; `-AcceptPlugins` approves only the chosen plugin
stage. Neither authorizes sign-in. `-IncludeDataverse` adds Dataverse to either
the default set or an explicit selection and applies only to plugins;
Azure CLI is now a default prerequisite. `-SkipAzureCli` is a minimal-setup
opt-out, not recommended for the full plugin set.

Noninteractive runs without `-PluginHost` skip plugins. `-PluginHost Skip`
explicitly suppresses the interactive chooser. `-CheckOnly -PluginHost
CopilotCli -Plugins "dataverse,model-apps"` can print the later plugin plan but remains offline, prompt-free and
CLI-free; it does **not** verify the host/plugins. If prerequisites are already
ready, rerun setup with a chosen host to perform just that plugin stage.

### Why not simply run the two often-shared commands?

The official
[`microsoft/power-platform-skills`](https://github.com/microsoft/power-platform-skills)
`scripts/install.js --include-dataverse` is a broad installer. It detects
Copilot CLI/Claude Code, can configure both if present, may install/update PAC,
attempts Azure CLI installation when absent, and enables
auto-update. It can be useful when those effects are intended, but it is not a
desktop-only installer. Setup does **not** download/execute `install.js` or pipe
remote JavaScript into Node. It uses scoped host commands instead, without
changing auto-update settings, updating PAC, or installing unselected prerequisites.
Existing host-managed update behavior is left unchanged.

Those official quick-install commands are **alternatives to** this script's
plugin stage, not additional required steps. The setup skill can run scoped
host commands directly; a separate terminal or chat is not needed just to
install Power Platform plugins. If the broad installer is explicitly chosen,
review/approve its wider effects and verify results instead of also repeating
the narrower plugin stage.

On Windows, use **`curl.exe`** for native curl syntax such as `-fsSL`; plain
`curl` can be a Windows PowerShell alias for `Invoke-WebRequest`. For reviewed
PowerShell downloads use `Invoke-WebRequest -UseBasicParsing` to avoid its
HTML-parsing confirmation. Downloading is distinct from execution, and a
remote pipeline to Node executes before manual review. Neither spelling makes
the broad installer applicable to a desktop-only host without a supported CLI.

The restriction is in that quick installer's **host-detection code**, not in
PowerShell/curl or the skill/plugin format. Copilot desktop has normal
marketplace controls; VS Code Copilot agent mode also supports native plugin
installation without Copilot CLI. In VS Code use **Chat: Manage Plugin
Marketplaces > Add Marketplace...**, add `microsoft/power-platform-skills`,
then **Customize > Browse > Install**. See
[GitHub's VS Code plugin documentation](https://docs.github.com/en/copilot/how-tos/copilot-in-your-ide/customize-copilot/extend-copilot-with-tools-and-context/using-plugins).
The current script does not implement a VS Code host selector. Do not equate
that IDE with `CopilotCli` or send desktop-only confirmation links expecting
them to target VS Code. Installation and component support must be verified
in the intended host.

The user-verified menu route is **Customizations > Browse > source dropdown
(All Sources) > Configure Marketplaces > Add Marketplace...**. Enter
`microsoft/power-platform-skills` and press **Enter**, then select that source
on Browse and install the desired plugins individually. Merely adding the
marketplace makes the catalog available; it is not an all-plugin install or
an authentication step. See the [README screenshot walkthrough](../README.md#manual-option-add-the-power-platform-plugins-in-vs-code).
Git must be discoverable by the running IDE, not only installed somewhere.

## Step 3: optional Copilot Studio MCP registration

The script now offers this stage after plugin setup (including a plugin skip
or a pending Copilot desktop link handoff). It never runs after prerequisite
failure/restart or plugin failure/cancellation. Choose the desired existing
host independently of your plugin choice, or press Enter to skip.

The package comes from
[`@microsoft/copilot-studio-mcp`](https://github.com/microsoft/copilot-studio-mcp).
This is **MCP server registration**, not installation of the cloud Copilot Studio
product, a new agent host, or an authentication session.

| Host | Registration method |
|---|---|
| Claude Code | Runs the existing `claude mcp add --scope user --transport stdio copilot-studio -- npx -y @microsoft/copilot-studio-mcp@latest`, then checks the saved user definition in `%USERPROFILE%\.claude.json`. |
| Copilot CLI or desktop app | Safely adds the user definition to `%USERPROFILE%\.copilot\mcp-config.json`. The desktop path does **not** require installing Copilot CLI. |

Review the printed user-scope path and close that host before approving, to
avoid concurrent configuration writes. Matching existing user definitions,
including an equivalent name, are reused without changing tool restrictions or
disabled settings. Conflicting definitions, pinned versions, duplicate keys,
invalid JSON, unsupported encodings, and genuinely custom `COPILOT_HOME` /
`CLAUDE_CONFIG_DIR` locations stop setup rather than being overwritten.
An unset `COPILOT_HOME` or one explicitly equal to `%USERPROFILE%\.copilot`
(including normalized casing, separators and trailing slashes) uses that default.
Setup neither clears the variable nor interprets a different path as the default.
Project, plugin, and managed definitions may override user configuration;
setup does not start those servers to inspect them.

For Copilot, existing **UTF-8 JSON** is edited without reserializing unrelated
content. An atomic replacement preserves the existing file's access controls
and retains its original content in a sibling
`mcp-config.json.setup-backup-<id>` file. This backup may contain credentials
from other servers: **keep it private**, never attach it to issues or include
it in a repository/ZIP. A stale snapshot stops the write; if a race is detected
after replacement, the displaced live content is retained in the backup and
setup reports an error for manual reconciliation. It never silently discards
a concurrent new file. No JSON/configuration content is logged.

After separate approval for prerequisites and MCP registration, an agent can use:

```powershell
.\Setup.cmd -Install -Accept -NonInteractive -CopilotStudioHost CopilotApp -AcceptCopilotStudio
```

Use `ClaudeCode` or `CopilotCli` instead for that host. Add the separate
`-PluginHost <host> -AcceptPlugins` options if plugin setup was also approved,
and `-IncludeDataverse` only when requested. Noninteractive runs without
`-CopilotStudioHost` skip MCP registration. `-Accept` and `-AcceptPlugins` do
**not** authorize it. `-CopilotStudioHost Skip` skips the interactive MCP chooser.
`-CheckOnly` never reads or writes MCP configuration, even with a requested host.

The result is explicitly **CONFIGURED, NOT RUNTIME-VERIFIED**. Restart the host,
check its MCP list and trust/permission prompts, and deliberately sign in when
ready. Setup does not check connectivity to an environment or invoke cloud tools.
If plugin links were printed, exit `4` still means those app confirmations are
pending even when MCP configuration succeeded.

### Optional integration skill

The [integration skill](../skills/power-platform-integrations/SKILL.md) remains
available for custom plugin selections and agent-guided Copilot Studio MCP
registration. In a Copilot desktop chat, ask it to read the skill and propose a
plan; it should reuse plugins already installed by Setup.cmd. A repository URL
does not permanently install the skill into any host.

For the normal user-scope registration, the skill should reuse the script's
separately approved MCP stage. Neither plugin approval nor prerequisite approval
authorizes MCP registration or sign-in.

`npx -y @microsoft/copilot-studio-mcp@latest` **launches a server**; by itself it
does not register that server with the app. The script's MCP stage saves the approved launch
configuration so the app can start it over stdio when needed. The first launch
can download/cache the package; `@latest` permits future version changes.
The [package instructions](https://www.npmjs.com/package/@microsoft/copilot-studio-mcp)
currently require Node 22.18+ and recommend Node 24 LTS. Do not start a standalone
server in a terminal and mistake the running process for a completed integration.

### Desktop controls and verification

The documented desktop path is **Customize**, then marketplace settings beside
the marketplace dropdown to add `microsoft/power-platform-skills`; find and
**Install** the chosen plugins. Examples include `canvas-apps`,
`code-apps-preview`, `model-apps`, and `power-automate`. Dataverse is explicit
opt-in and comes from
[`microsoft/Dataverse-skills`](https://github.com/microsoft/Dataverse-skills);
avoid duplicate installs from two marketplaces. For a custom MCP server,
use **Customize > MCP**. Check **Installed** afterward.

These are documented controls, not a claim that every app version or enterprise
policy exposes the same UI. Refresh/restart the app/session if necessary and
verify that the actual capabilities appear. This repository's tests do **not**
install plugins, alter real user MCP configuration, launch an MCP server, or
prove a live desktop integration.

## Step 4: install the optional connection skill

After the plugin and MCP stages complete or are skipped, setup offers to copy
the bundled `power-platform-connect` skill into the **chosen host's personal
skills directory**:

| Host | Destination |
|---|---|
| Claude Code | `%USERPROFILE%\.claude\skills\power-platform-connect\SKILL.md` |
| Copilot CLI or desktop app | `%USERPROFILE%\.copilot\skills\power-platform-connect\SKILL.md` |

These are documented [Copilot personal skill locations](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills)
and [Claude Code skill locations](https://code.claude.com/docs/en/skills).
No CLI executable is needed just to copy the skill. The host must already be
installed and must permit/discover personal skills; file presence alone does not
prove that an enterprise policy allows it.

The script asks for separate **SKILL** approval. It copies only the reviewed
instruction file from this download, verifies the content, and does not enable
auto-approval or start any tool, MCP server, or sign-in. An identical existing
file is reused. A different existing definition, occupied directory, or linked
destination causes an explicit error rather than overwriting the user's skill.
Genuinely custom `COPILOT_HOME` / `CLAUDE_CONFIG_DIR` locations need manual review
instead of a guessed destination. The Copilot app may explicitly set
`COPILOT_HOME` to the normal `%USERPROFILE%\.copilot`; that is accepted and left
unchanged. Updates of a different previously installed copy need
intentional review; rerunning is not permission to replace it.

After approval, agents/noninteractive callers can append:

```powershell
.\Setup.cmd -Install -Accept -NonInteractive -ConnectionSkillHost CopilotApp -AcceptConnectionSkill
```

Choose `ClaudeCode` or `CopilotCli` instead if appropriate. This approval is
independent of `-Accept`, `-AcceptPlugins`, and `-AcceptCopilotStudio`.
Without a host flag, noninteractive runs skip skill installation and still print
the next-step prompt. `-ConnectionSkillHost Skip` skips the interactive chooser.
`-CheckOnly` never installs a skill or inspects the user's skill directories.
Earlier failures/cancellations/restart requirements stop later stages. Pending
desktop plugin links still return exit `4` even if skill installation succeeds.

Whether you install or skip the skill, successful setup prints a ready-to-copy
chat request for connection onboarding, with the public skill URL as a fallback.
In the full guided flow the entry skill can read the bundled file directly and
continue with its own approvals. Reopen after PATH changes or when capability
discovery requires it, then resume; do not make a new prompt a mandatory extra
stage when no restart is needed. Installing the instructions does **not** run them.

## Step 5: connect and remember sign-in (optional skill)

Use [power-platform-connect](../skills/power-platform-connect/SKILL.md) **after**
prerequisites and the requested plugins/MCP definitions are installed. The final
setup stage can install the skill for you, or you can ask the agent to read the
linked source. This
agent-guided stage is deliberately not run by `Setup.cmd`: installation flags
do not grant permission to sign in, select an environment, switch an active
profile, or call a tenant.

### User-facing connection questions

The connection skill must ask one explained question at a time, not collect a
technical six-field form followed by speculative installation consent:

- **Environment selection:** default to PAC sign-in/reuse in an approved context,
  then `pac env list`, then show returned environment names and exact URLs.
  Let the user choose one or more, reuse saved connections, or enter another
  existing URL. Manual entry remains available with zero/partial results,
  errors, or an already configured machine.
- **Tenant ID / Directory ID:** identifies the Microsoft organization that owns
  the environment. It differs from both an Azure Subscription ID and a Power
  Platform Environment ID. Offer help finding it via
  [Microsoft's documented portal location](https://learn.microsoft.com/en-us/entra/fundamentals/how-to-find-tenant)
  or, with permission, matching local profile metadata; confirm the candidate.
  PPAC environment details may show **Organization ID** and **Environment ID**;
  neither is the Tenant ID. Select the owning directory in Entra admin center
  and open **Entra ID > Overview > Properties > Tenant ID**, or ask its admin.
  Include this navigation in the question's own visible help text, not only in
  a separate documentation link or after the user asks where to find it.
- **Subscription ID:** identifies an Azure resource/billing subscription. It is
  not required for normal tenant-scoped Power Platform onboarding. Azure CLI
  selection alone is not a reason to require one.
- **Work sign-in email (UPN):** the Microsoft sign-in username, usually the
  user's work/school email. Do not assume it always equals their mailbox address.
- **Connection nickname (alias):** a local label such as `my-demo-environment`,
  not a tenant-provided ID or a request to rename/create an environment. Explain
  the lowercase/hyphen/30-character rules and propose a friendly default.
- **Tools to connect:** describe each requested CLI/MCP in plain language.
  Checking a tool is not advance approval to install an unchecked dependency.

### Discovery and multiple persistent connections

`pac env list` is an authenticated Global Discovery Service metadata read, not
an offline check or a guarantee of every environment across all tenants. The
older `pac org list` alias still works; current Microsoft guidance recommends
`pac env`. Its list command does not document a `--tenant` or `--json` switch:
do not invent either. Do not substitute administrator enumeration, create an
environment, or auto-switch directory when discovery is empty/blocked.

Confirm the actual account, tenant and exact environment URL of the proposed
PAC discovery profile before selecting it or making live calls. With approval,
reuse a matching working profile. If none exists, first confirm one existing
environment URL as the initial PAC sign-in context and approve that sign-in,
then return to discovery and selection. Do not use bare `pac auth create` to
silently pick a default environment. The initial context is not automatically
included in the user's saved target selection.

Discovery approval is separate from target-specific setup. For each selected
or manually entered target, confirm its account/tenant/URL, nickname and tools.
Inspect/install shared dependencies once when needed and approved; then process
targets serially with one existing schema-version-1 private binding per alias,
matching profiles and a unique named MCP definition. Do not overwrite or migrate
healthy old bindings into a new combined credential file. An unlisted URL can
be added, but identity, reachability and permissions must still be verified.

CLI active-profile state is shared and not multi-target isolation. Ask which
connection should be active afterward, or before restoring the old selection.
Same-tenant/account environments may reuse the approved Azure cache. Stage
multiple approved MCP definitions before one reload where supported, then
verify each target in the intended host and a new process/chat. A partial failure
remains partial; one working environment does not verify the others.

On every later use, **Add another existing environment** remains available
through saved connections, approved discovery or manual URL entry. This creates
local connection bindings, not cloud environments. Persistence means supported
session/cache reuse, not a promise that MFA or renewal never occurs.

Sources: [PAC environment commands](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/env)
and [PAC authentication profiles](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/auth).

### Why an additional Dataverse package may be requested

The base installer installs **PAC CLI**, not the separate **Dataverse CLI**.
The optional **Dataverse plugin** supplies agent capabilities and connection
instructions, but installing it does not guarantee that the global npm package
`@microsoft/dataverse` exists. The connection skill must inspect the command and,
if needed, the installed global package metadata before proposing an install.
An installed package with a missing PATH entry needs launcher discovery/restart
guidance, not an automatic duplicate install.

If the package is actually missing and its CLI/MCP proxy is requested, explain
what it adds, the actual configured npm install location and permissions, then
ask separately to download/install it. Do not use the vague initial question
"Approve installing @microsoft/dataverse globally via npm?" without that context.
Here, "global" means available outside one project via npm's configured prefix;
it does not mean access to every environment or a universal Microsoft login.

Older installed skill copies are not silently replaced by Setup.cmd. A user can
ask the agent to follow the latest public skill for these clearer questions, or
approve a reviewed update to their personal copy. Writing documentation/tests
does not prove an AI host will always phrase every question identically.

The skill coordinates the existing tools, not a new authentication service:

| Surface | Reuse strategy |
|---|---|
| Azure CLI, when selected | Reuse an approved cache directory for the expected tenant/account, or create a dedicated local directory after approval. Scope `AZURE_CONFIG_DIR` for each process rather than changing the default account for every tool. |
| PAC CLI | Reuse a matching named profile. It has its own authentication client/cache; an initial PAC sign-in may still be necessary. |
| Dataverse CLI | Reuse a matching saved profile through the official Dataverse plugin's connection/authentication flow. The CLI is an additional package, not automatically installed merely by selecting the plugin. |
| Dataverse MCP | Configure the installed official CLI stdio proxy to use supported cached authentication and an explicit environment URL. A direct HTTP MCP connection can have separate OAuth. |
| Copilot Studio MCP, when selected | Reuse its registered server and supported sign-in flow. The current package documents OS-protected persistence across chats; verify the installed version and actual reported persistence. |

The agent first confirms the exact account, tenant, environment URL and
selected surfaces. It checks matching profiles before proposing new login,
and saves only approved connection bindings in a private local record under
`%LOCALAPPDATA%\PowerPlatformSetup\connections`. A connection alias is a convenient
lookup, not authorization to access its tenant. Personal connection records,
cache files and MCP configuration must never be copied into this public repo.

Missing Dataverse CLI, Azure CLI, or optional Python SDK dependencies need their
own installation approval. Python/SDK setup is not required merely to authenticate
the CLIs. The skill reuses Microsoft's installed `dv-connect` guidance, but does
not authorize its broader environment-creation or administrative operations.
Tenant consent, MCP allowlisting, role assignment, and connector creation remain
separate decisions; a blocked setup stops rather than silently granting access.

**The promise is one guided onboarding and fewer repeat prompts, not one
universal login.** Separate OAuth clients, MFA, revoked sessions and tenant
policy can require additional sign-in. Credentials stay in the official tools'
supported stores; the skill never reads/copies tokens or implements its own
refresh mechanism. Matching profile metadata is not proof of a valid session.

After permission for bounded read-only verification, the agent checks the
selected account/tenant/environment and actual MCP identity. Then test a fresh
terminal and new host chat under the same Windows user to confirm session reuse.
If a restart or user sign-in is pending, the result must say so. A working
Dataverse CLI is not proof that PAC or every MCP server is connected.

In Sandbox, do this restart test **inside the same running guest**. Closing or
resetting Sandbox normally discards its caches. Do not copy protected caches
back to the host to try to preserve sign-in.

Relevant licensing and permissions remain separate. The installer and integration
stage still never run `az login` or `pac auth create`; the connection skill may
guide those only after its own explicit approval. It does not collect passwords
or tokens, enable agent auto-approval or Windows features, or write cloud resources.
Some plugins have additional workflow-specific prerequisites.

**PAC limitation:** Microsoft's .NET tool does not include `pac data` or certain
`pac package` commands (`deploy`, `show`), even on Windows.
If you need these, use the
[official Windows MSI alternative](https://learn.microsoft.com/en-us/power-platform/developer/howto/install-cli-msi)
intentionally and manage overlapping PATH entries. See the
[installation-method comparison](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction).
PAC prints its version when called as **`pac`**, not a presumed `pac --version`.
Use **`npm.cmd`** in PowerShell to avoid the unrelated `npm.ps1` policy issue.

## Exit codes and troubleshooting

| Code | Meaning / next action |
|---|---|
| `0` | Selected prerequisites ready; optional plugin/MCP/skill stages skipped or their registrations/files verified. Actual host discovery, runtime/auth readiness is still separate. |
| `1` | Check-only found missing or unsupported prerequisites. This is an expected readiness result. |
| `2` | Cancelled, invalid options, missing explicit opt-in, or a selected-host installation handoff. Completed prerequisite installs remain; follow the official host guide yourself, reopen and rerun. |
| `3` | Unsupported host/CLI output, detection, download, trust, installer, or prerequisite/plugin/MCP/skill verification failure. Stop and fix the reported cause. |
| `4` | Copilot desktop plugin links printed. App confirmations and plugin verification are still required. Prerequisites are ready. |
| `3010` | Installer requested/reported a restart. Chain stopped; restart Windows yourself, then rerun. |

The launcher forwards this code. Policy/PowerShell failures before the script
starts may return PowerShell's own nonzero code instead.

For live installer feedback, run `Setup.cmd` directly or stream its output.
Piping all output through `Select-Object -Last ...` hides it until the command
finishes, including the new wait heartbeat. A heartbeat is not evidence that
individual vendor packages are advancing; if the installer is blocked, investigate
its own diagnostics without starting a competing setup.

| Symptom | Safe next step |
|---|---|
| No `winget` in Sandbox | No action needed; this setup uses official direct installers. |
| Direct `Setup.ps1` execution is blocked | Use `.\Setup.cmd` with the same flags. Do not persistently relax execution policy; enterprise restrictions still apply. |
| Permission/UAC denied or installer code `1603` | Review admin/policy requirements; ask your administrator. Do not elevate the whole agent. |
| Installer code `1618` | Another Windows installation is running; let it finish, then rerun. |
| Installer succeeded but tool is still missing/old | Restart the Copilot app and terminal; inspect the reported path for a shadowing old install. Do not repeatedly install blindly. |
| Marketplace says Git is missing, but Git works by its full path | Check in a fresh terminal. If appending the saved Machine/User PATH to that terminal's existing PATH makes `git --version` work, persisted PATH is registered and the process inherited a stale copy. Fully exit the IDE and launch it from that refreshed terminal (for VS Code, `code` if available). A new terminal inside an old app process can inherit the same stale PATH. Do not reinstall Git or move the setup repository as a PATH fix. |
| .NET download/installation appears slow | User-reported ARM64 Sandbox installation has taken 30-60 minutes or longer. During vendor installer execution the script prints an elapsed-time heartbeat about every 30 seconds; it does not measure per-package progress or predict completion. Downloads use `Invoke-WebRequest -TimeoutSec 600` and PAC's tool command has separate output; neither uses that heartbeat. There is no download resume/alternate endpoint in this version. Do not launch parallel retries or assume a reachable URL proves the full transfer will complete. |
| `Access to the path 'dotnet.exe' is denied` / exit `3` | Treat it as a failure, even if a later check finds the SDK. The supplied screenshot does not establish whether the fault was download, installation, cleanup, permissions, or a file lock. Let any active installer finish; reopen the terminal and run `.\Setup.cmd -CheckOnly`. Continue only after reviewing the new plan. If the error repeats or the SDK is still missing, stop and investigate rather than weakening Windows security. |
| TLS/proxy/certificate/download error or GitHub API rate limit | Fix access to the listed official endpoints, wait for a rate-limit reset if applicable, then rerun. Do not disable certificate checks or substitute random downloads. |
| .NET SDK exists but a project uses another SDK | Inspect that project's `global.json`; setup does not change it. |
| Azure reported unrecognized despite a working portable CLI | This release recognizes MSI metadata only. Use/repair the official MSI or manage that tool outside setup. |
| PAC installation fails | Check NuGet.org access, Windows policy, and whether an existing PAC shim conflicts. Source configuration is isolated, not taken from your project. |
| Selected `claude`/`copilot` command is missing | Use the host already installed. For Copilot desktop only choose `CopilotApp`; do not install another host as a workaround. |
| Plugin JSON output/source/disabled-state error | Review the selected CLI's supported version, marketplace source, scope, and policy privately. Setup does not fall back to guessed text parsing, force-enable plugins, or expose full configuration. |
| MCP configuration conflict, encoding, or concurrent-edit error | Stop, close the host, and inspect/reconcile the local configuration privately. Keep any reported backup; do not share it. No sign-in or cloud operation is needed to repair local registration. |
| An older release rejects the default `COPILOT_HOME` | Download the latest full source. The corrected setup accepts an explicitly configured default; it still rejects genuinely custom paths for manual review. Do not remove your working configuration or clear the variable globally. |
| Existing connection skill differs or the destination is linked | Review/update it intentionally in the host's supported skill location. Setup will not overwrite a custom or older definition. You can use the printed public-skill prompt without installing another copy. |

It is safe to rerun: completed compatible tools are skipped; a failure stops
the chain and does not roll back earlier successful vendor installations.
Remove software through Windows Installed apps or its own package manager;
there is no broad cleanup/uninstall command.

## Automatic version maintenance

The **Review tool versions** workflow runs on Mondays at **07:23 UTC**, or
manually through **Actions > Review tool versions > Run workflow** on the
default branch. GitHub schedules can be delayed; this is a maintenance aid,
not a guarantee that every new release is accepted immediately.
GitHub can also disable public-repository schedules after inactivity; owners
must re-enable a disabled schedule when notified.

The bounded first automation covers **Node LTS compatibility additions**:

1. Read the fixed official Node release index and support schedule, without
   installing or executing downloaded packages.
2. Propose only majors with a published stable LTS release whose LTS period
   has started and whose support end date has not passed. Scheduled future LTS,
   Current-only releases, prereleases, and already end-of-life majors are not
   newly accepted. Existing end-of-life majors are flagged, not silently removed.
3. Guardedly update the policy in `Setup.ps1`, its displayed requirement,
   directly related documentation, and explicit Node regression cases. Missing
   metadata or unexpected file structure fails the run rather than guessing.
4. Run the existing isolated tests in both PowerShell versions and package the
   allowlisted public files before creating a PR.
5. Open a review PR on a dedicated branch. Never approve, auto-merge, force-push,
   or overwrite an existing proposal. A closed proposal is not recreated
   automatically; maintainers can reopen or review it themselves.

**LTS status is a proposal signal, not proof of Power Platform compatibility.**
The maintainer must review the selected plugins' current runtime requirements
and any required real acceptance before merging. Existing downloaded source
and runtime ZIPs retain their checked-in policy until replaced by a newer
download. User check-only remains offline, read-only and CLI-free.

The Node 22 minimum, npm minimum, architecture gates, new-install Node 24 LTS
default, integrity checks, and all other tools' major-version requirements are
not automatically changed. Git, PAC and Azure already resolve current packages;
Node and .NET resolve current releases within their configured channels.
New .NET majors cannot simply replace the PAC-required SDK channel. Changes to
other tools' compatibility baselines remain an explicit maintenance decision.

Repository prerequisite: **Settings > Actions > General > Workflow permissions >
Allow GitHub Actions to create and approve pull requests** must be enabled and
permitted by organization policy. The workflow never exercises approval or merge
capabilities. Its write permissions are job-scoped: contents for its proposal
branch, pull requests for creation, and actions to dispatch `validate.yml`.
That explicit dispatch is needed because PRs created using `GITHUB_TOKEN` do
not trigger the normal `pull_request` workflow. No personal token is required.

From the full contributor source, preview public metadata without editing files:

```powershell
.\scripts\Update-NodeSupport.ps1
```

Use `-Apply` only in a clean maintainer checkout when you intend to write the
proposed source changes. The script does not install tools, authenticate,
create a PR, or change user configuration itself. It is not part of the
packaged runtime ZIP; the GitHub workflow owns the separate PR operation.

## Validate and create a shareable ZIP

For contributors, from a checkout or **Code > Download ZIP** source folder
(the smaller packaged runtime ZIP intentionally omits contributor scripts):

```powershell
.\scripts\Test-Setup.ps1
.\scripts\New-Release.ps1
```

The dependency-free tests parse every PowerShell script and mock all
installation paths: approval, ordered plan, skip/rerun, failures, restart,
version verification, architecture detection (including an emulated shell),
x64/ARM64 package selection, PAC/SDK architecture matching, source/integrity
gates, and PATH preservation. Default Copilot-home tests use isolated profiles,
and heartbeat tests start only harmless test processes, not vendor installers.
Plugin tests mock both CLI schemas, approvals,
source collisions, skip/rerun, failures and official desktop links. MCP tests use
isolated dummy files for safe merge, backup, rerun, malformed/conflicting config,
and concurrent-write cases, plus mocked Claude registration. No plugin install,
app/server launch, real user configuration write, or sign-in is performed.
A real local inventory test uses only reads.
CI runs on Windows PowerShell 5.1 and PowerShell 7. CI does **not** install tools
or validate a pristine Sandbox installation on either architecture.

### Test steps 4 and 5 without Windows Sandbox

Run `.\scripts\Test-Setup.ps1` from the full source folder. A disposable Windows
VM is **not needed** for these local, non-authenticating checks:

- **Step 4:** the tests run the actual skill-copy stage in separate PowerShell
  processes with temporary user-profile directories for all three host choices.
  They verify the copied content and a rerun in a new process, check that no
  other files were created there, and delete those specific test directories.
  Existing personal skills and credential stores are not changed.
- **Step 5:** the tests parse the skill's command examples and binding-record
  JSON, check that its links work as a standalone file, and execute its
  Azure-directory scoping example against a mocked CLI, including failure
  paths. These are instruction/example checks, **not real authentication**.

The tests do not start an AI host to prove skill discovery, test an agent's
decisions, or establish that a cached session survives an actual sign-in.
File visibility from a second PowerShell process is not proof of desktop skill
discovery or cross-chat authentication.

For a manual instruction rehearsal without personal installation, ask the
agent to read the skill file from the extracted source in a fresh chat. No
personal skill copy is needed for that route. Merely loading the instructions
does not prove automatic skill discovery or authorize authentication or
configuration changes.

**A local folder is not an authentication sandbox.** A dedicated Azure cache
can be scoped to that folder, but PAC/Dataverse profiles and Windows protected
authentication can still be shared with other sessions of the same Windows
user. Do not copy their caches, redirect undocumented storage, or delete
working profiles after a test. For a live test with safe disposal, use a
separately approved disposable Windows user/VM, or explicitly approve a
specific existing account/environment and non-destructive checks. Track any
new profiles, registrations, bindings and files before making changes; cleanup
must target only those additions, preserve shared sessions, and be approved
separately before removing authentication or host configuration.

Keep the current division of responsibility: **the script installs the skill;
the skill guides sign-in** with the user choosing the target and completing MFA.
Combining them into automatic post-install login would not solve separate
credential caches, consent, or account-selection requirements.

### Manual Sandbox acceptance (x64 or ARM64)

Use a separately authorized disposable Windows environment of the architecture
you want to test; an x64 CI runner with ARM64 mocks is not an ARM64 install test.
No Windows feature is enabled by these scripts. In your own Sandbox:

1. Download/extract the **full current source ZIP** inside the Sandbox. Keep any
   shared host folder read-only; install inside the guest, not on the host.
2. Run `.\Setup.cmd -CheckOnly`. Confirm it reports the guest's Windows
   architecture and lists missing tools in order without downloading or prompting.
3. Double-click `Setup.cmd`, review the plan (Azure comes after PAC), and type
   `INSTALL` to approve. On ARM64 confirm the plan explicitly identifies x64
   Azure emulation. Use `-SkipAzureCli` only for an intentional minimal-tool test.
4. If a restart is required, stop and follow the reported instructions. Do not
   treat that as a passing install or assume that closing/reopening Sandbox
   preserves its state.
5. After success, reopen the terminal and run `.\Setup.cmd -CheckOnly` again
   (with the same `-SkipAzureCli` flag if used). Expect exit `0` and no install plan.
   An interactive rerun should skip compatible tools without asking to install
   prerequisites; its optional plugin chooser can be skipped with Enter or
   `-PluginHost Skip`.
6. Only for this deliberately approved runtime acceptance, check `git --version`,
   `node --version`, `npm.cmd --version`, `dotnet --list-sdks`, and `pac`; if Azure
   was selected, check `az version`. Do not sign in or query a tenant.
   Keep plugin/MCP testing as the separate stage described above.

Record failures and exit codes, redacting personal paths before sharing output.
Full clean-machine acceptance is not claimed until these vendor installations
have actually succeeded on the relevant architecture.

Packaging writes only `dist\power-platform-setup-windows.zip` and its `.sha256`
file. An explicit file allowlist includes the launcher, installer, README, detailed guide,
selected screenshots, agent instructions, license, and skills; it excludes repository history, test outputs,
personal configuration, secrets, and installed packages. The ZIP is also
uploaded as a CI artifact. An artifact checksum detects accidental changes;
it is not a code-signing certificate or proof of publisher identity.

## License

[MIT](../LICENSE) for this project's code. Vendor tools have their own licenses
and support policies. Review downloaded code before running it.
