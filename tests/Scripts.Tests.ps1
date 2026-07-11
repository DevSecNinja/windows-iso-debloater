#Requires -Modules Pester

# Lightweight, cross-platform tests for the repository's PowerShell scripts.
# These run on every push to main (and on pull requests) via .github/workflows/ci.yml.
# They validate that the scripts stay syntactically valid and keep the contract the
# build pipeline relies on (headless parameters and the oscdimg install path), without
# needing a Windows host or actually building an ISO.

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $scriptFiles = Get-ChildItem -Path $repoRoot -Recurse -Force -Filter '*.ps1' |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        ForEach-Object { @{ Path = $_.FullName; Name = $_.Name } }
}

Describe 'PowerShell script quality' {
    It 'parses <Name> without syntax errors' -ForEach $scriptFiles {
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors) | Out-Null
        $parseErrors | Should -BeNullOrEmpty
    }
}

Describe 'isoDebloaterScript.ps1' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $scriptPath = Join-Path $repoRoot 'isoDebloaterScript.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $paramNames = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
        $scriptText = Get-Content -Path $scriptPath -Raw
    }

    It 'exposes the -<_> parameter required for headless/CI use' -ForEach @(
        'noPrompt', 'isoPath', 'winEdition', 'outputISO', 'useOscdimg'
    ) {
        $paramNames | Should -Contain $_
    }

    It 'resolves oscdimg from the standard Windows ADK Deployment Tools path' {
        # The CI workflow installs oscdimg.exe to this exact path, so keep them in sync.
        $scriptText | Should -Match 'Assessment and Deployment Kit\\Deployment Tools\\amd64\\Oscdimg'
    }
}

Describe 'Build pipeline (build-debloated-iso.yml)' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $workflowPath = Join-Path $repoRoot '.github/workflows/build-debloated-iso.yml'
        $workflowText = Get-Content -Path $workflowPath -Raw
    }

    It 'installs oscdimg via the Chocolatey windows-adk-oscdimg package' {
        $workflowText | Should -Match 'choco install windows-adk-oscdimg'
    }

    It 'does not download or run the incompatible ADK web installer' {
        # Guard against regressing to the adksetup.exe bootstrapper, which fails to
        # launch on the hosted Windows Server 2025 runner.
        $workflowText | Should -Not -Match '\$adkInstaller'
        $workflowText | Should -Not -Match 'linkid=2250347'
    }
}

Describe 'GitHub Actions supply-chain hardening' {
    BeforeDiscovery {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $workflowDir = Join-Path $repoRoot '.github/workflows'
        $usesRefs = Get-ChildItem -Path $workflowDir -Filter '*.yml' | ForEach-Object {
            $file = $_.Name
            Get-Content -Path $_.FullName |
                Where-Object { $_ -match '^\s*(-\s*)?uses:\s*\S' } |
                ForEach-Object {
                    # Strip everything up to and including "uses:" and any trailing comment.
                    $ref = ($_ -replace '^.*?uses:\s*', '') -replace '\s*#.*$', ''
                    @{ File = $file; Ref = $ref.Trim() }
                }
        }
    }

    # Third-party actions must be pinned to an immutable 40-character commit SHA so a
    # retagged/hijacked release tag can't silently change what runs in CI.
    It 'pins action to a full commit SHA: <Ref> (<File>)' -ForEach $usesRefs {
        # Local actions referenced by path (./ or ../) are exempt.
        if ($Ref -match '^\.{1,2}/') { return }
        $Ref | Should -Match '@[0-9a-f]{40}$'
    }
}

Describe 'Debloat data files' {
    BeforeDiscovery {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $dataDir = Join-Path $repoRoot 'data'

        $features = (Get-Content (Join-Path $dataDir 'features.json') -Raw | ConvertFrom-Json).features

        # Flatten every package entry and registry op into per-item test cases.
        $packageEntries = foreach ($feature in $features) {
            foreach ($entry in $feature.packages) {
                @{ Feature = $feature.id; Type = $entry.type; Pattern = $entry.pattern; Description = $entry.description; Remove = $entry.remove }
            }
        }
        $registryOps = foreach ($feature in $features) {
            foreach ($op in $feature.registry) {
                @{ Feature = $feature.id; Phase = $op.phase; Key = $op.key; Action = $op.action; Description = $op.description }
            }
        }
    }

    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $dataDir = Join-Path $repoRoot 'data'
        $features = (Get-Content (Join-Path $dataDir 'features.json') -Raw | ConvertFrom-Json).features
    }

    It 'features.json is valid JSON with a non-empty features list' {
        $features | Should -Not -BeNullOrEmpty
    }

    It 'every feature has an id, name and description' {
        foreach ($feature in $features) {
            $feature.id          | Should -Not -BeNullOrEmpty
            $feature.name        | Should -Not -BeNullOrEmpty
            $feature.description | Should -Not -BeNullOrEmpty
        }
    }

    It 'covers all five package types' {
        $types = $features.packages.type | Sort-Object -Unique
        foreach ($t in 'appx', 'capability', 'windowsPackage', 'edgeAppx', 'aiAppx') {
            $types | Should -Contain $t
        }
    }

    It 'contains all 219 extracted registry operations' {
        $count = ($features | ForEach-Object { $_.registry.Count } | Measure-Object -Sum).Sum
        $count | Should -Be 219
    }

    It 'keeps Recall in its own feature (disable Recall while keeping Copilot)' {
        $recall = $features | Where-Object { $_.id -eq 'recall' }
        $recall | Should -Not -BeNullOrEmpty
        # Recall's own registry ops are tagged with the 'recall' phase and live only here.
        ($features | Where-Object { $_.id -ne 'recall' }).registry.phase | Should -Not -Contain 'recall'
    }

    # The project rule: every setting the tool changes must explain itself.
    It 'every package entry has a non-empty description (<Feature>/<Type>: <Pattern>)' -ForEach $packageEntries {
        $Description | Should -Not -BeNullOrEmpty
    }

    It 'every package entry has a boolean remove flag (<Feature>/<Type>: <Pattern>)' -ForEach $packageEntries {
        $Remove | Should -BeOfType [bool]
    }

    It 'every registry op has a non-empty description (<Feature>/<Phase>: <Key>)' -ForEach $registryOps {
        $Description | Should -Not -BeNullOrEmpty
    }

    It 'registry ops are limited to add/delete actions (<Feature>/<Phase>: <Key>)' -ForEach $registryOps {
        $Action | Should -BeIn @('add', 'delete')
    }
}

Describe 'isoDebloaterScript.ps1 is data-driven' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $scriptText = Get-Content (Join-Path $repoRoot 'isoDebloaterScript.ps1') -Raw
    }

    It 'loads the external data file' {
        $scriptText | Should -Match "Import-DebloatData -Name 'features\.json'"
    }

    It 'no longer hardcodes static registry operations inline' {
        # Only dynamic ($variable) reg writes and reg load/unload may remain; the
        # literal HKLM\z* / HKLM\x* add/delete operations now live in features.json.
        $inline = [regex]::Matches($scriptText, '(?m)^\s*reg (add|delete) "HKLM\\[zx]')
        $inline.Count | Should -Be 0
    }
}
