#requires -Version 5.1
<#
.SYNOPSIS
Checks and, only with approval, installs local Power Platform and Copilot Managed Runtime prerequisites and offers plugin/MCP setup.
.EXAMPLE
.\Setup.ps1 -CheckOnly
.EXAMPLE
.\Setup.ps1 -Install -Accept -NonInteractive
.EXAMPLE
.\Setup.cmd -NonInteractive -PluginHost CopilotCli -Plugins "dataverse,model-apps" -AcceptPlugins
.EXAMPLE
.\Setup.cmd -NonInteractive -PluginHost CopilotCli -MarketplaceOnly -AcceptPlugins
.EXAMPLE
.\Setup.cmd -CheckOnly -PluginHost CopilotCli -Plugins "canvas-apps,power-automate" -Prerequisites FromPlugins
.EXAMPLE
.\Setup.cmd -CheckOnly -Plugins "copilot-managed-runtime" -Prerequisites FromPlugins
.EXAMPLE
.\Setup.cmd -Install -Accept -NonInteractive -PluginHost CopilotCli -Plugins "model-apps,copilot-managed-runtime" -Prerequisites FromPlugins -AcceptPlugins
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Install,
    [switch]$Accept,
    [switch]$NonInteractive,
    [switch]$IncludeAzureCli,
    [switch]$SkipAzureCli,
    [AllowEmptyString()][string]$Prerequisites = 'All',
    [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$PluginHost,
    [AllowEmptyString()][string]$Plugins = 'All',
    [switch]$MarketplaceOnly,
    [ValidateSet('PowerPlatform', 'CopilotManagedRuntime', 'Both')][string]$Marketplace = 'PowerPlatform',
    [switch]$SkipMarketplace,
    [switch]$IncludeDataverse,
    [switch]$IncludeCmr,
    [switch]$AcceptPlugins,
    [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$CopilotStudioHost,
    [switch]$AcceptCopilotStudio,
    [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$ConnectionSkillHost,
    [switch]$AcceptConnectionSkill
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SetupArchitecture {
    if ($env:OS -ne 'Windows_NT') { throw 'This installer supports Windows only.' }
    # Machine registry is authoritative even when PowerShell itself runs under emulation.
    $native = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name PROCESSOR_ARCHITECTURE
    switch ($native) {
        'AMD64' { $architecture = 'x64' }
        'ARM64' { $architecture = 'arm64' }
        default { throw 'This release supports x64 and ARM64 Windows only, not 32-bit Windows.' }
    }
    if (-not [Environment]::Is64BitProcess) {
        throw 'Open 64-bit Windows PowerShell or PowerShell and run setup again.'
    }
    $build = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber
    if ([int]$build -lt 19045 -or ($architecture -eq 'arm64' -and [int]$build -lt 22000)) {
        throw 'Use Windows 11 on ARM64, or vendor-supported x64 Windows 11 / Windows 10 22H2 (build 19045 or newer).'
    }
    return $architecture
}

function Get-ExecutableArchitecture {
    param([AllowNull()][string]$Path)
    if (-not $Path) { return $null }
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { return 'unknown' }
        $stream.Position = 0x3C
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt ($stream.Length - 6)) { return 'unknown' }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { return 'unknown' }
        switch ($reader.ReadUInt16()) {
            0x8664 { return 'x64' }
            0xAA64 { return 'arm64' }
            0xA641 { return 'arm64' }
            0xA64E { return 'arm64' }
            0x014C { return 'x86' }
            default { return 'unknown' }
        }
    } finally { $reader.Dispose() }
}

function Test-ExecutableArchitecture {
    param([AllowNull()][string]$Actual, [string]$WindowsArchitecture)
    if ($WindowsArchitecture -eq 'arm64') { return $Actual -in @('arm64', 'x64', 'x86') }
    return $Actual -in @('x64', 'x86')
}

function ConvertTo-ToolVersion {
    param([AllowEmptyString()][string]$Text)
    if ($Text -match '(?<!\d)(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    return $null
}

function Find-SetupExecutable {
    param([string]$Name, [string[]]$Candidates = @())
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return $null
}

function Get-BinaryVersion {
    param([AllowNull()][string]$Path)
    if (-not $Path) { return $null }
    return ConvertTo-ToolVersion (Get-Item -LiteralPath $Path).VersionInfo.ProductVersion
}

function New-ToolState {
    param([string]$Id, [string]$Name, $Version, [bool]$Ready, [string]$Path, [string]$Requirement, [string]$Architecture)
    [pscustomobject]@{
        Id = $Id; Name = $Name; Version = $Version; Ready = $Ready
        Path = $Path; Requirement = $Requirement; Architecture = $Architecture
    }
}

function Get-SetupState {
    param([switch]$Azure, [switch]$Cmr, [ValidateSet('x64', 'arm64')][string]$Architecture = (Get-SetupArchitecture))
    # Read files/registry only: even first-run CLI initialization is excluded.
    $git = Find-SetupExecutable 'git.exe' @(
        "$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")
    $version = Get-BinaryVersion $git
    $binaryArchitecture = Get-ExecutableArchitecture $git
    $compatible = Test-ExecutableArchitecture $binaryArchitecture $Architecture
    $gitReady = $compatible -and $null -ne $version -and $version -ge [version]'2.40.0'
    $gitRequirement = 'Git >= 2.40'
    if ($Cmr) {
        $gcmCandidates = @()
        if ($git) {
            $gitRoot = Split-Path -Parent (Split-Path -Parent $git)
            $gcmCandidates = @(
                (Join-Path $gitRoot 'mingw64\bin\git-credential-manager.exe'),
                (Join-Path $gitRoot 'mingw64\libexec\git-core\git-credential-manager.exe'),
                (Join-Path $gitRoot 'clangarm64\bin\git-credential-manager.exe'),
                (Join-Path $gitRoot 'clangarm64\libexec\git-core\git-credential-manager.exe'),
                (Join-Path $gitRoot 'mingw32\bin\git-credential-manager.exe'),
                (Join-Path $gitRoot 'mingw32\libexec\git-core\git-credential-manager.exe'),
                (Join-Path $gitRoot 'cmd\git-credential-manager.exe'))
        }
        $gcm = Find-SetupExecutable 'git-credential-manager.exe' $gcmCandidates
        $gitReady = $gitReady -and $null -ne $gcm
        $gitRequirement = 'Git >= 2.40 with Git Credential Manager'
    }
    New-ToolState 'git' 'Git' $version $gitReady $git $gitRequirement $binaryArchitecture

    $node = Find-SetupExecutable 'node.exe' @("$env:ProgramFiles\nodejs\node.exe")
    $version = Get-BinaryVersion $node
    $npmVersion = $null
    if ($node) {
        $nodeRoot = Split-Path -Parent $node
        $npm = Join-Path $nodeRoot 'npm.cmd'
        $npmManifest = Join-Path $nodeRoot 'node_modules\npm\package.json'
        if ((Test-Path -LiteralPath $npm -PathType Leaf) -and (Test-Path -LiteralPath $npmManifest -PathType Leaf)) {
            $npmVersion = ConvertTo-ToolVersion ((Get-Content -LiteralPath $npmManifest -Raw | ConvertFrom-Json).version)
        }
    }
    $supportedNodeMajors = @(22, 24, 26)
    $nodeSupported = $null -ne $version -and $version.Major -in $supportedNodeMajors -and
        ($version.Major -ne 22 -or $version -ge [version]'22.18.0')
    $nodeRequirement = 'Node 22.18+ (22.x), 24 or 26 with bundled npm >= 10'
    if ($Cmr) {
        $nodeSupported = $nodeSupported -and $version -ge [version]'24.11.0'
        $nodeRequirement = 'Node 24.11+ (approved LTS) with bundled npm >= 10 (required by Copilot Managed Runtime)'
    }
    $nodeArchitecture = Get-ExecutableArchitecture $node
    $nodeReady = $nodeSupported -and (Test-ExecutableArchitecture $nodeArchitecture $Architecture) -and
        $null -ne $npmVersion -and $npmVersion -ge [version]'10.0.0'
    New-ToolState 'node' "Node.js / npm ($npmVersion)" $version $nodeReady $node $nodeRequirement $nodeArchitecture

    $dotnet = Find-SetupExecutable 'dotnet.exe' @(
        "$env:ProgramFiles\dotnet\dotnet.exe", "$env:ProgramFiles\dotnet\x64\dotnet.exe")
    $dotnetArchitecture = Get-ExecutableArchitecture $dotnet
    $sdk = $null
    if ($dotnet) {
        $sdkRoot = Join-Path (Split-Path -Parent $dotnet) 'sdk'
        if (Test-Path -LiteralPath $sdkRoot -PathType Container) {
            $sdk = Get-ChildItem -LiteralPath $sdkRoot -Directory |
                Where-Object { $_.Name -match '^10\.0\.\d+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'dotnet.dll')) } |
                ForEach-Object { [version]$_.Name } | Sort-Object -Descending | Select-Object -First 1
        }
    }
    $sdkReady = $null -ne $sdk -and (Test-ExecutableArchitecture $dotnetArchitecture $Architecture)
    New-ToolState 'dotnet' '.NET SDK' $sdk $sdkReady $dotnet '.NET 10.0 stable SDK (not just runtime)' $dotnetArchitecture

    $pac = Find-SetupExecutable 'pac.exe' @("$env:USERPROFILE\.dotnet\tools\pac.exe")
    $version = Get-BinaryVersion $pac
    $binaryArchitecture = Get-ExecutableArchitecture $pac
    $ready = $sdkReady -and $binaryArchitecture -eq $dotnetArchitecture -and
        $null -ne $version -and $version -gt [version]'2.10.0'
    New-ToolState 'pac' 'Power Platform CLI' $version $ready $pac 'PAC > 2.10.0 with a shim matching the selected .NET architecture' $binaryArchitecture

    if ($Azure) {
        $az = Find-SetupExecutable 'az.cmd' @(
            "$env:ProgramFiles\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
            "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\CLI2\wbin\az.cmd")
        $version = $null
        foreach ($key in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
            if (Test-Path $key) {
                $entry = Get-ItemProperty $key | Where-Object {
                    $_.PSObject.Properties['DisplayName'] -and
                        $_.DisplayName -match '^Microsoft Azure CLI(?: \((?:32|64)-bit\))?$'
                } | Select-Object -First 1
                if ($entry -and $entry.PSObject.Properties['DisplayVersion']) {
                    $version = ConvertTo-ToolVersion $entry.DisplayVersion
                    if ($version) { break }
                }
            }
        }
        $azArchitecture = $null
        if ($az) {
            $python = Join-Path (Split-Path -Parent (Split-Path -Parent $az)) 'python.exe'
            if (Test-Path -LiteralPath $python -PathType Leaf) { $azArchitecture = Get-ExecutableArchitecture $python }
        }
        $ready = $null -ne $az -and $null -ne $version -and $version -ge [version]'2.60.0' -and
            (Test-ExecutableArchitecture $azArchitecture $Architecture)
        New-ToolState 'azure' 'Azure CLI' $version $ready $az 'Azure CLI MSI >= 2.60 (x64 emulation on ARM64)' $azArchitecture
    }

    if ($Cmr) {
        $ms = Find-SetupExecutable 'ms.cmd' @("$env:APPDATA\npm\ms.cmd")
        $cmrVersion = $null
        if ($ms) {
            $cmrManifest = Join-Path (Split-Path -Parent $ms) 'node_modules\@microsoft\cmr-cli\package.json'
            if (Test-Path -LiteralPath $cmrManifest -PathType Leaf) {
                try {
                    $cmrPkg = Get-Content -LiteralPath $cmrManifest -Raw | ConvertFrom-Json
                    if ($cmrPkg -is [pscustomobject] -and
                        $cmrPkg.PSObject.Properties['name'] -and $cmrPkg.name -ceq '@microsoft/cmr-cli' -and
                        $cmrPkg.PSObject.Properties['version']) {
                        $cmrVersion = ConvertTo-ToolVersion $cmrPkg.version
                    }
                } catch { $cmrVersion = $null }
            }
        }
        $cmrReady = $nodeReady -and $null -ne $ms -and $null -ne $cmrVersion -and $cmrVersion -ge [version]'1.0.0'
        New-ToolState 'cmr' 'Copilot Managed Runtime CLI (ms)' $cmrVersion $cmrReady $ms '@microsoft/cmr-cli >= 1.0.0 (ms command, requires Node >= 24.11.0)' $nodeArchitecture
    }
}

function Show-SetupState {
    param([object[]]$State, [switch]$Selective)
    Write-Host "`nLocal prerequisite readiness (no tenant access):"
    foreach ($tool in $State) {
        $status = if ($tool.Ready) { 'READY' } else { 'NEEDS SETUP' }
        $detected = if ($tool.Version) { $tool.Version.ToString() } else { 'not detected / unrecognized' }
        Write-Host ("  [{0}] {1}: {2}" -f $status, $tool.Name, $detected)
        Write-Host "    Required: $($tool.Requirement)"
        if ($tool.Path) { Write-Host "    Found: $($tool.Path)" }
        if ($tool.Architecture) { Write-Host "    Executable architecture: $($tool.Architecture)" }
    }
    Write-Host "`nDesktop plugins: NOT VERIFIED. Configure separately in the Copilot app; see README."
    Write-Host 'Authentication / environment permissions: NOT CHECKED. Setup never signs you in.'
    if ($Selective) {
        Write-Host 'Selective prerequisite mode: unselected core tools were skipped intentionally.'
    } else {
        Write-Host 'Azure CLI is included after PAC by default. -SkipAzureCli is for minimal setups without Azure-dependent plugins.'
    }
}

function Update-SetupPath {
    # Preserve inherited process entries, then append newly registered and known locations.
    $paths = @($env:PATH -split ';') +
        @([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';') +
        @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') +
        @("$env:LOCALAPPDATA\Programs\Git\cmd", "$env:ProgramFiles\Git\cmd",
          "$env:ProgramFiles\nodejs", "$env:APPDATA\npm", "$env:ProgramFiles\dotnet",
          "$env:USERPROFILE\.dotnet\tools", "$env:ProgramFiles\Microsoft SDKs\Azure\CLI2\wbin")
    $unique = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $paths) {
        if ($path) {
            $expanded = [Environment]::ExpandEnvironmentVariables($path.Trim())
            if (-not $unique.Contains($expanded)) { $unique.Add($expanded) }
        }
    }
    $env:PATH = $unique -join ';'
}

function Assert-OfficialUrl {
    param([string]$Url)
    $uri = [uri]$Url
    $allowed = @('api.github.com', 'github.com', 'nodejs.org',
        'dotnetcli.blob.core.windows.net', 'builds.dotnet.microsoft.com',
        'download.visualstudio.microsoft.com', 'aka.ms')
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or
        $uri.Host -notin $allowed -or $uri.UserInfo -or -not $uri.IsDefaultPort) {
        throw "Refusing an installer source outside the built-in official HTTPS allowlist: $Url"
    }
}

function Get-OfficialJson {
    param([string]$Url)
    Assert-OfficialUrl $Url
    Invoke-RestMethod -Uri $Url -Headers @{ 'User-Agent' = 'power-platform-cmr-setup' } -TimeoutSec 60
}

function Get-InstallerSpec {
    param(
        [ValidateSet('git', 'node', 'dotnet', 'azure')][string]$Id,
        [ValidateSet('x64', 'arm64')][string]$Architecture = (Get-SetupArchitecture)
    )
    switch ($Id) {
        'git' {
            $release = Get-OfficialJson 'https://api.github.com/repos/git-for-windows/git/releases/latest'
            $suffix = if ($Architecture -eq 'arm64') { 'arm64' } else { '64-bit' }
            $asset = @($release.assets | Where-Object { $_.name -match "^Git-[\d.]+-$suffix\.exe$" })
            if ($asset.Count -ne 1 -or $asset[0].digest -notmatch '^sha256:([a-fA-F0-9]{64})$') {
                throw "Git release metadata has no unique $Architecture installer with SHA256 digest. No installer was run."
            }
            $hash = $Matches[1]
            return @{ Url = $asset[0].browser_download_url; File = 'git.exe'; Hash = $hash
                Algorithm = 'SHA256'; Publisher = $null; Admin = $false
                Arguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR=`"$env:LOCALAPPDATA\Programs\Git`"" }
        }
        'node' {
            $releases = Get-OfficialJson 'https://nodejs.org/dist/index.json'
            $release = $releases | Where-Object { $_.version -match '^v24\.\d+\.\d+$' -and $_.lts } |
                Select-Object -First 1
            if (-not $release) { throw 'Official metadata contains no stable Node 24 LTS release.' }
            $file = "node-$($release.version)-$Architecture.msi"
            $base = "https://nodejs.org/dist/$($release.version)"
            $checksums = (Invoke-WebRequest -UseBasicParsing -Uri "$base/SHASUMS256.txt" -TimeoutSec 60).Content
            $pattern = '(?m)^([a-fA-F0-9]{64})\s+' + [regex]::Escape($file) + '\s*$'
            if ($checksums -notmatch $pattern) { throw "No SHA256 checksum found for the Node $Architecture MSI." }
            return @{ Url = "$base/$file"; File = 'node.msi'; Hash = $Matches[1]
                Algorithm = 'SHA256'; Publisher = 'OpenJS Foundation|Node\.js Foundation'; Admin = $true
                Arguments = '/qn /norestart' }
        }
        'dotnet' {
            $metadata = Get-OfficialJson 'https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/10.0/releases.json'
            $release = $metadata.releases | Where-Object { $_.sdk.version -eq $metadata.'latest-sdk' } |
                Select-Object -First 1
            $asset = @($release.sdk.files | Where-Object { $_.rid -eq "win-$Architecture" -and $_.name -like '*.exe' })
            if ($asset.Count -ne 1 -or $asset[0].hash -notmatch '^[a-fA-F0-9]{128}$') {
                throw "No unique .NET 10 $Architecture SDK installer with SHA512 checksum was found."
            }
            return @{ Url = $asset[0].url; File = 'dotnet.exe'; Hash = $asset[0].hash
                Algorithm = 'SHA512'; Publisher = 'Microsoft Corporation'; Admin = $true
                Arguments = '/install /quiet /norestart' }
        }
        'azure' {
            return @{ Url = 'https://aka.ms/installazurecliwindowsx64'; File = 'azure.msi'
                Hash = $null; Algorithm = $null; Publisher = 'Microsoft Corporation'; Admin = $true
                Arguments = '/qn /norestart' }
        }
    }
}

function Assert-InstallerIntegrity {
    param([string]$Path, [hashtable]$Spec)
    if ($Spec.Hash) {
        $actual = (Get-FileHash -LiteralPath $Path -Algorithm $Spec.Algorithm).Hash
        if ($actual -ne $Spec.Hash) { throw "Checksum mismatch for $($Spec.File). No installer was run." }
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid') {
        throw "Invalid/untrusted Authenticode signature on $($Spec.File): $($signature.Status). No installer was run."
    }
    if ($Spec.Publisher -and $signature.SignerCertificate.Subject -notmatch $Spec.Publisher) {
        throw "Unexpected signer on $($Spec.File). No installer was run."
    }
}

function Invoke-InstallerProcess {
    [CmdletBinding()]
    param(
        [hashtable]$Parameters,
        [string]$Label,
        [ValidateRange(1, 3600)][int]$HeartbeatSeconds = 30
    )
    # Keep Start-Process -Wait's process-tree semantics while the caller prints heartbeat output.
    $runner = [PowerShell]::Create()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $runner.AddScript({
            param($StartParameters)
            $ErrorActionPreference = 'Stop'
            $process = Start-Process @StartParameters
            $process.ExitCode
        }).AddArgument($Parameters) | Out-Null
        Write-Host "Starting $Label installer. Check for any Windows permission prompt; keep this window open."
        $operation = $runner.BeginInvoke()
        while (-not $operation.AsyncWaitHandle.WaitOne($HeartbeatSeconds * 1000)) {
            Write-Host ("Still waiting for {0} installer ({1:hh\:mm\:ss} elapsed). No completion result yet; do not start another installer." -f $Label, $clock.Elapsed)
        }
        $result = @($runner.EndInvoke($operation))
        if ($runner.HadErrors) { throw $runner.Streams.Error[0].Exception }
        if ($result.Count -ne 1 -or $result[0] -isnot [int]) {
            throw "The $Label installer did not return a usable exit code."
        }
        Write-Host ("{0} installer exited after {1:hh\:mm\:ss}; checking its exit code and installed version." -f $Label, $clock.Elapsed)
        return $result[0]
    } finally {
        $clock.Stop()
        $runner.Dispose()
    }
}

function Invoke-VerifiedInstaller {
    param([string]$Path, [hashtable]$Spec)
    $arguments = $Spec.Arguments
    if ([IO.Path]::GetExtension($Path) -eq '.msi') {
        $executable = "$env:SystemRoot\System32\msiexec.exe"
        $arguments = "/i `"$Path`" $arguments"
    } else { $executable = $Path }
    $parameters = @{ FilePath = $executable; ArgumentList = $arguments; Wait = $true; PassThru = $true }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($Spec.Admin -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $parameters.Verb = 'RunAs'
        Write-Host 'Windows will ask for administrator approval for this prerequisite only.'
    }
    $exitCode = Invoke-InstallerProcess -Parameters $parameters -Label ([IO.Path]::GetFileName($Path))
    if ($exitCode -notin @(0, 1641, 3010)) {
        throw "Installer failed with exit code $exitCode. Resolve Windows Installer/UAC or policy issues, then rerun."
    }
    return ($exitCode -in @(1641, 3010))
}

function Invoke-SetupNative {
    param([string]$Path, [string[]]$Arguments)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "The expected executable is missing: $Path"
    }
    # Capture stderr without PowerShell 5.1 turning benign native stderr into a terminating error.
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    # Native processes update the global value, not a local variable with the same name.
    # A sentinel also catches failure to start, while exit 0 with stderr remains success.
    $global:LASTEXITCODE = -1
    $output = & $Path @Arguments 2>&1
    $exitCode = $global:LASTEXITCODE
    if ($exitCode -ne 0) {
        # Do not echo raw CLI output, which can include private feed configuration.
        throw "Command '$([IO.Path]::GetFileName($Path)) $($Arguments -join ' ')' failed (exit $exitCode). Check connectivity, policy, and package sources."
    }
    return ($output -join "`n")
}

function Install-PacTool {
    $sdk = Get-SetupState | Where-Object Id -eq 'dotnet'
    if (-not $sdk.Ready) { throw '.NET SDK is not discoverable; open a new terminal and rerun setup.' }
    $dotnet = $sdk.Path
    # Run outside the repository so a project global.json/NuGet.Config cannot select the SDK/feed.
    $working = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $working | Out-Null
    Push-Location $working
    try {
        $config = Join-Path $working 'NuGet.Config'
        @'
<?xml version="1.0" encoding="utf-8"?>
<configuration><packageSources><clear /><add key="nuget.org" value="https://api.nuget.org/v3/index.json" /></packageSources></configuration>
'@ | Set-Content -LiteralPath $config -Encoding UTF8
        $tools = Invoke-SetupNative $dotnet @('tool', 'list', '--global')
        $verb = if ($tools -match '(?im)^microsoft\.powerapps\.cli\.tool\s') { 'update' } else { 'install' }
        $arguments = @('tool', $verb, '--global', 'Microsoft.PowerApps.CLI.Tool', '--configfile', $config)
        if ($verb -eq 'install') { $arguments += @('--arch', $sdk.Architecture) }
        Invoke-SetupNative $dotnet $arguments | Out-Null
    } finally {
        Pop-Location
        Remove-Item -LiteralPath $working -Recurse -Force
    }
}

function Install-CmrTool {
    $node = Get-SetupState -Cmr | Where-Object Id -eq 'node'
    if (-not $node -or -not $node.Ready) {
        throw 'Node.js 24.11.0+ is not discoverable; open a new terminal and rerun setup.'
    }
    $npm = Join-Path (Split-Path -Parent $node.Path) 'npm.cmd'
    if (-not (Test-Path -LiteralPath $npm -PathType Leaf)) {
        throw 'npm.cmd is missing next to the detected Node.js installation.'
    }
    # Run outside the repository so a project .npmrc cannot override package sources.
    $working = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $working | Out-Null
    Push-Location $working
    try {
        Invoke-SetupNative $npm @('install', '-g', '@microsoft/cmr-cli@latest', '--no-audit', '--no-fund') | Out-Null
    } finally {
        Pop-Location
        Remove-Item -LiteralPath $working -Recurse -Force
    }
}

function Confirm-InstalledTool {
    param([string]$Id, [object[]]$State)
    $tool = $State | Where-Object Id -eq $Id
    if (-not $tool -or -not $tool.Ready) {
        throw "The $Id installer completed, but a compatible installation is not discoverable. Restart the terminal/Copilot app and rerun -CheckOnly. An older PATH entry may be shadowing it."
    }
    switch ($Id) {
        'git' { $output = Invoke-SetupNative $tool.Path @('--version'); $expected = $tool.Version }
        'node' {
            $output = Invoke-SetupNative $tool.Path @('--version'); $expected = $tool.Version
            $npm = Join-Path (Split-Path -Parent $tool.Path) 'npm.cmd'
            $npmVersion = ConvertTo-ToolVersion (Invoke-SetupNative $npm @('--version'))
            if (-not $npmVersion -or $npmVersion -lt [version]'10.0.0') { throw 'npm version verification failed.' }
        }
        'dotnet' {
            $output = Invoke-SetupNative $tool.Path @('--list-sdks')
            if ($output -notmatch '(?m)^10\.0\.\d+\s') { throw '.NET 10 SDK runtime verification failed.' }
            return
        }
        'pac' { $output = Invoke-SetupNative $tool.Path @(); $expected = $tool.Version }
        'azure' {
            $output = Invoke-SetupNative $tool.Path @('version', '--output', 'json')
            $actual = ConvertTo-ToolVersion (($output | ConvertFrom-Json).'azure-cli')
            if (-not $actual -or $actual -lt [version]'2.60.0') { throw 'Azure CLI version verification failed.' }
            return
        }
        'cmr' { $output = Invoke-SetupNative $tool.Path @('--version'); $expected = $tool.Version }
    }
    if ((ConvertTo-ToolVersion $output) -ne $expected) { throw "$Id executable version verification failed." }
}

function Install-SetupTool {
    param([string]$Id)
    if ($Id -eq 'pac') { Install-PacTool; return $false }
    if ($Id -eq 'cmr') { Install-CmrTool; return $false }
    $spec = Get-InstallerSpec $Id
    Assert-OfficialUrl $spec.Url
    $working = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $working | Out-Null
    try {
        $path = Join-Path $working $spec.File
        Write-Host "Downloading from $($spec.Url)"
        Invoke-WebRequest -UseBasicParsing -Uri $spec.Url -OutFile $path -TimeoutSec 600
        Assert-InstallerIntegrity $path $spec
        return Invoke-VerifiedInstaller $path $spec
    } finally {
        Remove-Item -LiteralPath $working -Recurse -Force
    }
}

function Get-SetupMarketplaceCatalog {
    @(
        [pscustomobject]@{
            Key = 'PowerPlatform'
            Name = 'power-platform-skills'
            Repo = 'microsoft/power-platform-skills'
            OfficialUrls = @(
                'microsoft/power-platform-skills',
                'https://github.com/microsoft/power-platform-skills',
                'https://github.com/microsoft/power-platform-skills.git')
        },
        [pscustomobject]@{
            Key = 'CopilotManagedRuntime'
            Name = 'Copilot-Managed-Runtime'
            Repo = 'microsoft/Copilot-Managed-Runtime'
            OfficialUrls = @(
                'microsoft/Copilot-Managed-Runtime',
                'https://github.com/microsoft/Copilot-Managed-Runtime',
                'https://github.com/microsoft/Copilot-Managed-Runtime.git')
        }
    )
}

function Get-SetupPluginCatalog {
    # Reviewed official catalog and core Windows prerequisite mapping.
    @(
        [pscustomobject]@{ Id = 'power-pages'; Summary = 'Power Pages websites'; Marketplace = 'power-platform-skills'; MarketplaceKey = 'PowerPlatform'; Prerequisites = @('git', 'node', 'dotnet', 'pac', 'azure'); ExtraNote = $null },
        [pscustomobject]@{ Id = 'model-apps'; Summary = 'Model-driven apps & generative pages'; Marketplace = 'power-platform-skills'; MarketplaceKey = 'PowerPlatform'; Prerequisites = @('git', 'node', 'dotnet', 'pac', 'azure'); ExtraNote = $null },
        [pscustomobject]@{ Id = 'canvas-apps'; Summary = 'Canvas Apps Studio coauthoring'; Marketplace = 'power-platform-skills'; MarketplaceKey = 'PowerPlatform'; Prerequisites = @('git', 'dotnet'); ExtraNote = 'Requires an existing saved Canvas App open in Power Apps Studio with coauthoring enabled.' },
        [pscustomobject]@{ Id = 'code-apps-preview'; Summary = 'Power Apps Code Apps (React/Vite)'; Marketplace = 'power-platform-skills'; MarketplaceKey = 'PowerPlatform'; Prerequisites = @('git', 'node'); ExtraNote = 'Uses project-local Power Apps CLI (pa), installed during app scaffolding.' },
        [pscustomobject]@{ Id = 'mobile-app'; Summary = 'Native mobile apps (Private Preview)'; Marketplace = 'power-platform-skills'; MarketplaceKey = 'PowerPlatform'; Prerequisites = @('git', 'node', 'azure'); ExtraNote = 'Documents Node 24 LTS, Git Bash/WSL on Windows, and the Power Apps Mobile Preview phone app.' },
        [pscustomobject]@{ Id = 'power-apps-mobile-extension'; Summary = 'Wrapped Canvas native extensions'; Marketplace = 'power-platform-skills'; MarketplaceKey = 'PowerPlatform'; Prerequisites = @('git', 'node', 'dotnet', 'pac'); ExtraNote = 'Native binary builds also need JDK 17+ / Android SDK 35 (Android) or macOS Xcode 16+ (iOS).' },
        [pscustomobject]@{ Id = 'power-automate'; Summary = 'Power Automate cloud & desktop flows'; Marketplace = 'power-platform-skills'; MarketplaceKey = 'PowerPlatform'; Prerequisites = @('git', 'node', 'azure'); ExtraNote = $null },
        [pscustomobject]@{ Id = 'process-intelligence'; Summary = 'Process Mining analytics'; Marketplace = 'power-platform-skills'; MarketplaceKey = 'PowerPlatform'; Prerequisites = @('git', 'node', 'azure'); ExtraNote = $null },
        [pscustomobject]@{ Id = 'pcf'; Summary = 'PCF custom code components'; Marketplace = 'power-platform-skills'; MarketplaceKey = 'PowerPlatform'; Prerequisites = @('git', 'node', 'dotnet', 'pac', 'azure'); ExtraNote = $null },
        [pscustomobject]@{ Id = 'mcp-apps'; Summary = 'Codeful MCP tools & HTML widgets'; Marketplace = 'power-platform-skills'; MarketplaceKey = 'PowerPlatform'; Prerequisites = @('git', 'node', 'dotnet', 'pac'); ExtraNote = 'PAC/.NET are used when generating Dataverse-backed tool schemas; UI-only widgets use Node.' },
        [pscustomobject]@{ Id = 'dataverse'; Summary = 'Dataverse data, schema & solutions'; Marketplace = 'power-platform-skills'; MarketplaceKey = 'PowerPlatform'; Prerequisites = @('git', 'node', 'dotnet', 'pac', 'azure'); ExtraNote = 'Dataverse CLI (@microsoft/dataverse) and optional Python SDK are checked later during connection onboarding.' },
        [pscustomobject]@{ Id = 'copilot-managed-runtime'; Summary = 'Copilot Managed Runtime (Managed Apps, ms CLI)'; Marketplace = 'Copilot-Managed-Runtime'; MarketplaceKey = 'CopilotManagedRuntime'; Prerequisites = @('git', 'node', 'cmr'); ExtraNote = 'Requires Node.js 24.11.0+, Git with Git Credential Manager, and @microsoft/cmr-cli (ms). Signs in separately via ms auth login; distinct from Power Apps Code Apps (pa).' }
    )
}

function Get-SetupPluginNames {
    param([switch]$IncludeDataverse, [switch]$IncludeCmr, [AllowEmptyString()][string]$Plugins = 'All')
    # Reviewed official catalog: adding future plugins requires a deliberate release.
    $entries = @(Get-SetupPluginCatalog)
    $catalog = @($entries | Where-Object { $_.Id -notin @('dataverse', 'copilot-managed-runtime') } | ForEach-Object { $_.Id })
    $valid = @($entries | ForEach-Object { $_.Id })
    if ([string]::IsNullOrWhiteSpace($Plugins)) {
        throw [ArgumentException]::new('Plugin selection is empty. Choose explicit plugin IDs or All; use -PluginHost Skip to install none.')
    }
    if ($Plugins -eq 'All') {
        $names = $catalog
    } else {
        $names = @($Plugins.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() })
        if (@($names | Where-Object { $_ -notin $valid }).Count) {
            throw [ArgumentException]::new('Unsupported plugin selection. Use comma-separated reviewed plugin IDs, without marketplace suffixes, URLs or empty entries.')
        }
        $names = @($names | Select-Object -Unique)
    }
    if ($IncludeDataverse -and 'dataverse' -notin $names) { $names += 'dataverse' }
    if ($IncludeCmr -and 'copilot-managed-runtime' -notin $names) { $names += 'copilot-managed-runtime' }
    return $names
}

function Resolve-SetupPrerequisites {
    param(
        [AllowEmptyString()][string]$Prerequisites = 'All',
        [AllowEmptyString()][string]$Plugins = 'All',
        [switch]$IncludeDataverse,
        [switch]$IncludeCmr,
        [switch]$MarketplaceOnly,
        [switch]$IncludeAzureCli,
        [switch]$SkipAzureCli,
        [switch]$IncludeCopilotStudioMcp
    )
    $coreOrder = @('git', 'node', 'dotnet', 'pac', 'azure')
    $canonicalOrder = @('git', 'node', 'dotnet', 'pac', 'azure', 'cmr')
    if ([string]::IsNullOrWhiteSpace($Prerequisites)) {
        throw [ArgumentException]::new('Prerequisite selection is empty. Use All, FromPlugins, or comma-separated IDs from git,node,dotnet,pac,azure,cmr.')
    }
    $trimmed = $Prerequisites.Trim()
    if ($trimmed -ieq 'All') {
        $selected = $coreOrder
        if ($SkipAzureCli) { $selected = @($selected | Where-Object { $_ -ne 'azure' }) }
        if ($IncludeCmr) { $selected += 'cmr' }
        return $selected
    }
    if ($trimmed -ieq 'FromPlugins') {
        $needed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($MarketplaceOnly) {
            $null = $needed.Add('git')
        } else {
            $pluginNames = @(Get-SetupPluginNames -Plugins $Plugins -IncludeDataverse:$IncludeDataverse -IncludeCmr:$IncludeCmr)
            $catalogById = @{}
            foreach ($entry in @(Get-SetupPluginCatalog)) { $catalogById[$entry.Id] = $entry }
            foreach ($name in $pluginNames) {
                foreach ($req in $catalogById[$name].Prerequisites) { $null = $needed.Add($req) }
            }
        }
        if ($IncludeCopilotStudioMcp) { $null = $needed.Add('node') }
        if ($IncludeAzureCli) { $null = $needed.Add('azure') }
        if ($needed.Contains('pac')) { $null = $needed.Add('dotnet') }
        if ($needed.Contains('cmr')) {
            $null = $needed.Add('git')
            $null = $needed.Add('node')
        }
        if ($SkipAzureCli) { $null = $needed.Remove('azure') }
        return @($canonicalOrder | Where-Object { $needed.Contains($_) })
    }
    $requested = @($trimmed.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() })
    if (@($requested | Where-Object { $_ -notin $canonicalOrder }).Count) {
        throw [ArgumentException]::new('Unsupported prerequisite selection. Use All, FromPlugins, or comma-separated IDs from git,node,dotnet,pac,azure,cmr.')
    }
    if ($SkipAzureCli -and 'azure' -in $requested) {
        throw [ArgumentException]::new('Do not combine -SkipAzureCli with an explicit azure prerequisite selection.')
    }
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $requested) { $null = $set.Add($id) }
    if ($IncludeAzureCli) { $null = $set.Add('azure') }
    if ($IncludeCmr) { $null = $set.Add('cmr') }
    if ($set.Contains('pac')) { $null = $set.Add('dotnet') }
    if ($set.Contains('cmr')) {
        $null = $set.Add('git')
        $null = $set.Add('node')
    }
    return @($canonicalOrder | Where-Object { $set.Contains($_) })
}

