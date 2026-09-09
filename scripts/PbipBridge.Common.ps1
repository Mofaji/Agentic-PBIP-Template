# PbipBridge.Common.ps1
# Shared helpers for the Power BI Desktop Bridge verification loop.
# Dot-sourced by Test-PbipBridge.ps1, Invoke-PbipVerify.ps1 and hooks/pbip-stop-hook.ps1.
# Targets Windows PowerShell 5.1 (no ternary / null-coalescing / -AsHashtable).

# Deliberately no Set-StrictMode: these helpers run inside a Stop hook, where an
# over-eager strict-mode error would turn into a skipped verification.

# Desktop Bridge shipped in the June 2026 build. Older builds have no pipe and
# no preview-features checkbox at all.
$script:MinDesktopVersion = [Version]"2.155.756.0"

function Get-RepoRoot {
    param([string]$StartPath = $PSScriptRoot)
    # scripts/ and scripts/hooks/ both resolve up to the repo root that holds the .pbip
    $dir = Get-Item -LiteralPath $StartPath
    while ($null -ne $dir) {
        if (Get-ChildItem -LiteralPath $dir.FullName -Filter "*.pbip" -File -ErrorAction SilentlyContinue) {
            return $dir.FullName
        }
        $dir = $dir.Parent
    }
    throw "Could not locate a .pbip file walking up from '$StartPath'."
}

function Get-PbipProject {
    <#
      Discovers the PBIP project without hardcoding "Template" — this repo is a
      template and gets renamed downstream.
      Returns: PbipPath, ProjectName, ReportDir, SemanticModelDir, RepoRoot
    #>
    param([string]$RepoRoot)

    if (-not $RepoRoot) { $RepoRoot = Get-RepoRoot }

    $pbipFiles = @(Get-ChildItem -LiteralPath $RepoRoot -Filter "*.pbip" -File)
    if ($pbipFiles.Count -eq 0) { throw "No .pbip file found in '$RepoRoot'." }
    if ($pbipFiles.Count -gt 1) {
        throw ("Multiple .pbip files found in '{0}': {1}. Pass -PbipPath explicitly." -f $RepoRoot, (($pbipFiles | ForEach-Object { $_.Name }) -join ", "))
    }
    $pbipFile = $pbipFiles[0]

    $pbip = Get-Content -LiteralPath $pbipFile.FullName -Raw | ConvertFrom-Json
    if (-not $pbip.artifacts -or $pbip.artifacts.Count -eq 0) {
        throw "'$($pbipFile.Name)' declares no artifacts."
    }
    $reportRel = $pbip.artifacts[0].report.path
    if ([string]::IsNullOrWhiteSpace($reportRel)) {
        throw "'$($pbipFile.Name)' artifact report path is empty."
    }

    $reportDir = (Resolve-Path -LiteralPath (Join-Path $RepoRoot $reportRel)).Path

    $semanticDir = $null
    $pbirPath = Join-Path $reportDir "definition.pbir"
    if (Test-Path -LiteralPath $pbirPath) {
        $pbir = Get-Content -LiteralPath $pbirPath -Raw | ConvertFrom-Json
        # byPath is absent for reports bound to a published dataset (byConnection)
        if ($pbir.datasetReference -and $pbir.datasetReference.PSObject.Properties.Name -contains 'byPath' -and $pbir.datasetReference.byPath) {
            $smRel = $pbir.datasetReference.byPath.path
            if (-not [string]::IsNullOrWhiteSpace($smRel)) {
                $candidate = Join-Path $reportDir $smRel
                if (Test-Path -LiteralPath $candidate) {
                    $semanticDir = (Resolve-Path -LiteralPath $candidate).Path
                }
            }
        }
    }

    return [PSCustomObject]@{
        RepoRoot         = $RepoRoot
        PbipPath         = $pbipFile.FullName
        ProjectName      = [System.IO.Path]::GetFileNameWithoutExtension($pbipFile.Name)
        ReportDir        = $reportDir
        SemanticModelDir = $semanticDir
    }
}

