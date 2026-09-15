<#
.SYNOPSIS
    Reads Power BI Desktop's load and reload error dialogs so the agent can act on
    them, and optionally answers the dialog (dismiss, continue, close Desktop).

.DESCRIPTION
    Desktop reports a rejected definition through a modal that no bridge method can
    see - during a failed load there is no report to serve the API, and a reload that
    trips the dialog still returns "success": true. This script reads it through UI
    Automation.

    TWO DIALOG KINDS, measured on Power BI Desktop 2.157.879.0:

      definition_error   Title "Issues were found". Raised on OPEN when TMDL or PBIR
                         cannot be loaded at all. Named Window element; content in an
                         "Internet Explorer_Server" (MSHTML) pane. Buttons: Close.
                         The "Copy details to clipboard" diagnostic carries an
                         "Error Message:" block naming the document and line.

      report_issues      Title "Your report has issues that could not be resolved".
                         Raised on OPEN or RELOAD when PBIR fails schema validation.
                         UNNAMED Window element; the title is a Group/Text inside a
                         WebView2 host (desktopDialogHost.html). Each issue is its own
                         ListItem. Buttons: Copy details to clipboard, Continue,
                         Close Desktop, Close Dialog.

    PRECONDITIONS - both are load-bearing:

      1. Search with an UNFILTERED FindAll(Descendants, TrueCondition) and filter in
         PowerShell. A filtered FindAll returns nothing on a cold process.
      2. Bring the dialog to the foreground before reading its content. Both hosts
         build their accessibility tree lazily; cold, the dialog shows only unnamed
         Panes.

    Candidate windows must have a real NativeWindowHandle. Desktop's onboarding
    flyouts ("Run DAX queries on your model", "Edit your model with TMDL") also appear
    as Window elements with their own "Close Dialog" button, but report handle 0 -
    that is what keeps an action from landing on the wrong window.

    WHAT THE ACTIONS DO (report_issues):

      Continue        Loads the report with the failing objects silently dropped - a
                      broken visual filter simply stops filtering, and the page looks
                      normal. Writes nothing to disk. The dialog can re-raise on the
                      next validation pass (for example during a screenshot).
      CloseDesktop    Exits the instance cleanly within a few seconds. No save prompt,
                      nothing written.

    THE ISSUE LIST COLLAPSES. One malformed expression expands into one "Required
    property" line per expression kind the schema accepts - 49 lines for a single
    typo'd key. Among them, one "An additional property 'X' was included" line names
    the actual defect. RootCauses groups the list by file and JSON pointer and leads
    with that line.

    This is the SECOND line of defence. scripts\Test-PbipSemantics.ps1 finds both
    classes in the source before Desktop is launched. Everything here degrades to a
    partial result rather than throwing.

.PARAMETER ProcessId
    Target PBIDesktop.exe pid. Strongly preferred: without it every running instance
    is searched, including ones holding unrelated work.

.PARAMETER ExcludeProcessId
    Comma-separated pids never to search or act on - for example instances the
    bridge reports are holding a different project.

.PARAMETER SkipCapture
    Find the dialog and perform -Action only: no text, clipboard, or PNG. For
    repeat presses when a dialog re-raises and its content is already captured.

.PARAMETER OutputDir
    Where to write the dialog PNG and the raw clipboard text. Defaults to
    tests\screenshots\latest.

.PARAMETER Action
    None (default), Dismiss, Continue or CloseDesktop. Dismiss uses Close/OK on a
    definition_error and Close Desktop on a report_issues dialog.

.PARAMETER Dismiss
    Shorthand for -Action Dismiss.

.PARAMETER Json
    Emit the result as JSON on stdout, for callers running this as a child process
    under a hard timeout.

.EXAMPLE
    powershell -NoProfile -File scripts\Get-PbipLoadError.ps1 -ProcessId 2440
    powershell -NoProfile -File scripts\Get-PbipLoadError.ps1 -ProcessId 2440 -Action Continue -Json
