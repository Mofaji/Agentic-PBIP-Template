<#
.SYNOPSIS
    Captures Power BI Desktop's load-error dialog so the agent can read it, and
    dismisses it so the project can be reopened.

.DESCRIPTION
    When Desktop rejects a PBIP definition it shows a modal ("Issues were found")
    naming the offending object and leaves the window on "Untitled". No bridge method
    reaches it: during a failed load there is no report to serve the API.

    WHAT WAS MEASURED, on Power BI Desktop 2.157.879.0:

      REACHABLE via UI Automation
        - the dialog as ControlType.Window, Name = "Issues were found"
        - its BoundingRectangle and NativeWindowHandle
        - its "Close" button, invokable
        - the main window's IsEnabled = False while the modal is up

      REACHABLE, BUT ONLY AFTER THE TREE IS FORCED TO MATERIALIZE
        - the dialog Window element, the body text, and the "Copy details to
          clipboard" link, invokable. Two things were measured to matter, and both
          are load-bearing:

          1. The search must be an UNFILTERED FindAll(Descendants, TrueCondition).
             A filtered FindAll - say, ControlType.Window only - returns nothing on
             a cold process: the shell publishes no subtree until something walks
             the whole thing. Filtering happens in PowerShell afterwards instead.
          2. The dialog must be brought to the foreground before its own text is
             read. Its content sits in an "Internet Explorer_Server" (legacy MSHTML)
             pane that builds its accessibility tree lazily; cold, the dialog shows
             four unnamed Panes and nothing else.

      NOT REACHABLE
        - Ctrl+C on the dialog is inert, and tabbing leaves focus on the container
          pane, so neither is a route to the text.

    Three channels, most useful first: the on-screen text (short and exactly the
    actionable sentence), the clipboard details (the same message plus a stack trace
    and a full environment dump - trimmed here to the Error Message block, with the
    raw text written beside the PNG), and a cropped screenshot of the dialog, which
    works even if UIA publishes nothing at all.

    This is the SECOND line of defence. scripts\Test-PbipSemantics.ps1 finds this
    class of error in the source before Desktop is ever launched and should catch
    most of it. Everything here degrades: no dialog, no rect, no screenshot, all
    return a partial result rather than throwing.

.PARAMETER ProcessId
    Target PBIDesktop.exe pid. Defaults to every running instance.

.PARAMETER OutputDir
    Where to write the dialog PNG. Defaults to tests\screenshots\latest.

.PARAMETER Dismiss
    Invoke the dialog's Close button after capturing. Required before a reopen:
    a modal blocks everything, including Desktop's own File > Open.

.PARAMETER Json
    Emit the result as JSON on stdout, for callers running this as a child process
    under a hard timeout.

.EXAMPLE
    powershell -NoProfile -File scripts\Get-PbipLoadError.ps1
    powershell -NoProfile -File scripts\Get-PbipLoadError.ps1 -Dismiss -Json
#>
[CmdletBinding()]
param(
    [int]$ProcessId = 0,
    [string]$OutputDir,
    [int]$TimeoutSeconds = 25,
    [switch]$Dismiss,
    [switch]$Json
)

# Dialog titles Desktop uses for a rejected definition. Matched as substrings
# against every Window element under the app, so a reworded title still lands
# as long as one of these fragments survives.
$script:DialogTitlePhrases = @(
    "Issues were found",
    "problem with the definition",
    "Couldn't load",
    "Can't open",
    "Unable to open",
    "Error"
)
$script:CopyLinkNames = @(
    "Copy details to clipboard", "Copy Details to clipboard", "Copy details", "Copy Details"
)
$script:DismissNames = @("Close", "OK", "Ok")

function Get-PbiTopLevelWindows {
    <#
      Process.MainWindowHandle is not usable here: while the modal is up it can
      point at the dialog's "SysShadow" drop-shadow window, which has an empty UIA
      subtree. Enumerate the desktop's children and filter by process id instead.
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
            # The real shell window; skip SysShadow and other decoration.
            if ($cls -like "WindowsForms10*") { $out += $w }
        }
    } catch { }
    return $out
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

        # A little margin: the drop shadow sits outside the reported rect and the
        # first/last text line can hug the edge.
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

