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
    [switch]$SkipValidation,
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
        [switch]$Dismiss,
        [ValidateSet("None", "Dismiss", "Continue", "CloseDesktop")][string]$Action = "None",
        [int]$ProcessId = 0,
        [switch]$SkipCapture
    )

    $out = [PSCustomObject]@{
        Report = $null; Found = $false; Dismissed = $false; Pid = $null
        Kind = $null; RootCauses = @(); IssueCount = 0; ActionTaken = $null
        ScreenshotPath = $null; DetailsPath = $null
    }

    try {
        $script = Join-Path $PSScriptRoot "Get-PbipLoadError.ps1"
        if (-not (Test-Path -LiteralPath $script)) { return $out }

        $act = $Action
        if ($Dismiss -and $act -eq "None") { $act = "Dismiss" }

        $cliArgs = @("-Json", "-Action", $act)
        if ($ProcessId -gt 0) {
            $cliArgs += @("-ProcessId", "$ProcessId")
        } else {
            # No specific instance: never search one holding a different project.
            $foreign = @(Get-PbiForeignInstancePids -Project $Project)
            if ($foreign.Count -gt 0) { $cliArgs += @("-ExcludeProcessId", ($foreign -join ",")) }
        }
        if ($SkipCapture) { $cliArgs += "-SkipCapture" }
        if ($OutputDir) { $cliArgs += @("-OutputDir", $OutputDir) }

        $res = Invoke-PsScript -ScriptPath $script -ScriptArgs $cliArgs -TimeoutSeconds 90
        if (-not $res.Json) { return $out }

        $d = $res.Json
        if (-not $d.Found) { return $out }

        $out.Found = $true
        $out.Dismissed = [bool]$d.Dismissed
        if ($d.Pid) { $out.Pid = [int]$d.Pid }
        $out.Kind = $d.Kind
        $out.ActionTaken = $d.ActionTaken
        $out.ScreenshotPath = $d.ScreenshotPath
        $out.DetailsPath = $d.DetailsPath
        if ($d.RootCauses) { $out.RootCauses = @($d.RootCauses) }
        if ($d.IssueCount) { $out.IssueCount = [int]$d.IssueCount }
        if ($SkipCapture) { return $out }

        $sb = New-Object System.Text.StringBuilder
        $null = $sb.AppendLine("POWER BI DESKTOP REJECTED THE PROJECT - dialog captured")
        $null = $sb.AppendLine("")
        if ($d.Heading) { $null = $sb.AppendLine("Dialog: $($d.Heading)") }
        if ($out.RootCauses.Count -gt 0) {
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("Root cause(s) - $($out.IssueCount) dialog issue(s) collapsed to $($out.RootCauses.Count):")
            foreach ($rc in $out.RootCauses) { $null = $sb.AppendLine("  - $rc") }
        } elseif ($d.Text) {
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine($d.Text)
        }
        if ($out.RootCauses.Count -eq 0 -and $d.ErrorMessage -and $d.ErrorMessage -ne $d.Text) {
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

function Format-PbirValidationFailure {
    <#
      Turns a failed powerbi-report-author run into something an agent can act on.

      The validator reports a single malformed expression as one "must have required
      property" error per expression kind the schema accepts - 49 errors, each with a
      full absolute path, for one typo'd key. Passed through raw, that is tens of
      kilobytes in which the actual defect is buried. So: lead with the root causes
      from the semantic checks (which name the bad key and suggest the right one),
      then summarise the validator's errors by file and JSON pointer.
    #>
    param([Parameter(Mandatory = $true)]$Project, [Parameter(Mandatory = $true)]$Validation)

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("PBIR validation failed ($($Validation.ErrorCount) error(s)) - Desktop was NOT reloaded.")

    $rootCauses = @()
    try {
        . (Join-Path $PSScriptRoot "Test-PbipSemantics.ps1")
        $sem = Test-PbipSemantics -Project $Project
        $rootCauses = @($sem.Errors)
    } catch { }

    if ($rootCauses.Count -gt 0) {
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("Root cause(s):")
        foreach ($rc in $rootCauses) { $null = $sb.AppendLine("  - $rc") }
    }

    $groups = [ordered]@{}
    $parsed = $false
    try {
        $j = $Validation.Detail | ConvertFrom-Json -ErrorAction Stop
        $diag = $j.data.diagnostics
        $reportDir = [System.IO.Path]::GetFullPath($Project.ReportDir).TrimEnd('\')
        foreach ($code in @($diag.PSObject.Properties.Name)) {
            foreach ($item in @($diag.$code.items)) {
                $file = [string]$item.file
                try {
                    $full = [System.IO.Path]::GetFullPath($file)
                    if ($full.StartsWith($reportDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $file = $full.Substring($reportDir.Length).TrimStart('\').Replace('\', '/')
                    }
                } catch { }
                $key = "$code|$file|$($item.path)"
                if (-not $groups.Contains($key)) {
                    $groups[$key] = [PSCustomObject]@{ Code = $code; File = $file; Path = [string]$item.path; Count = 0; First = [string]$item.message }
                }
                $groups[$key].Count++
            }
        }
        $parsed = $true
    } catch { }

    $null = $sb.AppendLine("")
    if ($parsed -and $groups.Count -gt 0) {
        $null = $sb.AppendLine("Validator errors by location:")
        foreach ($g in $groups.Values) {
            $first = $g.First
            $colon = $first.LastIndexOf(': ')
            if ($colon -gt 0) { $first = $first.Substring(0, $colon) }
            if ($first.Length -gt 160) { $first = $first.Substring(0, 160) + "..." }
            $null = $sb.AppendLine("  - [$($g.Code)] $($g.File) $($g.Path) - $($g.Count) error(s), e.g. $first")
        }
        if ($rootCauses.Count -gt 0) {
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("Many errors at a single pointer almost always mean ONE malformed expression: the")
            $null = $sb.AppendLine("schema lists every expression kind it would have accepted. Fix the root cause first.")
        }
    } else {
        $detail = [string]$Validation.Detail
        if ($detail.Length -gt 2000) { $detail = $detail.Substring(0, 2000) + " ... (truncated)" }
        $null = $sb.AppendLine($detail)
    }

    return $sb.ToString().TrimEnd()
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
        [switch]$SkipValidation,
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
    # -SkipValidation exists to reproduce Desktop-side failures on purpose: it lets a
    # definition these gates would reject reach Desktop, so the dialog handling in
    # step 4b can be exercised. Never pass it from the Stop hook.
    if ($SkipValidation) {
        $warnings.Add("Validation was skipped (-SkipValidation). This run exists to reproduce a Desktop-side failure; do not treat its outcome as verification.")
    }
    $val = [PSCustomObject]@{ Ok = $true; NotInstalled = $false; ErrorCount = 0; Detail = "" }
    if (-not $SkipValidation) { $val = Test-PbirValid -Project $project }
    if ($val.NotInstalled) {
        return [PSCustomObject]@{
            Status = "bridge_unavailable"; Ok = $false; Message = $val.Detail
            Screenshots = @(); Warnings = @(); OutputDir = $OutputDir; Pid = $null
        }
    }
    if (-not $val.Ok) {
        return [PSCustomObject]@{
            Status = "validation_failed"; Ok = $false
            Message = (Format-PbirValidationFailure -Project $project -Validation $val)
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
    if (-not $SkipValidation) {
    try {
        . (Join-Path $PSScriptRoot "Test-PbipSemantics.ps1")
        $sem = Test-PbipSemantics -Project $project
        if (-not $sem.Ok) {
            $detail = ($sem.Errors | ForEach-Object { "  - $_" }) -join "`n"
            return [PSCustomObject]@{
                Status = "validation_failed"; Ok = $false
                Message = "Semantic validation failed ($($sem.Errors.Count) error(s)) - Desktop was NOT reloaded.`nThese are the failures Power BI Desktop reports as a dialog on load or reload:`n$detail"
                Screenshots = @(); Warnings = @(); OutputDir = $OutputDir; Pid = $null
            }
        }
        foreach ($w in $sem.Warnings) { $warnings.Add($w) }
    } catch {
        # Never let the semantic gate itself break the loop.
        $warnings.Add("Semantic validation could not run: $($_.Exception.Message)")
    }
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

    # --- 4b. Do not trust the reload's exit code --------------------------------
    # "reload" returns exit 0 and "success": true even when Desktop rejects the
    # reloaded definition and raises a dialog. The real signal is the window: a
    # modal disables it.
    #
    #   report_issues     "Your report has issues that could not be resolved".
    #                     Capture it, press Continue (again if it re-raises), take
    #                     the screenshots anyway and mark them UNTRUSTED - Continue
    #                     silently drops whatever failed validation, so a broken
    #                     filter stops filtering and the page still looks normal.
    #                     The instance is closed afterwards so that degraded report
    #                     cannot be edited and saved over the source.
    #   definition_error  "Issues were found". Nothing loaded; handled like
    #                     load_failed - capture, close, and the next round reopens.
    $issuesDialog = $null
    if (Wait-PbiShellBlocked -ProcessId $targetPid -Seconds 6) {
        $dlg = Get-PbipDialogReport -Project $project -OutputDir $OutputDir -ProcessId $targetPid -Action None

        if ($dlg.Found -and $dlg.Kind -eq "report_issues") {
            $issuesDialog = $dlg
            for ($press = 0; $press -lt 3; $press++) {
                $c = Get-PbipDialogReport -Project $project -ProcessId $targetPid -Action Continue -SkipCapture
                if (-not $c.Found) { break }
                Start-Sleep -Seconds 3
                if (-not (Test-PbiShellBlocked -ProcessId $targetPid)) { break }
            }
        } elseif ($dlg.Found) {
            $info = Get-PbiInstanceInfo -ProcessId $targetPid
            $closed = $false
            if ($info.HasUnsavedChanges -ne $true) {
                $null = Get-PbipDialogReport -Project $project -ProcessId $targetPid -Action Dismiss -SkipCapture
                $closed = Close-PbipInstance -ProcessId $targetPid
            }
            $tail = "The reload was rejected. The instance was closed; after fixing the source, the next round reopens the project on its own."
            if (-not $closed) {
                $tail = "The reload was rejected. The instance was NOT closed because Desktop reports unsaved changes in it - close it yourself, then the next round reopens the project."
            }
            return [PSCustomObject]@{
                Status = "load_failed"; Ok = $false
                Message = ($dlg.Report + "`n`n" + $tail)
                Screenshots = @(); Warnings = @($warnings); OutputDir = $OutputDir; Pid = $targetPid
            }
        } else {
            $warnings.Add("Power BI Desktop's window was blocked by a modal after reload, but no error dialog was recognised. Screenshots may not reflect the reloaded definition.")
        }
    }

    if (-not $issuesDialog -and $reload.ExitCode -ne 0) {
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

    if ($shot.ExitCode -ne 0 -and $issuesDialog) {
        # The issues are the finding; a missing screenshot must not demote them to a
        # fail-open skip.
        $warnings.Add("screenshot-all failed after pressing Continue, so there are no screenshots for this round: " + (($shot.Stdout + " " + $shot.Stderr).Trim()))
    } elseif ($shot.ExitCode -ne 0) {
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

    if ($issuesDialog) {
        # Close the instance holding the degraded report, unless it has unsaved work.
        $info = Get-PbiInstanceInfo -ProcessId $targetPid
        $closed = $false
        if ($info.HasUnsavedChanges -ne $true) {
            if (Test-PbiShellBlocked -ProcessId $targetPid) {
                $null = Get-PbipDialogReport -Project $project -ProcessId $targetPid -Action CloseDesktop -SkipCapture
                $closed = Wait-ProcessExit -ProcessId $targetPid -TimeoutSeconds 20
            }
            if (-not $closed) { $closed = Close-PbipInstance -ProcessId $targetPid }
        }

        return [PSCustomObject]@{
            Status         = "loaded_with_issues"
            Ok             = $false
            Mode           = $Mode
            Message        = "Power BI Desktop reported $($issuesDialog.IssueCount) issue(s) in the report definition and loaded it only after Continue."
            RootCauses     = @($issuesDialog.RootCauses)
            DialogImage    = $issuesDialog.ScreenshotPath
            DetailsPath    = $issuesDialog.DetailsPath
            InstanceClosed = $closed
            Screenshots    = @($shots | Sort-Object Ordinal)
            Warnings       = @($warnings)
            OutputDir      = $OutputDir
            Pid            = $targetPid
            Project        = $project
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

    if ($Result.Status -eq "loaded_with_issues") {
        $null = $sb.AppendLine("POWER BI DESKTOP REJECTED PART OF THE REPORT - SCREENSHOTS BELOW ARE UNTRUSTED")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine($Result.Message)
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("Root cause(s):")
        foreach ($rc in $Result.RootCauses) { $null = $sb.AppendLine("  - $rc") }
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("Why the screenshots are untrusted: Continue loads the report with every object")
        $null = $sb.AppendLine("that failed validation silently dropped. A broken filter simply stops filtering,")
        $null = $sb.AppendLine("and the page still looks normal - so these images show a report that is NOT the")
        $null = $sb.AppendLine("one in source. Use them only to see what went missing.")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("Pages captured (UNTRUSTED):")
        foreach ($s in $Result.Screenshots) {
            if ($s.Path) {
                $null = $sb.AppendLine(("  [UNTRUSTED] [{0}] {1}" -f $s.Ordinal, $s.DisplayName))
                $null = $sb.AppendLine(("        {0}" -f $s.Path))
            }
        }
        if ($Result.DialogImage) { $null = $sb.AppendLine(""); $null = $sb.AppendLine("Dialog image:     $($Result.DialogImage)") }
        if ($Result.DetailsPath) { $null = $sb.AppendLine("Full issue list:  $($Result.DetailsPath)") }
        $null = $sb.AppendLine("")
        if ($Result.InstanceClosed) {
            $null = $sb.AppendLine("The Desktop instance was closed so the degraded report cannot be edited and saved")
            $null = $sb.AppendLine("over the source. The next round reopens the project after the fix.")
        } else {
            $null = $sb.AppendLine("The Desktop instance was NOT closed (it reports unsaved changes). Do not save it -")
            $null = $sb.AppendLine("that would write the degraded report over the source. Close it without saving.")
        }
        if ($Result.Warnings.Count -gt 0) {
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("Warnings:")
            foreach ($w in $Result.Warnings) { $null = $sb.AppendLine("  ! $w") }
        }
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("ACTION: fix the root cause(s) above in the PBIR source, then end your turn.")
        $null = $sb.AppendLine("Do not judge page correctness from these screenshots.")
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
    $result = Invoke-PbipVerify -Mode $Mode -OutputDir $OutputDir -RepoRoot $RepoRoot -Scale $Scale -SettleMs $SettleMs -LoadTimeoutSeconds $LoadTimeoutSeconds -NoReopen:$NoReopen -SkipValidation:$SkipValidation -TmdlChanged:$TmdlChanged
    Write-Host (Format-PbipVerifyReport -Result $result -Mode $Mode)
    if ($result.Ok) { exit 0 } else { exit 1 }
}
