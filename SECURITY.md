# Security Policy

## Reporting a Vulnerability

Please **do not** open a public issue for security vulnerabilities.

Instead, report them privately through GitHub Security Advisories:

1. Go to the **Security** tab of this repository.
2. Click **Report a vulnerability** (Private vulnerability reporting).
3. Provide as much detail as possible: affected file(s), a description of the
   issue, reproduction steps, and any suggested remediation.

You can also find the reporting form at:
<https://github.com/DevSecNinja/windows-iso-debloater/security/advisories/new>

We will acknowledge your report as soon as possible and keep you informed of the
remediation progress.

## Scope and considerations

This project modifies Windows installation media and runs with administrative
privileges. Please keep the following in mind:

- **Run scripts as Administrator only after reviewing them.** The debloater
  makes far-reaching changes to a Windows image.
- **Verify what you download.** Only obtain the scripts and ISOs from the
  official sources referenced in the `README.md`, and prefer released,
  checksum-/attestation-backed artifacts where available. ISOs produced by the
  `Build debloated ISO` workflow are published with a SHA256 checksum and a
  build-provenance attestation.
- **GitHub Actions are pinned to immutable commit SHAs** to reduce supply-chain
  risk. Dependency updates are managed via Renovate.

## Supported Versions

Security fixes are applied to the latest released version and the `main` branch.
