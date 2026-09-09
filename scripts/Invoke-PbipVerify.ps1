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
    [int]$LoadTimeoutSeconds = 30,
    [switch]$NoReopen,
    [switch]$TmdlChanged
)

. (Join-Path $PSScriptRoot "PbipBridge.Common.ps1")

function Get-PbipDialogReport {
    <#
      Runs the UI Automation dialog capture in a child process (see Invoke-PsScript
      for why it must not be dot-sourced) and renders the result as text for the
      agent. Returns @{ Report; Dismissed }.

      Never throws: a capture that fails leaves the caller with the state-based
      diagnosis from Wait-PbipLoaded, which is already actionable.
    #>
    param(
        [Parameter(Mandatory = $true)]$Project,
        [string]$OutputDir,
        [switch]$Dismiss
    )

    $out = [PSCustomObject]@{ Report = $null; Found = $false; Dismissed = $false; Pid = $null }

    try {
        $script = Join-Path $PSScriptRoot "Get-PbipLoadError.ps1"
        if (-not (Test-Path -LiteralPath $script)) { return $out }

        $cliArgs = @("-Json")
        if ($Dismiss) { $cliArgs += "-Dismiss" }
        if ($OutputDir) { $cliArgs += @("-OutputDir", $OutputDir) }

        $res = Invoke-PsScript -ScriptPath $script -ScriptArgs $cliArgs -TimeoutSeconds 90
        if (-not $res.Json) { return $out }

        $d = $res.Json
        if (-not $d.Found) { return $out }

        $out.Found = $true
        $out.Dismissed = [bool]$d.Dismissed
        if ($d.Pid) { $out.Pid = [int]$d.Pid }

        $sb = New-Object System.Text.StringBuilder
        $null = $sb.AppendLine("POWER BI DESKTOP REJECTED THE PROJECT - dialog captured")
        $null = $sb.AppendLine("")
        if ($d.Heading) { $null = $sb.AppendLine("Dialog: $($d.Heading)") }
        if ($d.Text) {
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine($d.Text)
        }
        if ($d.ErrorMessage -and $d.ErrorMessage -ne $d.Text) {
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("From 'Copy details to clipboard':")
            $null = $sb.AppendLine($d.ErrorMessage)
        }
        if ($d.ScreenshotPath) { $null = $sb.AppendLine(""); $null = $sb.AppendLine("Dialog image:     $($d.ScreenshotPath)") }
        if ($d.DetailsPath) { $null = $sb.AppendLine("Full diagnostic:  $($d.DetailsPath)") }
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("ACTION: fix the object named above in the PBIR/TMDL source, then end your turn.")
        $null = $sb.AppendLine("Verification reopens the project and retries on its own. Do NOT choose 'continue")
        $null = $sb.AppendLine("with errors': it loads the report with the failing objects dropped, so every")
        $null = $sb.AppendLine("screenshot after it shows a report that is not in source.")

        $out.Report = $sb.ToString().TrimEnd()
        return $out
    } catch {
        return $out
    }
}

