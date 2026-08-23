<#
.SYNOPSIS
    Validate -> reload -> screenshot every page of the PBIP project.

.DESCRIPTION
    The engine behind the visual verification loop. Runnable by hand for debugging,
    and dot-sourced by scripts/hooks/pbip-stop-hook.ps1 so the hook stays thin.

    All bridge operations are strictly serial against a single PID: the bridge runs
    one operation at a time, and overlapping calls fail with "Cancelled".

.EXAMPLE
    powershell -NoProfile -File scripts\Invoke-PbipVerify.ps1
    powershell -NoProfile -File scripts\Invoke-PbipVerify.ps1 -Mode Confirm
#>
[CmdletBinding()]
param(
    [ValidateSet("Review", "Confirm")][string]$Mode = "Review",
    [string]$OutputDir,
    [string]$RepoRoot,
    [int]$Scale = 2,
    [int]$SettleMs = 400,
    [switch]$TmdlChanged
)

. (Join-Path $PSScriptRoot "PbipBridge.Common.ps1")

function Invoke-PbipVerify {
    [CmdletBinding()]
    param(
        [ValidateSet("Review", "Confirm")][string]$Mode = "Review",
        [string]$OutputDir,
        [string]$RepoRoot,
        [int]$Scale = 2,
        [int]$SettleMs = 400,
        [switch]$TmdlChanged
    )

    $warnings = New-Object System.Collections.Generic.List[string]

    # --- 1. Discover the project -------------------------------------------------
    try {
        $project = Get-PbipProject -RepoRoot $RepoRoot
    } catch {
        return [PSCustomObject]@{
            Status = "error"; Ok = $false; Message = $_.Exception.Message
            Screenshots = @(); Warnings = @(); OutputDir = $null; Pid = $null
        }
    }

    if (-not $OutputDir) {
        $OutputDir = Join-Path $project.RepoRoot "tests\screenshots\latest"
    }

    # --- 2. Validate BEFORE touching Desktop ------------------------------------
    # Invalid PBIR is rejected by reload anyway; failing here saves a Desktop cycle
    # and gives a far better error than the bridge does.
    $val = Test-PbirValid -Project $project
    if ($val.NotInstalled) {
        return [PSCustomObject]@{
            Status = "bridge_unavailable"; Ok = $false; Message = $val.Detail
            Screenshots = @(); Warnings = @(); OutputDir = $OutputDir; Pid = $null
        }
    }
    if (-not $val.Ok) {
        return [PSCustomObject]@{
            Status = "validation_failed"; Ok = $false
            Message = "PBIR validation failed ($($val.ErrorCount) error(s)) - Desktop was NOT reloaded.`n$($val.Detail)"
            Screenshots = @(); Warnings = @(); OutputDir = $OutputDir; Pid = $null
        }
    }

    # --- 3. Find the instance holding THIS project ------------------------------
    $inst = Get-BridgeInstance -Project $project -WaitSeconds 5
    if (-not $inst.Ok) {
        return [PSCustomObject]@{
            Status = "bridge_unavailable"; Ok = $false; Message = $inst.Reason
            Screenshots = @(); Warnings = @(); OutputDir = $OutputDir; Pid = $null
        }
    }
    $targetPid = $inst.Pid

    # --- 4. Reload (serial) ------------------------------------------------------
    $reload = Invoke-BridgeCli -Exe "powerbi-desktop" -CliArgs @("reload", "--pid", "$targetPid", "--wait-seconds", "90") -TimeoutSeconds 180
    if ($reload.ExitCode -ne 0) {
        $detail = ($reload.Stdout + "`n" + $reload.Stderr).Trim()
        return [PSCustomObject]@{
            Status = "bridge_unavailable"; Ok = $false
            Message = "Reload failed on pid ${targetPid}:`n$detail"
            Screenshots = @(); Warnings = @(); OutputDir = $OutputDir; Pid = $targetPid
        }
    }

    # --- 5. Clear stale PNGs, then capture (serial, same PID) -------------------
    # Without the clear, a page deleted since the last run leaves an orphan PNG and
    # the agent reviews a page that no longer exists.
    if (Test-Path -LiteralPath $OutputDir) {
        Get-ChildItem -LiteralPath $OutputDir -Filter "*.png" -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $shot = Invoke-BridgeCli -Exe "powerbi-desktop" -CliArgs @(
        "screenshot-all", "--pid", "$targetPid",
        "--output-dir", $OutputDir,
        "--scale", "$Scale",
        "--settle", "$SettleMs",
        "--wait-seconds", "90"
    ) -TimeoutSeconds 300

    if ($shot.ExitCode -ne 0) {
        $detail = ($shot.Stdout + "`n" + $shot.Stderr).Trim()
        return [PSCustomObject]@{
            Status = "bridge_unavailable"; Ok = $false
            Message = "screenshot-all failed on pid ${targetPid}:`n$detail"
            Screenshots = @(); Warnings = @(); OutputDir = $OutputDir; Pid = $targetPid
        }
    }

    # --- 6. Join PNGs to page display names -------------------------------------
    $manifest = Get-PbipPageManifest -Project $project
    $pngs = @(Get-ChildItem -LiteralPath $OutputDir -Filter "*.png" -File -ErrorAction SilentlyContinue | Sort-Object Name)

    $shots = New-Object System.Collections.Generic.List[object]
    $claimed = New-Object System.Collections.Generic.List[string]

    # screenshot-all names PNGs after the page DISPLAY NAME ("Page 1.png"), not the
    # page id. Match on display name first, then fall back to the id in case the CLI
    # changes convention between preview versions.
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    function ConvertTo-SafeName {
        param([string]$Value)
        if (-not $Value) { return "" }
        $out = $Value
        foreach ($ch in $invalid) { $out = $out.Replace([string]$ch, "_") }
        return $out.Trim()
    }

    foreach ($page in ($manifest | Sort-Object Ordinal)) {
        $match = $null
        $safeDisplay = ConvertTo-SafeName -Value $page.DisplayName
        foreach ($candidate in @($page.DisplayName, $safeDisplay, $page.Name)) {
            if (-not $candidate) { continue }
            foreach ($png in $pngs) {
                if ($claimed.Contains($png.FullName)) { continue }
                if ($png.BaseName -eq $candidate) { $match = $png; break }
            }
            if ($match) { break }
        }
        if (-not $match) {
            # Last resort: id appearing anywhere in the filename.
            foreach ($png in $pngs) {
                if ($claimed.Contains($png.FullName)) { continue }
                if ($png.BaseName -like "*$($page.Name)*") { $match = $png; break }
            }
        }
        if ($match) { $claimed.Add($match.FullName) | Out-Null }
        $shots.Add([PSCustomObject]@{
            PageId      = $page.Name
            DisplayName = $page.DisplayName
            Ordinal     = $page.Ordinal
            VisualCount = $page.VisualCount
            Path        = $(if ($match) { $match.FullName } else { $null })
        })
    }

    # PNGs the manifest did not account for - surface rather than silently drop.
    foreach ($png in $pngs) {
        if (-not $claimed.Contains($png.FullName)) {
            $shots.Add([PSCustomObject]@{
                PageId = "(unmatched)"; DisplayName = $png.BaseName; Ordinal = 999
                VisualCount = $null; Path = $png.FullName
            })
        }
    }

    $missing = @($shots | Where-Object { -not $_.Path })
    if ($missing.Count -gt 0) {
        $warnings.Add("No PNG captured for: " + (($missing | ForEach-Object { "$($_.DisplayName) [$($_.PageId)]" }) -join ", "))
    }

    # --- 7. Caveat warnings ------------------------------------------------------
    if ($TmdlChanged) {
        $warnings.Add("Semantic model (TMDL) files changed. 'reload' is report-definition oriented - new or edited measures may NOT be reflected in these screenshots. If a visual shows stale or missing measure values, close and reopen: powerbi-desktop open `"$($project.PbipPath)`"")
    }

    $themeDir = Join-Path $project.ReportDir "StaticResources\RegisteredResources"
    if (Test-Path -LiteralPath $themeDir) {
        $recentThemes = @(Get-ChildItem -LiteralPath $themeDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddMinutes(-10) })
        if ($recentThemes.Count -gt 0) {
            $warnings.Add("Theme JSON changed recently (" + (($recentThemes | ForEach-Object { $_.Name }) -join ", ") + "). Power BI Desktop caches themes: reload alone shows STALE colors. Rename the theme file with a new suffix and update its report.json registration, or close and reopen Desktop.")
        }
    }

    return [PSCustomObject]@{
        Status      = "verified"
        Ok          = $true
        Mode        = $Mode
        Message     = "Captured $($pngs.Count) page screenshot(s) from pid $targetPid."
        Screenshots = @($shots | Sort-Object Ordinal)
        Warnings    = @($warnings)
        OutputDir   = $OutputDir
        Pid         = $targetPid
        Project     = $project
    }
}

function Format-PbipVerifyReport {
    <#
      Renders a verify result as the text handed to the agent (hook reason) or
      printed to the console on a manual run.
    #>
    param(
        [Parameter(Mandatory = $true)]$Result,
        [ValidateSet("Review", "Confirm")][string]$Mode = "Review",
        [string]$ChecklistPath = "skills/powerbi-visual-verify/SKILL.md"
    )

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("== PBIP visual verification ($($Result.Status)) ==")

    if ($Result.Status -eq "validation_failed") {
        $null = $sb.AppendLine($Result.Message)
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("ACTION: fix the PBIR errors above. Desktop was not reloaded, so no screenshots exist for this round.")
        return $sb.ToString()
    }

    if (-not $Result.Ok) {
        $null = $sb.AppendLine($Result.Message)
        return $sb.ToString()
    }

    $null = $sb.AppendLine($Result.Message)
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("Pages captured:")
    foreach ($s in $Result.Screenshots) {
        if ($s.Path) {
            $null = $sb.AppendLine(("  [{0}] {1}  ({2} visual(s))" -f $s.Ordinal, $s.DisplayName, $s.VisualCount))
            $null = $sb.AppendLine(("        {0}" -f $s.Path))
        } else {
            $null = $sb.AppendLine(("  [{0}] {1}  -- NO SCREENSHOT CAPTURED" -f $s.Ordinal, $s.DisplayName))
        }
    }

    if ($Result.Warnings.Count -gt 0) {
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("Warnings:")
        foreach ($w in $Result.Warnings) { $null = $sb.AppendLine("  ! $w") }
    }

    $null = $sb.AppendLine("")
    if ($Mode -eq "Review") {
        $null = $sb.AppendLine("ACTION (review round):")
        $null = $sb.AppendLine("  1. Read EVERY screenshot listed above with the Read tool. Do not skip any.")
        $null = $sb.AppendLine("  2. Check each against $ChecklistPath.")
        $null = $sb.AppendLine("  3. Fix any issues you find by editing the PBIR/TMDL files, then end your turn -")
        $null = $sb.AppendLine("     verification re-runs automatically and you get confirmation screenshots.")
        $null = $sb.AppendLine("  4. If everything already looks correct, change nothing and end your turn.")
    } else {
        $null = $sb.AppendLine("ACTION (confirmation round - fix budget spent):")
        $null = $sb.AppendLine("  1. Read EVERY screenshot listed above with the Read tool.")
        $null = $sb.AppendLine("  2. Do NOT make further edits. Report to the user what the fix achieved and")
        $null = $sb.AppendLine("     list anything still wrong, naming pages by display name.")
        $null = $sb.AppendLine("  3. Then end your turn.")
    }

    return $sb.ToString()
}

# Auto-run only when executed directly, not when dot-sourced by the hook.
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-PbipVerify -Mode $Mode -OutputDir $OutputDir -RepoRoot $RepoRoot -Scale $Scale -SettleMs $SettleMs -TmdlChanged:$TmdlChanged
    Write-Host (Format-PbipVerifyReport -Result $result -Mode $Mode)
    if ($result.Ok) { exit 0 } else { exit 1 }
}
