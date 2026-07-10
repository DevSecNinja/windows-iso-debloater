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