function Show-SelectiveScopeSummary {
    param(
        [string]$Prerequisites,
        [string[]]$SelectedPrerequisiteIds,
        [string]$Plugins,
        [switch]$IncludeDataverse,
        [switch]$IncludeCmr,
        [switch]$MarketplaceOnly,
        [string]$Marketplace = 'PowerPlatform'
    )
    if ($Prerequisites.Trim() -ieq 'All') { return }
    if ($Prerequisites.Trim() -ieq 'FromPlugins') {
        if ($MarketplaceOnly) {
            $mpRepos = switch ($Marketplace) {
                'CopilotManagedRuntime' { 'microsoft/Copilot-Managed-Runtime' }
                'Both' { 'microsoft/power-platform-skills, microsoft/Copilot-Managed-Runtime' }
                default { 'microsoft/power-platform-skills' }
            }
            Write-Host "Selective mode: official marketplace preparation only ($mpRepos)."
            Write-Host "Resolved core prerequisites: $($SelectedPrerequisiteIds -join ', ')"
            return
        }
        $pluginNames = @(Get-SetupPluginNames -Plugins $Plugins -IncludeDataverse:$IncludeDataverse -IncludeCmr:$IncludeCmr)
        Write-Host "Selective mode for plugins: $($pluginNames -join ', ')"
        Write-Host "Resolved core prerequisites: $($SelectedPrerequisiteIds -join ', ')"
        foreach ($entry in @(Get-SetupPluginCatalog | Where-Object { $_.Id -in $pluginNames -and $_.ExtraNote })) {
            Write-Host "  Note ($($entry.Id)): $($entry.ExtraNote)"
        }
        return
    }
    Write-Host "Selective prerequisite filter: $($SelectedPrerequisiteIds -join ', ')"
}