#>
[CmdletBinding()]
param(
    [int]$ProcessId = 0,
    [string]$ExcludeProcessId = "",
    [string]$OutputDir,
    [int]$TimeoutSeconds = 25,
    [ValidateSet("None", "Dismiss", "Continue", "CloseDesktop")][string]$Action = "None",
    [switch]$Dismiss,
    [switch]$SkipCapture,
    [switch]$Json
)

$script:DefinitionErrorPhrases = @(
    "Issues were found",
    "problem with the definition",
    "Couldn't load",
    "Can't open",
    "Unable to open"
)
$script:ReportIssuesPhrases = @(
    "Your report has issues",
    "could not be resolved"
)
$script:CopyLinkNames = @(
    "Copy details to clipboard", "Copy Details to clipboard", "Copy details", "Copy Details"
)
$script:DefinitionDismissNames = @("Close", "OK", "Ok")
$script:ChromeButtonNames = @("Close", "OK", "Ok", "Close Dialog", "Continue", "Close Desktop")

function Get-PbiTopLevelWindows {
    <#
      Process.MainWindowHandle is not usable here: while a modal is up it can point
      at the dialog's "SysShadow" drop-shadow window, which has an empty UIA subtree.
      Enumerate the desktop's children and filter by process id instead.
    #>
    param([int[]]$ProcessIds)

    $out = @()
    try {
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $children = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
                                  [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($w in $children) {
            $wpid = 0
            try { $wpid = [int]$w.Current.ProcessId } catch { continue }
            if ($ProcessIds -notcontains $wpid) { continue }
            $cls = ""
            try { $cls = [string]$w.Current.ClassName } catch { }
            if ($cls -like "WindowsForms10*") { $out += $w }
        }
    } catch { }
    return $out
}

function Set-PbipForeground {
    param([IntPtr]$Handle)
    if ($Handle -eq [IntPtr]::Zero) { return }
    try {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class PbipFg {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
    } catch { }
    try { [PbipFg]::SetForegroundWindow($Handle) | Out-Null; Start-Sleep -Milliseconds 700 } catch { }
}

function Get-ElementText {
    param($Element)
    try { return ([string]$Element.Current.Name).Trim() } catch { return "" }
}

function Save-DialogImage {
    param(
        [Parameter(Mandatory = $true)]$Rect,
        [Parameter(Mandatory = $true)][string]$Path
    )
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $x = [int][math]::Floor($Rect.X)
        $y = [int][math]::Floor($Rect.Y)
        $w = [int][math]::Ceiling($Rect.Width)
        $h = [int][math]::Ceiling($Rect.Height)
        if ($w -le 0 -or $h -le 0) { return $null }

        $pad = 8
        $x = [math]::Max(0, $x - $pad); $y = [math]::Max(0, $y - $pad)
        $w = $w + ($pad * 2); $h = $h + ($pad * 2)

        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size($w, $h)))
            } finally { $g.Dispose() }
            $dir = Split-Path -Parent $Path
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $bmp.Dispose() }
        return $Path
    } catch {
        return $null
    }
}

function Get-NearestKind {
    param([string]$Name, [string[]]$Candidates)
    $best = $null; $bestD = 99
    foreach ($c in $Candidates) {
        if ($c -ieq $Name) { return $c }
        $a = $Name.ToLowerInvariant(); $b = $c.ToLowerInvariant()
        $prev = New-Object int[] ($b.Length + 1)
        for ($j = 0; $j -le $b.Length; $j++) { $prev[$j] = $j }
        for ($i = 1; $i -le $a.Length; $i++) {
            $cur = New-Object int[] ($b.Length + 1)
            $cur[0] = $i
            for ($j = 1; $j -le $b.Length; $j++) {
                $cost = 1
                if ($a[$i - 1] -eq $b[$j - 1]) { $cost = 0 }
                $cur[$j] = [math]::Min([math]::Min($prev[$j] + 1, $cur[$j - 1] + 1), $prev[$j - 1] + $cost)
            }
            $prev = $cur
        }
        if ($prev[$b.Length] -lt $bestD) { $bestD = $prev[$b.Length]; $best = $c }
    }
    if ($bestD -le 2) { return $best }
    return $null
}