function Get-PbiDesktopVersion {
    # Returns [Version] of the installed Desktop, or $null when not found.
    $candidates = @(
        "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe",
        "C:\Program Files (x86)\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
    )
    $storeRoot = "C:\Program Files\WindowsApps"
    if (Test-Path -LiteralPath $storeRoot) {
        try {
            $storeExes = Get-ChildItem -LiteralPath $storeRoot -Filter "*PowerBI*" -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName "bin\PBIDesktop.exe" }
            $candidates += $storeExes
        } catch { }
    }

    $best = $null
    foreach ($exe in $candidates) {
        if (Test-Path -LiteralPath $exe) {
            try {
                $fv = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
                # FileVersion is a clean 4-part number; ProductVersion carries a git suffix.
                $parsed = [Version]($fv -replace '[^0-9\.].*$', '')
                if ($null -eq $best -or $parsed -gt $best) { $best = $parsed }
            } catch { }
        }
    }
    return $best
}

function Test-BridgePipe {
    <#
      The named pipe pbi-desktop-bridge-{pid} only exists while the bridge server
      is up, so this is ground truth for "is the preview flag on and Desktop running".
      Far cheaper than shelling out to the CLI.
    #>
    try {
        $pipes = [System.IO.Directory]::GetFiles("\\.\pipe\")
    } catch {
        return @()
    }
    $result = @()
    foreach ($p in $pipes) {
        if ($p -match 'pbi-desktop-bridge-(\d+)') { $result += [int]$Matches[1] }
    }
    return $result
}

function Invoke-BridgeCli {
    <#
      Runs a bridge/author CLI and returns @{ ExitCode; Stdout; Stderr; Json }.
      Never throws on a non-zero exit — callers decide what a failure means.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$CliArgs,
        [int]$TimeoutSeconds = 180
    )

    # The npm shims are .ps1/.cmd; resolve to the .cmd so Start-Process can run it directly.
    $cmd = Get-Command "$Exe.cmd" -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command $Exe -ErrorAction SilentlyContinue }
    if (-not $cmd) {
        return [PSCustomObject]@{ ExitCode = 127; Stdout = ""; Stderr = "$Exe is not installed or not on PATH."; Json = $null }
    }

    # Quote args containing whitespace. Without this, a repo path like
    # "...\PBIP Template\Template.Report" is split into two arguments and the CLI
    # rejects the call with commander.excessArguments.
    $quoted = @()
    foreach ($a in $CliArgs) {
        $s = [string]$a
        if ($s -match '\s' -and -not ($s.StartsWith('"') -and $s.EndsWith('"'))) {
            $quoted += '"' + ($s -replace '"', '\"') + '"'
        } else {
            $quoted += $s
        }
    }

    # System.Diagnostics.Process, not Start-Process: with -PassThru plus the timed
    # WaitForExit overload, ExitCode comes back empty, so every call looked like a
    # failure even when the CLI succeeded.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $cmd.Source
    $psi.Arguments = ($quoted -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        # Read both streams asynchronously, otherwise a full pipe buffer deadlocks
        # against WaitForExit.
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill() } catch { }
            return [PSCustomObject]@{ ExitCode = 124; Stdout = ""; Stderr = "$Exe timed out after ${TimeoutSeconds}s."; Json = $null }
        }
        # Parameterless overload flushes the async readers and settles ExitCode.
        $proc.WaitForExit()

        $stdout = $outTask.Result
        $stderr = $errTask.Result
        if ($null -eq $stdout) { $stdout = "" }
        if ($null -eq $stderr) { $stderr = "" }
        $exitCode = $proc.ExitCode

        $json = $null
        $trimmed = $stdout.Trim()
        if ($trimmed.StartsWith("{") -or $trimmed.StartsWith("[")) {
            try { $json = $trimmed | ConvertFrom-Json } catch { $json = $null }
        }

        return [PSCustomObject]@{ ExitCode = $exitCode; Stdout = $stdout; Stderr = $stderr; Json = $json }
    } catch {
        return [PSCustomObject]@{ ExitCode = 126; Stdout = ""; Stderr = "Failed to run ${Exe}: $($_.Exception.Message)"; Json = $null }
    } finally {
        if ($proc) { $proc.Dispose() }
    }
}