function Get-PluginProperty {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}

function Read-PluginJson {
    param([string]$Path, [string[]]$Arguments)
    $text = Invoke-SetupNative $Path $Arguments
    if (-not $text.Trim().StartsWith('[') -or -not $text.Trim().EndsWith(']')) {
        throw 'Unsupported plugin CLI output: expected a JSON array. Check the installed CLI version; no text-output fallback is used.'
    }
    try { $rows = $text | ConvertFrom-Json } catch {
        throw 'The plugin CLI returned invalid JSON. Inspect its configuration privately; raw output is not logged.'
    }
    foreach ($row in $rows) {
        if ($null -eq $row -or $row -isnot [pscustomobject]) {
            throw 'Unsupported plugin CLI listing entry. Check the installed CLI version.'
        }
        $row
    }
}

function Get-PluginInventory {
    param([string]$Path, [string]$PluginHost)
    foreach ($row in @(Read-PluginJson $Path @('plugin', 'list', '--json'))) {
        $id = Get-PluginProperty $row 'id'
        if ($PluginHost -eq 'CopilotCli') {
            $id = Get-PluginProperty $row 'name'
            $marketplace = Get-PluginProperty $row 'marketplace'
            if ($id -is [string] -and $id -notmatch '@' -and $marketplace) { $id += "@$marketplace" }
        }
        $enabled = Get-PluginProperty $row 'enabled'
        if ($id -isnot [string] -or $id -notmatch '^[a-z0-9][a-z0-9.-]*(?:@[A-Za-z0-9][A-Za-z0-9.-]*)?$' -or
            $enabled -isnot [bool]) {
            throw 'Unsupported plugin identity/status fields. Check the installed CLI version before retrying.'
        }
        [pscustomobject]@{
            Id = $id; Name = ($id -split '@')[0]; Enabled = $enabled
            Scope = Get-PluginProperty $row 'scope'
            Errors = Get-PluginProperty $row 'errors'
        }
    }
}

