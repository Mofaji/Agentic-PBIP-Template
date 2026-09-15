[CmdletBinding()]
param(
    [string]$Root = ".",
    # Name of the .pbip entry file. Omit to validate every .pbip found under $Root.
    [string]$Project
)

$ErrorActionPreference = "Stop"

function Assert-PathExists {
    param(
        [Parameter(Mandatory = $true)][string]$PathToTest,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not (Test-Path -Path $PathToTest)) {
        throw "Missing $Description at path: $PathToTest"
    }
}

function Get-ResourceItemPath {
    <#
        Resolves where a report.json resourcePackages item actually lives on disk.

        Most package types sit under StaticResources/<packageName>/<item.path>, but
        custom visuals do NOT: Power BI writes them to CustomVisuals/<guid>/resources/.
        Validating those against StaticResources throws on any report that embeds a
        .pbiviz, which is why this function exists rather than one hardcoded join.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ReportPath,
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)]$Item
    )

    if ($Package.type -eq "CustomVisual") {
        return (Join-Path (Join-Path $ReportPath "CustomVisuals/$($Package.name)/resources") $Item.path)
    }

    return (Join-Path (Join-Path $ReportPath "StaticResources/$($Package.name)") $Item.path)
}

function Test-PbipProject {
    param(
        [Parameter(Mandatory = $true)][string]$PbipPath,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $pbipName = Split-Path $PbipPath -Leaf

    $pbip = Get-Content -Path $PbipPath -Raw | ConvertFrom-Json
    if (-not $pbip.artifacts -or $pbip.artifacts.Count -eq 0) {
        throw "$pbipName has no artifacts defined."
    }

    $reportRelativePath = $pbip.artifacts[0].report.path
    if ([string]::IsNullOrWhiteSpace($reportRelativePath)) {
        throw "$pbipName artifact report path is empty."
    }

    $reportPath = Join-Path $Root $reportRelativePath
    Assert-PathExists -PathToTest $reportPath -Description "report folder"

    $pbirPath = Join-Path $reportPath "definition.pbir"
    Assert-PathExists -PathToTest $pbirPath -Description "report definition file"
    $pbir = Get-Content -Path $pbirPath -Raw | ConvertFrom-Json

    $datasetRelativePath = $pbir.datasetReference.byPath.path
    if ([string]::IsNullOrWhiteSpace($datasetRelativePath)) {
        throw "definition.pbir is missing datasetReference.byPath.path"
    }

    $semanticModelPath = Resolve-Path -Path (Join-Path $reportPath $datasetRelativePath)
    if (-not $semanticModelPath) {
        throw "Semantic model path could not be resolved from definition.pbir"
    }

    $requiredPaths = @(
        (Join-Path $reportPath "definition/report.json"),
        (Join-Path $reportPath "definition/pages/pages.json"),
        (Join-Path $semanticModelPath "definition/database.tmdl"),
        (Join-Path $semanticModelPath "definition/model.tmdl")
    )

    foreach ($path in $requiredPaths) {
        Assert-PathExists -PathToTest $path -Description "required PBIP artifact"
    }

    $reportDefinition = Get-Content -Path (Join-Path $reportPath "definition/report.json") -Raw | ConvertFrom-Json
    if ($reportDefinition.resourcePackages) {
        foreach ($package in $reportDefinition.resourcePackages) {
            if ($package.items) {
                foreach ($item in $package.items) {
                    $resourcePath = Get-ResourceItemPath -ReportPath $reportPath -Package $package -Item $item
                    Assert-PathExists -PathToTest $resourcePath -Description "$($package.type) resource package item"
                }
            }
        }
    }

    # A custom visual is only usable if all three of these line up: the payload on
    # disk, the report.json registration, and the visual.json visualType. The first
    # two are checked above; this checks the third, which otherwise fails silently
    # at render time as a blank visual with no diagnostic.
    $customVisualGuids = @()
    if ($reportDefinition.resourcePackages) {
        $customVisualGuids = @(
            $reportDefinition.resourcePackages |
                Where-Object { $_.type -eq "CustomVisual" } |
                ForEach-Object { $_.name }
        )
    }
    # Third-party marketplace visuals are not embedded: Desktop lists
    # them under publicCustomVisuals and fetches the bundle itself.
    if ($reportDefinition.publicCustomVisuals) {
        $customVisualGuids += @($reportDefinition.publicCustomVisuals)
    }

    $pagesDir = Join-Path $reportPath "definition/pages"
    if (Test-Path $pagesDir) {
        foreach ($visualFile in Get-ChildItem -Path $pagesDir -Filter "visual.json" -Recurse -File) {
            $visual = Get-Content -Path $visualFile.FullName -Raw | ConvertFrom-Json
            $visualType = $visual.visual.visualType
            if ([string]::IsNullOrWhiteSpace($visualType)) { continue }

            # A guid-shaped visualType (name + 32 hex chars) is a custom visual reference.
            if ($visualType -match '^[A-Za-z][A-Za-z0-9]*[0-9A-F]{32}$') {
                if ($customVisualGuids -notcontains $visualType) {
                    throw "Visual '$($visualFile.Directory.Name)' references custom visual '$visualType', which is not registered in report.json resourcePackages or publicCustomVisuals."
                }
            }
        }
    }

    Write-Host "  OK: $pbipName"
}

# The template ships as "Template.pbip" but gets renamed downstream, and a folder
# may hold more than one project. Discover rather than hardcode.
if ($Project) {
    if (-not $Project.EndsWith(".pbip")) { $Project = "$Project.pbip" }
    $pbipPath = Join-Path $Root $Project
    Assert-PathExists -PathToTest $pbipPath -Description "PBIP entry file"
    $pbipFiles = @($pbipPath)
} else {
    $pbipFiles = @(Get-ChildItem -Path $Root -Filter "*.pbip" -File | ForEach-Object { $_.FullName })
    if ($pbipFiles.Count -eq 0) {
        throw "No .pbip entry file found under: $((Resolve-Path $Root).Path)"
    }
}

foreach ($pbipFile in $pbipFiles) {
    Test-PbipProject -PbipPath $pbipFile -Root $Root
}

Write-Host "PBIP structure validation completed successfully."
