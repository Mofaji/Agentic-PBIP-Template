<#
.SYNOPSIS
    Static semantic checks on PBIP source - the errors Power BI Desktop reports as a
    modal dialog at load time, caught before Desktop ever sees the file.

.DESCRIPTION
    The Desktop Bridge cannot read Desktop's "Issues were found" dialog: during a
    failed load there is no report to serve the API, and the dialog is WPF UI that no
    bridge method exposes. The answer is not to scrape the popup - it is to make the
    popup impossible, because every error in that class is visible in the source.

    Two tiers, deliberately:

      FILE-LOCAL   Always true regardless of what else is mid-write. Safe to run on
                   every edit from the PostToolUse hook.
                     - a measure and a column sharing a name in the same table
                       (exactly the error in the reported dialog)
                     - duplicate column names in a table
                     - duplicate measure names in a table

      CROSS-FILE   Only meaningful once the model is complete, so these run in the
                   verify loop before Desktop is opened - never per-edit, where a
                   half-written model would trip them constantly.
                     - measure names must be unique model-wide
                     - relationship endpoints pointing at a missing table or column
                     - qualified DAX references ('Table'[Column]) that do not resolve
                     - resource items referenced but never registered in report.json
                     - duplicate page ids in pages.json, or a page id with no folder

.EXAMPLE
    powershell -NoProfile -File scripts\Test-PbipSemantics.ps1
    powershell -NoProfile -File scripts\Test-PbipSemantics.ps1 -Path Template.SemanticModel\definition\tables\Sales.tmdl
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$Path,
    [switch]$Quiet
)

. (Join-Path $PSScriptRoot "PbipBridge.Common.ps1")

function Expand-TmdlName {
    # TMDL quotes a name only when it needs to. Compare unquoted.
    param([string]$Raw)
    if ($null -eq $Raw) { return "" }
    $n = $Raw.Trim()
    if ($n.Length -ge 2 -and $n.StartsWith("'") -and $n.EndsWith("'")) {
        $n = $n.Substring(1, $n.Length - 2).Replace("''", "'")
    }
    return $n.Trim()
}

function Remove-DaxNoise {
    <#
      Strips what would otherwise produce phantom references: double-quoted string
      literals, // and -- line comments. Length is preserved where it is cheap to do
      so, but callers only use this for pattern matching, not for column offsets.
    #>
    param([string]$Line)
    $s = $Line
    $s = [regex]::Replace($s, '"(?:[^"\\]|\\.)*"', '""')
    $s = [regex]::Replace($s, '//.*$', '')
    $s = [regex]::Replace($s, '--.*$', '')
    return $s
}

