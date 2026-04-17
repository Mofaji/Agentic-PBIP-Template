[CmdletBinding()]
param(
    [string]$Root = "."
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

$pbipPath = Join-Path $Root "Template.pbip"
Assert-PathExists -PathToTest $pbipPath -Description "PBIP entry file"

$pbip = Get-Content -Path $pbipPath -Raw | ConvertFrom-Json
if (-not $pbip.artifacts -or $pbip.artifacts.Count -eq 0) {
    throw "Template.pbip has no artifacts defined."
}

$reportRelativePath = $pbip.artifacts[0].report.path
if ([string]::IsNullOrWhiteSpace($reportRelativePath)) {
    throw "Template.pbip artifact report path is empty."
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
                $resourcePath = Join-Path (Join-Path $reportPath "StaticResources/$($package.name)") $item.path
                Assert-PathExists -PathToTest $resourcePath -Description "resource package item"
            }
        }
    }
}

Write-Host "PBIP structure validation completed successfully."