function Assert-OfficialMarketplace {
    param([object[]]$Marketplaces, [string]$MarketplaceName = 'power-platform-skills')
    $spec = Get-SetupMarketplaceCatalog | Where-Object { $_.Name -eq $MarketplaceName } | Select-Object -First 1
    if (-not $spec) { throw "Unsupported marketplace '$MarketplaceName'." }
    foreach ($row in $Marketplaces) {
        if ((Get-PluginProperty $row 'name') -isnot [string]) {
            throw 'Unsupported marketplace listing fields. Check the installed CLI version.'
        }
    }
    $matching = @($Marketplaces | Where-Object { $_.name -eq $spec.Name })
    if ($matching.Count -eq 0) { return $false }
    if ($matching.Count -ne 1) { throw "Multiple $($spec.Name) marketplaces found; resolve the conflict manually." }
    $row = $matching[0]
    $source = Get-PluginProperty $row 'source'
    $repo = Get-PluginProperty $row 'repo'
    $url = Get-PluginProperty $row 'url'
    if ($source -is [pscustomobject]) {
        $repo = Get-PluginProperty $source 'repo'
        $url = Get-PluginProperty $source 'url'
        $kind = Get-PluginProperty $source 'source'
        if (-not $kind) { $kind = Get-PluginProperty $source 'type' }
        $source = $kind
    }
    $official = $spec.OfficialUrls
    if ($source -in $official -or ($source -eq 'github' -and $repo -eq $official[0]) -or
        ($source -in @('git', 'url') -and $url -in $official[1..2])) {
        return $true
    }
    throw "The existing $($spec.Name) marketplace source is different or unrecognized. Setup will not overwrite or trust it; review it manually."
}

function Assert-SetupPlugin {
    param($Plugin, [string]$PluginHost)
    if (-not $Plugin.Enabled -or ($null -ne $Plugin.Errors -and @($Plugin.Errors).Count -gt 0)) {
        throw "Plugin '$($Plugin.Name)' is disabled or has load errors. Resolve this in the selected host; setup will not override policy/settings."
    }
    if ($PluginHost -eq 'ClaudeCode' -and $Plugin.Scope -ne 'user') {
        throw "Plugin '$($Plugin.Name)' exists outside user scope. Review its scope manually rather than creating a duplicate."
    }
}

function Get-TargetMarketplaces {
    param([string[]]$Names = @(), [switch]$MarketplaceOnly, [ValidateSet('PowerPlatform', 'CopilotManagedRuntime', 'Both')][string]$Marketplace = 'PowerPlatform')
    $all = @(Get-SetupMarketplaceCatalog)
    if ($MarketplaceOnly) {
        if ($Marketplace -eq 'Both') { return $all }
        return @($all | Where-Object { $_.Key -eq $Marketplace })
    }
    $catalogById = @{}
    foreach ($entry in @(Get-SetupPluginCatalog)) { $catalogById[$entry.Id] = $entry }
    $keys = @($Names | ForEach-Object { $catalogById[$_].MarketplaceKey } | Select-Object -Unique)
    return @($all | Where-Object { $_.Key -in $keys })
}

function Install-SetupPlugins {
    param(
        [string]$Path, [string]$PluginHost, [string[]]$Names = @(),
        [switch]$MarketplaceOnly,
        [ValidateSet('PowerPlatform', 'CopilotManagedRuntime', 'Both')][string]$Marketplace = 'PowerPlatform'
    )
    if (($MarketplaceOnly -and $Names.Count) -or (-not $MarketplaceOnly -and -not $Names.Count)) {
        throw [ArgumentException]::new('Choose marketplace-only preparation or a nonempty plugin selection, not both.')
    }
    $catalogById = @{}
    foreach ($entry in @(Get-SetupPluginCatalog)) { $catalogById[$entry.Id] = $entry }
    $targetMarketplaces = @(Get-TargetMarketplaces -Names $Names -MarketplaceOnly:$MarketplaceOnly -Marketplace $Marketplace)
    $marketplaces = @(Read-PluginJson $Path @('plugin', 'marketplace', 'list', '--json'))
    $missingMarketplaces = @()
    foreach ($mp in $targetMarketplaces) {
        if (-not (Assert-OfficialMarketplace $marketplaces $mp.Name)) { $missingMarketplaces += $mp }
    }
    $inventory = @()
    if (-not $MarketplaceOnly) { $inventory = @(Get-PluginInventory $Path $PluginHost) }
    $pending = @()
    foreach ($name in $Names) {
        $expectedMarketplace = $catalogById[$name].Marketplace
        $existing = @($inventory | Where-Object Name -eq $name)
        if ($existing.Count) {
            if ($existing.Count -ne 1 -or
                ($existing[0].Id -ne "$name@$expectedMarketplace" -and
                 -not ($name -eq 'dataverse' -and $existing[0].Id -eq 'dataverse@dataverse-skills'))) {
                throw "Plugin '$name' already has another or duplicate source. Review it manually; no duplicate will be installed."
            }
            Assert-SetupPlugin $existing[0] $PluginHost
            Write-Host "Keeping installed plugin: $name"
        } else { $pending += $name }
    }
    foreach ($mp in $missingMarketplaces) {
        Invoke-SetupNative $Path @('plugin', 'marketplace', 'add', $mp.Repo) | Out-Null
        if (-not (Assert-OfficialMarketplace @(Read-PluginJson $Path @('plugin', 'marketplace', 'list', '--json')) $mp.Name)) {
            throw "Marketplace registration for $($mp.Name) returned success but the official source could not be verified."
        }
    }
    if ($MarketplaceOnly) {
        Write-Host 'Official marketplace registration verified. No plugins were installed; choose them next with the setup guide.'
        return
    }
    foreach ($name in $pending) {
        $expectedMarketplace = $catalogById[$name].Marketplace
        Write-Host "Installing $name for $PluginHost..."
        $arguments = @('plugin', 'install', "$name@$expectedMarketplace")
        if ($PluginHost -eq 'ClaudeCode') { $arguments += @('--scope', 'user') }
        Invoke-SetupNative $Path $arguments | Out-Null
        $installed = @(Get-PluginInventory $Path $PluginHost | Where-Object Id -eq "$name@$expectedMarketplace")
        if ($installed.Count -ne 1) {
            throw "Plugin '$name' install returned success but its installation could not be verified."
        }
        Assert-SetupPlugin $installed[0] $PluginHost
    }
    Write-Host 'Selected host plugin registrations verified. Restart that host and check its actual skills/tools.'
    Write-Host 'Desktop visibility, bundled MCP setup, licensing and authentication are NOT verified.'
}

function Get-CopilotAppProtocolUri {
    param([string]$Name, [ValidateSet('PowerPlatform', 'CopilotManagedRuntime')][string]$Marketplace = 'PowerPlatform')
    if ($Name) {
        $entry = Get-SetupPluginCatalog | Where-Object { $_.Id -eq $Name } | Select-Object -First 1
        if (-not $entry) { throw 'Unknown plugin link.' }
        return 'ghapp://plugins/install?source=' + [uri]::EscapeDataString("$($entry.Id)@$($entry.Marketplace)")
    }
    $mp = Get-SetupMarketplaceCatalog | Where-Object { $_.Key -eq $Marketplace } | Select-Object -First 1
    return 'ghapp://plugins/marketplace/add?source=' + [uri]::EscapeDataString($mp.Repo)
}

function Get-CopilotAppPluginLink {
    param([string]$Name, [ValidateSet('PowerPlatform', 'CopilotManagedRuntime')][string]$Marketplace = 'PowerPlatform')
    return 'https://github.com/copilot/app/launch?open=' + [uri]::EscapeDataString((Get-CopilotAppProtocolUri -Name $Name -Marketplace $Marketplace))
}

function Open-CopilotAppMarketplacePrompt {
    param([ValidateSet('PowerPlatform', 'CopilotManagedRuntime')][string]$Marketplace = 'PowerPlatform')
    $protocol = 'Registry::HKEY_CLASSES_ROOT\ghapp'
    if (-not (Test-Path -LiteralPath $protocol -ErrorAction SilentlyContinue)) { return $false }
    $registration = Get-ItemProperty -LiteralPath $protocol -ErrorAction SilentlyContinue
    if ($null -eq $registration -or $null -eq $registration.PSObject.Properties['URL Protocol']) { return $false }
    $uri = Get-CopilotAppProtocolUri -Marketplace $Marketplace
    if ($uri -notmatch '^ghapp://plugins/marketplace/add\?source=microsoft%2F(?:power-platform-skills|Copilot-Managed-Runtime)$') {
        throw 'Unexpected Copilot app protocol URI.'
    }
    Start-Process -FilePath $uri | Out-Null
    return $true
}

function Open-CopilotAppPluginPrompt {
    param([Parameter(Mandatory)][string]$Name)
    $protocol = 'Registry::HKEY_CLASSES_ROOT\ghapp'
    if (-not (Test-Path -LiteralPath $protocol -ErrorAction SilentlyContinue)) { return $false }
    $registration = Get-ItemProperty -LiteralPath $protocol -ErrorAction SilentlyContinue
    if ($null -eq $registration -or $null -eq $registration.PSObject.Properties['URL Protocol']) { return $false }
    $uri = Get-CopilotAppProtocolUri -Name $Name
    if ($uri -notmatch '^ghapp://plugins/install\?source=[a-z0-9-]+%40(?:power-platform-skills|Copilot-Managed-Runtime)$') {
        throw 'Unexpected Copilot app plugin protocol URI.'
    }
    Start-Process -FilePath $uri | Out-Null
    return $true
}

function Get-SetupAgentHosts {
    foreach ($definition in @(
        @{ Id = 'ClaudeCode'; Name = 'Claude Code CLI'; Command = 'claude' },
        @{ Id = 'CopilotCli'; Name = 'GitHub Copilot CLI'; Command = 'copilot' })) {
        $path = Find-SetupExecutable $definition.Command
        [pscustomobject]@{
            Id = $definition.Id; Name = $definition.Name
            Detected = -not [string]::IsNullOrWhiteSpace($path); Path = $path
        }
    }
    $registered = $false
    $protocol = 'Registry::HKEY_CLASSES_ROOT\ghapp'
    if (Test-Path -LiteralPath $protocol -ErrorAction Stop) {
        $registration = Get-ItemProperty -LiteralPath $protocol -ErrorAction Stop
        $registered = $null -ne $registration.PSObject.Properties['URL Protocol']
    }
    [pscustomobject]@{
        Id = 'CopilotApp'; Name = 'GitHub Copilot desktop app'
        Detected = $registered; Path = $null
    }
}

