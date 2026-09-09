<#
.SYNOPSIS
    Claude Code SessionStart hook - puts the repository's guardrails and the live
    Desktop Bridge status into context before the first prompt.

.DESCRIPTION
    Without this, the rules only load when a human remembers to say "read
    copilot-instructions.md". The brief is deliberately short: a session brief that
    costs thousands of tokens defeats its own purpose. Detail stays in the rulebook.

    Bridge status is read from the named pipe, not from the CLI - Test-BridgePipe is
    a directory listing, while 'powerbi-desktop status' spawns node and costs seconds
    at every session start.

    Fails open and silent: no brief is better than a session that will not start.
#>

$ErrorActionPreference = "Stop"

try {
    $bridge = "not checked"
    try {
        . (Join-Path $PSScriptRoot "..\PbipBridge.Common.ps1")
        $pipePids = @(Test-BridgePipe)
        $running = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)

        if ($pipePids.Count -gt 0) {
            $bridge = "up (pid $($pipePids -join ', ')) - run scripts\Test-PbipBridge.ps1 to confirm the project itself is open"
        } elseif ($running.Count -gt 0) {
            $bridge = "Power BI Desktop is running but exposes no bridge pipe - enable the preview feature 'external tool access ... through secure local APIs' and restart Desktop"
        } else {
            $bridge = "Power BI Desktop is not running - visual verification will skip until you open the project"
        }
    } catch {
        $bridge = "could not be determined"
    }

    $brief = @"
PBIP Agentic BI Starter Pack - session brief

RULEBOOK: copilot-instructions.md is the final authority for PBIP authoring. Read it
before touching any *.Report or *.SemanticModel file. AGENTS.md and CLAUDE.md are
digests of it, not replacements.

GUARDRAILS
 1. Business measures in _Measures only.
 2. SVG KPI measures in _SVG_Measures only, page-prefixed (P1_, P2_, ...).
 3. SVG backgrounds and themes in StaticResources/RegisteredResources/, registered in report.json.
 4. Follow the PBIP schema and forbidden-property rules exactly.
 5. TMDL is UTF-8 without BOM; no // comments (/// descriptions are fine).
 6. Whole numbers, thousand separators, data labels on, descending sort except time series, Jan->Dec months.
 7. SVG KPI cards use the image visual pattern (sourceType='imageData').
 8. Fake CSV data via Python (numpy + pandas), no venv.
 9. Never call a page done on JSON validity alone - verify what Desktop rendered.
10. Every measure carries a description.

WORKFLOW: write a spec in specs/ before building a new dashboard or page. Build, then
verify. A Stop hook runs the screenshot loop and blocks until the PNGs are reviewed
against .claude/skills/powerbi-visual-verify/SKILL.md. Fix budget is one round.

FIRST BUILD: if Desktop shows an error dialog and the window stays on 'Untitled', the
PBIP did not load. That is a source error, not a bridge problem, and 'continue with
errors' drops the broken visuals so the screenshots lie.

DESKTOP BRIDGE: $bridge
"@

    $payload = @{
        hookSpecificOutput = @{
            hookEventName   = "SessionStart"
            additionalContext = $brief
        }
    }
    $payload | ConvertTo-Json -Depth 5 -Compress
    exit 0

} catch {
    exit 0
}
