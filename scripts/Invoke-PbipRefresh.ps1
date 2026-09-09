<#
.SYNOPSIS
    Triggers a data refresh in a running Power BI Desktop via UI automation.

.DESCRIPTION
    A freshly generated PBIP carries no data cache, so import-mode partitions are
    schema-only until refreshed once. Desktop shows "Some of the tables have
    incomplete or no data." and every visual renders empty.

    The Desktop Bridge cannot do this: its manifest exposes only
    application.state.get/v1, report.snapshot.capture/v1 and file.reload/v1.
    None of them refresh data. So this drives the UI instead - first the
    "Refresh now" button in the warning banner, falling back to the Home
    ribbon's Refresh button.

    After a successful refresh, save in Desktop so .pbi/cache.abf persists and
    later opens come up with data already loaded.

.PARAMETER ProcessId
    Target PBIDesktop.exe pid. Defaults to the only running instance.

.PARAMETER TimeoutSeconds
    How long to wait for the refresh to finish.
#>
[CmdletBinding()]
param(
    [int]$ProcessId = 0,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

function Get-DesktopWindow {
    param([int]$TargetPid)   # not $Pid - that is a read-only automatic variable

    $procs = @(Get-Process -Name PBIDesktop -ErrorAction SilentlyContinue |
               Where-Object { $_.MainWindowHandle -ne 0 })
    if ($TargetPid -gt 0) { $procs = @($procs | Where-Object { $_.Id -eq $TargetPid }) }
    if ($procs.Count -eq 0) { throw "No Power BI Desktop window found." }

    return [System.Windows.Automation.AutomationElement]::FromHandle($procs[0].MainWindowHandle)
}

function Find-ByName {
    <# Depth-limited descendant search. The full Desktop tree is enormous, so a
       TreeScope::Descendants FindAll on Name alone can take minutes. #>
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string[]]$Names
    )

    $cond = [System.Windows.Automation.Condition]::TrueCondition
    $walker = New-Object System.Windows.Automation.TreeWalker $cond
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue(@{ El = $Root; Depth = 0 })

    while ($queue.Count -gt 0) {
        # The banner's "Refresh now" button sits at depth 14 in Desktop
        # 2.157.879.0, so anything shallower than ~16 silently finds nothing.
        $item = $queue.Dequeue()
        if ($item.Depth -gt 16) { continue }

        $el = $item.El
        try { $name = $el.Current.Name } catch { continue }

        foreach ($n in $Names) {
            if ($name -and $name.Trim() -eq $n) { return $el }
        }

        try { $child = $walker.GetFirstChild($el) } catch { continue }
        while ($child -ne $null) {
            $queue.Enqueue(@{ El = $child; Depth = $item.Depth + 1 })
            try { $child = $walker.GetNextSibling($child) } catch { break }
        }
    }
    return $null
}

function Invoke-Element {
    param([System.Windows.Automation.AutomationElement]$El)

    $invokePattern = [System.Windows.Automation.InvokePattern]::Pattern
    $obj = $null
    if ($El.TryGetCurrentPattern($invokePattern, [ref]$obj)) {
        $obj.Invoke()
        return $true
    }
    return $false
}

$win = Get-DesktopWindow -TargetPid $ProcessId
Write-Host "Target window: '$($win.Current.Name)'"

# "Refresh now" appears in the incomplete-data banner; "Refresh" is the Home
# ribbon button, present whether or not the banner is showing.
$btn = Find-ByName -Root $win -Names @("Refresh now", "Refresh")
if (-not $btn) { throw "Could not find a Refresh control in the Desktop window." }

Write-Host "Found control: '$($btn.Current.Name)' ($($btn.Current.ControlType.ProgrammaticName))"
if (-not (Invoke-Element -El $btn)) {
    throw "Refresh control does not support InvokePattern."
}
Write-Host "Refresh invoked; waiting for it to settle..."

# The refresh dialog appears and disappears; treat its absence plus a quiet
# window as done.
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$quiet = 0
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $dlg = Find-ByName -Root $win -Names @("Refresh")
    $banner = Find-ByName -Root $win -Names @("Refresh now")
    if (-not $banner) { $quiet++ } else { $quiet = 0 }
    if ($quiet -ge 3) {
        Write-Host "Refresh appears complete (banner gone)."
        exit 0
    }
}

Write-Warning "Timed out after $TimeoutSeconds s waiting for refresh to settle."
exit 1
