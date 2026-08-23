<#
.SYNOPSIS
    Preflight check for the Power BI Desktop Bridge verification loop.

.DESCRIPTION
    Read-only. Verifies Desktop version, bridge availability, both CLIs, and that
    a running Desktop instance actually has this project's .pbip open.
    Run this first when the loop misbehaves, or on a fresh clone of the template.

.EXAMPLE
    powershell -NoProfile -File scripts\Test-PbipBridge.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [int]$WaitSeconds = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PbipBridge.Common.ps1")

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail, [string]$Fix)
    $checks.Add([PSCustomObject]@{ Name = $Name; Ok = $Ok; Detail = $Detail; Fix = $Fix })
}

Write-Host "Power BI Desktop Bridge preflight" -ForegroundColor Cyan
Write-Host ("-" * 60)

# 1. Project discovery
$project = $null
try {
    $project = Get-PbipProject -RepoRoot $RepoRoot
    Add-Check -Name "PBIP project" -Ok $true -Detail "$($project.ProjectName) -> $($project.PbipPath)"
} catch {
    Add-Check -Name "PBIP project" -Ok $false -Detail $_.Exception.Message -Fix "Run this from inside the PBIP repo."
}

# 2. Desktop version
$ver = Get-PbiDesktopVersion
if ($null -eq $ver) {
    Add-Check -Name "Power BI Desktop" -Ok $false -Detail "PBIDesktop.exe not found" -Fix "Install Power BI Desktop $script:MinDesktopVersion or later."
} elseif ($ver -lt $script:MinDesktopVersion) {
    Add-Check -Name "Power BI Desktop" -Ok $false -Detail "$ver (too old)" -Fix "Upgrade to $script:MinDesktopVersion or later. Below that build the bridge does not exist and the preview checkbox is absent entirely."
} else {
    Add-Check -Name "Power BI Desktop" -Ok $true -Detail "$ver"
}

# 3. CLIs
foreach ($pair in @(@("powerbi-desktop", "@microsoft/powerbi-desktop-bridge-cli"), @("powerbi-report-author", "@microsoft/powerbi-report-authoring-cli"))) {
    $exe = $pair[0]; $pkg = $pair[1]
    $found = Get-Command "$exe.cmd" -ErrorAction SilentlyContinue
    if (-not $found) { $found = Get-Command $exe -ErrorAction SilentlyContinue }
    if ($found) {
        $v = Invoke-BridgeCli -Exe $exe -CliArgs @("--version") -TimeoutSeconds 30
        Add-Check -Name "CLI $exe" -Ok $true -Detail ("v" + $v.Stdout.Trim())
    } else {
        Add-Check -Name "CLI $exe" -Ok $false -Detail "not on PATH" -Fix "npm install -g $pkg@latest"
    }
}

# 4. Bridge pipe - ground truth that the server is up and the preview flag is on
$pipePids = Test-BridgePipe
if ($pipePids.Count -gt 0) {
    Add-Check -Name "Bridge pipe" -Ok $true -Detail ("pbi-desktop-bridge-" + ($pipePids -join ", "))
} else {
    $running = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) {
        Add-Check -Name "Bridge pipe" -Ok $false -Detail "no pipe; Power BI Desktop is not running" -Fix "Open the project: powerbi-desktop open `"$($project.PbipPath)`""
    } else {
        Add-Check -Name "Bridge pipe" -Ok $false -Detail "Desktop is running but exposes no bridge pipe" -Fix "File > Options and settings > Options > Preview features > enable 'Enable external tool access to Power BI Desktop through secure local APIs', then restart Power BI Desktop."
    }
}

# 5. An instance with THIS project open
if ($project) {
    $inst = Get-BridgeInstance -Project $project -WaitSeconds $WaitSeconds
    if ($inst.Ok) {
        Add-Check -Name "Bridge instance" -Ok $true -Detail "pid $($inst.Pid) has $($project.ProjectName).pbip open"
    } else {
        Add-Check -Name "Bridge instance" -Ok $false -Detail $inst.Reason -Fix "An idle 'Untitled' window connects but fails every reload/screenshot with REPORT_DIR_REQUIRED - the project itself must be open."
    }
}

# 6. PBIR validity (offline schema skip keeps preflight fast and network-independent)
if ($project) {
    $val = Test-PbirValid -Project $project -NoSchema
    if ($val.NotInstalled) {
        Add-Check -Name "PBIR validation" -Ok $false -Detail $val.Detail -Fix "npm install -g @microsoft/powerbi-report-authoring-cli@latest"
    } elseif ($val.Ok) {
        Add-Check -Name "PBIR validation" -Ok $true -Detail "clean ($($val.WarningCount) warning(s))"
    } else {
        Add-Check -Name "PBIR validation" -Ok $false -Detail $val.Detail -Fix "Fix the reported PBIR errors; reload is refused while the definition is invalid."
    }
}

Write-Host ""
$failed = 0
foreach ($c in $checks) {
    if ($c.Ok) {
        Write-Host ("  [ OK ] {0,-20} {1}" -f $c.Name, $c.Detail) -ForegroundColor Green
    } else {
        $failed++
        Write-Host ("  [FAIL] {0,-20} {1}" -f $c.Name, $c.Detail) -ForegroundColor Red
        if ($c.Fix) { Write-Host ("         -> {0}" -f $c.Fix) -ForegroundColor Yellow }
    }
}

Write-Host ""
if ($failed -eq 0) {
    Write-Host "All checks passed. The verification loop is ready." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$failed check(s) failed." -ForegroundColor Red
    exit 1
}