function Get-BridgeInstance {
    <#
      Selects the Desktop instance that actually has THIS project open.
      Picking the first connected instance is wrong: an idle "Untitled" window
      reports connected but fails every reload/screenshot with REPORT_DIR_REQUIRED.
      Returns @{ Ok; Pid; Reason; Instances }.
    #>
    param(
        [Parameter(Mandatory = $true)]$Project,
        [int]$WaitSeconds = 0
    )

    $cliArgs = @("status")
    if ($WaitSeconds -gt 0) { $cliArgs += @("--wait-seconds", "$WaitSeconds") }
    $res = Invoke-BridgeCli -Exe "powerbi-desktop" -CliArgs $cliArgs

    if ($res.ExitCode -eq 127) {
        return [PSCustomObject]@{ Ok = $false; Pid = $null; Instances = @(); Reason = $res.Stderr }
    }
    if (-not $res.Json) {
        return [PSCustomObject]@{ Ok = $false; Pid = $null; Instances = @(); Reason = "Could not parse 'powerbi-desktop status' output: $($res.Stdout)$($res.Stderr)" }
    }

    $instances = @()
    if ($res.Json.PSObject.Properties.Name -contains 'instances' -and $res.Json.instances) {
        $instances = @($res.Json.instances)
    }

    if ($instances.Count -eq 0) {
        return [PSCustomObject]@{
            Ok = $false; Pid = $null; Instances = @()
            Reason = "No Desktop Bridge instances found (status: $($res.Json.status)). Open '$($Project.PbipPath)' in Power BI Desktop, or run: powerbi-desktop open `"$($Project.PbipPath)`""
        }
    }

    # Match on the open file, comparing resolved full paths.
    $targetPbip = [System.IO.Path]::GetFullPath($Project.PbipPath)
    $targetReport = [System.IO.Path]::GetFullPath($Project.ReportDir)

    $match = $null
    foreach ($inst in $instances) {
        $names = $inst.PSObject.Properties.Name
        $filePath = $null
        foreach ($k in @('currentFilePath', 'filePath', 'path')) {
            if ($names -contains $k -and -not [string]::IsNullOrWhiteSpace($inst.$k)) { $filePath = $inst.$k; break }
        }
        $reportDir = $null
        foreach ($k in @('reportDir', 'reportDirectory')) {
            if ($names -contains $k -and -not [string]::IsNullOrWhiteSpace($inst.$k)) { $reportDir = $inst.$k; break }
        }

        $isMatch = $false
        if ($filePath) {
            try { if ([System.IO.Path]::GetFullPath($filePath) -eq $targetPbip) { $isMatch = $true } } catch { }
        }
        if (-not $isMatch -and $reportDir) {
            try { if ([System.IO.Path]::GetFullPath($reportDir).TrimEnd('\') -eq $targetReport.TrimEnd('\')) { $isMatch = $true } } catch { }
        }
        if ($isMatch) { $match = $inst; break }
    }

    if (-not $match) {
        $open = @()
        foreach ($inst in $instances) {
            $names = $inst.PSObject.Properties.Name
            $fp = "(no file open)"
            foreach ($k in @('currentFilePath', 'filePath', 'path')) {
                if ($names -contains $k -and -not [string]::IsNullOrWhiteSpace($inst.$k)) { $fp = $inst.$k; break }
            }
            $ip = "?"
            foreach ($k in @('pid', 'processId', 'processID')) {
                if ($names -contains $k -and $inst.$k) { $ip = $inst.$k; break }
            }
            $open += "  pid $ip -> $fp"
        }
        return [PSCustomObject]@{
            Ok = $false; Pid = $null; Instances = $instances
            Reason = ("No running Power BI Desktop instance has '{0}' open.`nRunning instances:`n{1}`nFix: powerbi-desktop open `"{0}`"" -f $Project.PbipPath, ($open -join "`n"))
        }
    }

    $matchPid = $null
    foreach ($k in @('pid', 'processId', 'processID')) {
        if ($match.PSObject.Properties.Name -contains $k -and $match.$k) { $matchPid = [int]$match.$k; break }
    }
    if (-not $matchPid) {
        return [PSCustomObject]@{ Ok = $false; Pid = $null; Instances = $instances; Reason = "Matched an instance for this project but could not read its process id from status output." }
    }

    return [PSCustomObject]@{ Ok = $true; Pid = $matchPid; Instances = $instances; Reason = $null }
}