function Show-AgentHostInstallHandoff {
    param([ValidateSet('ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$HostName)
    $url = switch ($HostName) {
        'ClaudeCode' { 'https://code.claude.com/docs/en/setup' }
        'CopilotCli' { 'https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli' }
        'CopilotApp' { 'https://github.com/features/ai/github-app' }
    }
    Write-Host "`nACTION REQUIRED: install or confirm the selected host yourself using its official instructions:"
    Write-Host $url
    Write-Host 'If already installed, reopen the terminal/host and check its PATH or app-link registration before retrying.'
    Write-Host 'This setup does not download, install, launch or sign in to an agent host. No alternative host was configured.'
    Write-Host 'Complete the chosen host setup independently, then rerun .\Setup.cmd or resume the guided setup skill.'
    Write-Host 'Any completed prerequisite installations are preserved. Host installation may have its own requirements and approvals.'
}

function Invoke-PluginSetup {
    [CmdletBinding()]
    param(
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$PluginHost,
        [AllowEmptyString()][string]$Plugins = 'All',
        [switch]$MarketplaceOnly,
        [ValidateSet('PowerPlatform', 'CopilotManagedRuntime', 'Both')][string]$Marketplace = 'PowerPlatform',
        [switch]$SkipMarketplace,
        [switch]$IncludeDataverse, [switch]$IncludeCmr, [switch]$AcceptPlugins, [switch]$NonInteractive
    )
    if ($MarketplaceOnly -and ($PluginHost -notin @('CopilotCli', 'ClaudeCode', 'CopilotApp') -or $Plugins -ne 'All' -or $IncludeDataverse -or $IncludeCmr -or $SkipMarketplace)) {
        Write-Host 'Marketplace-only preparation requires -PluginHost ClaudeCode, CopilotCli or CopilotApp and cannot include a plugin selection, -SkipMarketplace, or Dataverse/CMR opt-in.'
        return 2
    }
    if (-not $MarketplaceOnly -and $Marketplace -ne 'PowerPlatform') {
        Write-Host '-Marketplace applies only to -MarketplaceOnly preparation; when selecting plugins, marketplaces are derived automatically from the chosen plugin IDs.'
        return 2
    }
    if ($MarketplaceOnly -and $Marketplace -eq 'Both' -and $PluginHost -eq 'CopilotApp' -and $NonInteractive) {
        Write-Host 'Add one marketplace at a time on CopilotApp in noninteractive mode (-Marketplace PowerPlatform, then -Marketplace CopilotManagedRuntime) so the user can confirm each dialog in order.'
        return 2
    }
    if ($SkipMarketplace -and $PluginHost -ne 'CopilotApp') {
        Write-Host '-SkipMarketplace applies only to -PluginHost CopilotApp after the official marketplace has been confirmed in the app.'
        return 2
    }
    if (-not $PluginHost) {
        if ($NonInteractive) {
            Write-Host 'Plugin stage skipped. Request it explicitly with -PluginHost and -AcceptPlugins.'
            return 0
        }
        Write-Host "`nOptional next stage: Power Platform / Copilot Managed Runtime plugins (separate approval)."
        $agentHosts = @(Get-SetupAgentHosts)
        Write-Host 'Passive host discovery only: commands and app-link registrations are not proof that a host works or is signed in.'
        foreach ($candidate in $agentHosts) {
            $status = if (-not $candidate.Detected) { 'not detected' }
                elseif ($candidate.Id -eq 'CopilotApp') { 'ghapp URL handler registered; app not runtime-verified' }
                else { 'command found; may be a first-run launcher, not a verified CLI' }
            Write-Host ("  {0}: {1}" -f $candidate.Name, $status)
        }
        if (-not @($agentHosts | Where-Object Detected).Count) {
            Write-Host 'No host candidate was detected. Select a host for official installation guidance, or confirm an already installed app.'
        }
        Write-Host '1 = Claude Code (claude command); 2 = Copilot CLI; 3 = Copilot desktop app links; Enter = skip.'
        $choice = Read-Host 'Choose the host you already use; no new host will be installed'
        switch ($choice) {
            '' { Write-Host 'Plugin stage skipped. You can run it later or use the integration skill.'; return 0 }
            '1' { $PluginHost = 'ClaudeCode' }
            '2' { $PluginHost = 'CopilotCli' }
            '3' { $PluginHost = 'CopilotApp' }
            default { Write-Host 'Unrecognized host selection. Plugin stage cancelled.'; return 2 }
        }
        if ($PluginHost -eq 'CopilotApp' -and -not @($agentHosts | Where-Object { $_.Id -eq 'CopilotApp' -and $_.Detected }).Count) {
            Write-Host 'The Copilot desktop app link handler was not detected. This does not prove the app is absent.'
            if ((Read-Host 'If you already installed the Copilot desktop app, type APP to use its confirmation links; Enter = official install guidance') -cne 'APP') {
                Show-AgentHostInstallHandoff 'CopilotApp'
                return 2
            }
        }
    }
    if ($PluginHost -eq 'Skip') { Write-Host 'Plugin stage skipped explicitly.'; return 0 }
    if ($NonInteractive -and -not $AcceptPlugins) {
        Write-Host 'Plugin approval missing. Use -AcceptPlugins only after the user approves this separate plan.'
        return 2
    }
    $path = $null
    if ($PluginHost -ne 'CopilotApp') {
        $command = if ($PluginHost -eq 'ClaudeCode') { 'claude' } else { 'copilot' }
        $path = Find-SetupExecutable $command
        if (-not $path) {
            Write-Host "The selected host command '$command' was not found on PATH; no other CLI will be substituted."
            Show-AgentHostInstallHandoff $PluginHost
            return 2
        }
    }
    if (-not $NonInteractive -and -not $AcceptPlugins -and -not $IncludeDataverse -and $Plugins -eq 'All' -and -not $MarketplaceOnly) {
        $IncludeDataverse = (Read-Host 'Also include Dataverse? Type YES to opt in; Enter = no') -ceq 'YES'
    }
    $names = @()
    if ($MarketplaceOnly) {
        Write-Host "`nMarketplace-only plan for ${PluginHost}. No plugins will be installed in this stage."
    } else {
        $names = @(Get-SetupPluginNames -IncludeDataverse:$IncludeDataverse -IncludeCmr:$IncludeCmr -Plugins $Plugins)
        if ($SkipMarketplace -and $NonInteractive -and $names.Count -ne 1) {
            Write-Host 'Pass exactly one plugin at a time with -PluginHost CopilotApp -SkipMarketplace -NonInteractive so the user can confirm each dialog in the Copilot app before the next opens.'
            return 2
        }
        Write-Host "`nPlugin plan for ${PluginHost}: $($names -join ', ')"
    }
    $targetMarketplaces = @(Get-TargetMarketplaces -Names $names -MarketplaceOnly:$MarketplaceOnly -Marketplace $Marketplace)
    $sourceList = ($targetMarketplaces | ForEach-Object { $_.Repo }) -join ', '
    $sourceSuffix = if ($targetMarketplaces.Key -contains 'PowerPlatform') { ' (Dataverse, if selected, comes from Microsoft/Dataverse-skills)' } else { '' }
    Write-Host "Source: ${sourceList}${sourceSuffix}."
    Write-Host 'Plugins may include executable hooks, agents and MCP servers. Review their permissions in your host.'
    Write-Host 'Setup will not enable auto-update, install another host, update prerequisites, or sign in.'
    if ($PluginHost -ne 'CopilotApp') {
        Write-Host "Using existing command: $path"
        Write-Host 'Only this host will be configured, at user scope. Existing plugins/disabled settings will be preserved.'
    } else {
        if ($MarketplaceOnly) {
            Write-Host 'Setup will open the Add Marketplace confirmation in the Copilot app (when registered) and print the official link.'
        } elseif ($SkipMarketplace) {
            Write-Host 'Marketplace was confirmed earlier; setup will open the selected plugin install confirmation directly in the Copilot app.'
        } else {
            Write-Host 'Setup will open the Add Marketplace confirmation in the Copilot app first and print official links for each selected plugin.'
        }
        Write-Host 'Opening or printing a link does not install a plugin until you confirm it in the Copilot app. No web browser is opened.'
    }
    if (-not $AcceptPlugins) {
        $approval = if ($MarketplaceOnly) { 'MARKETPLACE' } else { 'PLUGINS' }
        if ((Read-Host "Type $approval to approve this stage (anything else cancels)") -cne $approval) {
            Write-Host 'Plugin stage cancelled. Any completed prerequisite installs are retained.'
            return 2
        }
    }
    if ($PluginHost -eq 'CopilotApp') {
        if ($SkipMarketplace) {
            foreach ($name in $names) {
                $openedPlugin = Open-CopilotAppPluginPrompt $name
                if ($openedPlugin) {
                    Write-Host "`nOpened the plugin install prompt in the GitHub Copilot desktop app for: $name"
                }
                Write-Host "`n${name}:"
                Write-Host (Get-CopilotAppPluginLink -Name $name)
                if (-not $NonInteractive -and $openedPlugin -and $names.Count -gt 1) {
                    $null = Read-Host "Confirm '$name' in the Copilot app, then press Enter for the next plugin"
                }
            }
            Write-Host "`nACTION REQUIRED: confirm the plugin installation dialog in the Copilot app, then check Customize > Installed."
            Write-Host 'Plugin installation is pending until confirmed in the app. Copilot Studio MCP/authentication remain separate.'
            return 4
        }
        if ($MarketplaceOnly) {
            foreach ($mp in $targetMarketplaces) {
                $openedInApp = Open-CopilotAppMarketplacePrompt -Marketplace $mp.Key
                if ($openedInApp) {
                    Write-Host "`nOpened the Add Marketplace confirmation prompt directly in the GitHub Copilot desktop app ($($mp.Name))."
                }
                Write-Host "`nAdd $($mp.Name) marketplace in the Copilot app:"
                Write-Host (Get-CopilotAppPluginLink -Marketplace $mp.Key)
                Write-Host "`nACTION REQUIRED: confirm Allow -> Add in the Copilot app until 'Added $($mp.Name) marketplace' appears."
                if (-not $NonInteractive -and $openedInApp -and $targetMarketplaces.Count -gt 1 -and $mp -ne $targetMarketplaces[-1]) {
                    $null = Read-Host "Confirm '$($mp.Name)' in the Copilot app, then press Enter for the next marketplace"
                }
            }
            Write-Host 'Marketplace addition is pending, not verified. No plugins were installed yet.'
            return 4
        }
        $openedAny = $false
        if ($targetMarketplaces.Count -eq 1) {
            $openedAny = Open-CopilotAppMarketplacePrompt -Marketplace $targetMarketplaces[0].Key
            if ($openedAny) {
                Write-Host "`nOpened the Add Marketplace confirmation prompt directly in the GitHub Copilot desktop app."
            }
            Write-Host "`nAdd marketplace first (confirm Allow -> Add in the Copilot app before installing plugins):"
            Write-Host (Get-CopilotAppPluginLink -Marketplace $targetMarketplaces[0].Key)
        } else {
            Write-Host "`nAdd marketplaces first (confirm Allow -> Add in the Copilot app before installing plugins):"
            foreach ($mp in $targetMarketplaces) {
                if ($NonInteractive) {
                    if ($mp -eq $targetMarketplaces[0]) {
                        $openedAny = Open-CopilotAppMarketplacePrompt -Marketplace $mp.Key
                        if ($openedAny) {
                            Write-Host "`nOpened the Add Marketplace confirmation prompt directly in the GitHub Copilot desktop app ($($mp.Name))."
                        }
                    }
                } else {
                    if (Open-CopilotAppMarketplacePrompt -Marketplace $mp.Key) {
                        $openedAny = $true
                        Write-Host "`nOpened the Add Marketplace confirmation prompt directly in the GitHub Copilot desktop app ($($mp.Name))."
                        if ($mp -ne $targetMarketplaces[-1]) {
                            $null = Read-Host "Confirm '$($mp.Name)' in the Copilot app, then press Enter for the next marketplace"
                        }
                    }
                }
                Write-Host "`n$($mp.Name):"
                Write-Host (Get-CopilotAppPluginLink -Marketplace $mp.Key)
            }
        }
        foreach ($name in $names) {
            Write-Host "`n${name}:"
            Write-Host (Get-CopilotAppPluginLink -Name $name)
        }
        if (-not $NonInteractive -and $openedAny) {
            $stepReply = Read-Host "`nAfter clicking Allow -> Add for the marketplace in the Copilot app, press Enter to open each selected plugin prompt one by one (or type LINKS to finish manually)"
            if ([string]::IsNullOrWhiteSpace($stepReply)) {
                foreach ($name in $names) {
                    if (Open-CopilotAppPluginPrompt $name) {
                        Write-Host "Opened install prompt in the Copilot app for: $name"
                        $null = Read-Host "Confirm '$name' in the Copilot app, then press Enter to continue"
                    }
                }
            }
        }
        Write-Host "`nACTION REQUIRED: confirm the marketplace in the Copilot app first, then confirm each selected plugin and check Customize > Installed."
        Write-Host 'Plugin installation is pending, not verified. Copilot Studio MCP/authentication remain separate.'
        return 4
    }
    Update-SetupPath
    Install-SetupPlugins -Path $path -PluginHost $PluginHost -Names $names -MarketplaceOnly:$MarketplaceOnly -Marketplace $Marketplace
    return 0
}

function Get-CopilotSetupHome {
    $default = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.copilot')).TrimEnd('\', '/')
    if ($env:COPILOT_HOME) {
        $configured = [Environment]::ExpandEnvironmentVariables($env:COPILOT_HOME)
        if ($configured -notmatch '^(?:[a-zA-Z]:[\\/]|\\\\)' -or
            -not [IO.Path]::GetFullPath($configured).TrimEnd('\', '/').Equals($default, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'COPILOT_HOME points to a custom location rather than the default user .copilot directory. Review registration/skill installation through that host explicitly; setup will not guess another location.'
        }
    }
    return $default
}

function Get-CopilotStudioConfigPath {
    param([string]$HostName)
    if ($HostName -eq 'ClaudeCode') {
        if ($env:CLAUDE_CONFIG_DIR) { throw 'Custom CLAUDE_CONFIG_DIR is set. Register the server through that host explicitly; setup will not guess its user config location.' }
        return Join-Path $env:USERPROFILE '.claude.json'
    }
    return Join-Path (Get-CopilotSetupHome) 'mcp-config.json'
}

function Read-McpUserConfig {
    param([string]$Path)
    $bytes = $null
    $text = '{}'
    if (Test-Path -LiteralPath $Path) {
        if ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'MCP configuration is a link/reparse point. Review it manually; setup will not replace it.'
        }
        $bytes = [IO.File]::ReadAllBytes($Path)
        try { $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes).TrimStart([char]0xFEFF) } catch {
            throw 'MCP configuration is not valid UTF-8. Review it privately; setup will not rewrite its encoding.'
        }
    }
    try { $data = $text | ConvertFrom-Json } catch {
        throw 'MCP configuration contains invalid JSON. No configuration was replaced; inspect the file privately.'
    }
    if (-not $text.TrimStart().StartsWith('{') -or $data -isnot [pscustomobject]) {
        throw 'MCP configuration must be a JSON object; no configuration was replaced.'
    }
    $servers = Get-PluginProperty $data 'mcpServers'
    if ($data.PSObject.Properties['mcpServers'] -and $servers -isnot [pscustomobject]) {
        throw 'The mcpServers value must be a JSON object; no configuration was replaced.'
    }
    # Locate insertion points without reserializing unrelated settings, numbers or secrets.
    $depth = 0
    $serverStart = -1
    $serverEnd = -1
    $rootKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $serverKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    for ($i = 0; $i -lt $text.Length; $i++) {
        $character = $text[$i]
        if ($character -eq '"') {
            $start = $i
            for ($i++; $i -lt $text.Length; $i++) {
                if ($text[$i] -eq '\') { $i++; continue }
                if ($text[$i] -eq '"') { break }
            }
            $after = $i + 1
            while ($after -lt $text.Length -and [char]::IsWhiteSpace($text[$after])) { $after++ }
            if ($after -lt $text.Length -and $text[$after] -eq ':') {
                $key = @(('[' + $text.Substring($start, $i - $start + 1) + ']') | ConvertFrom-Json)[0]
                if ($depth -eq 1) {
                    if (-not $rootKeys.Add($key)) { throw 'Duplicate root configuration keys are unsupported; review the file privately.' }
                    if ($key -ceq 'mcpServers') {
                        $serverStart = $after + 1
                        while ([char]::IsWhiteSpace($text[$serverStart])) { $serverStart++ }
                        if ($text[$serverStart] -ne '{') { throw 'The mcpServers value must be a JSON object.' }
                    } elseif ($key -ieq 'mcpServers') {
                        throw 'Use the exact mcpServers key casing before running setup.'
                    }
                } elseif ($depth -eq 2 -and $serverStart -ge 0 -and $serverEnd -lt 0) {
                    if (-not $serverKeys.Add($key)) { throw 'Duplicate MCP server keys are unsupported; review the file privately.' }
                }
            }
        } elseif ($character -in @('{', '[')) {
            $depth++
        } elseif ($character -in @('}', ']')) {
            if ($depth -eq 2 -and $serverStart -ge 0 -and $serverEnd -lt 0) { $serverEnd = $i }
            $depth--
        } elseif ($character -eq '/') {
            throw 'Comments in MCP JSON are unsupported; review the file privately.'
        } elseif ($character -eq ',') {
            $after = $i + 1
            while ($after -lt $text.Length -and [char]::IsWhiteSpace($text[$after])) { $after++ }
            if ($text[$after] -in @('}', ']')) { throw 'Trailing commas in MCP JSON are unsupported.' }
        }
    }
    [pscustomobject]@{ Bytes = $bytes; Text = $text; Data = $data; ServerEnd = $serverEnd }
}

function Test-CopilotStudioRegistration {
    param($Config)
    $servers = Get-PluginProperty $Config.Data 'mcpServers'
    if ($null -eq $servers) { return $false }
    $found = $false
    foreach ($property in $servers.PSObject.Properties) {
        $entry = $property.Value
        $arguments = @(Get-PluginProperty $entry 'args')
        $isStudio = @($arguments | Where-Object { $_ -is [string] -and $_ -match '^@microsoft/copilot-studio-mcp(?:@|$)' }).Count -gt 0
        if ($property.Name -ieq 'copilot-studio' -or $isStudio) {
            if ($found) { throw 'Multiple Copilot Studio MCP definitions found. Resolve duplicates manually.' }
            $command = Get-PluginProperty $entry 'command'
            $type = Get-PluginProperty $entry 'type'
            if ($command -notin @('npx', 'npx.cmd') -or
                ($type -and $type -notin @('local', 'stdio')) -or
                ($arguments -join "`n") -cne "-y`n@microsoft/copilot-studio-mcp@latest") {
                throw 'An existing Copilot Studio MCP definition differs (possibly a pinned version). Setup will not overwrite or duplicate it.'
            }
            $found = $true
        }
    }
    return $found
}

function Save-CopilotStudioConfig {
    param([string]$Path, $Config)
    $entry = '"copilot-studio":{"type":"local","command":"npx","args":["-y","@microsoft/copilot-studio-mcp@latest"],"tools":["*"]}'
    $servers = Get-PluginProperty $Config.Data 'mcpServers'
    if ($null -ne $servers) {
        $position = $Config.ServerEnd
        $separator = if (@($servers.PSObject.Properties).Count) { ',' } else { '' }
        $insertion = $separator + "`n" + $entry + "`n"
    } else {
        $position = $Config.Text.LastIndexOf('}')
        $separator = if (@($Config.Data.PSObject.Properties).Count) { ',' } else { '' }
        $insertion = $separator + "`n`"mcpServers`":{" + $entry + "}`n"
    }
    $content = $Config.Text.Insert($position, $insertion)
    $parent = Split-Path -Parent $Path
    if ((Test-Path -LiteralPath $parent) -and
        ((Get-Item -LiteralPath $parent).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'MCP config directory is a link/reparse point. Review it manually before registration.'
    }
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ([guid]::NewGuid().ToString('N') + '.setup-tmp')
    $backup = $Path + '.setup-backup-' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($temporary, [byte[]]@())
        if ($null -ne $Config.Bytes) {
            $acl = Get-Acl -LiteralPath $Path
            Set-Acl -LiteralPath $temporary -AclObject $acl
        }
        $hadBom = $null -ne $Config.Bytes -and $Config.Bytes.Length -ge 3 -and
            $Config.Bytes[0] -eq 0xEF -and $Config.Bytes[1] -eq 0xBB -and $Config.Bytes[2] -eq 0xBF
        [IO.File]::WriteAllText($temporary, $content, [Text.UTF8Encoding]::new($hadBom, $true))
        if ($null -ne $Config.Bytes) {
            $live = [IO.File]::ReadAllBytes($Path)
            if ([Convert]::ToBase64String($live) -cne [Convert]::ToBase64String($Config.Bytes)) {
                throw 'MCP configuration changed while setup was preparing the update. No replacement was made; close the host and retry explicitly.'
            }
            [IO.File]::Replace($temporary, $Path, $backup)
            if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backup)) -cne [Convert]::ToBase64String($Config.Bytes)) {
                throw "A concurrent config replacement was detected. Its displaced content is preserved in $backup. Stop and reconcile it before using the host."
            }
            Write-Host "Previous MCP configuration preserved in $backup (may contain secrets; keep private)."
        } else {
            # Move without overwrite: a concurrently created config must not be discarded.
            if (Test-Path -LiteralPath $Path) {
                throw 'MCP configuration was created while setup was preparing the update. No replacement was made; close the host and retry explicitly.'
            }
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Invoke-CopilotStudioSetup {
    [CmdletBinding()]
    param(
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$CopilotStudioHost,
        [switch]$AcceptCopilotStudio, [switch]$NonInteractive
    )
    if (-not $CopilotStudioHost) {
        if ($NonInteractive) { Write-Host 'Copilot Studio MCP stage skipped (no explicit host/approval).'; return 0 }
        Write-Host "`nOptional Copilot Studio MCP registration: 1 = Claude Code; 2 = Copilot CLI; 3 = Copilot desktop; Enter = skip."
        switch (Read-Host 'Choose the host for Copilot Studio MCP') {
            '' { Write-Host 'Copilot Studio MCP stage skipped.'; return 0 }
            '1' { $CopilotStudioHost = 'ClaudeCode' }
            '2' { $CopilotStudioHost = 'CopilotCli' }
            '3' { $CopilotStudioHost = 'CopilotApp' }
            default { Write-Host 'Unrecognized host. Copilot Studio MCP stage cancelled.'; return 2 }
        }
    }
    if ($CopilotStudioHost -eq 'Skip') { return 0 }
    if ($NonInteractive -and -not $AcceptCopilotStudio) { Write-Host 'Separate -AcceptCopilotStudio approval is required.'; return 2 }
    $path = Get-CopilotStudioConfigPath $CopilotStudioHost
    Write-Host "`nCopilot Studio MCP plan for ${CopilotStudioHost}: user-scope registration in $path"
    Write-Host 'Launch command: npx -y @microsoft/copilot-studio-mcp@latest'
    Write-Host 'The host downloads/caches the package on first launch; @latest allows future package updates.'
    Write-Host 'This stage saves configuration only: no server launch, sign-in, tenant selection or cloud operations.'
    Write-Host 'New Copilot entries expose the server tools to the host without enabling automatic approval.'
    Write-Host 'Close the selected host before approval to avoid concurrent config writes. Existing definitions/settings are preserved.'
    if (-not $AcceptCopilotStudio -and (Read-Host 'Type MCP to approve registration (anything else cancels)') -cne 'MCP') {
        Write-Host 'Copilot Studio MCP stage cancelled. Earlier installations are retained.'
        return 2
    }
    $config = Read-McpUserConfig $path
    if (Test-CopilotStudioRegistration $config) {
        Write-Host 'Matching user-scope Copilot Studio MCP definition already exists; left unchanged (including tool restrictions/disabled settings).'
    } elseif ($CopilotStudioHost -eq 'ClaudeCode') {
        $claude = Find-SetupExecutable 'claude'
        if (-not $claude) { throw 'Claude Code command not found. No host was installed and no configuration was changed.' }
        Invoke-SetupNative $claude @('mcp', 'add', '--scope', 'user', '--transport', 'stdio', 'copilot-studio', '--',
            'npx', '-y', '@microsoft/copilot-studio-mcp@latest') | Out-Null
    } else {
        Save-CopilotStudioConfig $path $config
    }
    if (-not (Test-CopilotStudioRegistration (Read-McpUserConfig $path))) {
        throw 'Copilot Studio MCP registration could not be verified in the user configuration.'
    }
    Write-Host 'Copilot Studio MCP: CONFIGURED, NOT RUNTIME-VERIFIED. Restart the host and inspect its MCP list/permissions.'
    Write-Host 'Project/plugin/managed definitions can override this user config; runtime visibility, authentication and environment access remain unverified.'
    return 0
}

function Invoke-SetupIntegrations {
    param(
        [string]$PluginHost, [string]$Plugins = 'All', [switch]$MarketplaceOnly,
        [ValidateSet('PowerPlatform', 'CopilotManagedRuntime', 'Both')][string]$Marketplace = 'PowerPlatform',
        [switch]$SkipMarketplace,
        [switch]$IncludeDataverse, [switch]$IncludeCmr, [switch]$AcceptPlugins, [switch]$NonInteractive,
        [string]$CopilotStudioHost, [switch]$AcceptCopilotStudio,
        [string]$ConnectionSkillHost, [switch]$AcceptConnectionSkill
    )
    $pluginResult = Invoke-PluginSetup -PluginHost $PluginHost -Plugins $Plugins -MarketplaceOnly:$MarketplaceOnly -Marketplace $Marketplace -SkipMarketplace:$SkipMarketplace -IncludeDataverse:$IncludeDataverse -IncludeCmr:$IncludeCmr -AcceptPlugins:$AcceptPlugins -NonInteractive:$NonInteractive
    if ($pluginResult -notin @(0, 4)) { return $pluginResult }
    $mcp = Invoke-CopilotStudioSetup -CopilotStudioHost $CopilotStudioHost -AcceptCopilotStudio:$AcceptCopilotStudio -NonInteractive:$NonInteractive
    if ($mcp -ne 0) { return $mcp }
    $skill = Invoke-ConnectionSkillSetup -ConnectionSkillHost $ConnectionSkillHost -AcceptConnectionSkill:$AcceptConnectionSkill -NonInteractive:$NonInteractive
    if ($skill -ne 0) { return $skill }
    return $pluginResult
}

function Get-ConnectionSkillDirectory {
    param([string]$HostName, [string]$SkillName = 'power-platform-connect')
    if ($HostName -eq 'ClaudeCode') {
        if ($env:CLAUDE_CONFIG_DIR) { throw 'Custom CLAUDE_CONFIG_DIR is set. Install the connection skill through that host explicitly; setup will not guess its personal skill directory.' }
        return Join-Path $env:USERPROFILE ".claude\skills\$SkillName"
    }
    return Join-Path (Get-CopilotSetupHome) "skills\$SkillName"
}

function Assert-SkillDirectoryChain {
    param([string]$Path)
    $directory = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($Path))
    while ($null -ne $directory) {
        if (Test-Path -LiteralPath $directory.FullName) {
            $item = Get-Item -LiteralPath $directory.FullName -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'The skill destination includes a file or linked directory. Review the location manually; nothing will be overwritten.'
            }
        }
        $directory = $directory.Parent
    }
}

function Install-ConnectionSkill {
    param([string]$Source, [string]$Destination, [string]$ExpectedSkillName = 'power-platform-connect')
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw 'Bundled connection skill is missing. Download/extract the full setup ZIP; do not run just the launcher/script.'
    }
    $text = Get-Content -LiteralPath $Source -Raw
    $escapedName = [regex]::Escape($ExpectedSkillName)
    if ($text -notmatch "(?s)^---\s*\r?\nname: $escapedName\r?\ndescription: [^\r\n]+\r?\n---" -or
        $text -match '(?m)^allowed-tools:') {
        throw 'The bundled connection skill has an unexpected definition. Review the full source before installing it.'
    }
    Assert-SkillDirectoryChain $Destination
    $expectedHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $target = Join-Path $Destination 'SKILL.md'
    if (Test-Path -LiteralPath $Destination) {
        if ((Test-Path -LiteralPath $target -PathType Leaf) -and
            -not ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $expectedHash) {
            Write-Host "Matching $ExpectedSkillName skill already exists; left unchanged."
            return
        }
        throw 'The connection skill directory already contains a different definition or other content. Review/update it manually; setup will not overwrite it.'
    }
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $staging = Join-Path $parent ('.setup-skill-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging | Out-Null
    try {
        $stagedFile = Join-Path $staging 'SKILL.md'
        Copy-Item -LiteralPath $Source -Destination $stagedFile
        if ((Get-FileHash -LiteralPath $stagedFile -Algorithm SHA256).Hash -ne $expectedHash) {
            throw 'The bundled skill changed during copy. No skill was installed; retry after reviewing the source.'
        }
        # A concurrent installation must not be overwritten.
        [IO.Directory]::Move($staging, $Destination)
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $expectedHash) {
            throw 'The installed skill no longer matches the reviewed bundle. Stop and inspect the destination.'
        }
        Write-Host "Skill saved to $target"
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }
}