function ConvertFrom-Tmdl {
    <#
      Line-oriented TMDL reader. Deliberately not a full parser: it needs table,
      column, measure and relationship declarations, and nothing else.

      Fenced blocks (```) hold M partition source and Power Query expressions. Their
      syntax overlaps DAX enough to generate false positives, so they are skipped
      wholesale - a false alarm in a blocking hook costs far more than a missed check.
    #>
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $lines = @()
    try { $lines = [System.IO.File]::ReadAllLines($FilePath) } catch { return $null }

    $tables = New-Object System.Collections.Generic.List[object]
    $relationships = New-Object System.Collections.Generic.List[object]
    $refs = New-Object System.Collections.Generic.List[object]

    $current = $null
    $currentRel = $null
    $inFence = $false

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $lineNo = $i + 1
        $trimmed = $line.Trim()

        if ($trimmed -match '^```') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        if ($trimmed.Length -eq 0) { continue }

        # Declarations sit at column 0 (table, relationship) or one indent in
        # (measure, column). Anything deeper is a property or an expression body.
        if ($line -match '^table\s+(.+?)\s*$') {
            $current = [PSCustomObject]@{
                Name     = (Expand-TmdlName $Matches[1])
                Columns  = (New-Object System.Collections.Generic.List[object])
                Measures = (New-Object System.Collections.Generic.List[object])
                File     = $FilePath
                Line     = $lineNo
            }
            $tables.Add($current)
            $currentRel = $null
            continue
        }

        if ($line -match '^relationship\s+(.+?)\s*$') {
            $currentRel = [PSCustomObject]@{
                Name = $Matches[1].Trim(); FromTable = $null; FromColumn = $null
                ToTable = $null; ToColumn = $null; File = $FilePath; Line = $lineNo
            }
            $relationships.Add($currentRel)
            $current = $null
            continue
        }

        if ($currentRel -and $trimmed -match '^(fromColumn|toColumn)\s*:\s*(.+?)\s*$') {
            $which = $Matches[1]
            $value = $Matches[2].Trim()
            # 'Table Name'.Column or Table.Column
            if ($value -match "^'((?:[^']|'')+)'\.(.+)$" -or $value -match '^([^.]+)\.(.+)$') {
                $tbl = Expand-TmdlName $Matches[1]
                $col = Expand-TmdlName $Matches[2]
                if ($which -eq 'fromColumn') {
                    $currentRel.FromTable = $tbl; $currentRel.FromColumn = $col
                } else {
                    $currentRel.ToTable = $tbl; $currentRel.ToColumn = $col
                }
            }
            continue
        }

        if ($current -and $line -match '^[\t ]{1,8}(measure|column)\s+(.+?)\s*$') {
            $kind = $Matches[1]
            $rest = $Matches[2]

            # 'Name' = expr  /  Name = expr  /  Name
            $name = $rest
            $eq = -1
            $inQuote = $false
            for ($c = 0; $c -lt $rest.Length; $c++) {
                if ($rest[$c] -eq "'") { $inQuote = -not $inQuote }
                elseif ($rest[$c] -eq '=' -and -not $inQuote) { $eq = $c; break }
            }
            if ($eq -ge 0) { $name = $rest.Substring(0, $eq) }
            $name = Expand-TmdlName $name
            if ($name.Length -eq 0) { continue }

            $entry = [PSCustomObject]@{ Name = $name; Line = $lineNo; File = $FilePath }
            if ($kind -eq 'measure') { $current.Measures.Add($entry) } else { $current.Columns.Add($entry) }

            # A single-line measure carries its whole expression here, so the
            # reference scan below never sees it. Scan the right-hand side now.
            if ($eq -ge 0) {
                $expr = Remove-DaxNoise $rest.Substring($eq + 1)
                foreach ($m in [regex]::Matches($expr, "(?:'((?:[^']|'')+)'|(?<![\w\]])([A-Za-z_]\w*))\[([^\]\[]+)\]")) {
                    $rt = $m.Groups[1].Value
                    if ([string]::IsNullOrEmpty($rt)) { $rt = $m.Groups[2].Value }
                    $rt = Expand-TmdlName $rt
                    if ($rt.Length -eq 0) { continue }
                    $refs.Add([PSCustomObject]@{
                        Table = $rt; Item = (Expand-TmdlName $m.Groups[3].Value)
                        Line = $lineNo; File = $FilePath
                    })
                }
            }
            continue
        }

        # Qualified DAX references anywhere outside a fence.
        $clean = Remove-DaxNoise $line
        foreach ($m in [regex]::Matches($clean, "(?:'((?:[^']|'')+)'|(?<![\w\]])([A-Za-z_]\w*))\[([^\]\[]+)\]")) {
            $tbl = $m.Groups[1].Value
            if ([string]::IsNullOrEmpty($tbl)) { $tbl = $m.Groups[2].Value }
            $tbl = Expand-TmdlName $tbl
            if ($tbl.Length -eq 0) { continue }
            $refs.Add([PSCustomObject]@{
                Table = $tbl; Item = (Expand-TmdlName $m.Groups[3].Value)
                Line = $lineNo; File = $FilePath
            })
        }
    }

    return [PSCustomObject]@{ Tables = $tables; Relationships = $relationships; Refs = $refs }
}

function Test-TmdlFileLocal {
    <#
      Checks that hold no matter what else is half-written. Safe on every edit.
      Returns a string[] of problems, empty when clean.
    #>
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $problems = New-Object System.Collections.Generic.List[string]
    $parsed = ConvertFrom-Tmdl -FilePath $FilePath
    if (-not $parsed) { return @() }

    foreach ($t in $parsed.Tables) {
        $colNames = @{}
        foreach ($c in $t.Columns) {
            $key = $c.Name.ToLowerInvariant()
            if ($colNames.ContainsKey($key)) {
                $problems.Add("line $($c.Line): table '$($t.Name)' declares column '$($c.Name)' twice (first at line $($colNames[$key])).")
            } else {
                $colNames[$key] = $c.Line
            }
        }

        $measNames = @{}
        foreach ($m in $t.Measures) {
            $key = $m.Name.ToLowerInvariant()
            if ($measNames.ContainsKey($key)) {
                $problems.Add("line $($m.Line): table '$($t.Name)' declares measure '$($m.Name)' twice (first at line $($measNames[$key])).")
            } else {
                $measNames[$key] = $m.Line
            }

            # The exact failure Desktop reports as:
            #   "The '<name>' measure cannot be created because a column with the
            #    same name already exists."
            if ($colNames.ContainsKey($key)) {
                $problems.Add("line $($m.Line): measure '$($m.Name)' collides with the column of the same name in table '$($t.Name)' (column at line $($colNames[$key])). Power BI Desktop refuses to load the project with this - rename one of them.")
            }
        }
    }

    return @($problems)
}