function Get-PbipIssueRootCauses {
    <#
      Collapses Desktop's schema issue list into one finding per file + JSON pointer.

      Recognised lines:
        An additional property 'X' was included in the <ptr> property of <file>.
        Required property 'X' was not included in the <ptr> property of <file>.
        One of the properties 'A,B,...' must be provided in the <ptr> property of <file>.
    #>
    param([string[]]$Issues)

    $groups = [ordered]@{}
    $unparsed = New-Object System.Collections.Generic.List[string]

    foreach ($line in $Issues) {
        $l = ([string]$line).Trim()
        if ($l.Length -eq 0) { continue }

        $m = [regex]::Match($l, "^An additional property '(?<k>[^']+)' was included in the (?<p>\S+) property of (?<f>.+?)\.?$")
        $kind = "additional"
        if (-not $m.Success) { $m = [regex]::Match($l, "^Required property '(?<k>[^']+)' was not included in the (?<p>\S+) property of (?<f>.+?)\.?$"); $kind = "required" }
        if (-not $m.Success) { $m = [regex]::Match($l, "^One of the properties '(?<k>[^']+)' must be provided in the (?<p>\S+) property of (?<f>.+?)\.?$"); $kind = "oneof" }
        if (-not $m.Success) { $unparsed.Add($l); continue }

        $key = $m.Groups['f'].Value + "|" + $m.Groups['p'].Value
        if (-not $groups.Contains($key)) {
            $groups[$key] = [PSCustomObject]@{
                File = $m.Groups['f'].Value; Pointer = $m.Groups['p'].Value
                Additional = New-Object System.Collections.Generic.List[string]
                Required = New-Object System.Collections.Generic.List[string]
                Allowed = @(); Lines = 0
            }
        }
        $g = $groups[$key]
        $g.Lines++
        switch ($kind) {
            "additional" { $g.Additional.Add($m.Groups['k'].Value) }
            "required"   { $g.Required.Add($m.Groups['k'].Value) }
            "oneof"      { $g.Allowed = @($m.Groups['k'].Value -split ',' | ForEach-Object { $_.Trim() }) }
        }
    }

    $causes = New-Object System.Collections.Generic.List[string]
    foreach ($g in $groups.Values) {
        $where = "$($g.File) $($g.Pointer)"
        if ($g.Additional.Count -gt 0) {
            foreach ($k in $g.Additional) {
                $msg = "$where uses '$k', which the schema does not accept here."
                $hint = $null
                if ($g.Allowed.Count -gt 0) { $hint = Get-NearestKind -Name $k -Candidates $g.Allowed }
                if ($hint) { $msg += " Did you mean '$hint'?" }
                $causes.Add("$msg ($($g.Lines) dialog lines)")
            }
        } elseif ($g.Allowed.Count -gt 0) {
            $causes.Add("$where has no valid expression kind - it must contain one of $($g.Allowed.Count) kinds such as Comparison, In or Column. ($($g.Lines) dialog lines)")
        } else {
            $shown = @($g.Required | Select-Object -First 5) -join "', '"
            $more = ""
            if ($g.Required.Count -gt 5) { $more = " (+$($g.Required.Count - 5) more)" }
            $causes.Add("$where is missing required '$shown'$more. ($($g.Lines) dialog lines)")
        }
    }
    foreach ($u in $unparsed) { $causes.Add($u) }
    return @($causes)
}

function Invoke-DialogButton {
    param($Dialog, [string[]]$Names)
    foreach ($name in $Names) {
        try {
            $cond = New-Object System.Windows.Automation.AndCondition(
                (New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::Button)),
                (New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::NameProperty, $name))
            )
            $btn = $Dialog.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
            if ($btn) {
                $bp = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                if ($bp) { $bp.Invoke(); Start-Sleep -Milliseconds 500; return $name }
            }
        } catch { }
    }
    return $null
}

