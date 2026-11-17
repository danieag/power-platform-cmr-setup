#requires -Version 5.1
[CmdletBinding()]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-NodeSupportDate {
    param([string]$Value)
    $date = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Value, 'yyyy-MM-dd',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$date)) {
        throw 'Official Node metadata contains a missing or invalid release/support date.'
    }
    return $date
}

function Get-NodeSupportMajors {
    param([string]$Source)
    $matches = [regex]::Matches($Source, '(?m)^    \$supportedNodeMajors = @\((?<majors>\d+(?:, \d+)*)\)\r?$')
    if ($matches.Count -ne 1) {
        throw 'Expected one literal supportedNodeMajors policy in Setup.ps1; review the updater after source changes.'
    }
    $majors = @($matches[0].Groups['majors'].Value -split ', ' | ForEach-Object { [int]$_ })
    if (($majors -join ',') -ne (($majors | Sort-Object -Unique) -join ',') -or $majors[0] -lt 22) {
        throw 'The Node major-version policy must be unique, sorted and start at 22 or later.'
    }
    return $majors
}

function Format-NodeSupportLabel {
    param([int[]]$Majors)
    $labels = @($Majors | ForEach-Object { if ($_ -eq 22) { '22.18+ (22.x)' } else { "$_" } })
    if ($labels.Count -eq 1) { return $labels[0] }
    return (($labels[0..($labels.Count - 2)] -join ', ') + ' or ' + $labels[-1])
}

function Get-NodeSupportProposal {
    param(
        [int[]]$CurrentMajors, [object[]]$Releases, [object]$Schedule,
        [datetime]$AsOf = [datetime]::UtcNow.Date
    )
    if (-not $CurrentMajors.Count -or -not $Releases.Count -or $null -eq $Schedule) {
        throw 'Node support metadata or the current policy is empty; refusing to propose changes.'
    }
    $releasedLtsMajors = @()
    foreach ($release in $Releases) {
        if ($release.version -notmatch '^v(?<major>\d+)\.\d+\.\d+$') {
            if ($release.version -match '^v\d+\.\d+\.\d+-') { continue }
            throw 'Unexpected Node release version in official metadata.'
        }
        $major = [int]$Matches['major']
        if ($release.lts -ceq $false) { continue }
        if ($release.lts -isnot [string] -or [string]::IsNullOrWhiteSpace($release.lts)) {
            throw 'Unexpected Node LTS marker in official metadata.'
        }
        if ((Read-NodeSupportDate $release.date) -le $AsOf.Date) { $releasedLtsMajors += $major }
    }
    $eligible = @()
    $endOfLife = @()
    foreach ($major in @(($CurrentMajors + $releasedLtsMajors) | Sort-Object -Unique)) {
        $entry = $Schedule.PSObject.Properties["v$major"]
        if ($null -eq $entry -or -not $entry.Value.PSObject.Properties['lts']) {
            throw "Official support schedule has no LTS entry for Node $major."
        }
        $start = Read-NodeSupportDate $entry.Value.start
        $lts = Read-NodeSupportDate $entry.Value.lts
        $end = Read-NodeSupportDate $entry.Value.end
        if ($start -gt $lts -or $lts -ge $end) { throw "Invalid support-date ordering for Node $major." }
        if ($major -in $CurrentMajors -and $end -le $AsOf.Date) { $endOfLife += $major }
        if ($major -ge 22 -and $major -in $releasedLtsMajors -and $lts -le $AsOf.Date -and $end -gt $AsOf.Date) {
            $eligible += $major
        }
    }
    $added = @($eligible | Where-Object { $_ -notin $CurrentMajors } | Sort-Object -Unique)
    [pscustomobject]@{
        AsOf = $AsOf.ToString('yyyy-MM-dd')
        Changed = $added.Count -gt 0
        CurrentMajors = [int[]]$CurrentMajors
        AddedMajors = [int[]]$added
        ProposedMajors = [int[]]@(($CurrentMajors + $added) | Sort-Object -Unique)
        EndOfLifeMajors = [int[]]$endOfLife
    }
}