function Show-ConnectionNextStep {
    Write-Host "`nNEXT STEP: continue the power-platform-setup entry skill; finish marketplace/plugin choices before connection onboarding."
    Write-Host 'For Power Platform environments, ask:'
    Write-Host '"Use the power-platform-connect skill to connect my selected Dataverse/PAC/Azure CLIs and MCP.'
    Write-Host 'Check existing profiles first, confirm my account/tenant/environment, and ask before sign-in or configuration changes."'
    Write-Host 'If the skill is not installed/visible, ask the agent to read:'
    Write-Host 'https://github.com/danieag/power-platform-cmr-setup/blob/main/skills/power-platform-connect/SKILL.md'
    Write-Host 'For Copilot Managed Runtime apps, authenticate with ''ms auth login'' or start ''/copilot-managed-runtime:create-app''.'
    Write-Host 'Remove unneeded surfaces from the request. Skill installation does not sign you in or grant tenant access.'
    Write-Host 'After PATH changes, reopen the host. If new plugins/MCP tools need a reload, pause, reopen and resume the same guided flow.'
    Write-Host 'Connection onboarding needs its own confirmed target and approvals; do not authenticate under installation approval.'
}

function Invoke-ConnectionSkillSetup {
    [CmdletBinding()]
    param(
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$ConnectionSkillHost,
        [switch]$AcceptConnectionSkill, [switch]$NonInteractive
    )
    if (-not $ConnectionSkillHost -and -not $NonInteractive) {
        Write-Host "`nOptional final step: install the bundled power-platform-connect and power-platform-router skills for your user."
        Write-Host '1 = Claude Code; 2 = Copilot CLI; 3 = Copilot desktop; Enter = skip and show next-step instructions.'
        switch (Read-Host 'Choose the skill host (no authentication will run)') {
            '' { $ConnectionSkillHost = 'Skip' }
            '1' { $ConnectionSkillHost = 'ClaudeCode' }
            '2' { $ConnectionSkillHost = 'CopilotCli' }
            '3' { $ConnectionSkillHost = 'CopilotApp' }
            default { Write-Host 'Unrecognized host. Connection skill stage cancelled.'; return 2 }
        }
    }
    if (-not $ConnectionSkillHost -or $ConnectionSkillHost -eq 'Skip') {
        Write-Host 'Connection skill installation skipped.'
        Show-ConnectionNextStep
        return 0
    }
    if ($NonInteractive -and -not $AcceptConnectionSkill) {
        Write-Host 'Separate -AcceptConnectionSkill approval is required.'
        return 2
    }
    $connectDestination = Get-ConnectionSkillDirectory $ConnectionSkillHost 'power-platform-connect'
    $routerDestination = Get-ConnectionSkillDirectory $ConnectionSkillHost 'power-platform-router'
    Write-Host "`nPersonal skill plan for ${ConnectionSkillHost}:"
    Write-Host "  - $connectDestination (connect/manage saved environments)"
    Write-Host "  - $routerDestination (automatically reuse saved environments & confirm Solution Y in future builds)"
    Write-Host 'Copy the bundled instructions into the documented personal skills directory; no CLI, server or sign-in is started.'
    Write-Host 'This makes saved environments discoverable across future projects/chats. Existing definitions are never overwritten.'
    Write-Host 'Host discovery/policy must still be checked after restart; no auto-approval permissions will be enabled.'
    if (-not $AcceptConnectionSkill -and (Read-Host 'Type SKILL to approve installation (anything else cancels)') -cne 'SKILL') {
        Write-Host 'Connection skill installation cancelled. Earlier setup is retained.'
        Show-ConnectionNextStep
        return 2
    }
    Install-ConnectionSkill -Source (Join-Path $PSScriptRoot 'skills\power-platform-connect\SKILL.md') -Destination $connectDestination -ExpectedSkillName 'power-platform-connect'
    Install-ConnectionSkill -Source (Join-Path $PSScriptRoot 'skills\power-platform-router\SKILL.md') -Destination $routerDestination -ExpectedSkillName 'power-platform-router'
    Write-Host 'Personal skill file installation verified (power-platform-connect and power-platform-router). Host discovery and authentication are NOT verified.'
    Show-ConnectionNextStep
    return 0
}

