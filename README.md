# Power Platform setup for Windows

Set up the **local developer tools** used by Microsoft Power Platform skills, in
the right order, with a plan and approval before anything is installed.

You already have **Claude Code, GitHub Copilot CLI, or the GitHub Copilot desktop
app**. Setup installs prerequisites, then offers a separately approved Power
Platform plugin stage for the host you choose, followed by optional **Copilot
Studio MCP registration** with its own approval. It does not install an agent
host, sign in, or create cloud resources. The optional
[integration skill](skills/power-platform-integrations/SKILL.md) can guide custom
plugin selections and separate Copilot Studio MCP registration. After setup,
the optional [connection skill](skills/power-platform-connect/SKILL.md) guides
separately approved sign-in and secure session reuse. This is a community
bootstrap, not a Microsoft product or an official installer.

## Short version

**Run Setup.cmd: prerequisites, plugins, optional Copilot Studio MCP, then the connection skill.**

| Step | What you do | What it sets up |
|---|---|---|
| 1. Prerequisites | Download/extract this repository, review the script, then double-click **Setup.cmd**. Approve the displayed plan by typing **INSTALL**. | Git, Node.js/npm, .NET 10 SDK, and PAC CLI, in order. Azure CLI is optional. |
| 2. Power Platform plugins | Once prerequisites are ready, choose **Claude Code**, **Copilot CLI**, or **Copilot desktop app links**. Opt into Dataverse if needed, review the plugin plan, and type **PLUGINS** to approve. Enter skips this stage. | Installs the reviewed Power Platform plugin set through the chosen existing CLI, or prints official Copilot desktop links for you to open and confirm. |
| 3. Copilot Studio MCP | Choose the host for MCP registration (or Enter to skip). Close that host, review the plan, and type **MCP** to approve. | Saves `npx -y @microsoft/copilot-studio-mcp@latest` as the host's server launch command. No server or sign-in is started by setup. |
| 4. Install the connection skill | At the final prompt choose Claude Code, Copilot CLI, or Copilot desktop, review the personal skill directory, and type **SKILL** to approve. Enter skips installation. | Installs the bundled **power-platform-connect** instructions locally. No authentication is started. |
| 5. Connect and reuse sign-in | Restart your host, then use **power-platform-connect** with the prompt below (also printed at setup's end). Confirm your account, tenant, environment, and separate onboarding plan. | Reuses matching Dataverse/PAC/Azure profiles and supported MCP sessions; guides only missing sign-ins. No shared-token copying or automatic tenant writes. |

**Setup.cmd already launches PowerShell.** You do not need to open a terminal
or paste the official JavaScript one-liner separately. CLI installation is
automated; desktop-only Copilot installation still requires the app's own
confirmations. Choose the host you actually use; setup never configures all
detected hosts behind your back.

For **custom or agent-guided setup**, you can instead paste this into a Copilot desktop chat:

> I have finished running Setup.cmd. Read and follow
> https://github.com/danieag/power-platform-setup/blob/main/skills/power-platform-integrations/SKILL.md.
> Check the plugins I already installed and help me register Copilot Studio MCP.
> Show the plan and ask for approval before changing anything.
> Do not sign in or select an environment.

For **sign-in and persistent connections after installation**, use this separate
prompt in your chosen agent chat:

> Read and follow
> https://github.com/danieag/power-platform-setup/blob/main/skills/power-platform-connect/SKILL.md.
> Help me connect Dataverse CLI, PAC CLI, Azure CLI, and my Dataverse MCP server.
> Check existing profiles first. Ask me to confirm my account, tenant, environment,
> and the plan before signing in, switching profiles, or changing configuration.
> Reuse working sessions and do not change tenant permissions or create resources.

Remove Azure or any other surface you do not need. Mention Copilot Studio MCP
if you also want its separate sign-in configured. You do not need to type
authentication commands yourself when the agent has the necessary approved
tools; you still complete Microsoft sign-in/MFA and any host trust prompts.

If you skip skill installation or the host does not discover it, the agent can
read the linked skill directly. A link does not permanently register a skill
in the app. Setup always prints this next-chat handoff after completed/skipped
optional stages; it never invokes the connection skill or signs you in itself.

**Setup.cmd offers plugin and Copilot Studio MCP setup directly but does not automatically run the
integration skill.** The skill is an alternative for agent-guided selections
and MCP registration, not a mandatory extra step after plugin installation.
If a required capability or permission is unavailable, setup reports the
remaining action instead of claiming success.

Already have the prerequisites? Run `.\Setup.cmd -CheckOnly` first. If it reports
that all selected prerequisites are ready, go straight to step 2.

The other skill, [power-platform-setup](skills/power-platform-setup/SKILL.md),
is an **alternative way to guide step 1 through an agent**, not an extra step
you must run after Setup.cmd.

Continue with the [long version](#long-version) for detailed instructions,
supported PCs, security, troubleshooting, and what each stage changes.

## Long version

### Supported PCs and current limitations

> **Initial release status:** syntax and non-installing regression tests are
> automated. A complete installation on a pristine Windows Sandbox has **not**
> been verified. The same script supports **x64 Windows 11 / Windows 10 22H2**
> and **ARM64 Windows 11**, with 64-bit Windows PowerShell 5.1 or PowerShell 7.
> ARM64 Windows 10 and 32-bit Windows/processes are rejected. Use a
> vendor-supported Windows version; Windows 10 support/security servicing is
> your responsibility.

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
| Optional Azure CLI | Official x64 MSI | Official **x64 MSI under Windows 11 emulation**, not a native ARM64 package |

Compatible existing x64/x86 tools are preserved on ARM64 and run using
[Windows 11's built-in emulation](https://learn.microsoft.com/en-us/windows/arm/apps-on-arm-x86-emulation).
Executable architectures are read from file headers without running the tools.
PAC's shim must match the selected .NET host; a mixed ARM64/x64 installation
must not be treated as ready just because both version numbers look correct.
An emulated x64 SDK/PAC pair can remain in place; a fresh installation uses the
native SDK and PAC shim. No emulation software or Windows feature is installed.

The optional Azure CLI emulation path is explicitly shown in the plan when you
use `-IncludeAzureCli` on ARM64. Its real-world compatibility, including a clean
ARM64 Sandbox installation, still needs acceptance testing; the script verifies
that `az version` works after an approved installation and stops on failure.
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
   Microsoft .NET SDK, or optional Microsoft Azure CLI installer.
   If setup requests a restart, save your work, restart yourself, and run it again.
5. After prerequisites succeed, the same window offers
   [step 2: Power Platform plugins](#step-2-power-platform-plugins-in-the-same-setup-window).
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
(if requested) Azure CLI's Windows uninstall registration and bundled Python
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

For workflows that need Azure CLI, opt in explicitly on **both** the check and
install commands:

```powershell
.\Setup.cmd -CheckOnly -IncludeAzureCli
.\Setup.cmd -Install -Accept -NonInteractive -IncludeAzureCli
```

The optional [prerequisite skill](skills/power-platform-setup/SKILL.md) contains
these same instructions. Noninteractive runs do not silently opt into the new
plugin stage: use the separate flags below only after approval. The
[integration skill](skills/power-platform-integrations/SKILL.md) can guide
plugin setup or register Copilot Studio MCP. Skills instruct the agent to
execute approved work; they are not just command lists for the user to copy.

A GitHub URL does not itself install a skill. Load/copy the skills only using a
mechanism supported by your app version, or let the agent read them directly.
No personalized skills, MCP endpoints, or account settings are bundled.

## What gets installed

Compatible tools are left alone. Missing/unsupported tools are handled in this
order; optional Azure CLI comes last:

| Order | Tool | Preserved when | If setup is needed |
|---|---|---|---|
| 1 | Git for Windows | Version 2.40+ with a compatible executable architecture | Current stable native x64/ARM64 Git installer, current-user program directory |
| 2 | Node.js and npm | Node **22.18+ or 24 LTS**, bundled npm 10+, compatible executable architecture | Current **24 LTS** native x64/ARM64 MSI, machine-wide |
| 3 | .NET **SDK** | Stable **10.0** SDK files and a compatible SDK host present | Current stable .NET 10 native x64/ARM64 SDK installer, machine-wide |
| 4 | Power Platform CLI (PAC) | Recognized PAC executable version 1.0+ with a shim matching the selected SDK host architecture | Current stable `Microsoft.PowerApps.CLI.Tool`, global .NET tool for the current user |
| Optional | Azure CLI | Recognized MSI installation 2.60+, launcher, and compatible bundled Python present | Official x64 Azure CLI MSI, machine-wide; uses emulation on ARM64 |

These are this bootstrap's compatibility baselines, not a guarantee that every
Power Platform plugin supports every accepted version. Node 22.18+ and 24 cover
the current Copilot Studio MCP package's requirements as well as the marketplace's
LTS requirements; this setup deliberately does not treat an arbitrary newer Node
major as compatible. The .NET runtime alone is insufficient. Newer .NET SDK
majors do not replace the required 10.0 SDK. Compatible tools are not automatically
updated to the latest patch; keep them patched using your normal maintenance
process.

Nonstandard/portable installations, version-manager shims, stale PATH entries,
unknown file versions, and non-MSI Azure CLI installs may need manual repair.
The first executable on PATH is authoritative; setup does not delete or
reorder competing installations or overwrite version-manager configuration.
Installing Node 24 over a newer MSI may require manually removing that
unsupported major first. Setup stops if it cannot verify the result.
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

### PowerShell and downloaded-file security

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

## Step 2: Power Platform plugins in the same setup window

This stage runs **only after all selected prerequisites are ready**, never after
an installer failure or restart requirement. An interactive launch, including a
rerun on an already prepared PC, offers a host chooser. No selection is guessed
from the presence of a different application.

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

Prerequisite approval and plugin approval are distinct. After the user approves
both plans, for example:

```powershell
.\Setup.cmd -Install -Accept -NonInteractive -PluginHost ClaudeCode -AcceptPlugins
.\Setup.cmd -Install -Accept -NonInteractive -PluginHost CopilotCli -AcceptPlugins -IncludeDataverse
.\Setup.cmd -Install -Accept -NonInteractive -PluginHost CopilotApp -AcceptPlugins -IncludeDataverse
```

Choose **one** command for the intended host; do not run all three.
`-Accept` approves prerequisites; `-AcceptPlugins` approves only the chosen plugin
stage. Neither authorizes sign-in. `-IncludeDataverse` applies only to plugins;
`-IncludeAzureCli` remains a separate prerequisite option.

Noninteractive runs without `-PluginHost` skip plugins. `-PluginHost Skip`
explicitly suppresses the interactive chooser. `-CheckOnly -PluginHost
CopilotCli` can print the later plugin plan but remains offline, prompt-free and
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
invalid JSON, unsupported encodings, and custom `COPILOT_HOME` /
`CLAUDE_CONFIG_DIR` locations stop setup rather than being overwritten.
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

The [integration skill](skills/power-platform-integrations/SKILL.md) remains
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
Custom `COPILOT_HOME` / `CLAUDE_CONFIG_DIR` locations need manual review instead
of a guessed destination. Updates of a different previously installed copy need
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
Restart the chosen host or open a fresh chat, check that it discovers the skill,
then make that request yourself. Installing the instructions does **not** run them.

## Step 5: connect and remember sign-in (optional skill)

Use [power-platform-connect](skills/power-platform-connect/SKILL.md) **after**
prerequisites and the requested plugins/MCP definitions are installed. The final
setup stage can install the skill for you, or you can ask the agent to read the
linked source. This
agent-guided stage is deliberately not run by `Setup.cmd`: installation flags
do not grant permission to sign in, select an environment, switch an active
profile, or call a tenant.

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
| `2` | Cancelled, invalid options, or missing explicit opt-in. A cancelled plugin stage retains any prerequisites already installed. |
| `3` | Unsupported host/CLI output, detection, download, trust, installer, or prerequisite/plugin/MCP/skill verification failure. Stop and fix the reported cause. |
| `4` | Copilot desktop plugin links printed. App confirmations and plugin verification are still required. Prerequisites are ready. |
| `3010` | Installer requested/reported a restart. Chain stopped; restart Windows yourself, then rerun. |

The launcher forwards this code. Policy/PowerShell failures before the script
starts may return PowerShell's own nonzero code instead.

| Symptom | Safe next step |
|---|---|
| No `winget` in Sandbox | No action needed; this setup uses official direct installers. |
| Permission/UAC denied or installer code `1603` | Review admin/policy requirements; ask your administrator. Do not elevate the whole agent. |
| Installer code `1618` | Another Windows installation is running; let it finish, then rerun. |
| Installer succeeded but tool is still missing/old | Restart the Copilot app and terminal; inspect the reported path for a shadowing old install. Do not repeatedly install blindly. |
| TLS/proxy/certificate/download error or GitHub API rate limit | Fix access to the listed official endpoints, wait for a rate-limit reset if applicable, then rerun. Do not disable certificate checks or substitute random downloads. |
| .NET SDK exists but a project uses another SDK | Inspect that project's `global.json`; setup does not change it. |
| Azure reported unrecognized despite a working portable CLI | This release recognizes MSI metadata only. Use/repair the official MSI or manage that tool outside setup. |
| PAC installation fails | Check NuGet.org access, Windows policy, and whether an existing PAC shim conflicts. Source configuration is isolated, not taken from your project. |
| Selected `claude`/`copilot` command is missing | Use the host already installed. For Copilot desktop only choose `CopilotApp`; do not install another host as a workaround. |
| Plugin JSON output/source/disabled-state error | Review the selected CLI's supported version, marketplace source, scope, and policy privately. Setup does not fall back to guessed text parsing, force-enable plugins, or expose full configuration. |
| MCP configuration conflict, encoding, or concurrent-edit error | Stop, close the host, and inspect/reconcile the local configuration privately. Keep any reported backup; do not share it. No sign-in or cloud operation is needed to repair local registration. |
| Existing connection skill differs or the destination is linked | Review/update it intentionally in the host's supported skill location. Setup will not overwrite a custom or older definition. You can use the printed public-skill prompt without installing another copy. |

It is safe to rerun: completed compatible tools are skipped; a failure stops
the chain and does not roll back earlier successful vendor installations.
Remove software through Windows Installed apps or its own package manager;
there is no broad cleanup/uninstall command.

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
gates, and PATH preservation. Plugin tests mock both CLI schemas, approvals,
source collisions, skip/rerun, failures and official desktop links. MCP tests use
isolated dummy files for safe merge, backup, rerun, malformed/conflicting config,
and concurrent-write cases, plus mocked Claude registration. No plugin install,
app/server launch, real user configuration write, or sign-in is performed.
A real local inventory test uses only reads.
CI runs on Windows PowerShell 5.1 and PowerShell 7. CI does **not** install tools
or validate a pristine Sandbox installation on either architecture.

### Manual Sandbox acceptance (x64 or ARM64)

Use a separately authorized disposable Windows environment of the architecture
you want to test; an x64 CI runner with ARM64 mocks is not an ARM64 install test.
No Windows feature is enabled by these scripts. In your own Sandbox:

1. Download/extract the **full current source ZIP** inside the Sandbox. Keep any
   shared host folder read-only; install inside the guest, not on the host.
2. Run `.\Setup.cmd -CheckOnly`. Confirm it reports the guest's Windows
   architecture and lists missing tools in order without downloading or prompting.
3. Double-click `Setup.cmd`, review the plan, and type `INSTALL` to approve.
   For an Azure-dependent workflow, use `.\Setup.cmd -IncludeAzureCli` instead;
   on ARM64 confirm the plan explicitly identifies x64 Azure emulation.
4. If a restart is required, stop and follow the reported instructions. Do not
   treat that as a passing install or assume that closing/reopening Sandbox
   preserves its state.
5. After success, reopen the terminal and run `.\Setup.cmd -CheckOnly` again
   (with the same Azure flag if used). Expect exit `0` and no install plan.
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
file. An explicit allowlist includes the launcher, installer, README, agent
instructions, license, and skill; it excludes repository history, test outputs,
personal configuration, secrets, and installed packages. The ZIP is also
uploaded as a CI artifact. An artifact checksum detects accidental changes;
it is not a code-signing certificate or proof of publisher identity.

## License

[MIT](LICENSE) for this project's code. Vendor tools have their own licenses
and support policies. Review downloaded code before running it.