function Invoke-PsScript {
    <#
      Runs a PowerShell script as a child process under a hard timeout, returning
      @{ ExitCode; Stdout; Stderr; Json }.

      Used for the UI Automation dialog capture. Two reasons it must not be
      dot-sourced instead: a UIA tree walk against a wedged Desktop can block
      indefinitely, and Get-PbipLoadError.ps1 declares $OutputDir and
      $TimeoutSeconds parameters that would overwrite the caller's variables of
      the same name.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$ScriptArgs = @(),
        [int]$TimeoutSeconds = 90
    )

    $quoted = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + $ScriptPath + '"'))
    foreach ($a in $ScriptArgs) {
        $t = [string]$a
        if ($t -match '\s' -and -not ($t.StartsWith('"') -and $t.EndsWith('"'))) {
            $quoted += '"' + ($t -replace '"', '\"') + '"'
        } else {
            $quoted += $t
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = ($quoted -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill() } catch { }
            return [PSCustomObject]@{ ExitCode = 124; Stdout = ""; Stderr = "Timed out after ${TimeoutSeconds}s."; Json = $null }
        }
        $proc.WaitForExit()

        $stdout = $outTask.Result
        $stderr = $errTask.Result
        if ($null -eq $stdout) { $stdout = "" }
        if ($null -eq $stderr) { $stderr = "" }

        $json = $null
        $trimmed = $stdout.Trim()
        if ($trimmed.StartsWith("{") -or $trimmed.StartsWith("[")) {
            try { $json = $trimmed | ConvertFrom-Json } catch { $json = $null }
        }

        return [PSCustomObject]@{ ExitCode = $proc.ExitCode; Stdout = $stdout; Stderr = $stderr; Json = $json }
    } catch {
        return [PSCustomObject]@{ ExitCode = 126; Stdout = ""; Stderr = $_.Exception.Message; Json = $null }
    } finally {
        if ($proc) { $proc.Dispose() }
    }
}

function Wait-ProcessExit {
    param([int]$ProcessId, [int]$TimeoutSeconds = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $p) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue))
}

function Close-PbipInstance {
    <#
      Closes ONE Power BI Desktop instance, politely first.

      Only ever call this on an instance proven to hold no document: either one
      this run started itself, or the one that was showing a load-error dialog
      (a rejected definition never loaded, so there is nothing in it to lose).
      Never call it on an arbitrary "Untitled" window - that could be a new report
      someone is building.

      Returns $true when the process is gone.
    #>
    param([int]$ProcessId, [int]$GraceSeconds = 10)

    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p) { return $true }

    try { $null = $p.CloseMainWindow() } catch { }
    if (Wait-ProcessExit -ProcessId $ProcessId -TimeoutSeconds $GraceSeconds) { return $true }

    # It ignored the close request - a modal can swallow WM_CLOSE.
    try { $p.Kill() } catch { return $false }
    return (Wait-ProcessExit -ProcessId $ProcessId -TimeoutSeconds 5)
}