function Select-InteractiveSetupMode {
    Write-Host "`nChoose what you want to set up:"
    Write-Host '  1 = Power Platform plugins or marketplace (installs only required prerequisites)'
    Write-Host '  2 = Copilot Managed Runtime / Managed Apps (Git + GCM, Node 24.11+, ms CLI & plugin)'
    Write-Host '  3 = Both (Power Platform plugins + Copilot Managed Runtime)'
    Write-Host '  4 = Full Power Platform workstation setup (Git, Node.js/npm, .NET 10 SDK, PAC CLI, Azure CLI)'
    Write-Host '  Enter = cancel'
    $mode = Read-Host 'Select 1, 2, 3, or 4 (anything else cancels)'
    if ($mode -eq '4') {
        return [pscustomobject]@{ Cancelled = $false; Prerequisites = 'All'; Plugins = 'All'; PluginHost = ''; MarketplaceOnly = $false; Marketplace = 'PowerPlatform'; IncludeCmr = $false }
    }
    if ($mode -notin @('1', '2', '3')) {
        Write-Host 'Cancelled. No changes made.'
        return [pscustomobject]@{ Cancelled = $true }
    }
    $marketplaceOnly = $false
    $marketplace = 'PowerPlatform'
    $includeCmr = ($mode -in @('2', '3'))
    $selectedPlugins = 'copilot-managed-runtime'
    if ($mode -in @('1', '3')) {
        $ppCatalog = @(Get-SetupPluginCatalog | Where-Object { $_.MarketplaceKey -eq 'PowerPlatform' })
        Write-Host "`nAvailable Power Platform plugins and their core Windows prerequisites:"
        for ($i = 0; $i -lt $ppCatalog.Count; $i++) {
            $entry = $ppCatalog[$i]
            Write-Host ("  {0,2}. {1,-28} - {2} [{3}]" -f ($i + 1), $entry.Id, $entry.Summary, ($entry.Prerequisites -join ', '))
        }
        if ($mode -eq '1') {
            Write-Host '   M. Marketplace only             - Official Power Platform marketplace without plugins [git]'
        }
        Write-Host '   A. All 11 Power Platform plugins - Full catalog including Dataverse [git, node, dotnet, pac, azure]'
        $prompt = if ($mode -eq '1') {
            'Pick one or more (e.g. 2,3,7 or 2 3 7), plugin IDs, M, or A (Enter = cancel)'
        } else {
            'Pick one or more Power Platform plugins to combine with CMR (e.g. 2,3,7), plugin IDs, or A (Enter = cancel)'
        }
        $raw = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-Host 'Cancelled. No changes made.'
            return [pscustomobject]@{ Cancelled = $true }
        }
        $trimmedRaw = $raw.Trim()
        if ($mode -eq '1' -and $trimmedRaw -ieq 'M') {
            $marketplaceOnly = $true
            $selectedPlugins = 'All'
        } elseif ($trimmedRaw -ieq 'A' -or $trimmedRaw -ieq 'All') {
            $pickedIds = @($ppCatalog | ForEach-Object { $_.Id })
            if ($includeCmr) { $pickedIds += 'copilot-managed-runtime' }
            $selectedPlugins = $pickedIds -join ','
        } else {
            if ($trimmedRaw -match '(^|,)\s*(,|$)') {
                Write-Host 'Empty entry in plugin selection. Setup cancelled.'
                return [pscustomobject]@{ Cancelled = $true }
            }
            $picked = [System.Collections.Generic.List[string]]::new()
            foreach ($token in [regex]::Split($trimmedRaw, '[\s,]+')) {
                $part = $token.Trim().ToLowerInvariant()
                if (-not $part) { continue }
                $num = 0
                if ([int]::TryParse($part, [ref]$num)) {
                    if ($num -lt 1 -or $num -gt $ppCatalog.Count) {
                        Write-Host "Plugin number '$part' is out of range (1-$($ppCatalog.Count)). Setup cancelled."
                        return [pscustomobject]@{ Cancelled = $true }
                    }
                    $part = $ppCatalog[$num - 1].Id
                } elseif ($part -notin @($ppCatalog | ForEach-Object { $_.Id })) {
                    Write-Host "Unrecognized plugin '$part'. Setup cancelled."
                    return [pscustomobject]@{ Cancelled = $true }
                }
                if (-not $picked.Contains($part)) { $picked.Add($part) }
            }
            if ($includeCmr -and -not $picked.Contains('copilot-managed-runtime')) { $picked.Add('copilot-managed-runtime') }
            $selectedPlugins = $picked -join ','
        }
    }
    Write-Host "`nChoose where to set up the marketplace/plugins:"
    $agentHosts = @(Get-SetupAgentHosts)
    Write-Host 'Passive host discovery only: commands and app-link registrations are not proof that a host works or is signed in.'
    foreach ($candidate in $agentHosts) {
        $status = if (-not $candidate.Detected) { 'not detected' }
            elseif ($candidate.Id -eq 'CopilotApp') { 'ghapp URL handler registered; app not runtime-verified' }
            else { 'command found; may be a first-run launcher, not a verified CLI' }
        Write-Host ("  {0}: {1}" -f $candidate.Name, $status)
    }
    if ($marketplaceOnly) {
        Write-Host '1 = Claude Code (claude command); 2 = Copilot CLI; 3 = Copilot desktop app link; Enter = cancel.'
    } else {
        Write-Host '1 = Claude Code (claude command); 2 = Copilot CLI; 3 = Copilot desktop app links; 4 = VS Code / manual UI (prerequisites only); Enter = cancel.'
    }
    $hostChoice = Read-Host 'Choose the host you already use; no new host will be installed'
    $chosenHost = switch ($hostChoice) {
        '1' { 'ClaudeCode' }
        '2' { 'CopilotCli' }
        '3' { 'CopilotApp' }
        '4' { if (-not $marketplaceOnly) { 'Skip' } else { '' } }
        default { '' }
    }
    if (-not $chosenHost) {
        Write-Host 'Host selection cancelled. No changes made.'
        return [pscustomobject]@{ Cancelled = $true }
    }
    if ($chosenHost -eq 'CopilotApp' -and -not @($agentHosts | Where-Object { $_.Id -eq 'CopilotApp' -and $_.Detected }).Count) {
        Write-Host 'The Copilot desktop app link handler was not detected. This does not prove the app is absent.'
        if ((Read-Host 'If you already installed the Copilot desktop app, type APP to use its confirmation links; Enter = official install guidance') -cne 'APP') {
            Show-AgentHostInstallHandoff 'CopilotApp'
            return [pscustomobject]@{ Cancelled = $true }
        }
    }
    if ($chosenHost -eq 'Skip') {
        Write-Host 'Prerequisites for your selected plugins will be checked/installed; add the plugins afterward in VS Code Customizations > Browse.'
    }
    return [pscustomobject]@{
        Cancelled = $false; Prerequisites = 'FromPlugins'
        Plugins = $selectedPlugins; PluginHost = $chosenHost
        MarketplaceOnly = $marketplaceOnly; Marketplace = $marketplace; IncludeCmr = $includeCmr
    }
}

