<#
.SYNOPSIS
    Claude Code Stop hook - runs the PBIP visual verification loop before a turn ends.

.DESCRIPTION
    Fires when Claude tries to finish. If the report/model definition changed since
    the last verified state, it validates, reloads Power BI Desktop, screenshots every
    page, and BLOCKS the turn so Claude must read and review the PNGs.

    Fix budget is one round: at most two blocks per session-turn sequence
    (round 1 = review + fix, round 2 = confirmation + report).

    FAIL OPEN is the cardinal rule. Any failure - missing CLI, dead bridge, closed
    Desktop, unexpected exception - must exit 0. A Stop hook that blocks on a broken
    bridge makes the session impossible to end.
#>

$ErrorActionPreference = "Stop"

# Everything below is best-effort. Nothing here may prevent a turn from ending.
try {
    $raw = [Console]::In.ReadToEnd()
    $hookInput = $null
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        try { $hookInput = $raw | ConvertFrom-Json } catch { $hookInput = $null }
    }

    $sessionId = "default"
    if ($hookInput -and $hookInput.PSObject.Properties.Name -contains 'session_id' -and $hookInput.session_id) {
        $sessionId = $hookInput.session_id
    }
    # Belt and braces against a runaway loop if the harness signals re-entry.
    $stopHookActive = $false
    if ($hookInput -and $hookInput.PSObject.Properties.Name -contains 'stop_hook_active') {
        $stopHookActive = [bool]$hookInput.stop_hook_active
    }

    . (Join-Path $PSScriptRoot "..\PbipBridge.Common.ps1")
    . (Join-Path $PSScriptRoot "..\Invoke-PbipVerify.ps1")

    $project = Get-PbipProject
    $fingerprint = Get-PbipDefinitionHash -Project $project

    $stateDir = Join-Path $project.RepoRoot ".claude\.pbip-state"
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }
    $safeSession = ($sessionId -replace '[^A-Za-z0-9_\-]', '_')
    $statePath = Join-Path $stateDir "$safeSession.json"

    $state = [PSCustomObject]@{ lastHash = ""; lastModelHash = ""; blockCount = 0 }
    if (Test-Path -LiteralPath $statePath) {
        try {
            $loaded = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            if ($loaded) { $state = $loaded }
        } catch { }
    }
    foreach ($p in @('lastHash', 'lastModelHash', 'blockCount')) {
        if ($state.PSObject.Properties.Name -notcontains $p) {
            $default = if ($p -eq 'blockCount') { 0 } else { "" }
            Add-Member -InputObject $state -NotePropertyName $p -NotePropertyValue $default -Force
        }
    }

    # --- Gate 1: nothing changed -> never touch Power BI -------------------------
    # This also makes the "reviewed, nothing to fix" path free: Claude edits nothing,
    # the hash is unchanged, the turn simply ends.
    if ($fingerprint.Hash -eq $state.lastHash) {
        exit 0
    }

    # --- Gate 2: fix budget spent ------------------------------------------------
    if ([int]$state.blockCount -ge 2 -or ($stopHookActive -and [int]$state.blockCount -ge 1)) {
        $state.lastHash = $fingerprint.Hash
        $state.lastModelHash = $fingerprint.ModelHash
        $state | ConvertTo-Json -Compress | Set-Content -LiteralPath $statePath -Encoding UTF8
        exit 0
    }

    $mode = if ([int]$state.blockCount -eq 0) { "Review" } else { "Confirm" }
    $tmdlChanged = ($state.lastModelHash -ne "" -and $fingerprint.ModelHash -ne $state.lastModelHash)

    $result = Invoke-PbipVerify -Mode $mode -TmdlChanged:$tmdlChanged -RepoRoot $project.RepoRoot

    # --- Fail open on anything the bridge could not do ---------------------------
    if ($result.Status -eq "bridge_unavailable" -or $result.Status -eq "error") {
        $state.lastHash = $fingerprint.Hash
        $state.lastModelHash = $fingerprint.ModelHash
        $state | ConvertTo-Json -Compress | Set-Content -LiteralPath $statePath -Encoding UTF8

        $payload = @{
            systemMessage = "PBIP visual verification skipped: $($result.Message)"
        }
        $payload | ConvertTo-Json -Depth 5 -Compress
        exit 0
    }

    # --- Block: validation failure, or screenshots ready for review --------------
    $reason = Format-PbipVerifyReport -Result $result -Mode $mode

    $state.lastHash = $fingerprint.Hash
    $state.lastModelHash = $fingerprint.ModelHash
    $state.blockCount = [int]$state.blockCount + 1
    $state | ConvertTo-Json -Compress | Set-Content -LiteralPath $statePath -Encoding UTF8

    $payload = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision      = "block"
            reason        = $reason
        }
    }
    $payload | ConvertTo-Json -Depth 5 -Compress
    exit 0

} catch {
    # Last-resort fail-open. Report, never block.
    $msg = "PBIP visual verification hook error (verification skipped): $($_.Exception.Message)"
    try {
        @{ systemMessage = $msg } | ConvertTo-Json -Compress
    } catch {
        # If even JSON encoding fails, stay silent rather than emit garbage.
    }
    exit 0
}