function Invoke-PbipVerify {
    [CmdletBinding()]
    param(
        [ValidateSet("Review", "Confirm")][string]$Mode = "Review",
        [string]$OutputDir,
        [string]$RepoRoot,
        [int]$Scale = 2,
        [int]$SettleMs = 400,
        [int]$LoadTimeoutSeconds = 30,
        [switch]$NoReopen,
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

    # --- 2b. Semantic gate ------------------------------------------------------
    # PBIR validation is report-side only, so a model that Desktop will refuse to
    # load (a measure colliding with a column, an unresolved reference) sails
    # through it. These checks are the source-side equivalent of the "Issues were
    # found" dialog, and running them here means the dialog never appears.
    #
    # Dot-sourced HERE, not at script scope, on purpose: Test-PbipSemantics.ps1 has
    # its own param block, and dot-sourcing it at the top would clobber this
    # script's $RepoRoot with $null before the bottom-of-file call reads it. By this
    # point $RepoRoot has already been consumed by Get-PbipProject above.
    try {
        . (Join-Path $PSScriptRoot "Test-PbipSemantics.ps1")
        $sem = Test-PbipSemantics -Project $project
        if (-not $sem.Ok) {
            $detail = ($sem.Errors | ForEach-Object { "  - $_" }) -join "`n"
            return [PSCustomObject]@{
                Status = "validation_failed"; Ok = $false
                Message = "Semantic validation failed ($($sem.Errors.Count) error(s)) - Desktop was NOT reloaded.`nThese are the failures Power BI Desktop reports as an 'Issues were found' dialog at load time:`n$detail"
                Screenshots = @(); Warnings = @(); OutputDir = $OutputDir; Pid = $null
            }
        }
        foreach ($w in $sem.Warnings) { $warnings.Add($w) }
    } catch {
        # Never let the semantic gate itself break the loop.
        $warnings.Add("Semantic validation could not run: $($_.Exception.Message)")
    }

    # --- 3. Find the instance holding THIS project ------------------------------
    # Waits out a slow open, then classifies the failure instead of reporting every
    # cause as the same skip. 'load_failed' means Desktop rejected the definition
    # and is sitting behind a modal - a defect to fix, not a bridge outage.
    $inst = Wait-PbipLoaded -Project $project -TimeoutSeconds $LoadTimeoutSeconds

    # Recover from a rejected definition, without leaving windows behind.
    #
    # Order: read the dialog, dismiss it, wait for that instance to go, and only
    # then open. It has to be that way round because "powerbi-desktop open" starts
    # a NEW instance rather than reusing the running one, and Desktop takes a moment
    # to exit after its error dialog is dismissed - opening into that gap leaves a
    # second window behind.
    #
    # Invoke-PbipReopen holds the contract that the running-instance count returns
    # to its starting value if the reopen fails.
    $reopenable = @("load_failed", "not_running")

    if (-not $inst.Ok -and $reopenable -contains $inst.Status) {
        $dialog = [PSCustomObject]@{ Report = $null; Found = $false; Dismissed = $false; Pid = $null }
        if ($inst.Status -eq "load_failed") {
            # Dismiss unconditionally here: the modal blocks Desktop's own File >
            # Open, so it has to go before any reopen can work. The message has
            # already been captured by this point.
            $dialog = Get-PbipDialogReport -Project $project -OutputDir $OutputDir -Dismiss
        }

        if (-not $NoReopen) {
            # An instance that was showing a load-error dialog never loaded a
            # document, so closing it loses nothing. That is the only pre-existing
            # instance this is allowed to close.
            $spent = @()
            if ($dialog.Pid) { $spent += [int]$dialog.Pid }

            $re = Invoke-PbipReopen -Project $project -TimeoutSeconds $LoadTimeoutSeconds -ClosePids $spent

            if ($re.Ok) {
                $inst = [PSCustomObject]@{
                    Ok = $true; Pid = $re.Pid; Status = "loaded"; Reason = $null; ElapsedSeconds = 0
                }
                if ($re.Status -eq "opened") {
                    $warnings.Add("Power BI Desktop had rejected the project; it was reopened automatically after the fix and loaded cleanly.")
                }
            } else {
                # Failed again. Capture the current dialog, then hand back exactly
                # the instance count we started with.
                if ($re.Status -eq "load_failed") {
                    $dialog = Get-PbipDialogReport -Project $project -OutputDir $OutputDir -Dismiss
                }
                if ($re.StartedPid) { $null = Close-PbipInstance -ProcessId $re.StartedPid }

                $msg = $re.Reason
                if ($dialog.Report) {
                    $msg = $dialog.Report + "`n`n" + "Reopened automatically after capturing this; it failed to load the same way. Fix the source above - the next round reopens and retries on its own."
                }
                return [PSCustomObject]@{
                    Status = "load_failed"; Ok = $false; Message = $msg
                    Screenshots = @(); Warnings = @($warnings); OutputDir = $OutputDir; Pid = $null
                }
            }
        } elseif (-not $inst.Ok) {
            $msg = $inst.Reason
            if ($dialog.Report) {
                $msg = $dialog.Report + "`n`n" + "Reopen is disabled (-NoReopen). After fixing, reopen with: powerbi-desktop open `"$($project.PbipPath)`""
            }
            return [PSCustomObject]@{
                Status = "load_failed"; Ok = $false; Message = $msg
                Screenshots = @(); Warnings = @($warnings); OutputDir = $OutputDir; Pid = $null
            }
        }
    }

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
        [string]$ChecklistPath = ".claude/skills/powerbi-visual-verify/SKILL.md"
    )

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("== PBIP visual verification ($($Result.Status)) ==")

    if ($Result.Status -eq "load_failed") {
        $null = $sb.AppendLine($Result.Message)
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("No screenshots exist for this round - the project never opened.")
        return $sb.ToString()
    }

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
    $result = Invoke-PbipVerify -Mode $Mode -OutputDir $OutputDir -RepoRoot $RepoRoot -Scale $Scale -SettleMs $SettleMs -LoadTimeoutSeconds $LoadTimeoutSeconds -NoReopen:$NoReopen -TmdlChanged:$TmdlChanged
    Write-Host (Format-PbipVerifyReport -Result $result -Mode $Mode)
    if ($result.Ok) { exit 0 } else { exit 1 }
}