function Invoke-Setup {
    [CmdletBinding()]
    param(
        [switch]$CheckOnly, [switch]$Install, [switch]$Accept, [switch]$NonInteractive, [switch]$IncludeAzureCli, [switch]$SkipAzureCli,
        [AllowEmptyString()][string]$Prerequisites = 'All',
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$PluginHost,
        [AllowEmptyString()][string]$Plugins = 'All',
        [switch]$MarketplaceOnly,
        [ValidateSet('PowerPlatform', 'CopilotManagedRuntime', 'Both')][string]$Marketplace = 'PowerPlatform',
        [switch]$SkipMarketplace,
        [switch]$IncludeDataverse, [switch]$IncludeCmr, [switch]$AcceptPlugins,
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$CopilotStudioHost,
        [switch]$AcceptCopilotStudio,
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$ConnectionSkillHost,
        [switch]$AcceptConnectionSkill
    )
    if (($CheckOnly -and ($Install -or $Accept -or $AcceptPlugins -or $AcceptCopilotStudio -or $AcceptConnectionSkill)) -or ($Accept -and -not $Install)) {
        Write-Host 'Invalid options: use -CheckOnly alone, or -Install [-Accept] [-NonInteractive].'
        return 2
    }
    if ($IncludeAzureCli -and $SkipAzureCli) {
        Write-Host 'Do not combine -IncludeAzureCli and -SkipAzureCli. Azure CLI is included by default.'
        return 2
    }
    if ($MarketplaceOnly -and ($PluginHost -notin @('CopilotCli', 'ClaudeCode', 'CopilotApp') -or $Plugins -ne 'All' -or $IncludeDataverse -or $IncludeCmr -or $SkipMarketplace)) {
        Write-Host 'Marketplace-only preparation requires -PluginHost ClaudeCode, CopilotCli or CopilotApp and cannot include a plugin selection, -SkipMarketplace, or Dataverse/CMR opt-in.'
        return 2
    }
    if (-not $MarketplaceOnly -and $Marketplace -ne 'PowerPlatform') {
        Write-Host '-Marketplace applies only to -MarketplaceOnly preparation; when selecting plugins, marketplaces are derived automatically from the chosen plugin IDs.'
        return 2
    }
    if ($MarketplaceOnly -and $Marketplace -eq 'Both' -and $PluginHost -eq 'CopilotApp' -and $NonInteractive) {
        Write-Host 'Add one marketplace at a time on CopilotApp in noninteractive mode (-Marketplace PowerPlatform, then -Marketplace CopilotManagedRuntime) so the user can confirm each dialog in order.'
        return 2
    }
    if ($SkipMarketplace -and $PluginHost -ne 'CopilotApp') {
        Write-Host '-SkipMarketplace applies only to -PluginHost CopilotApp after the official marketplace has been confirmed in the app.'
        return 2
    }
    try {
        $null = @(Get-SetupPluginNames -Plugins $Plugins -IncludeDataverse:$IncludeDataverse -IncludeCmr:$IncludeCmr)
        $includeMcpNode = [bool]($CopilotStudioHost -and $CopilotStudioHost -ne 'Skip')
        $selectedPrerequisites = @(Resolve-SetupPrerequisites -Prerequisites $Prerequisites -Plugins $Plugins -IncludeDataverse:$IncludeDataverse -IncludeCmr:$IncludeCmr -MarketplaceOnly:$MarketplaceOnly -IncludeAzureCli:$IncludeAzureCli -SkipAzureCli:$SkipAzureCli -IncludeCopilotStudioMcp:$includeMcpNode)
    } catch [ArgumentException] {
        Write-Host $_.Exception.Message
        return 2
    }
    $fromPlugins = $Prerequisites.Trim() -ieq 'FromPlugins'
    if ($Plugins -ne 'All' -and (-not $PluginHost -or $PluginHost -eq 'Skip') -and (-not $fromPlugins -or $AcceptPlugins)) {
        Write-Host 'An explicit -Plugins selection requires -PluginHost ClaudeCode, CopilotCli or CopilotApp (unless resolving -Prerequisites FromPlugins without -AcceptPlugins).'
        return 2
    }
    if (($AcceptConnectionSkill -and (-not $ConnectionSkillHost -or $ConnectionSkillHost -eq 'Skip')) -or
        ($NonInteractive -and -not $CheckOnly -and $ConnectionSkillHost -and $ConnectionSkillHost -ne 'Skip' -and -not $AcceptConnectionSkill)) {
        Write-Host 'Choose -ConnectionSkillHost ClaudeCode, CopilotCli or CopilotApp and provide separate -AcceptConnectionSkill approval for noninteractive skill installation.'
        return 2
    }
    if (($AcceptCopilotStudio -and (-not $CopilotStudioHost -or $CopilotStudioHost -eq 'Skip')) -or
        ($NonInteractive -and -not $CheckOnly -and $CopilotStudioHost -and $CopilotStudioHost -ne 'Skip' -and -not $AcceptCopilotStudio)) {
        Write-Host 'Choose -CopilotStudioHost ClaudeCode, CopilotCli or CopilotApp and provide separate -AcceptCopilotStudio approval for noninteractive registration.'
        return 2
    }
    if (($AcceptPlugins -and (-not $PluginHost -or $PluginHost -eq 'Skip')) -or
        (($IncludeDataverse -or $IncludeCmr) -and $PluginHost -eq 'Skip' -and -not $fromPlugins) -or
        ($NonInteractive -and -not $CheckOnly -and
            ((($IncludeDataverse -or $IncludeCmr) -and -not $PluginHost -and -not $fromPlugins) -or
             ($PluginHost -and $PluginHost -ne 'Skip' -and -not $AcceptPlugins)))) {
        Write-Host 'Specify -PluginHost ClaudeCode, CopilotCli or CopilotApp. Noninteractive plugin setup also requires separate -AcceptPlugins approval.'
        return 2
    }
    try {
        $architecture = Get-SetupArchitecture
        $isDefaultInteractive = -not $CheckOnly -and -not $NonInteractive -and -not $Install -and -not $Accept -and
            -not $IncludeAzureCli -and -not $SkipAzureCli -and $Prerequisites -eq 'All' -and
            -not $PluginHost -and $Plugins -eq 'All' -and -not $MarketplaceOnly -and $Marketplace -eq 'PowerPlatform' -and -not $SkipMarketplace -and
            -not $IncludeDataverse -and -not $IncludeCmr -and -not $AcceptPlugins -and
            -not $CopilotStudioHost -and -not $AcceptCopilotStudio -and
            -not $ConnectionSkillHost -and -not $AcceptConnectionSkill
        if ($isDefaultInteractive) {
            $interactivePlan = Select-InteractiveSetupMode
            if ($interactivePlan.Cancelled) { return 2 }
            $Prerequisites = $interactivePlan.Prerequisites
            $Plugins = $interactivePlan.Plugins
            $PluginHost = $interactivePlan.PluginHost
            $MarketplaceOnly = $interactivePlan.MarketplaceOnly
            $Marketplace = $interactivePlan.Marketplace
            $IncludeCmr = $interactivePlan.IncludeCmr
            $selectedPrerequisites = @(Resolve-SetupPrerequisites -Prerequisites $Prerequisites -Plugins $Plugins -IncludeCmr:$IncludeCmr -MarketplaceOnly:$MarketplaceOnly)
        }
        $isSelective = $Prerequisites.Trim() -ine 'All'
        $includeAzure = 'azure' -in $selectedPrerequisites
        $includeCmrTools = 'cmr' -in $selectedPrerequisites
        Write-Host "Windows architecture: $architecture (setup process: $env:PROCESSOR_ARCHITECTURE)"
        Write-Host "Missing Git, Node and .NET will use native $architecture installers. PAC will match the selected .NET host."
        if ($architecture -eq 'arm64') {
            Write-Host 'Compatible existing x64/x86 tools are preserved and use Windows 11 emulation.'
            if ($includeAzure) { Write-Host 'Azure CLI uses the official x64 MSI under Windows 11 emulation, not a native ARM64 build.' }
        }
        if ($SkipAzureCli) { Write-Host 'Azure CLI skipped explicitly; Azure-dependent plugin workflows may need it installed later.' }
        Show-SelectiveScopeSummary -Prerequisites $Prerequisites -SelectedPrerequisiteIds $selectedPrerequisites -Plugins $Plugins -IncludeDataverse:$IncludeDataverse -IncludeCmr:$IncludeCmr -MarketplaceOnly:$MarketplaceOnly -Marketplace $Marketplace
        $stateParams = @{ Azure = $includeAzure; Architecture = $architecture }
        if ($includeCmrTools) { $stateParams.Cmr = $true }
        $state = @(Get-SetupState @stateParams | Where-Object { $_.Id -in $selectedPrerequisites })
        Show-SetupState $state -Selective:$isSelective
        $pending = @($state | Where-Object { -not $_.Ready })
        if ($CheckOnly) {
            if ($ConnectionSkillHost -and $ConnectionSkillHost -ne 'Skip') {
                Write-Host "Requested later connection skill installation: $ConnectionSkillHost (no user skill directory inspected or changed)."
            }
            if ($CopilotStudioHost -and $CopilotStudioHost -ne 'Skip') {
                Write-Host "Requested later Copilot Studio MCP stage: $CopilotStudioHost (configuration/runtime not inspected in offline check-only mode)."
            }
            if ($PluginHost -and $PluginHost -ne 'Skip') {
                Write-Host "Requested later plugin stage: $PluginHost. Host/plugin readiness is NOT checked in offline check-only mode."
                if ($MarketplaceOnly) { Write-Host "Marketplace registration only ($Marketplace); no plugins selected." }
                else { Write-Host (@(Get-SetupPluginNames -IncludeDataverse:$IncludeDataverse -IncludeCmr:$IncludeCmr -Plugins $Plugins) -join ', ') }
            }
            if ($pending.Count) {
                Write-Host "`nPlanned order: $($pending.Name -join ' -> ')"
                return 1
            }
            return 0
        }
        if ($pending.Count -eq 0) {
            Write-Host "`nAll selected prerequisites are ready. Plugins and authentication still need separate verification."
            return (Invoke-SetupIntegrations -PluginHost $PluginHost -Plugins $Plugins -MarketplaceOnly:$MarketplaceOnly -Marketplace $Marketplace -SkipMarketplace:$SkipMarketplace -IncludeDataverse:$IncludeDataverse -IncludeCmr:$IncludeCmr -AcceptPlugins:$AcceptPlugins -NonInteractive:$NonInteractive -CopilotStudioHost $CopilotStudioHost -AcceptCopilotStudio:$AcceptCopilotStudio -ConnectionSkillHost $ConnectionSkillHost -AcceptConnectionSkill:$AcceptConnectionSkill)
        }
        Write-Host "`nPlanned order: $($pending.Name -join ' -> ')"
        if ($NonInteractive -and -not ($Install -and $Accept)) {
            Write-Host 'No changes made. Agent installation requires explicit -Install -Accept -NonInteractive approval.'
            return 2
        }
        if (-not ($Install -and $Accept)) {
            Write-Host 'This will download and run official installers, accept their licenses, and may request UAC.'
            Write-Host 'Git, PAC and CMR CLI are per-user; Node/.NET/Azure are machine-wide. No cloud login or automatic reboot.'
            $answer = Read-Host 'Type INSTALL to approve this plan (anything else cancels)'
            if ($answer -cne 'INSTALL') { Write-Host 'Cancelled. No changes made.'; return 2 }
        }
        # TLS is changed for this approved process only, never persisted.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Update-SetupPath
        foreach ($tool in $pending) {
            Write-Host "`nSetting up $($tool.Name)..."
            $restart = Install-SetupTool $tool.Id
            Update-SetupPath
            if ($restart) {
                Write-Host 'Windows reported a restart requirement. Save your work, restart Windows yourself, then rerun setup.'
                Write-Host 'Setup stopped before installing further prerequisites. No reboot was requested by this script.'
                return 3010
            }
            $state = @(Get-SetupState @stateParams | Where-Object { $_.Id -in $selectedPrerequisites })
            Confirm-InstalledTool $tool.Id $state
        }
        Show-SetupState $state -Selective:$isSelective
        Write-Host "`nPrerequisites ready. Keep this window open for the optional plugin stage."
        Write-Host 'After setup finishes, restart terminals and your chosen host so they inherit the new PATH.'
        Write-Host 'No tenant has been accessed. Optional MCP registration needs its own approval; intentional sign-in remains separate.'
        return (Invoke-SetupIntegrations -PluginHost $PluginHost -Plugins $Plugins -MarketplaceOnly:$MarketplaceOnly -Marketplace $Marketplace -SkipMarketplace:$SkipMarketplace -IncludeDataverse:$IncludeDataverse -IncludeCmr:$IncludeCmr -AcceptPlugins:$AcceptPlugins -NonInteractive:$NonInteractive -CopilotStudioHost $CopilotStudioHost -AcceptCopilotStudio:$AcceptCopilotStudio -ConnectionSkillHost $ConnectionSkillHost -AcceptConnectionSkill:$AcceptConnectionSkill)
    } catch {
        Write-Host "`nSetup failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'No later setup steps were run. Resolve the cause and rerun -CheckOnly; completed prerequisite/plugin installations are preserved.'
        return 3
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-Setup -CheckOnly:$CheckOnly -Install:$Install -Accept:$Accept -NonInteractive:$NonInteractive -IncludeAzureCli:$IncludeAzureCli -SkipAzureCli:$SkipAzureCli -Prerequisites $Prerequisites -PluginHost $PluginHost -Plugins $Plugins -MarketplaceOnly:$MarketplaceOnly -Marketplace $Marketplace -SkipMarketplace:$SkipMarketplace -IncludeDataverse:$IncludeDataverse -IncludeCmr:$IncludeCmr -AcceptPlugins:$AcceptPlugins -CopilotStudioHost $CopilotStudioHost -AcceptCopilotStudio:$AcceptCopilotStudio -ConnectionSkillHost $ConnectionSkillHost -AcceptConnectionSkill:$AcceptConnectionSkill)
}
