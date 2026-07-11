# Fetch from this fork over GitHub-served TLS so we never execute upstream-author-controlled content.
$scriptUrl = "https://raw.githubusercontent.com/DevSecNinja/windows-iso-debloater/main/isoDebloaterScript.ps1"
$autounattendXmlUrl = "https://raw.githubusercontent.com/DevSecNinja/windows-iso-debloater/main/autounattend.xml"
$dataBaseUrl = "https://raw.githubusercontent.com/DevSecNinja/windows-iso-debloater/main/data"

# Fail closed on any error so a failed/partial download is never run elevated below.
$ErrorActionPreference = "Stop"
# Enforce TLS 1.2 so the download can't be silently downgraded on older hosts.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$scriptDirectory = "$env:SystemDrive\scriptdir"

if (-not (Test-Path -Path $scriptDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $scriptDirectory > $null 2>&1
}

$scriptPath = Join-Path -Path $scriptDirectory -ChildPath "isoDebloaterScript.ps1"
$XmlPath = Join-Path -Path $scriptDirectory -ChildPath "autounattend.xml"

Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath -UseBasicParsing
Invoke-WebRequest -Uri $autounattendXmlUrl -OutFile $XmlPath -UseBasicParsing

# Fetch the debloat data file (packages + registry tweaks grouped by capability).
# The script can also download this itself when missing, but pre-fetching keeps
# everything local.
$dataDirectory = Join-Path -Path $scriptDirectory -ChildPath "data"
if (-not (Test-Path -Path $dataDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $dataDirectory > $null 2>&1
}
foreach ($dataFile in @("features.json")) {
    Invoke-WebRequest -Uri "$dataBaseUrl/$dataFile" -OutFile (Join-Path -Path $dataDirectory -ChildPath $dataFile) -UseBasicParsing
}

# Never launch a missing/empty script with ExecutionPolicy Bypass.
if (-not (Test-Path -Path $scriptPath) -or (Get-Item $scriptPath).Length -eq 0) {
    throw "Downloaded isoDebloaterScript.ps1 is missing or empty; aborting."
}

function Test-WindowsTerminalInstalled {
    $terminalPath = "$env:LocalAppData\Microsoft\WindowsApps\wt.exe"
    return (Test-Path -Path $terminalPath)
}

if (Test-WindowsTerminalInstalled) {
    Start-Process -FilePath "$env:LocalAppData\Microsoft\WindowsApps\wt.exe" -ArgumentList "powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
} else {
    Start-Process -FilePath "PowerShell" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
}
Start-Sleep -Milliseconds 200
Exit