function Invoke-PbipReopen {
    <#
      Opens the project in Power BI Desktop so that exactly one instance ends up
      holding it.

      Two behaviours of Desktop drive the design:
        - "powerbi-desktop open" starts a NEW instance instead of reusing a running
          one, so any stale window must be gone before opening or a second one is
          left behind.
        - Desktop usually exits by itself once its load-error dialog is dismissed,
          but not always immediately, so the exit is waited for rather than assumed.

      Contract: on failure the instance count returns to what it was on entry. Any
      instance this function starts, it also cleans up.

      Returns @{ Ok; Pid; Status; Reason; StartedPid }.
    #>
    param(
        [Parameter(Mandatory = $true)]$Project,
        [int]$TimeoutSeconds = 60,
        [int[]]$ClosePids = @()
    )

    # Already open? Never start a second copy of the same project.
    $existing = Get-BridgeInstance -Project $Project
    if ($existing.Ok) {
        return [PSCustomObject]@{
            Ok = $true; Pid = $existing.Pid; Status = "already_open"
            Reason = $null; StartedPid = $null
        }
    }

    # Clear the instances we know are spent (a failed load holds no document).
    foreach ($deadPid in $ClosePids) {
        if ($deadPid -gt 0) { $null = Close-PbipInstance -ProcessId $deadPid }
    }

    $before = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })

    $open = Invoke-BridgeCli -Exe "powerbi-desktop" -CliArgs @("open", $Project.PbipPath) -TimeoutSeconds 90
    if ($open.ExitCode -eq 127) {
        return [PSCustomObject]@{
            Ok = $false; Pid = $null; Status = "cli_missing"; Reason = $open.Stderr; StartedPid = $null
        }
    }

    $inst = Wait-PbipLoaded -Project $Project -TimeoutSeconds $TimeoutSeconds

    # Whatever appeared during this call is ours, and ours alone to clean up.
    $after = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    $startedPid = $null
    foreach ($id in $after) { if ($before -notcontains $id) { $startedPid = $id; break } }

    if ($inst.Ok) {
        return [PSCustomObject]@{
            Ok = $true; Pid = $inst.Pid; Status = "opened"; Reason = $null; StartedPid = $startedPid
        }
    }

    return [PSCustomObject]@{
        Ok = $false; Pid = $null; Status = $inst.Status; Reason = $inst.Reason; StartedPid = $startedPid
    }
}

