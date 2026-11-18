---
name: power-platform-connect
description: Discover Dataverse environments with approved PAC context, choose one or more saved connections or enter an unlisted environment URL, and coordinate reusable CLI/MCP sessions with separate target and sign-in approvals. Add connections on later runs without replacing working profiles or copying tokens.
---

# Power Platform connection onboarding

Use after the local prerequisite/plugin setup when the user asks to connect,
sign in, remember an environment, switch an existing connection, or diagnose
repeated login prompts. This is an **agent-guided skill**, not an unattended
login script. Read the public setup repository's
[README](https://github.com/danieag/power-platform-setup/blob/main/README.md)
and [AGENTS.md](https://github.com/danieag/power-platform-setup/blob/main/AGENTS.md)
first. This skill can be installed standalone in a personal skills directory;
its source checkout is not necessarily the current working directory.

When the user started the complete guided flow, the bundled
`power-platform-setup` entry skill reads this file after the doctor stage.
Continue in that conversation if required capabilities are available; a
personal skill copy or a second user prompt is not required. Reopen the host
after prerequisite PATH changes, and use a clear pause/resume handoff if plugin
or MCP discovery needs a reload. None of the earlier installation/marketplace/
plugin approvals authorize this skill's authentication or configuration work.

The desired result is **one guided onboarding, then secure session reuse**.
It is not one shared token or a guarantee of no future MFA. Azure CLI, PAC,
Dataverse CLI, and Copilot Studio MCP can have separate authentication clients
and caches. Front-load only the sign-ins actually required; skip working ones.

## 1. Choose environments and confirm the approval boundary

The default guided sequence is **reuse/sign in with PAC > `pac env list` >
show environment names and URLs > choose one or more > set up only those
connections**. Do not start Dataverse CLI/MCP sign-ins before this choice just
to discover environments. A healthy existing PAC session needs no new login.
PAC discovery does not require installing Dataverse CLI, Python/SDK or an MCP
server, or signing into Azure; defer those choices until targets/tools are selected.

### Always offer discovery, saved connections, and a manual URL

On every run, including an already configured machine, offer:

- **Discover environments** using an approved PAC account/profile context.
- **Reuse a saved connection**, after permission to inspect the relevant private
  local binding/profile metadata.
- **Add another existing environment by URL**, whether or not discovery or a
  local saved-connection list contains it.

Do not treat "already connected" as a reason to ignore a request to add another
environment. "Add environment" here means **save a connection to an existing
environment**, not create/provision a Power Platform environment or register it
with a tenant. Manual entry remains available with zero results, partial
results, discovery failures, and previously saved connections.

### Discover with a confirmed PAC context, not an arbitrary active profile

First confirm the actual host, work sign-in account, owning Tenant ID and
permission to inspect local PAC profile/binding metadata. Complete step 2's
local prerequisite check before invoking PAC; missing tooling does not grant
installation consent. Ask one question at
a time using the help below. Use only supported profile commands, not token
files or cache decoding:

```powershell
pac auth list
pac auth who
```

These are local profile checks, not proof of live access. Profile names alone
are insufficient. Before any profile switch, sign-in or live discovery request,
show and confirm the account, tenant and **exact environment URL bound to the
proposed existing discovery profile**. Treat that environment as the explicitly
approved discovery context, not an automatically selected persistent target.
If metadata cannot establish the match, confirm the candidate with the user
and obtain approval for a bounded identity check before discovery. Stop on an
identity/tenant/URL mismatch; never silently use the default profile.

Ask permission for the specific discovery operation: list Dataverse environment
names/URLs through PAC under that confirmed context. It is an **authenticated
live metadata read**, not part of offline `Setup.cmd -CheckOnly`. Profile
selection, a needed sign-in/renewal, and discovery each need the corresponding
approval; do not make a network request just to populate an initial form.
Select an existing profile only with the user's approval, using the supported
`pac auth select` command, and recheck its metadata before listing.

After those approvals, use:

```powershell
pac env list
```

Microsoft documents this as Global Discovery Service discovery of **Dataverse
environments**. `pac org list` is a supported older alias; prefer `pac env list`.
Do not use `pac admin list`, change an environment, create one, or silently
fall back to Azure/other tenant-enumeration mechanisms. Do not invent a
`--tenant` or `--json` option for `pac env list`; check the installed version's
supported help/output and every exit code.

If there is **no matching authenticated PAC profile**, explain that live
discovery needs an approved sign-in. Confirm one existing environment URL as
the initial sign-in context, together with the account and tenant, then approve
and perform only its PAC setup/sign-in through step 4, using a transient
confirmed plan rather than saving a binding for an unselected target.
Return to `pac env list`
and the environment selection; the initial context is not automatically a
selected saved connection. Manual URL setup without discovery is also always
available. Do not run bare
`pac auth create`, which can choose a default environment, or bootstrap into an
unknown tenant just to obtain a list. A missing PAC CLI needs separate
installation approval; discovery does not authorize installing it.

Display a concise selection list with returned environment names and exact
URLs; include IDs only when the output explicitly identifies what they mean.
Show "already saved" only for an approved local binding with matching
account/tenant/URL. Do not treat cached profile presence, a discovery row, an
Organization ID or a friendly display name as full access verification.
Avoid publishing raw discovery/profile output or writing it into the repo.

Describe results as **environments returned by discovery in this context**,
not a guaranteed complete list across every tenant or every Power Platform
environment. Visibility, permissions, environment provisioning and service
availability can affect the result. Do not assign the confirmed tenant to a
row whose tenant is unknown; confirm it before onboarding. A different
directory requires its own context and approvals, not an automatic switch.

Ask which **one or more** environments the user wants saved connections for.
Use multi-select if supported, otherwise accept a numbered list. Always
include **Enter another environment URL** and **None / finish**. Resolve
duplicate display names by their exact URLs, then confirm the selected
account/tenant/URL mapping and tools before any target-specific changes.
An empty result or a failed discovery is not permission to invent targets,
declare that the user has no access, or disable manual entry.
If no targets are selected, create no further bindings/MCP definitions and
leave any earlier approved PAC sign-in/profile intact; do not delete it to
simulate rolling back discovery.

For manual entry, validate the existing environment's HTTPS origin and
confirm its account/tenant just as for discovered targets. An absent discovery
row or local registration does not bar setup, but neither proves access.
Reachability, identity and permissions still need approved verification.

### Ask in everyday language

Guide the user **one question at a time**, not through a six-question technical
form. Explain why each answer is needed and give a clearly fictional example.
Use details already supplied; do not make the user repeat them. Do not say
"per the skill" or expose implementation terms such as "exact HTTPS origin,"
"tenant GUID," "UPN," or "surfaces" without explaining them.

Use the following wording/help when a detail is missing:

| Detail | Plain-language question and explanation |
|---|---|
| Agent app | "Which app are you using for this connection?" Offer Copilot desktop, Copilot CLI, GitHub Copilot in VS Code, or Claude Code when it is not already clear. This determines where the connection is saved; VS Code and CLI are not interchangeable hosts. |
| Environment URL | For manual entry: "What is the web address of the existing Power Apps / Dataverse environment you want to connect to? For example, `https://yourorg.crm4.dynamics.com`." For discovery, let the user select returned URLs instead of typing them again. Explain that this is the environment's address, not `make.powerapps.com` or a link to a particular app/page. Help them find **Environment URL** in Power Platform admin center; the fictional example is not a target to use. |
| Tenant ID | "What is the Tenant ID of the Microsoft organization you want to discover or connect to environments in? Find it in **Microsoft Entra admin center > Entra ID > Overview > Properties > Tenant ID**. Select the directory that owns those environments, then copy and paste that Tenant ID here." Explain that **tenant = Microsoft organization/directory** and Tenant ID (also called Directory ID) is its unique identifier, normally shown as a long value such as `11111111-2222-3333-4444-555555555555`. It is **not** an Azure Subscription ID, PPAC Environment ID, or Dataverse Organization ID. Offer help if the user cannot access it. |
| Sign-in email | "Which work or school email address do you use to sign in to that Microsoft organization? For example, `alex@example.com`." Explain **UPN = sign-in username**, usually the work email address, but use the actual Microsoft sign-in name if their mailbox address differs. Never ask for a password. |
| Connection nickname | "What short name would you like to give this saved connection? For example, `my-demo-environment`." Explain that this **alias** is a local label so the agent can find the right saved setup later; it does **not** create or rename a Power Platform environment. Use lowercase letters, digits and hyphens, start with a letter, and keep it at most 30 characters. Suggest an alias and ask for confirmation rather than making it look like an ID the user must find. |
| Tools to connect | "Which tools would you like to connect?" Explain the selected choices: **PAC CLI** for Power Platform development/deployment; **Dataverse CLI** for Dataverse commands and its MCP proxy; **Azure CLI** for Azure-dependent plugin workflows; **Dataverse MCP** for Dataverse tools in chat; **Copilot Studio MCP** for Copilot Studio tools in chat. Do not silently select everything or label a choice "install via npm" before checking whether it is missing. |

**Tenant ID is not Subscription ID.** An Azure subscription organizes/bills
Azure resources and has a different ID. Do not ask for a subscription ID during
this ordinary Power Platform connection flow, even if Azure CLI is selected.
Use the tenant-scoped `--allow-no-subscriptions` flow below. Ask about a
subscription only for a separately requested Azure-resource task that needs it.

Include each field's explanation and example **in the question/help text shown
to the user**, not just in a separate chat summary or a link they may not open.
In particular, always include the Entra navigation in the Tenant ID question;
do not wait until the user gets stuck.

Offer "Help me find it" when the user does not know a value. For Tenant ID,
guide them to **Microsoft Entra admin center > Entra ID > Overview > Properties >
Tenant ID** (access depends on their permissions), or ask their administrator.
See [Microsoft's tenant ID guide](https://learn.microsoft.com/en-us/entra/fundamentals/how-to-find-tenant).
If the user pastes Power Platform admin center **environment details**, explain
that **Organization ID** identifies the Dataverse organization/database and
**Environment ID** identifies the Power Platform environment. Neither is the
Tenant ID, and "Trial (subscription-based)" is not an Azure Subscription ID.
Use any supplied environment URL without reasking, but guide them to Entra for
the still-missing Tenant ID and have them select the owning directory first.
The URL's region suffix does not identify that directory.
With approval, existing local profile metadata can supply a candidate to show
and confirm. Do not log in, enumerate tenants, or query the environment merely
to fill the form before that access has been approved. Do not guess or swap
in a subscription ID when the tenant is unknown.

**Do not ask for permission to install software as one of these initial
questions.** First collect/confirm the discovery context or connection targets
and requested tools, then inspect
the local installation as described in step 2. Ask about an additional package
only when there is evidence that it is needed and missing, or that a separately
approved upgrade is required. Configuration/sign-in approvals remain separate.

### Confirm the technical target before acting

For the discovery step, establish and approve its exact profile context as
described above. For **each selected or manually entered connection target**,
before authentication, profile selection, installation or configuration writes,
establish:

- The actual local host: Copilot desktop app, Copilot CLI, VS Code or Claude Code.
- An existing Dataverse environment's exact HTTPS origin URL and tenant GUID.
  Do not default to the active CLI profile, an example, a demo target, or a
  partially matched environment name. Reject credentials, query strings, and
  fragments in the URL. This Windows recipe targets the public Microsoft cloud;
  other clouds need their current official endpoint/authentication instructions.
- The expected work-account identity and a short local connection alias
  matching `^[a-z][a-z0-9-]{0,29}$` (also safe for PAC's 30-character profile name).
- Which surfaces the user wants: Dataverse CLI/PAC/Dataverse MCP, Azure CLI,
  optional Python SDK, and/or Copilot Studio MCP.

Collect missing details one question at a time. Show the proposed target,
account, surfaces, and local changes, then obtain explicit approval to sign in,
select/create named profiles, save private connection metadata, register the
requested MCP definition, and perform minimal **read-only identity checks**.
Installation approval is separate. Discovery approval does not authorize
persistent setup for every returned environment. An existing alias is a
candidate, not consent to its tenant or proof that cached authentication is valid.

For "status only" requests, inspect only approved local configuration/profile
metadata. Do not sign in, switch profiles, acquire tokens, launch servers, or
query an environment. State that local configuration does not prove live access.
The installer's `-CheckOnly` remains offline and does none of this onboarding.

For a test or rehearsal without an approved live target, use the repository's
isolated tests and instruction review only; do not run the authentication
examples against whatever account is already active. Installing this skill in
a temporary folder does not isolate PAC/Dataverse profiles, Windows account
brokers, or MCP servers under the same Windows user. Track explicitly approved
test additions and stop before removing anything not created by that test.
Never use broad logout/cache deletion as "cleanup."

No automatic environment creation, service principal, app registration, admin
consent, role grant, MCP allowlist change, connector creation, or cloud resource
write is part of this flow. A consent/403/policy blocker must be reported for a
separately approved admin action, not silently "fixed."

## 2. Check tools; reuse the official Dataverse connection skill

Locate the reviewed, extracted setup repository and run `.\Setup.cmd -CheckOnly`
**from that folder** first. If unavailable, ask where it was extracted or obtain
and review the full official source before running it; do not assume the script
exists in the current project or download a random launcher. The full setup now
includes Azure CLI after PAC by default. Use `-SkipAzureCli` only if the user
chooses a minimal setup without Azure-dependent workflows. Installing Azure
does not authorize signing into it; connect only the selected surfaces.
Missing prerequisites still need their own installation approval.
The same installer handles x64/ARM64; do not replace it with ad hoc installers.

Read the installed Microsoft Dataverse plugin's **`dv-overview`**, then
**`dv-connect`** and its current MCP/auth references. If the plugin is missing,
use this repository's integration stage only with the user's approval. Official
source: [Microsoft Dataverse connection skill](https://github.com/microsoft/Dataverse-skills/blob/main/.github/plugins/dataverse/skills/dv-connect/SKILL.md).

Use that specialist's supported profile/cache and proxy mechanisms; do not
copy its auth helper or implement another MSAL/device-code protocol. Its broader
flow can propose installs, `.env`, SDK scaffolding, or tenant writes: do **only**
the subset approved here. Do not create a project, solution, Python environment,
service principal, or repository-local settings just to sign in.

### Explain any additional Dataverse CLI installation

The three similarly named components are different:

| Component | What the user may already have |
|---|---|
| Power Platform CLI (**PAC**, command `pac`) | Installed by Setup.cmd as a .NET global tool. It is not the separate `dataverse` command. |
| **Dataverse plugin** | Agent instructions/tools installed through the optional plugin stage or app links. Selecting Dataverse in that stage does not by itself install the npm CLI. |
| **Dataverse CLI**, command `dataverse` | The separate official npm package **`@microsoft/dataverse`**. It provides commands and the stdio MCP proxy used by this connection flow. It may already be installed from previous setup, so check first. |

First check the local application command without attempting sign-in:

```powershell
Get-Command dataverse -CommandType Application -ErrorAction SilentlyContinue
```

If the command exists, inspect its installed package/version through supported
local tooling and reuse it when compatible. **Do not ask to install it again
merely because onboarding was invoked or the Dataverse plugin was selected.**
If the command is missing, check the installed npm global package listing:

```powershell
npm.cmd list --global @microsoft/dataverse --depth=0 --json
```

Treat an empty package listing differently from a command failure. If the
package is installed but its launcher is not on PATH, explain that the app/
terminal may need restarting and resolve its actual installed launcher; do
not reinstall a second copy as a PATH fix. A broken or incompatible installation
needs a stated diagnosis and repair/upgrade approval, not a claim it is absent.

Only when the package is missing and Dataverse CLI/proxy was selected, inspect
the current package requirements and explain the additional installation:

> "The Dataverse command-line tool is not installed yet. Setup installed PAC,
> and the Dataverse plugin adds instructions for your agent; neither is this
> separate command-line tool. The official `@microsoft/dataverse` package adds
> the `dataverse` command and the MCP proxy so your chat tools can reuse its
> sign-in. May I download and install it for this computer? This does not sign
> you in or change your Power Platform environment."

Replace this example with the **actual finding**; do not claim that a plugin
or PAC is installed if it is not. Explain that **npm** is the package manager
included with Node.js, **`@microsoft/dataverse`** is Microsoft's package name,
and **global** means a reusable command outside one project, not access to
all tenants/environments. Inspect/show the configured npm install prefix when
proposing the change: a custom or machine-wide prefix can require additional
permission; do not promise it always affects only one user.

After that specific approval, use:

```powershell
npm.cmd install --global @microsoft/dataverse@latest
```

Install once when missing, not on every chat. Preserve the organization's npm
registry/policy and an existing working package; upgrades need approval.
Use supported command help for the installed version, check every exit code,
and report incompatible versions instead of guessing flags. `pac` prints its
version banner; do not assume `pac --version` is supported.

Python is optional: if requested, use `dv-connect`'s current SDK/helper setup
and shared-cache integration. It requires its own dependency/file-change
approval. Do not install Python just to authenticate these CLIs.

## 3. Remember bindings, not credentials

### Process the selected environments separately

Show the proposed target list: confirmed account/tenant/URL, one unique nickname
per environment, selected tools, existing matches and actual missing items.
Deduplicate repeated selections of the same normalized URL/account/tenant
across discovery, saved connections and manual entry. Do not merge distinct
environments merely because display names match, or merge different identities.
Obtain approval for the specific changes to those targets, separately from
discovery. A bounded batch approval may name several exact targets, but must
not include unselected environments or silently add another tenant/account.
Group only the same action category across that target set; this does not
combine separate sign-in, binding-write, MCP-registration and live-check gates.

Check/install shared prerequisites once, only when missing and approved.
Then perform steps 3-7 **for each selected environment**, serializing PAC and
Dataverse profile changes. Reuse working sessions rather than signing in
again merely because a second environment or another chat was selected.
Do not promise one universal login or a distinct new login for every target:
the official clients decide whether cached sessions can be reused.

Keep one binding and distinct Dataverse MCP entry per selected target. Reuse
actual matching profile names instead of creating duplicates; an existing alias must not be repointed
to another environment. Same-tenant/account targets can reuse the approved
Azure cache directory, while every live check still uses its explicit target.
Never copy caches to make profiles appear persistent.

Only one PAC/Dataverse profile is active in each CLI at a time; saved
connections do not make all targets simultaneously active. Explain the effect
of each approved switch on other sessions, and recheck identity before the
next target. At the end, ask which saved connection should be active for
continued work, or whether the previous selection should be restored, before
making that state change. Never leave the last iterated target as an
unannounced default.

With approval, keep one **private, user-local connection record** at:

```text
%LOCALAPPDATA%\PowerPlatformSetup\connections\<alias>.json
```

This is a binding record, not another token cache. A representative record
shape is below; placeholders must be replaced with user-confirmed/verified
values. Never save a placeholder as a working connection.
This schema remains one record per alias; multiple selected environments do
not require replacing old records with a combined credential store.

```json
{
  "schemaVersion": 1,
  "alias": "<connection-alias>",
  "host": "CopilotApp",
  "tenantId": "<confirmed-tenant-guid>",
  "account": "<confirmed-work-account>",
  "environmentUrl": "<confirmed-https-environment-origin>",
  "environmentId": "<verified-environment-guid>",
  "organizationId": "<verified-organization-guid>",
  "pacProfile": "<matching-existing-or-new-profile-name>",
  "dataverseProfile": "<matching-existing-or-new-profile-name>",
  "azureConfigDir": "<approved-existing-or-dedicated-cache-directory>",
  "dataverseMcpServer": "<host-server-name>",
  "copilotStudioMcpServer": null
}
```

Omit optional surface fields when unused. Initially save only confirmed
bindings if onboarding is incomplete; do not invent missing IDs or label that
record verified. Save discovered environment/organization IDs only after both
identity and target have been checked. Add no passwords, tokens, cookies,
client secrets, exported profiles, or credential-cache content.

The record includes account/environment metadata, so keep it private even
though it contains no credentials. Never write it into this public setup repo,
attach it to an issue, or include it in a release ZIP. Preserve local ACLs and
other records; do not overwrite malformed JSON, a mismatched alias binding, or
concurrent edits. Use safe atomic editing with a private recovery copy when
needed. Do not adopt another user's or host's local registry.

If existing profiles match, record their actual names and cache location; do
not create duplicates to force them to use the alias. Reuse one Azure cache
for an already confirmed account/tenant pairing where possible, even across
its environments. Otherwise propose a dedicated directory:

```text
%LOCALAPPDATA%\PowerPlatformSetup\azure\<alias>
```

An alias bound to another account/tenant must not be repointed without a new
decision. A new Azure directory will not magically reuse the default directory's
session: explain that it may require one initial sign-in. Never move/copy cache
files to populate it.

## 4. Reuse or establish the selected sessions

Run the selected tools under the **same local Windows user**. Respect existing
`AZURE_CONFIG_DIR`, `COPILOT_HOME`, `CLAUDE_CONFIG_DIR`, and tool-specific
settings; inspect their effect and ask before changing a binding. Do not
permanently alter global environment variables or browser profiles.

### Azure CLI, only when selected

For **every** Azure command, set the connection's `AZURE_CONFIG_DIR` in that
process. Terminal variables do not carry across separate agent shell calls.
Restore the inherited process value in `finally`; never use `setx`. For example,
given an already validated `$connection` record:

```powershell
$previousAzureConfigDir = $env:AZURE_CONFIG_DIR
try {
    $env:AZURE_CONFIG_DIR = $connection.azureConfigDir
    az account show --query "{tenant:tenantId,user:user.name}" --output json
} finally {
    $env:AZURE_CONFIG_DIR = $previousAzureConfigDir
}
```

Compare the returned tenant/account with the approved record. Do not accept
the default subscription as proof of the right Dataverse environment.
If the directory is already authenticated to another identity, stop; do not
clear it or silently use that account.

Only if sign-in is missing or renewal is genuinely required and the user has
approved that sign-in, run in the **same scoped directory**:

```powershell
az login --tenant $connection.tenantId --allow-no-subscriptions
```

The user completes MFA. Recheck the tenant/account afterward. Azure
subscriptions are not required merely to authenticate to a Power Platform
tenant; selecting/managing subscriptions is a separate task.
Default Windows broker SSO can reduce prompts. A permitted device-code
alternative is `az login --tenant $connection.tenantId --allow-no-subscriptions
--use-device-code`; it is not an MFA/policy bypass.

Never open an authentication URL in an arbitrary browser/profile: use the
user-confirmed Microsoft Edge profile, or the approved OS broker. If the
host/server's automatic browser launch cannot respect the intended account,
pause for the user rather than completing sign-in under the wrong identity.
Do not sign out an unrelated browser account or disable the Windows broker.

### Dataverse CLI and PAC

Inspect the existing profiles through the supported CLIs, not raw token files:

```powershell
dataverse auth list
pac auth list
```

Inspect only the needed fields and do not publish account listings. Reuse a
profile only when its account, tenant, and environment match. Profile names
alone are not proof. No destructive `auth clear`, logout, profile deletion, or
credential injection is a normal setup step.
An expired access-token timestamp alone is not proof that a session needs a new
login: the official tool may refresh silently. Try its approved supported
identity check first; pause if interactive renewal is required.

For an existing match, select the recorded profile before using that CLI:

```powershell
dataverse auth select --name $connection.dataverseProfile
pac auth select --name $connection.pacProfile
```

These are real tool-state changes: the user must approve switching, and other
concurrent sessions may share the active selection. Where a command supports
an explicit target, pass it as well. Serialize conflicting profile operations,
and recheck identity immediately before later environment operations; never
assume a prior chat's active profile is still selected.

Only if a required profile is missing/expired and its sign-in is approved,
use `dv-connect`'s current user-auth flow. A typical new-profile sequence is:

```powershell
dataverse auth create --name $connection.alias --environment $connection.environmentUrl
pac auth create --name $connection.alias --environment $connection.environmentUrl
```

Check name collisions before creating either profile. If the alias already
names a different binding, stop and agree a new name instead of replacing it.
Use `--deviceCode` only when appropriate, supported by the installed version,
allowed by tenant policy, and agreed with the user. PAC uses its own auth
client/cache: a separate initial prompt can be expected. Do not blindly choose
PAC's `--managedIdentity` mode to make it appear to share an Azure login; using
that supported credential-chain mode is a separate, explicitly verified choice.

On failure, distinguish identity/MFA/consent, wrong profile, permissions, proxy,
TLS, timeout, and native-runtime errors. A network failure is not a reason to
log out working profiles or keep repeating device-code login.

## 5. Register Dataverse MCP to reuse the supported session

This skill's default is the official **Dataverse CLI stdio proxy** because it
can reuse the CLI's supported MSAL cache. Direct HTTP MCP OAuth is a different
authentication surface; do not promise it shares that cache or silently replace
an existing working HTTP registration.

Use the installed official `@microsoft/dataverse` package, rather than fetching
`@latest` every time the MCP process starts:

- Resolve `node.exe` and the installed package via the existing npm global
  location (`npm.cmd root --global`) and the `dataverse.cmd` command location.
  Confirm the package's identity and that the proxy entry point actually
  exists. Do not search arbitrary private host internals.
- Read the installed `dv-connect` reference for the current proxy invocation
  and required operation-context attribution. Follow its supported contract;
  do not invent an OAuth client ID, token header, server URL, or attribution.
- Present the actual absolute paths and exact target URL for approval. A launch
  shape is `node "<installed-dataverse.js>" mcp <confirmed-environment-url>`.
  This is a **host configuration**, not a command to leave running in a terminal.
- Choose a per-environment server name (for example `dataverse-<alias>`).
  Check existing host user/project/plugin registrations for an equivalent
  target. Reuse a match; stop on a conflicting source/URL or duplicate before
  modifying anything. Do not force-enable disabled or managed entries.
- Register with the chosen host's documented mechanism. Copilot desktop/CLI
  supports user-scope `%USERPROFILE%\.copilot\mcp-config.json`; Claude Code uses
  its supported `claude mcp add --scope user --transport stdio ...` form.
  For VS Code, use the actual selected harness's documented MCP configuration;
  do not assume the desktop/CLI file applies to every VS Code session.
  Preserve unrelated definitions, ACLs, tool restrictions and safe backups.
  Stop on malformed config, custom locations, or concurrent edits you cannot
  safely reconcile. A Copilot desktop user does not need another host installed.
- **Windows plugin `PreToolUse` hook errors (`"hook errored"`):** some installed
  Power Platform plugins (notably `model-apps@power-platform-skills`, `pcf`,
  `power-pages`, and `mobile-app`) attach Unix-quoted `PreToolUse` hooks to
  `Write|Edit|MultiEdit` that can fail on Windows when writing
  `%USERPROFILE%\.copilot\mcp-config.json` or
  `%LOCALAPPDATA%\PowerPlatformSetup\connections\<alias>.json` outside the
  workspace folder. Never silently bypass a blocked hook: name the exact plugin
  reported in the error, ask the user to **temporarily toggle that plugin off in
  `Customize > Installed`** (or disable it briefly in the selected host), retry
  the approved configuration write once they confirm, and **remind them to turn
  the plugin back on afterward**.
- Do not read, decode, copy, export, or transplant MSAL/DPAPI token caches.
  Authentication reuse is performed by the official tools, never by the skill.

Registration is not proof of connectivity. Tell the user when a host restart
or new chat is required and leave that step pending until it actually happens.
For several approved targets, prepare their distinct definitions before one
host reload where supported, rather than demanding a restart after every
entry. Verify each named server against its own environment afterward.
If Dataverse MCP needs tenant consent or an environment client allowlist
change, report the exact missing prerequisite and approval boundary. Do not
run `dataverse mcp allow`, create an enterprise app, or change permissions
under sign-in/registration approval.

## 6. Optional Copilot Studio MCP

Reuse the server already registered by Setup.cmd. For missing registration,
use the repository's [integration skill](https://github.com/danieag/power-platform-setup/blob/main/skills/power-platform-integrations/SKILL.md)
and separately approved `-CopilotStudioHost <host> -AcceptCopilotStudio` stage.
Never duplicate a working registration or run standalone `npx` as a login test.
For several selected environments, follow this server's actual advertised
connection model. Do not duplicate a registration or claim that every target
is simultaneously active; if only one active context is supported, ask which
approved target it should serve and report that limit.

After explicit approval to launch/connect, use the actual host's supported
MCP sign-in action. In Copilot desktop, prefer **Customize > Installed > the
server > Sign in**, or the actual server-provided sign-in flow; do not tell
desktop users to run CLI-only `/mcp auth`. Discover the current server status
and onboarding capabilities rather than guessing tools. A general CLI sign-in
does not authenticate Copilot Studio MCP.

The current package documents an OS-protected per-user cache across chats
(DPAPI on Windows). Inspect its advertised persistence status, when available,
without reading cache contents. If `credentialsPersisted` is false or memory-only
mode was deliberately selected, explain the consequence; do not override the
choice or write plaintext tokens. Older installed versions can differ; verify
the actual version before promising cross-chat reuse or proposing an update.

Confirm the selected account/environment using server status after sign-in.
Switching accounts/environments must retire stale tools/context as the host
requires. Do not disconnect/sign out a working server merely to "test" it:
disconnect can remove its remembered sign-in.

Other MCP servers (for example Power Automate) keep their own documented auth
contracts. Configure them only when requested, using that installed plugin's
setup; do not copy private wrappers, hardcode cache internals, or claim that
Azure/Dataverse auth automatically covers every server.

## 7. Verify identity, persistence, and honest completion

After the user has approved the **targeted read-only verification**, use
the specialist's supported checks:

```powershell
dataverse auth who
dataverse org who
pac auth who
pac env who --environment $connection.environmentUrl --json
```

Include the installed Dataverse plugin's required operation context for its
network call. Compare account, tenant, exact URL, environment and organization
IDs where each command exposes them; resolve missing identity fields through
the specialist's documented read-only identity check, never by guessing.
Use supported command help for older PAC versions (`org` is the documented
alias for `env`); do not silently drop explicit target verification.
An account/tenant/environment mismatch stops the workflow, not an automatic
switch to a different target.

For Azure, `az account show` proves only selected metadata, not a live session.
If approved, request a token for the confirmed resource using the supported CLI,
with an output query restricted to expiry metadata (`--query expiresOn --output
tsv`), so the token is never printed. This does not prove Dataverse permissions.
Dataverse/PAC identity checks above establish their live environment access.

Verify Dataverse MCP **through the selected host**, after restart if required.
Use one bounded read-only organization/identity request using the advertised
tools, not customer records or an agent/workflow creation. Compare organization
ID with the CLI-verified target. A registration listing alone is not "connected."
For Copilot Studio, distinguish saved definition, running server, sign-in,
environment connection, and credential persistence in its reported status.

Then test reuse in a fresh terminal/process and new host chat under the same
Windows user. Reload the approved private binding record, scope the Azure
directory, and select/recheck the matching CLI profiles. Skip new login when
the checks succeed. Record the restart check as **pending** until completed;
do not equate an existing cache file with proven persistence.

For multiple targets, verify and report **each alias/environment** separately,
including fresh-process/chat persistence. One working target does not verify
the others. Stop the batch on an identity/tenant mismatch; preserve completed
targets and report a per-target permission/reachability failure honestly,
asking before continuing with other approved targets. Do not label the whole
selection verified while any target remains blocked or pending.

Report a concise per-surface result for each target:

| Surface | Report separately |
|---|---|
| Azure CLI | Not selected / missing / matching local metadata / live auth checked / renewal needed |
| Dataverse CLI and PAC | Matching named profiles / live identity verified / blocked |
| Dataverse MCP | Definition saved / host restart needed / live identity verified |
| Copilot Studio MCP | Not selected / registered / signed in / connected to target / persistence reported |
| Restart acceptance | Pending / verified in a new process and chat |

Never print secrets or full configuration, and redact identity/path details
before a public report. Do not claim single sign-on forever: consent, policy,
MFA, token revocation, different OAuth clients, or a different Windows user
can legitimately require authentication again.

When finished, keep **Add another existing environment** available: reuse the
saved-connection choice, repeat approved discovery, or enter another URL.
On a later invocation, "add another environment" must reach these choices
even when previous connections are healthy. Do not repeat installations,
overwrite existing aliases, remove other profiles or require the new target
to appear in a local registry before it can be added. If the user chooses
finish/stop, do not keep prompting or initiate another target.

In Windows Sandbox, caches can persist between processes **inside the same
running guest**, but closing/resetting Sandbox normally discards them. Do not
export protected caches to the host or enable plaintext caching to survive it.

## Current official contracts

- [Dataverse connection flow](https://github.com/microsoft/Dataverse-skills/blob/main/.github/plugins/dataverse/skills/dv-connect/SKILL.md)
- [PAC authentication profiles](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/auth)
- [PAC Dataverse environment discovery](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/env#pac-env-list)
- [Azure interactive authentication](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli-interactively)
- [Azure configuration directory](https://learn.microsoft.com/en-us/cli/azure/azure-cli-configuration)
- [Copilot MCP configuration](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers)
- [Claude Code MCP configuration](https://code.claude.com/docs/en/mcp)
- [Copilot Studio MCP source](https://github.com/microsoft/copilot-studio-mcp)
- [Current package persistence documentation](https://www.npmjs.com/package/@microsoft/copilot-studio-mcp)
