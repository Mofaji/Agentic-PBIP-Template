[CmdletBinding()]
param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

$patterns = @("*.json", "*.pbip", "*.pbir", "*.pbism")
$files = Get-ChildItem -Path $Root -Recurse -File -Include $patterns

if (-not $files) {
    Write-Host "No JSON-based files found to validate."
    exit 0
}

$failed = @()
foreach ($file in $files) {
    try {
        $null = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
        Write-Host "OK: $($file.FullName)"
    }
    catch {
        Write-Error "Invalid JSON in $($file.FullName): $($_.Exception.Message)"
        $failed += $file.FullName
    }
}

if ($failed.Count -gt 0) {
    Write-Error "JSON validation failed for $($failed.Count) file(s)."
    exit 1
}

Write-Host "Validated $($files.Count) JSON-based file(s) successfully."
