---
name: power-platform-connect
description: After explicit target and sign-in approval, coordinate reusable Dataverse CLI, PAC CLI, and optional Azure CLI profiles plus Dataverse MCP on Windows. Reuse matching cached sessions, isolate tenants, and guide separate Copilot Studio MCP sign-in without copying tokens.
---

# Power Platform connection onboarding

Use after the local prerequisite/plugin setup when the user asks to connect,
sign in, remember an environment, switch an existing connection, or diagnose
repeated login prompts. This is an **agent-guided skill**, not an unattended
login script. Read this repository's `README.md` and `AGENTS.md` first.

The desired result is **one guided onboarding, then secure session reuse**.
It is not one shared token or a guarantee of no future MFA. Azure CLI, PAC,
Dataverse CLI, and Copilot Studio MCP can have separate authentication clients
and caches. Front-load only the sign-ins actually required; skip working ones.

## 1. Confirm the target and the approval boundary

Before any authentication, profile selection, tenant request, installation,
or configuration write, establish:

- The local host: Copilot desktop app, Copilot CLI, or Claude Code.
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
Installation approval is separate. An existing alias is a candidate, not consent
to its tenant or proof that cached authentication is valid.

For "status only" requests, inspect only approved local configuration/profile
metadata. Do not sign in, switch profiles, acquire tokens, launch servers, or
query an environment. State that local configuration does not prove live access.
The installer's `-CheckOnly` remains offline and does none of this onboarding.

No automatic environment creation, service principal, app registration, admin
consent, role grant, MCP allowlist change, connector creation, or cloud resource
write is part of this flow. A consent/403/policy blocker must be reported for a
separately approved admin action, not silently "fixed."

## 2. Check tools; reuse the official Dataverse connection skill

Check `.\Setup.cmd -CheckOnly` first. Use `-IncludeAzureCli` only when Azure was
selected. Missing prerequisites still need their own installation approval.
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

The Dataverse plugin is not the Dataverse CLI. Check for an installed
`dataverse` command. If missing, inspect the current package requirements and,
only after specific approval, use the official package:

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

With approval, keep one **private, user-local connection record** at:

```text
%LOCALAPPDATA%\PowerPlatformSetup\connections\<alias>.json
```

This is a binding record, not another token cache. A representative record
shape is below; placeholders must be replaced with user-confirmed/verified
values. Never save a placeholder as a working connection.

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
  Preserve unrelated definitions, ACLs, tool restrictions and safe backups.
  Stop on malformed config, custom locations, or concurrent edits you cannot
  safely reconcile. A Copilot desktop user does not need another host installed.
- Do not read, decode, copy, export, or transplant MSAL/DPAPI token caches.
  Authentication reuse is performed by the official tools, never by the skill.

Registration is not proof of connectivity. Tell the user when a host restart
or new chat is required and leave that step pending until it actually happens.
If Dataverse MCP needs tenant consent or an environment client allowlist
change, report the exact missing prerequisite and approval boundary. Do not
run `dataverse mcp allow`, create an enterprise app, or change permissions
under sign-in/registration approval.

## 6. Optional Copilot Studio MCP

Reuse the server already registered by Setup.cmd. For missing registration,
use the repository's [integration skill](../power-platform-integrations/SKILL.md)
and separately approved `-CopilotStudioHost <host> -AcceptCopilotStudio` stage.
Never duplicate a working registration or run standalone `npx` as a login test.

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
pac org who
```

Include the installed Dataverse plugin's required operation context for its
network call. Compare account, tenant, exact URL, environment and organization
IDs where each command exposes them; resolve missing identity fields through
the specialist's documented read-only identity check, never by guessing.
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

Report a concise per-surface result:

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

In Windows Sandbox, caches can persist between processes **inside the same
running guest**, but closing/resetting Sandbox normally discards them. Do not
export protected caches to the host or enable plaintext caching to survive it.

## Current official contracts

- [Dataverse connection flow](https://github.com/microsoft/Dataverse-skills/blob/main/.github/plugins/dataverse/skills/dv-connect/SKILL.md)
- [PAC authentication profiles](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/auth)
- [Azure interactive authentication](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli-interactively)
- [Azure configuration directory](https://learn.microsoft.com/en-us/cli/azure/azure-cli-configuration)
- [Copilot MCP configuration](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers)
- [Claude Code MCP configuration](https://code.claude.com/docs/en/mcp)
- [Copilot Studio MCP source](https://github.com/microsoft/copilot-studio-mcp)
- [Current package persistence documentation](https://www.npmjs.com/package/@microsoft/copilot-studio-mcp)