function Test-PbipSemantics {
    <#
      Whole-project checks, for the point where the model is supposed to be complete.
      Returns @{ Ok; Errors[]; Warnings[]; Checked }.
    #>
    param([Parameter(Mandatory = $true)]$Project)

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $checked = 0

    # ---- Model side ---------------------------------------------------------
    $tables = @{}          # lower name -> @{ Name; Columns(hash); Measures(hash) }
    $allMeasures = @{}     # lower name -> "Table (file:line)"
    $allRefs = New-Object System.Collections.Generic.List[object]
    $allRels = New-Object System.Collections.Generic.List[object]

    if ($Project.SemanticModelDir) {
        $defDir = Join-Path $Project.SemanticModelDir "definition"
        if (Test-Path -LiteralPath $defDir) {
            $tmdlFiles = @(Get-ChildItem -LiteralPath $defDir -Recurse -File -Filter "*.tmdl" -ErrorAction SilentlyContinue)
            foreach ($f in $tmdlFiles) {
                $checked++
                foreach ($p in (Test-TmdlFileLocal -FilePath $f.FullName)) {
                    $errors.Add("$($f.Name) $p")
                }

                $parsed = ConvertFrom-Tmdl -FilePath $f.FullName
                if (-not $parsed) { continue }

                foreach ($t in $parsed.Tables) {
                    $key = $t.Name.ToLowerInvariant()
                    if (-not $tables.ContainsKey($key)) {
                        $tables[$key] = [PSCustomObject]@{
                            Name = $t.Name; Columns = @{}; Measures = @{}
                        }
                    }
                    foreach ($c in $t.Columns) { $tables[$key].Columns[$c.Name.ToLowerInvariant()] = $true }
                    foreach ($m in $t.Measures) {
                        $tables[$key].Measures[$m.Name.ToLowerInvariant()] = $true

                        # Measure names are unique across the whole model, not per table.
                        $mk = $m.Name.ToLowerInvariant()
                        $where = "$($t.Name) ($($f.Name):$($m.Line))"
                        if ($allMeasures.ContainsKey($mk)) {
                            $errors.Add("measure '$($m.Name)' is declared twice in the model: $($allMeasures[$mk]) and $where. Measure names must be unique model-wide.")
                        } else {
                            $allMeasures[$mk] = $where
                        }
                    }
                }
                foreach ($r in $parsed.Relationships) { $allRels.Add($r) }
                foreach ($r in $parsed.Refs) { $allRefs.Add($r) }
            }
        }
    }

    if ($tables.Count -gt 0) {
        foreach ($r in $allRels) {
            foreach ($end in @(@{ T = $r.FromTable; C = $r.FromColumn; Side = "fromColumn" },
                               @{ T = $r.ToTable;   C = $r.ToColumn;   Side = "toColumn" })) {
                if (-not $end.T) { continue }
                $tk = $end.T.ToLowerInvariant()
                if (-not $tables.ContainsKey($tk)) {
                    $errors.Add("$(Split-Path $r.File -Leaf):$($r.Line): relationship '$($r.Name)' $($end.Side) points at table '$($end.T)', which does not exist.")
                } elseif ($end.C -and -not $tables[$tk].Columns.ContainsKey($end.C.ToLowerInvariant())) {
                    $errors.Add("$(Split-Path $r.File -Leaf):$($r.Line): relationship '$($r.Name)' $($end.Side) points at '$($end.T)'[$($end.C)], which does not exist.")
                }
            }
        }

        # Qualified references only. Unqualified [X] is ambiguous between a measure,
        # a column of the current table, and M record access - not worth the false
        # positives in a gate that blocks work.
        $seen = @{}
        foreach ($ref in $allRefs) {
            $tk = $ref.Table.ToLowerInvariant()
            if (-not $tables.ContainsKey($tk)) { continue }   # could be a variable or an M step
            $ik = $ref.Item.ToLowerInvariant()
            if ($tables[$tk].Columns.ContainsKey($ik) -or $tables[$tk].Measures.ContainsKey($ik)) { continue }
            $sig = "$tk|$ik"
            if ($seen.ContainsKey($sig)) { continue }
            $seen[$sig] = $true
            $errors.Add("$(Split-Path $ref.File -Leaf):$($ref.Line): reference to '$($ref.Table)'[$($ref.Item)] does not resolve - table '$($tables[$tk].Name)' has no such column or measure.")
        }
    }

    # ---- Report side --------------------------------------------------------
    $reportJson = Join-Path $Project.ReportDir "definition\report.json"
    $registered = @{}
    if (Test-Path -LiteralPath $reportJson) {
        $checked++
        try {
            $rj = Get-Content -LiteralPath $reportJson -Raw | ConvertFrom-Json
            foreach ($pkg in @($rj.resourcePackages)) {
                foreach ($item in @($pkg.items)) {
                    if ($item.name) { $registered[[string]$item.name] = $true }
                }
            }
        } catch {
            $errors.Add("report.json could not be parsed: $($_.Exception.Message)")
        }
    }

    if ($registered.Count -gt 0) {
        $defRoot = Join-Path $Project.ReportDir "definition"
        $jsonFiles = @(Get-ChildItem -LiteralPath $defRoot -Recurse -File -Filter "*.json" -ErrorAction SilentlyContinue)
        $seenItem = @{}
        foreach ($f in $jsonFiles) {
            $text = ""
            try { $text = [System.IO.File]::ReadAllText($f.FullName) } catch { continue }
            foreach ($m in [regex]::Matches($text, '"ItemName"\s*:\s*"([^"]+)"')) {
                $item = $m.Groups[1].Value
                if ($registered.ContainsKey($item)) { continue }
                $sig = "$($f.Name)|$item"
                if ($seenItem.ContainsKey($sig)) { continue }
                $seenItem[$sig] = $true
                $errors.Add("$($f.Name): references resource item '$item', which is not registered in report.json resourcePackages. Desktop fails to load a project whose background or theme points at an unregistered resource.")
            }
        }
    }

    $pagesJson = Join-Path $Project.ReportDir "definition\pages\pages.json"
    if (Test-Path -LiteralPath $pagesJson) {
        $checked++
        try {
            $pj = Get-Content -LiteralPath $pagesJson -Raw | ConvertFrom-Json
            $order = @($pj.pageOrder)
            $seenPage = @{}
            foreach ($p in $order) {
                $k = [string]$p
                if ($seenPage.ContainsKey($k)) {
                    $errors.Add("pages.json: page id '$k' appears more than once in pageOrder.")
                } else {
                    $seenPage[$k] = $true
                }
                $folder = Join-Path (Split-Path $pagesJson -Parent) $k
                if (-not (Test-Path -LiteralPath $folder)) {
                    $errors.Add("pages.json: pageOrder lists '$k' but no folder of that name exists under definition/pages/.")
                }
            }
            if ($pj.activePageName -and -not $seenPage.ContainsKey([string]$pj.activePageName)) {
                $warnings.Add("pages.json: activePageName '$($pj.activePageName)' is not in pageOrder.")
            }
        } catch {
            $errors.Add("pages.json could not be parsed: $($_.Exception.Message)")
        }
    }

    return [PSCustomObject]@{
        Ok       = ($errors.Count -eq 0)
        Errors   = @($errors)
        Warnings = @($warnings)
        Checked  = $checked
    }
}

# --- Standalone entry point -------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    if ($Path) {
        $problems = @(Test-TmdlFileLocal -FilePath $Path)
        if ($problems.Count -eq 0) {
            if (-not $Quiet) { Write-Host "OK: no file-local semantic problems in $(Split-Path $Path -Leaf)" }
            exit 0
        }
        Write-Host "Semantic problems in $(Split-Path $Path -Leaf):"
        foreach ($p in $problems) { Write-Host "  - $p" }
        exit 1
    }

    $project = Get-PbipProject -RepoRoot $RepoRoot
    $res = Test-PbipSemantics -Project $project

    if (-not $Quiet) {
        Write-Host "PBIP semantic validation - $($project.ProjectName) ($($res.Checked) file(s) checked)"
        Write-Host ("-" * 60)
    }
    foreach ($w in $res.Warnings) { Write-Host "  [WARN]  $w" }
    foreach ($e in $res.Errors) { Write-Host "  [ERROR] $e" }

    if ($res.Ok) {
        if (-not $Quiet) { Write-Host "  clean" }
        exit 0
    }
    Write-Host ""
    Write-Host "$($res.Errors.Count) error(s). These are the failures Power BI Desktop reports as an 'Issues were found' dialog at load time."
    exit 1
}
