<#
.SYNOPSIS
    Claude Code PostToolUse hook - validates a single PBIP file the moment it is written.

.DESCRIPTION
    Catches the class of defect that makes Power BI Desktop refuse to open a
    first-build PBIP, at the moment it is introduced rather than three steps later
    when Desktop shows an error dialog and leaves the window on "Untitled".

      *.json / *.pbir / *.pbism / *.pbip   must parse
      *.tmdl                               no UTF-8 BOM, no // comments (guardrail 5),
                                           and no file-local semantic error - a measure
                                           colliding with a column name, or a duplicate
                                           column or measure. Those are the errors
                                           Desktop reports as an "Issues were found"
                                           dialog, and they are true regardless of what
                                           else is mid-write, so they are safe to
                                           enforce on every edit.

    Cross-file semantics (model-wide duplicates, relationship endpoints, unresolved
    references, unregistered resources) deliberately do NOT run here: a half-written
    model would trip them on every intermediate save. They run in the verify loop,
    where the model is meant to be complete.

    Scope is one file - whatever the tool just wrote, inside a *.Report or
    *.SemanticModel folder, or the .pbip itself. Deliberately does NOT call
    scripts/validate-json.ps1, which recurses the whole repository including
    Proposals/ and is far too slow to run on every edit.

    Exit 2 hands stderr back to the agent. Anything unexpected exits 0.
#>

$ErrorActionPreference = "Stop"

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $hookInput = $null
    try { $hookInput = $raw | ConvertFrom-Json } catch { exit 0 }
    if (-not $hookInput -or -not $hookInput.tool_input) { exit 0 }

    $ti = $hookInput.tool_input
    $target = $null
    foreach ($k in @('file_path', 'path')) {
        if ($ti.PSObject.Properties.Name -contains $k -and -not [string]::IsNullOrWhiteSpace($ti.$k)) {
            $target = $ti.$k; break
        }
    }
    if (-not $target) { exit 0 }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { exit 0 }

    $full = [System.IO.Path]::GetFullPath($target)
    $rel = $full.Replace('\', '/')

    # Project name is not hardcoded: this template gets renamed downstream.
    $inPbipArtifact = ($rel -match '(?i)/[^/]+\.(Report|SemanticModel)/') -or ($rel -match '(?i)\.pbip$')
    if (-not $inPbipArtifact) { exit 0 }

    $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
    $name = [System.IO.Path]::GetFileName($full)
    $problems = @()

    if ($ext -in @('.json', '.pbir', '.pbism', '.pbip')) {
        try {
            $null = Get-Content -LiteralPath $full -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $problems += "invalid JSON: $($_.Exception.Message)"
        }
    } elseif ($ext -eq '.tmdl') {
        $bytes = [System.IO.File]::ReadAllBytes($full)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $problems += "starts with a UTF-8 BOM. TMDL must be UTF-8 with no BOM (guardrail 5) - write it with Python open(f, 'w', encoding='utf-8')."
        }

        # '///' is a TMDL description line and is encouraged. '//' after a colon is a
        # URL. Everything else is an inline comment, which guardrail 5 forbids.
        $lines = [System.IO.File]::ReadAllLines($full)
        $bad = @()
        for ($i = 0; $i -lt $lines.Length; $i++) {
            if ($lines[$i] -match '(?<![:/])//(?!/)') {
                $bad += "  line $($i + 1): $($lines[$i].Trim())"
            }
        }
        if ($bad.Count -gt 0) {
            $problems += ("contains // comments, which TMDL must not carry (guardrail 5). Use /// description lines instead:`n" + ($bad -join "`n"))
        }

        # File-local semantic checks. Wrapped: an analyser fault must never turn
        # into a blocked edit.
        try {
            . (Join-Path $PSScriptRoot "..\Test-PbipSemantics.ps1")
            $semProblems = @(Test-TmdlFileLocal -FilePath $full)
            foreach ($sp in $semProblems) { $problems += $sp }
        } catch { }
    }

    if ($problems.Count -gt 0) {
        [Console]::Error.WriteLine("PBIP validation failed for $name")
        foreach ($p in $problems) { [Console]::Error.WriteLine("  - $p") }
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("Fix it now. Power BI Desktop refuses to open a project with a malformed definition, and reports the failure as an error dialog with the window stuck on 'Untitled'.")
        exit 2
    }

    exit 0

} catch {
    # Fail open, exactly as the Stop hook does.
    exit 0
}
