# Tests

This directory contains both static validators and AI-executed markdown tests for PBIP quality checks.

## Structure

- `tests/prompts/PowerBI_Test.md`: prompt imported from your gist for Measure Killer-style PBIP testing
- `tests/prompts/Python_Data_Value_Test.md`: prompt for Python-based SQL value validation
- `tests/prompts/PBIP_Documentation_Page.md`: prompt to auto-generate a Documentation page with SVG canvas background from PBIP metadata
- `tests/python/README.md`: instruction guide for users to create their own preferred Python validator
- `tests/results/test_results.md`: latest AI test output
- `tests/results/latest_run.json`: latest run metadata
- `tests/results/history/`: timestamped markdown result history

## Local Execution

Run deterministic validators first:

```powershell
./scripts/validate-json.ps1
./scripts/validate-pbip.ps1
```

Run AI markdown test execution:

```powershell
./scripts/run-ai-md-test.ps1 -PromptFile tests/prompts/PowerBI_Test.md -OutputDir tests/results -OutputFileName test_results.md -IncludeBpaRules
```

Run documentation-page generation prompt:

```powershell
./scripts/run-ai-md-test.ps1 -PromptFile tests/prompts/PBIP_Documentation_Page.md -OutputDir tests/results -OutputFileName documentation_page_run.md
```

## Python-Based Data Value Testing

This section validates numeric dashboard values against SQL source data in CLI.

By design, this starter pack does not enforce one fixed Python script. Each team can build its own validator implementation in `tests/python/`.

Example target scenario:
- Sales of branch `ABV` in March 2026

Run Python directly:

```powershell
python tests/python/<your_script_name>.py --branch ABV --month March --year 2026
```

Dry-run mode (no SQL execution):

```powershell
python tests/python/<your_script_name>.py --branch ABV --month March --year 2026 --dry-run
```

Output files:
- `tests/results/python_value_validation.md`
- `tests/results/python_value_validation.json`
- `tests/results/history/python_value_validation_<timestamp>.md`

If no API key is configured, the runner writes a skipped-mode result file so pipelines still produce traceable output.

## Credentials for AI Execution

Set one of these before running AI tests:

- `GITHUB_MODELS_API_KEY`
- `AZURE_OPENAI_API_KEY`

## CI Integration

Workflow:
- `.github/workflows/ai-testing.yml`

Behavior:
- Runs automatically on pushes to `test`
- Can be run manually with model selection
- Uploads `tests/results/**` as workflow artifacts
- Optionally commits results back to `test` when `AI_TEST_COMMIT_RESULTS=true`