function Get-PbipLoadError {
    [CmdletBinding()]
    param(
        [int]$ProcessId = 0,
        [string]$OutputDir,
        [int]$TimeoutSeconds = 25,
        [switch]$Dismiss
    )

    $result = [PSCustomObject]@{
        Found             = $false
        Pid               = $null
        WindowTitle       = $null
        Heading           = $null
        Text              = $null
        ErrorMessage      = $null
        DetailsPath       = $null
        CopiedToClipboard = $false
        ScreenshotPath    = $null
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

    $tops = Get-PbiTopLevelWindows -ProcessIds @($procs | ForEach-Object { $_.Id })
    if ($tops.Count -eq 0) {
        $result.Note = "Power BI Desktop is running but exposes no shell window to UI Automation."
        return $result
    }

    # Find the modal - a child Window inside the shell window, not a top-level one.
    # Unfiltered FindAll, then filter here: see note 1 in the description.
    # Retried, because the dialog can lag the "Untitled" window title by seconds.
    $dlg = $null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ($true) {
        foreach ($top in $tops) {
            try { $result.WindowTitle = [string]$top.Current.Name } catch { }
            try { $result.Pid = [int]$top.Current.ProcessId } catch { }

            $all = $null
            try {
                $all = $top.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                                    [System.Windows.Automation.Condition]::TrueCondition)
            } catch { $all = $null }
            if (-not $all) { continue }

            foreach ($w in $all) {
                $ct = $null
                try { $ct = $w.Current.ControlType } catch { continue }
                if ($ct -ne [System.Windows.Automation.ControlType]::Window) { continue }
                $nm = ""
                try { $nm = [string]$w.Current.Name } catch { continue }
                if ([string]::IsNullOrWhiteSpace($nm)) { continue }
                foreach ($phrase in $script:DialogTitlePhrases) {
                    if ($nm -like "*$phrase*") { $dlg = $w; break }
                }
                if ($dlg) { break }
            }
            if ($dlg) { break }
        }
        if ($dlg) { break }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds 2
        $tops = Get-PbiTopLevelWindows -ProcessIds @($procs | ForEach-Object { $_.Id })
        if ($tops.Count -eq 0) { break }
    }

    if (-not $dlg) {
        $result.Note = "No load-error dialog found. If Desktop is mid-load, wait and retry; if the window title is not 'Untitled', the project may have opened after all."
        return $result
    }

    $result.Found = $true
    try { $result.Heading = ([string]$dlg.Current.Name).Trim() } catch { }

    # Focus the dialog FIRST. It is what makes MSHTML publish its accessibility
    # subtree, and a screen capture photographs whatever is on top anyway.
    $handle = [IntPtr]::Zero
    try { $handle = [IntPtr]$dlg.Current.NativeWindowHandle } catch { }
    if ($handle -ne [IntPtr]::Zero) {
        try {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class PbipFg {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
        } catch { }
        try { [PbipFg]::SetForegroundWindow($handle) | Out-Null; Start-Sleep -Milliseconds 600 } catch { }
    }

    # Now that the pane is active, its text is enumerable. This is the most useful
    # channel: it is exactly the sentence naming the offending object.
    try {
        $inner = $dlg.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                              [System.Windows.Automation.Condition]::TrueCondition)
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($t in $inner) {
            $ct = $null
            try { $ct = $t.Current.ControlType } catch { continue }
            if ($ct -ne [System.Windows.Automation.ControlType]::Text) { continue }
            $n = ""
            try { $n = ([string]$t.Current.Name).Trim() } catch { continue }
            if ($n.Length -eq 0) { continue }
            if ($script:DismissNames -contains $n) { continue }
            if ($script:CopyLinkNames -contains $n) { continue }
            if (-not $lines.Contains($n)) { $lines.Add($n) }
        }
        if ($lines.Count -gt 0) { $result.Text = ($lines -join "`n") }
    } catch { }

    if (-not $OutputDir) {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
        $OutputDir = Join-Path $repoRoot "tests\screenshots\latest"
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"

    # "Copy details to clipboard" yields the message plus a stack trace and a full
    # environment dump - around 50 KB. Only the Error Message block is actionable,
    # so that is what comes back; the raw text is written beside the PNG for the
    # rare case where the stack trace matters.
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
                Start-Sleep -Milliseconds 500
                $clip = $null
                try { $clip = Get-Clipboard -Raw -ErrorAction Stop } catch { $clip = $null }
                if (-not [string]::IsNullOrWhiteSpace($clip)) {
                    $result.CopiedToClipboard = $true

                    # Sliced, not regexed: the report is "Error Message:" then
                    # the message then "Stack Trace:". A regex here is where an
                    # escaped newline can silently rot into a literal one.
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

                    try {
                        if (-not (Test-Path -LiteralPath $OutputDir)) {
                            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
                        }
                        $txtPath = Join-Path $OutputDir "load-error-$stamp.txt"
                        [System.IO.File]::WriteAllText($txtPath, $clip, (New-Object System.Text.UTF8Encoding($false)))
                        $result.DetailsPath = $txtPath
                    } catch { }
                }
            }
        } catch { }
        break
    }

    # The picture, as a fallback that works even when UIA publishes nothing.
    $imgPath = Join-Path $OutputDir "load-error-$stamp.png"
    try {
        $rect = $dlg.Current.BoundingRectangle
        $saved = Save-DialogImage -Rect $rect -Path $imgPath
        if ($saved) { $result.ScreenshotPath = $saved }
    } catch { }
    if (-not $result.ScreenshotPath -and -not $result.CopiedToClipboard -and -not $result.Text) {
        $result.Note = "Dialog found but neither its text nor a screenshot could be captured. Read it on screen."
    }

    if ($Dismiss) {
        foreach ($name in $script:DismissNames) {
            try {
                $cond = New-Object System.Windows.Automation.AndCondition(
                    (New-Object System.Windows.Automation.PropertyCondition(
                        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                        [System.Windows.Automation.ControlType]::Button)),
                    (New-Object System.Windows.Automation.PropertyCondition(
                        [System.Windows.Automation.AutomationElement]::NameProperty, $name))
                )
                $btn = $dlg.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
                if ($btn) {
                    $bp = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                    if ($bp) { $bp.Invoke(); $result.Dismissed = $true; Start-Sleep -Milliseconds 400; break }
                }
            } catch { }
        }
    }

    return $result
}