function Replace-NodeSupportText {
    param([string]$Text, [string]$Old, [string]$New, [string]$File)
    if ([regex]::Matches($Text, [regex]::Escape($Old)).Count -ne 1) {
        throw "Expected one compatibility marker in $File; no proposal files have been written."
    }
    return $Text.Replace($Old, $New)
}

function Update-NodeSupportFiles {
    param([string]$Root, [object]$Proposal)
    if (-not $Proposal.Changed) { return }
    $oldLabel = Format-NodeSupportLabel $Proposal.CurrentMajors
    $newLabel = Format-NodeSupportLabel $Proposal.ProposedMajors
    $files = @('Setup.ps1', 'README.md', 'docs\advanced-setup.md',
        'skills\power-platform-integrations\SKILL.md', 'scripts\Test-Setup.ps1')
    $edits = @()
    foreach ($file in $files) {
        $path = Join-Path $Root $file
        if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to edit a linked proposal file: $file"
        }
        $original = [IO.File]::ReadAllText($path)
        $updated = $original
        if ($file -eq 'scripts\Test-Setup.ps1') {
            $pattern = '(?s)(?<prefix>Test-Case ''Node compatibility enforces approved majors and bundled npm'' \{.*?foreach \(\$case in @\()(?<rows>.*?)(?<closing>\)\) \{)'
            $matches = [regex]::Matches($original, $pattern)
            if ($matches.Count -ne 1) { throw 'Expected one Node compatibility case table; no proposal files have been written.' }
            $newline = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
            $rows = $matches[0].Groups['rows'].Value.TrimEnd()
            foreach ($major in $Proposal.AddedMajors) {
                if ($rows -match ("Version = '" + $major + '\.')) {
                    throw "Node $major already has compatibility cases; review them manually before proposing support."
                }
                $rows += ',' + $newline + "        @{ Version = '${major}.0.0'; Npm = '11.20.0'; Ready = " + '$true }'
            }
            $replacement = $matches[0].Groups['prefix'].Value + $rows + $matches[0].Groups['closing'].Value
            $updated = Replace-NodeSupportText $original $matches[0].Value $replacement $file
        } else {
            $updated = Replace-NodeSupportText $updated $oldLabel $newLabel $file
            if ($file -eq 'Setup.ps1') {
                $actual = @(Get-NodeSupportMajors $original)
                if (($actual -join ',') -ne ($Proposal.CurrentMajors -join ',')) {
                    throw 'The Node policy changed since metadata was checked; refusing to overwrite it.'
                }
                $oldPolicy = '$supportedNodeMajors = @(' + ($actual -join ', ') + ')'
                $newPolicy = '$supportedNodeMajors = @(' + ($Proposal.ProposedMajors -join ', ') + ')'
                $updated = Replace-NodeSupportText $updated $oldPolicy $newPolicy $file
            }
        }
        $edits += [pscustomobject]@{ Path = $path; Original = $original; Updated = $updated }
    }
    foreach ($edit in $edits) {
        if ([IO.File]::ReadAllText($edit.Path) -cne $edit.Original) {
            throw 'A proposal file changed concurrently; no proposal files have been written.'
        }
    }
    foreach ($edit in $edits) {
        [IO.File]::WriteAllText($edit.Path, $edit.Updated, [Text.UTF8Encoding]::new($false))
    }
}

function Invoke-NodeSupportMaintenance {
    param([string]$Root, [switch]$Apply)
    $current = @(Get-NodeSupportMajors ([IO.File]::ReadAllText((Join-Path $Root 'Setup.ps1'))))
    $releases = @(Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -TimeoutSec 60)
    $schedule = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/nodejs/Release/main/schedule.json' -TimeoutSec 60
    $proposal = Get-NodeSupportProposal -CurrentMajors $current -Releases $releases -Schedule $schedule
    if ($Apply) { Update-NodeSupportFiles -Root $Root -Proposal $proposal }
    return $proposal
}

if ($MyInvocation.InvocationName -ne '.') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-NodeSupportMaintenance -Root (Split-Path -Parent $PSScriptRoot) -Apply:$Apply |
        ConvertTo-Json -Depth 4
}