function Find-PbipErrorDialog {
    <#
      Returns @{ Dialog; Kind; Pid; WindowTitle } for the first error dialog found,
      or $null. Implements both preconditions from the description.
    #>
    param($Tops)

    foreach ($top in $Tops) {
        $all = $null
        try {
            $all = $top.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                                [System.Windows.Automation.Condition]::TrueCondition)
        } catch { $all = $null }
        if (-not $all) { continue }

        foreach ($w in $all) {
            try {
                if ($w.Current.ControlType -ne [System.Windows.Automation.ControlType]::Window) { continue }
                $handle = [IntPtr]$w.Current.NativeWindowHandle
            } catch { continue }
            # Onboarding flyouts report handle 0; real dialogs have a window.
            if ($handle -eq [IntPtr]::Zero) { continue }

            $name = Get-ElementText $w
            foreach ($phrase in $script:DefinitionErrorPhrases) {
                if ($name -like "*$phrase*") {
                    return [PSCustomObject]@{ Dialog = $w; Kind = "definition_error"; Pid = [int]$top.Current.ProcessId; WindowTitle = (Get-ElementText $top) }
                }
            }
            foreach ($phrase in $script:ReportIssuesPhrases) {
                if ($name -like "*$phrase*") {
                    return [PSCustomObject]@{ Dialog = $w; Kind = "report_issues"; Pid = [int]$top.Current.ProcessId; WindowTitle = (Get-ElementText $top) }
                }
            }

            # Unnamed: the title lives inside the web host, which only materializes
            # once the window is in front.
            if ([string]::IsNullOrWhiteSpace($name)) {
                Set-PbipForeground -Handle $handle
                $inner = $null
                try {
                    $inner = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                                        [System.Windows.Automation.Condition]::TrueCondition)
                } catch { $inner = $null }
                if (-not $inner) { continue }

                $kind = $null
                foreach ($e in $inner) {
                    $t = Get-ElementText $e
                    if ($t.Length -eq 0) { continue }
                    foreach ($phrase in $script:ReportIssuesPhrases) { if ($t -like "*$phrase*") { $kind = "report_issues"; break } }
                    if ($kind) { break }
                    foreach ($phrase in $script:DefinitionErrorPhrases) { if ($t -like "*$phrase*") { $kind = "definition_error"; break } }
                    if ($kind) { break }
                }
                if ($kind) {
                    return [PSCustomObject]@{ Dialog = $w; Kind = $kind; Pid = [int]$top.Current.ProcessId; WindowTitle = (Get-ElementText $top) }
                }
            }
        }
    }
    return $null
}

