# Power Platform setup for Windows

**Download, extract, run Setup.** This helps you prepare a Windows PC to use
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
3. **Run:** review the downloaded script, then double-click **Setup.cmd**
   (Windows may show it simply as **Setup**). You do not need to open PowerShell.
4. **Approve:** read the plan, type **INSTALL**, and press **Enter**.
   Setup installs missing tools in this order:
   **Git > Node.js/npm > .NET 10 SDK > PAC CLI > Azure CLI**.
   Compatible tools already installed are skipped.
5. **Wait, then answer the optional prompts** below. Keep this window open.
   When finished, restart your chosen app and terminals.

Only run code you trust. If unsure, ask your IT administrator or agent to review
`Setup.ps1` first. Start setup as your **normal user**, not "Run as administrator";
Windows can ask separately when an individual installer needs admin permission.
Follow your organization's restrictions rather than disabling Windows protections.

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
