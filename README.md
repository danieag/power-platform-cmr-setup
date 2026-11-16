# Power Platform setup for Windows

**Download, extract, then choose Setup or your coding agent.** This helps you prepare a Windows PC to use
Microsoft's Power Platform plugins with **GitHub Copilot or Claude Code**.
You must already have your chosen app installed.

Use the **same Setup.cmd** on Intel/AMD x64 PCs and ARM64 Windows 11 PCs.
It checks your computer, shows a plan, and asks before installing anything.
It does not sign you in or create anything in your Microsoft environment.

## Simple version

1. **Download:** on [this repository](https://github.com/danieag/power-platform-setup),
   click **Code > Download ZIP**.
2. **Extract:** right-click the ZIP, choose **Extract All**, and open the extracted
   folder containing `Setup.cmd` and `Setup.ps1`.

Now choose **Alternative A or B**, not both at the same time. They use the
same setup script and approval rules. Keep all extracted files together.

### Alternative A: run Setup yourself

1. **Run:** review the downloaded script, then double-click **Setup.cmd**
   (Windows may show it simply as **Setup**). You do not need to open PowerShell.
2. **Approve:** read the plan, type **INSTALL**, and press **Enter**.
   Setup installs missing tools in this order:
   **Git > Node.js/npm > .NET 10 SDK > PAC CLI > Azure CLI**.
   Compatible tools already installed are skipped.
3. **Wait, then answer the optional prompts** below. Keep this window open.
   When finished, restart your chosen app and terminals.

### Alternative B: use your coding agent

1. Open your coding agent and **add the extracted local folder to the session**.
   In the Copilot desktop app, click **+ > Add local folder or repository** and
   select the folder containing `AGENTS.md`, `README.md`, and `Setup.ps1`.
   In Claude Code, open/start it in that folder. You do not need to initialize
   a Git repository or install Git just to open the extracted folder.
2. Use an agent session that can run local terminal commands, with normal
   interactive approvals. If the app asks you to trust the folder, review it
   and make that decision yourself; do not enable blanket auto-approval.
3. Paste this prompt:

> Read `AGENTS.md`, `README.md`, and `Setup.ps1` in this folder.
> Run `.\Setup.cmd -CheckOnly`, explain which prerequisites are missing,
> and ask for approval before installing anything.
>
> After prerequisites are ready, guide me through Power Platform plugins,
> Copilot Studio MCP registration, and connection-skill installation.
> Ask for approval separately for each stage.
> Do not sign in, select a tenant, or change cloud resources.

`AGENTS.md` is an instruction file for the agent, **not a program you run**.
The agent checks first, explains the plan, and runs the same installer after
your approval. It can use the script's noninteractive flags after that approval,
so you may approve in chat rather than typing the terminal keywords yourself.
Windows administrator prompts and Copilot desktop plugin confirmations may
still need your action.

If Windows blocks running `Setup.ps1` directly, use **`Setup.cmd`** instead,
including for `-CheckOnly`. The launcher is the intended entry point and uses
a child-process-only policy exception; do not change persistent execution policy.
Enterprise restrictions can still block it and should be handled by your IT team.

<details>
<summary>Screenshots: add the local folder, then send the prompt</summary>

Choose **Add local folder or repository** (unrelated recent projects have been
cropped out):

![Copilot menu option to add a local folder or repository](docs/images/09-add-local-folder.png)

The extracted folder is attached to the session before the prompt is sent:

![Coding-agent setup prompt with the power-platform-setup-main folder attached](docs/images/10-agent-setup-prompt.png)

</details>

### Approvals and next steps for either alternative

Only run code you trust. If unsure, ask your IT administrator or agent to review
`Setup.ps1` first. Start setup as your **normal user**, not "Run as administrator";
Windows can ask separately when an individual installer needs admin permission.
Follow your organization's restrictions rather than disabling Windows protections.

For Alternative A, the terminal prompts are below. For Alternative B, the agent
guides the same stages and requests the corresponding approval in chat.

| Setup asks about... | What to do |
|---|---|
| Power Platform plugins | Choose **1** for an existing Claude Code command, **2** for an existing Copilot CLI command, or **3** for the Copilot desktop app. Type **PLUGINS** to approve the plan. Dataverse is optional: type **YES** when asked if you need it. |
| Copilot desktop links (option 3) | Open the **marketplace link first**, then each desired plugin link. Confirm each installation in the app. **Printing links does not install the plugins.** |
| Copilot Studio MCP | This gives your agent access to Copilot Studio tools. Choose your app, close that app as instructed, then type **MCP** to approve saving the connection setup. It does not sign you in. |
| Connection skill | Choose your app, then type **SKILL** to copy the instructions for later sign-in. Installing a skill does **not** run it. |

Press **Enter** at an optional host chooser to skip that stage. Other text at an
approval prompt cancels that stage; earlier successful installs stay installed.
Setup never installs another agent app just to make a host command available.

**Next: sign in through your agent chat.** Reopen your app, start a new chat,
and paste:

> Use the power-platform-connect skill to help me connect my Dataverse CLI,
> PAC CLI, Azure CLI, and Dataverse MCP. Check existing profiles first.
> Confirm my account, tenant, and environment, and ask before signing in or
> changing configuration. Reuse working sessions; do not change tenant permissions.

Remove anything you do not need; add Copilot Studio MCP if you also want its
sign-in. If the skill is missing or you skipped installation, ask the agent to
read [the connection skill](skills/power-platform-connect/SKILL.md) instead.
The agent can guide the commands; you still complete sign-in/MFA yourself.
Separate tools can require separate initial sign-ins. One universal login is
not guaranteed.

<details>
<summary>What will the connection skill ask me? Wasn't Dataverse already installed?</summary>

| Question | What it means |
|---|---|
| Environment URL | The web address of your Power Apps / Dataverse environment, for example `https://yourorg.crm4.dynamics.com`. It is not the general maker-portal address. |
| Tenant ID / Directory ID | The ID of your Microsoft organization. Find it in **Microsoft Entra admin center > Entra ID > Overview > Properties > Tenant ID**, after selecting the directory that owns your environment. It is **not** an Azure Subscription ID, PPAC Environment ID, or Dataverse Organization ID. |
| Work sign-in email (UPN) | The username you use to sign in, usually your work or school email address. It can differ from your email mailbox address. |
| Connection nickname (alias) | A friendly local name you choose, such as **`my-demo-environment`**. It helps the agent remember this connection; it does not rename your actual environment. |
| Tools to connect | Which tools you want to sign into or connect to chat. The agent should explain the choices, not assume you need every tool. |

**An Azure Subscription ID is not normally needed for this connection setup.**
It identifies an Azure resource/billing subscription, not your Microsoft
organization. The agent should not ask for it unless your separate Azure task
actually needs one. [How to find your Tenant ID](https://learn.microsoft.com/en-us/entra/fundamentals/how-to-find-tenant).

If PPAC's environment details show **Organization ID** and **Environment ID**,
neither is the Tenant ID. In **Microsoft Entra admin center**, select the
organization that owns the environment, then open **Entra ID > Overview >
Properties > Tenant ID**. Ask the tenant's administrator if you cannot access it.

**PAC CLI, the Dataverse plugin, and Dataverse CLI are different things.**
Setup installs **PAC CLI** (`pac`). The optional **Dataverse plugin** gives your
agent instructions and tools. The separate **Dataverse CLI** (`dataverse`) is
the npm package `@microsoft/dataverse`; it is not included in the base
prerequisite install.

The connection skill should **check whether that CLI is already installed
before asking to install it**. If it is missing and you want its commands/MCP
proxy, the agent explains the extra download and asks for approval then.
"Globally via npm" means making the command available outside one project,
using Node.js's package manager; it does not grant cloud access or sign you in.

Already installed an older copy of the connection skill? Setup deliberately
does not overwrite different skill content. Ask your agent to read the
[updated public skill](skills/power-platform-connect/SKILL.md), or review and
intentionally update your personal copy.

</details>

## Walkthrough with screenshots

These are cropped screenshots from a user-reported **ARM64 Windows Sandbox**
run of an older version. **Some show Azure CLI as optional; the current version
includes it after PAC.** Version numbers, language, and prompts can differ.
They show the workflow, not proof that every current feature has passed a
complete clean-machine test.

### 1. Download the ZIP

Use GitHub's green **Code** button and choose **Download ZIP**.
Download the whole repository, not just `Setup.cmd`.

![GitHub Code menu with Download ZIP selected](docs/images/01-download-zip.png)

### 2. Extract it and open Setup

Use **Extract All**, then open the folder that contains these files.
Do not run setup from inside the ZIP. Keep `Setup.ps1`, the `skills` folder,
and the other downloaded files together.

![Extracted setup folder containing Setup, Setup.ps1, and skills](docs/images/02-extracted-folder.png)

Double-click **Setup** / **Setup.cmd**, or right-click and choose **Open**
(the highlighted command in the supplied Norwegian screenshot). Do not choose
**Run as administrator** for the whole setup.

![Setup selected in File Explorer with the Open command visible](docs/images/03-open-setup.png)

### 3. Read the check and type INSTALL

The first check is called the **preflight**. `[READY]` means a compatible tool
was found. `[NEEDS SETUP]` means it needs installation or attention.
Nothing is downloaded until you approve the installation plan.

![Preflight showing missing tools and the INSTALL approval prompt](docs/images/04-approve-install.png)

### 4. Allow time for downloads and installation

**The .NET SDK stage can take much longer than the others.** In the reported
Sandbox session it took over an hour around this stage. That is one user's
experience, not an expected duration or a reason to ignore a reported failure.
Windows/connection speed can vary, and the download can time out.

While a vendor installer is running, the current script prints a **"Still
waiting" message about every 30 seconds**, with elapsed time. This is a heartbeat,
not a percentage, proof of package progress, or an estimated finish time.
Downloads and PAC's .NET tool command have their own output and are not covered
by this installer heartbeat.

Keep the window open while it is working and check for a Windows permission
prompt. Do not start a second setup while an installer is still running.
If setup reports **failed**, use [the recovery steps below](#if-setup-shows-an-error).

<details>
<summary>Screenshot: downloading the .NET SDK</summary>

![Setup downloading the ARM64 .NET SDK with PowerShell progress visible](docs/images/05-dotnet-download.png)

</details>

### 5. Choose the app for plugins

For **Copilot desktop**, choose **3**. Option **2** is for users who already
have the `copilot` terminal command; installing the desktop app alone does not
guarantee that command exists.

If requested, type **YES** for Dataverse, then review the plugin plan and type
**PLUGINS**. For option 3, open the printed links and confirm in the app.
Check **Customize > Installed** afterward.

<details>
<summary>Screenshot: choosing Copilot desktop and approving the plugin plan</summary>

![Copilot desktop option 3, Dataverse opt-in, and the PLUGINS approval prompt](docs/images/08-approve-plugins.png)

</details>

Keep following the window for optional **MCP** and **SKILL** setup, then use
the [sign-in prompt above](#simple-version) in your app. Sign-in is not started
by the installer.

## If setup shows an error

**A red error or exit code `3` is not a successful installation.**
Pressing Enter at "Press any key to continue" only closes the finished window.

In the supplied run, setup reported:

```text
Setup failed: Access to the path 'dotnet.exe' is denied.
Setup exit code: 3
```

<details>
<summary>Screenshots: the .NET error, and the SDK detected on a later run</summary>

![Setup reporting access denied for dotnet.exe and exit code 3](docs/images/06-dotnet-error.png)

On the later run, the check showed the .NET SDK as ready:

![A later check showing READY for .NET SDK 10.0.404](docs/images/07-dotnet-ready.png)

</details>

That later result **does not explain or fix the original error**. To check safely:

1. Let any active installer finish. If Windows asks for a restart, save your
   work and restart yourself. Do not run overlapping installers.
2. Open a new terminal in the extracted setup folder and run:

   ```powershell
   .\Setup.cmd -CheckOnly
   ```

   This only checks; it does not download, install, sign in, or open app links.
3. If .NET is now `[READY]` and PAC is still `[NEEDS SETUP]`, run `Setup.cmd`
   again, review the remaining plan, and approve it. Compatible installed tools
   are skipped. If the error repeats or .NET is still missing, stop and seek
   help using the exact error and exit code, with personal details removed.

Do not disable security software, change persistent PowerShell policy, or
assume administrator mode is the fix. See
[detailed troubleshooting and exit codes](docs/advanced-setup.md#exit-codes-and-troubleshooting).

## Detailed version

Read the [full technical guide](docs/advanced-setup.md) for all options, supported
Windows versions, download verification, architecture handling, authentication,
and contributor tests. Only install vendor tools on a supported Windows version.
On ARM64, Azure CLI uses the official x64 package under Windows 11 emulation.

For an agent-led start, ask it to read [AGENTS.md](AGENTS.md), check readiness,
and explain the plan before installing anything. Custom plugin/MCP setup uses
the [integration skill](skills/power-platform-integrations/SKILL.md).

This community bootstrap is not a Microsoft product. It never creates cloud
resources or enables agent auto-approval. Setup behavior has automated local
tests; full vendor installation, actual app discovery, and live authentication
are separate acceptance checks. [MIT license](LICENSE); vendor tools have their
own licenses.

**Latest user-reported ARM64 Sandbox result:** Git, Node.js/npm, .NET SDK, PAC,
and x64 Azure CLI under emulation completed. Copilot desktop plugin links were
printed (plugins not installed); MCP configuration and the skill file were saved
after a workaround for the then-incorrect default `COPILOT_HOME` rejection.
The current script accepts that default path without clearing the variable.
Actual app discovery and live sign-in were not tested in that run.