function Get-PbipLoadError {
    [CmdletBinding()]
    param(
        [int]$ProcessId = 0,
        [int[]]$ExcludeProcessId = @(),
        [string]$OutputDir,
        [int]$TimeoutSeconds = 25,
        [ValidateSet("None", "Dismiss", "Continue", "CloseDesktop")][string]$Action = "None",
        [switch]$SkipCapture
    )

    $result = [PSCustomObject]@{
        Found             = $false
        Kind              = $null
        Pid               = $null
        WindowTitle       = $null
        Heading           = $null
        Text              = $null
        Issues            = @()
        IssueCount        = 0
        RootCauses        = @()
        ErrorMessage      = $null
        DetailsPath       = $null
        CopiedToClipboard = $false
        ScreenshotPath    = $null
        ActionTaken       = $null
        Dismissed         = $false
        Note              = $null
    }

    try {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction Stop
    } catch {
        $result.Note = "UI Automation assemblies unavailable: $($_.Exception.Message)"
        return $result
    }

    $procs = @()
    if ($ProcessId -gt 0) {
        $procs = @(Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
    } else {
        $procs = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue)
    }
    if ($procs.Count -eq 0) {
        $result.Note = "No PBIDesktop process found."
        return $result
    }
    $pids = @($procs | ForEach-Object { $_.Id } | Where-Object { $ExcludeProcessId -notcontains $_ })
    if ($pids.Count -eq 0) {
        $result.Note = "Every running PBIDesktop instance was excluded."
        return $result
    }

    # Retried: the dialog can lag the window title by seconds.
    $found = $null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        $tops = Get-PbiTopLevelWindows -ProcessIds $pids
        if ($tops.Count -gt 0) { $found = Find-PbipErrorDialog -Tops $tops }
        if ($found) { break }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds 2
    }

    if (-not $found) {
        $result.Note = "No load-error dialog found. If Desktop is mid-load, wait and retry."
        return $result
    }

    $dlg = $found.Dialog
    $result.Found = $true
    $result.Kind = $found.Kind
    $result.Pid = $found.Pid
    $result.WindowTitle = $found.WindowTitle

    $handle = [IntPtr]::Zero
    try { $handle = [IntPtr]$dlg.Current.NativeWindowHandle } catch { }
    Set-PbipForeground -Handle $handle

    if (-not $SkipCapture) {
    # Content, now that the host is in front.
    $lines = New-Object System.Collections.Generic.List[string]
    $issues = New-Object System.Collections.Generic.List[string]
    try {
        $inner = $dlg.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                              [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($t in $inner) {
            $ct = $null
            try { $ct = $t.Current.ControlType } catch { continue }
            $n = Get-ElementText $t
            if ($n.Length -eq 0) { continue }
            if ($ct -eq [System.Windows.Automation.ControlType]::ListItem) {
                $issues.Add($n)
                continue
            }
            if ($ct -ne [System.Windows.Automation.ControlType]::Text) { continue }
            if ($script:ChromeButtonNames -contains $n) { continue }
            if ($script:CopyLinkNames -contains $n) { continue }
            if (-not $lines.Contains($n)) { $lines.Add($n) }
        }
    } catch { }
    if ($lines.Count -gt 0) {
        $result.Heading = $lines[0]
        $result.Text = ($lines -join "`n")
    }
    $dn = Get-ElementText $dlg
    if ($dn) { $result.Heading = $dn }

    if (-not $OutputDir) {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
        $OutputDir = Join-Path $repoRoot "tests\screenshots\latest"
    }
    if (-not (Test-Path -LiteralPath $OutputDir)) {
        try { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null } catch { }
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"

    # "Copy details to clipboard". A sentinel guards against reading whatever the
    # user already had on the clipboard if the button does nothing, and their text
    # is put back afterwards.
    $priorClip = $null
    try { $priorClip = Get-Clipboard -Raw -ErrorAction Stop } catch { $priorClip = $null }
    $sentinel = "PBIP-LOAD-ERROR-SENTINEL-" + [guid]::NewGuid().ToString("N")
    $clip = $null
    try {
        Set-Clipboard -Value $sentinel -ErrorAction Stop
        foreach ($name in $script:CopyLinkNames) {
            $cond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty, $name)
            $link = $null
            try { $link = $dlg.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond) } catch { $link = $null }
            if (-not $link) { continue }
            try {
                $pattern = $link.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                if ($pattern) {
                    $pattern.Invoke()
                    Start-Sleep -Milliseconds 800
                    $c = $null
                    try { $c = Get-Clipboard -Raw -ErrorAction Stop } catch { $c = $null }
                    if (-not [string]::IsNullOrWhiteSpace($c) -and $c -ne $sentinel) { $clip = $c }
                }
            } catch { }
            break
        }
    } catch { } finally {
        try {
            if ($null -ne $priorClip -and $priorClip.Length -gt 0) { Set-Clipboard -Value $priorClip -ErrorAction Stop }
        } catch { }
    }

    if ($clip) {
        $result.CopiedToClipboard = $true
        try {
            $txtPath = Join-Path $OutputDir "load-error-$stamp.txt"
            [System.IO.File]::WriteAllText($txtPath, $clip, (New-Object System.Text.UTF8Encoding($false)))
            $result.DetailsPath = $txtPath
        } catch { }

        if ($result.Kind -eq "definition_error") {
            # "Error Message:" ... "Stack Trace:". Sliced rather than regexed.
            $marker = "Error Message:"
            $i = $clip.IndexOf($marker)
            if ($i -ge 0) {
                $rest = $clip.Substring($i + $marker.Length)
                $j = $rest.IndexOf("Stack Trace:")
                if ($j -ge 0) { $rest = $rest.Substring(0, $j) }
                $result.ErrorMessage = $rest.Trim()
            } else {
                $trimmed = $clip.Trim()
                if ($trimmed.Length -gt 600) { $trimmed = $trimmed.Substring(0, 600) + " ..." }
                $result.ErrorMessage = $trimmed
            }
        } else {
            # The clipboard carries the untruncated list, one issue per line. Prefer
            # it over the UIA list, which a long dialog may virtualize.
            $clipIssues = @($clip -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
            if ($clipIssues.Count -ge $issues.Count) {
                $issues = New-Object System.Collections.Generic.List[string]
                foreach ($ci in $clipIssues) { $issues.Add($ci) }
            }
        }
    }

    if ($issues.Count -gt 0) {
        $result.Issues = @($issues)
        $result.IssueCount = $issues.Count
        $result.RootCauses = @(Get-PbipIssueRootCauses -Issues @($issues))
        if (-not $result.ErrorMessage) { $result.ErrorMessage = ($result.RootCauses -join "`n") }
    }

    # Picture of the dialog - works even if UIA publishes nothing.
    try {
        $rect = $dlg.Current.BoundingRectangle
        $saved = Save-DialogImage -Rect $rect -Path (Join-Path $OutputDir "load-error-$stamp.png")
        if ($saved) { $result.ScreenshotPath = $saved }
    } catch { }
    if (-not $result.ScreenshotPath -and -not $result.CopiedToClipboard -and -not $result.Text) {
        $result.Note = "Dialog found but neither its text nor a screenshot could be captured. Read it on screen."
    }

    }

    # Answer the dialog.
    $names = @()
    switch ($Action) {
        "Dismiss" {
            if ($result.Kind -eq "report_issues") { $names = @("Close Desktop") } else { $names = $script:DefinitionDismissNames }
        }
        "Continue"     { $names = @("Continue") }
        "CloseDesktop" { $names = @("Close Desktop") }
    }
    if ($names.Count -gt 0) {
        Set-PbipForeground -Handle $handle
        $pressed = Invoke-DialogButton -Dialog $dlg -Names $names
        if ($pressed) {
            $result.ActionTaken = $pressed
            if ($pressed -ne "Continue") { $result.Dismissed = $true }
        } else {
            $result.Note = "Could not find a '$($names -join "' / '")' button on the $($result.Kind) dialog."
        }
    }

    return $result
}

