[CmdletBinding()]
param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

$patterns = @("*.json", "*.pbip", "*.pbir", "*.pbism")

# Only our own files. Dependency trees and build output are not ours to validate,
# and some third-party JSON legitimately fails here: eslint's globals.json has
# both "ai" and "AI" keys, which ConvertFrom-Json rejects as duplicates because
# PowerShell hashtables are case-insensitive.
$excluded = '[\\/](node_modules|dist|\.tmp|\.vscode|\.git)[\\/]'

# Two more that fail for reasons unrelated to PBIP:
#   package-lock.json  keys the root package on an empty string, which
#                      ConvertFrom-Json will not accept as a property name
#   tsconfig.json      is JSONC - comments are legal and TypeScript expects
#                      them, but ConvertFrom-Json rejects them
$excludedNames = @("package-lock.json", "tsconfig.json")

$files = Get-ChildItem -Path $Root -Recurse -File -Include $patterns |
    Where-Object { $_.FullName -notmatch $excluded -and $excludedNames -notcontains $_.Name }

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