function Wait-PbipLoaded {
    <#
      Waits up to -TimeoutSeconds for a Desktop instance to actually have THIS
      project open, then says WHY if it never did.

      This exists because "no instance has this project open" has three completely
      different causes that the loop used to report identically as a skip:

        not_running   Desktop is closed. Nothing to verify. Fail open.
        no_bridge     Desktop is up but the preview flag is off. Fail open.
        load_failed   Desktop is up, the bridge is up, and the project still is not
                      loaded - which means Desktop rejected the definition and is
                      sitting behind an "Issues were found" dialog with the window
                      title on "Untitled". That is a real defect in the source, and
                      it must be reported as one rather than silently skipped.

      The dialog text itself is not reachable: during a failed load there is no
      report to serve the bridge API, and the dialog is WPF UI no method exposes.
      What IS reliable is the state, and the state is enough to name the problem.

      Returns @{ Ok; Pid; Status; Reason; ElapsedSeconds }.
    #>
    param(
        [Parameter(Mandatory = $true)]$Project,
        [int]$TimeoutSeconds = 30,
        [int]$PollMs = 1500
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastReason = $null

    $lastInstances = @()

    while ($true) {
        $inst = Get-BridgeInstance -Project $Project
        $lastInstances = @($inst.Instances)
        if ($inst.Ok) {
            $sw.Stop()
            return [PSCustomObject]@{
                Ok = $true; Pid = $inst.Pid; Status = "loaded"; Reason = $null
                ElapsedSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            }
        }
        $lastReason = $inst.Reason

        # A missing CLI will never resolve by waiting.
        if ($lastReason -and $lastReason -match 'is not installed or not on PATH') {
            $sw.Stop()
            return [PSCustomObject]@{
                Ok = $false; Pid = $null; Status = "cli_missing"; Reason = $lastReason
                ElapsedSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            }
        }

        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Milliseconds $PollMs
    }

    $sw.Stop()
    $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)

    $procs = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)
    $pipePids = @(Test-BridgePipe)

    if ($procs.Count -eq 0) {
        return [PSCustomObject]@{
            Ok = $false; Pid = $null; Status = "not_running"
            Reason = "Power BI Desktop is not running. Open the project: powerbi-desktop open `"$($Project.PbipPath)`""
            ElapsedSeconds = $elapsed
        }
    }

    if ($pipePids.Count -eq 0) {
        return [PSCustomObject]@{
            Ok = $false; Pid = $null; Status = "no_bridge"
            Reason = "Power BI Desktop is running but exposes no bridge pipe. Enable File > Options and settings > Options > Preview features > 'Enable external tool access to Power BI Desktop through secure local APIs', then restart Desktop."
            ElapsedSeconds = $elapsed
        }
    }

    # Desktop up, bridge up, project still not loaded. Three different situations,
    # and calling them all "failed to load" would be wrong: Desktop may simply
    # have a different project open.
    $titles = @()
    foreach ($p in $procs) {
        try { if (-not [string]::IsNullOrWhiteSpace($p.MainWindowTitle)) { $titles += $p.MainWindowTitle } } catch { }
    }
    $untitled = @($titles | Where-Object { $_ -match '^\s*Untitled\b' })

    $openFiles = @()
    $blankInstance = $false
    foreach ($i in $lastInstances) {
        $names = $i.PSObject.Properties.Name
        $fp = $null
        foreach ($k in @('currentFilePath', 'filePath', 'path')) {
            if ($names -contains $k -and -not [string]::IsNullOrWhiteSpace($i.$k)) { $fp = $i.$k; break }
        }
        if ($fp) { $openFiles += $fp } else { $blankInstance = $true }
    }

    # A different project being open is not a defect in this one. Fail open and name
    # what is actually loaded, rather than crying "failed to load".
    if ($openFiles.Count -gt 0 -and -not $blankInstance -and $untitled.Count -eq 0) {
        return [PSCustomObject]@{
            Ok = $false; Pid = $null; Status = "other_project"
            Reason = ("Power BI Desktop is running with a different project open: {0}`nThis project is not loaded. Open it with: powerbi-desktop open `"{1}`"" -f ($openFiles -join ', '), $Project.PbipPath)
            ElapsedSeconds = $elapsed
        }
    }

    # An instance reporting no file, or a window still titled Untitled, is the
    # signature of a definition Desktop rejected.

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("PBIP FAILED TO LOAD - Power BI Desktop rejected the project definition.")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("Waited ${elapsed}s (limit ${TimeoutSeconds}s). Desktop is running and the bridge is up (pid $($pipePids -join ', ')), but no instance has '$($Project.PbipPath)' open.")
    if ($untitled.Count -gt 0) {
        $null = $sb.AppendLine("Desktop window title is '$($untitled[0])' - the project never opened.")
    }
    if ($titles.Count -gt 0) {
        $null = $sb.AppendLine("Open windows: $($titles -join ' | ')")
    }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("Desktop is almost certainly showing an 'Issues were found' dialog naming the offending object. The bridge cannot read that dialog - it is WPF UI with no API surface, and during a failed load there is no report to serve the API.")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("ACTION:")
    $null = $sb.AppendLine("  1. Run: powershell -NoProfile -File scripts\Test-PbipSemantics.ps1")
    $null = $sb.AppendLine("     It checks the source for exactly this class of load error (name collisions,")
    $null = $sb.AppendLine("     unresolved references, unregistered resources, duplicate page ids).")
    $null = $sb.AppendLine("  2. If that comes back clean, read the dialog on screen (Copy details to clipboard).")
    $null = $sb.AppendLine("  3. Fix the PBIR/TMDL source, close the Untitled window, then reopen:")
    $null = $sb.AppendLine("     powerbi-desktop open `"$($Project.PbipPath)`"")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("Do NOT choose 'continue with errors'. It opens the report with the failing objects dropped, so every screenshot after it shows a report that does not exist in source.")

    return [PSCustomObject]@{
        Ok = $false; Pid = $null; Status = "load_failed"; Reason = $sb.ToString().TrimEnd()
        ElapsedSeconds = $elapsed
    }
}

function Get-PbipDefinitionHash {
    <#
      Content fingerprint of everything that affects rendering.
      Deliberately NOT tool-call based: this repo writes PBIP files from Python
      build scripts via Bash, so a PostToolUse matcher on Edit|Write would miss
      most changes. Hashing the tree catches every writer.
      Returns @{ Hash; TmdlChanged (bool: any semantic-model file present) }.
    #>
    param([Parameter(Mandatory = $true)]$Project)

    function Get-TreeFingerprint {
        param([string[]]$Roots, [string]$RepoRoot)
        $entries = New-Object System.Collections.Generic.List[string]
        foreach ($root in $Roots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            $files = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $rel = $f.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')
                $entries.Add(("{0}|{1}|{2}" -f $rel, $f.Length, $f.LastWriteTimeUtc.Ticks))
            }
        }
        $sorted = @($entries) | Sort-Object
        $payload = ($sorted -join "`n")
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
            $hex = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
        } finally {
            $sha.Dispose()
        }
        return [PSCustomObject]@{ Hash = $hex; Count = $sorted.Count }
    }

    # Report side: the definition tree plus StaticResources, because themes and SVG
    # backgrounds live outside definition/ but absolutely change what renders.
    $reportRoots = @(
        (Join-Path $Project.ReportDir "definition"),
        (Join-Path $Project.ReportDir "StaticResources")
    )
    $modelRoots = @()
    if ($Project.SemanticModelDir) {
        $modelRoots += (Join-Path $Project.SemanticModelDir "definition")
    }

    $report = Get-TreeFingerprint -Roots $reportRoots -RepoRoot $Project.RepoRoot
    $model = Get-TreeFingerprint -Roots $modelRoots -RepoRoot $Project.RepoRoot

    return [PSCustomObject]@{
        Hash        = "$($report.Hash):$($model.Hash)"
        ReportHash  = $report.Hash
        ModelHash   = $model.Hash
        FileCount   = $report.Count + $model.Count
    }
}