# --- Standalone entry point -------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    $act = $Action
    if ($Dismiss -and $act -eq "None") { $act = "Dismiss" }
    $excluded = @()
    foreach ($tok in ($ExcludeProcessId -split '[,\s]+')) {
        $n = 0
        if ([int]::TryParse($tok, [ref]$n) -and $n -gt 0) { $excluded += $n }
    }
    $res = Get-PbipLoadError -ProcessId $ProcessId -ExcludeProcessId $excluded -OutputDir $OutputDir -TimeoutSeconds $TimeoutSeconds -Action $act -SkipCapture:$SkipCapture

    if ($Json) {
        $res | ConvertTo-Json -Depth 5 -Compress
        exit 0
    }

    if (-not $res.Found) {
        Write-Host "No load-error dialog found."
        if ($res.Note) { Write-Host "  $($res.Note)" }
        exit 1
    }

    Write-Host "Power BI Desktop $($res.Kind) (pid $($res.Pid), shell window '$($res.WindowTitle)')"
    Write-Host ("-" * 70)
    Write-Host "Dialog: $($res.Heading)"
    if ($res.RootCauses.Count -gt 0) {
        Write-Host ""
        Write-Host "Root cause(s) - $($res.IssueCount) dialog issue(s) collapsed to $($res.RootCauses.Count):"
        foreach ($c in $res.RootCauses) { Write-Host "  - $c" }
    } elseif ($res.ErrorMessage) {
        Write-Host ""
        Write-Host "Error message (from 'Copy details to clipboard'):"
        Write-Host $res.ErrorMessage
    } elseif ($res.Text) {
        Write-Host ""
        Write-Host "On screen:"
        Write-Host $res.Text
    }
    if ($res.DetailsPath) { Write-Host ""; Write-Host "Full diagnostic: $($res.DetailsPath)" }
    if ($res.ScreenshotPath) { Write-Host "Dialog image:    $($res.ScreenshotPath)" }
    if ($res.ActionTaken) { Write-Host ""; Write-Host "Pressed: $($res.ActionTaken)" }
    if ($res.Note) { Write-Host ""; Write-Host $res.Note }
    exit 0
}