# --- Standalone entry point -------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    $res = Get-PbipLoadError -ProcessId $ProcessId -OutputDir $OutputDir -TimeoutSeconds $TimeoutSeconds -Dismiss:$Dismiss

    if ($Json) {
        $res | ConvertTo-Json -Depth 4 -Compress
        exit 0
    }

    if (-not $res.Found) {
        Write-Host "No load-error dialog found."
        if ($res.Note) { Write-Host "  $($res.Note)" }
        exit 1
    }

    Write-Host "Power BI Desktop load error (pid $($res.Pid), shell window '$($res.WindowTitle)')"
    Write-Host ("-" * 70)
    Write-Host "Dialog: $($res.Heading)"
    if ($res.Text) { Write-Host ""; Write-Host "On screen:"; Write-Host $res.Text }
    if ($res.ErrorMessage) {
        Write-Host ""
        Write-Host "Error message (from 'Copy details to clipboard'):"
        Write-Host $res.ErrorMessage
    }
    if ($res.DetailsPath) { Write-Host ""; Write-Host "Full diagnostic: $($res.DetailsPath)" }
    if ($res.ScreenshotPath) { Write-Host "Dialog image:    $($res.ScreenshotPath)" }
    if ($res.Dismissed) { Write-Host ""; Write-Host "Dialog dismissed." }
    if ($res.Note) { Write-Host ""; Write-Host $res.Note }
    exit 0
}