function Test-PbirValid {
    <#
      Runs the authoring CLI validator and interprets its envelope.
      Checks data.result / errorCount as well as the exit code, so a validator that
      reports failures in JSON while exiting 0 is still caught.
      Returns @{ Ok; NotInstalled; ErrorCount; WarningCount; Detail }.
    #>
    param(
        [Parameter(Mandatory = $true)]$Project,
        [switch]$NoSchema
    )

    $cliArgs = @("validate", $Project.ReportDir, "--format", "json")
    if ($NoSchema) { $cliArgs += "--no-schema" }
    $res = Invoke-BridgeCli -Exe "powerbi-report-author" -CliArgs $cliArgs

    if ($res.ExitCode -eq 127) {
        return [PSCustomObject]@{
            Ok = $false; NotInstalled = $true; ErrorCount = -1; WarningCount = 0
            Detail = "powerbi-report-author is not installed. Run: npm install -g @microsoft/powerbi-report-authoring-cli@latest"
        }
    }

    $errorCount = -1
    $warningCount = 0
    $result = $null
    if ($res.Json -and $res.Json.PSObject.Properties.Name -contains 'data') {
        $d = $res.Json.data
        if ($d.PSObject.Properties.Name -contains 'errorCount') { $errorCount = [int]$d.errorCount }
        if ($d.PSObject.Properties.Name -contains 'warningCount') { $warningCount = [int]$d.warningCount }
        if ($d.PSObject.Properties.Name -contains 'result') { $result = [string]$d.result }
    }

    $ok = ($res.ExitCode -eq 0)
    if ($errorCount -gt 0) { $ok = $false }
    if ($result -and $result -ne 'succeeded') { $ok = $false }

    $detail = ($res.Stdout + "`n" + $res.Stderr).Trim()
    return [PSCustomObject]@{
        Ok = $ok; NotInstalled = $false; ErrorCount = $errorCount; WarningCount = $warningCount; Detail = $detail
    }
}

function Get-PbipPageManifest {
    <#
      page id -> display name, via the authoring CLI's preview-pages.
      Without this the agent only sees opaque filenames like
      6e86f24a804ae4a905eb.png and cannot say which page is broken.
    #>
    param([Parameter(Mandatory = $true)]$Project)

    $res = Invoke-BridgeCli -Exe "powerbi-report-author" -CliArgs @("preview-pages", $Project.ReportDir, "--with-derived")
    $pages = @()
    if ($res.Json -and $res.Json.PSObject.Properties.Name -contains 'data' -and $res.Json.data.PSObject.Properties.Name -contains 'pages') {
        foreach ($p in @($res.Json.data.pages)) {
            $pages += [PSCustomObject]@{
                Name        = $p.name
                DisplayName = $p.displayName
                Ordinal     = $p.ordinal
                Width       = $p.width
                Height      = $p.height
                VisualCount = $(if ($p.PSObject.Properties.Name -contains 'visualCount') { $p.visualCount } else { $null })
            }
        }
    }
    return $pages
}
