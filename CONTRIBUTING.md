# Contributing to PSAnthropic

Thank you for your interest in contributing to PSAnthropic!

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/christaylorcodes/PSAnthropic.git
   cd PSAnthropic
   ```

2. Install build dependencies:
   ```powershell
   ./build-sampler.ps1 -ResolveDependency -Tasks noop
   ```

3. Build the module:
   ```powershell
   ./build-sampler.ps1 -Tasks build
   ```

4. Run tests:
   ```powershell
   ./build-sampler.ps1 -Tasks test
   ```

## Pre-Push Validation

Before pushing changes, run the local validation script:

```powershell
./test-local.ps1
```

This runs build, PSScriptAnalyzer, and Pester tests to catch issues early.

## Pull Request Process

1. Create a feature branch from `main`
2. Make your changes
3. Update `CHANGELOG.md` under the `[Unreleased]` section
4. Run `./test-local.ps1` to validate your changes
5. Commit with a clear message describing the change
6. Open a pull request against `main`

## Code Style

- Follow existing patterns in the codebase
- Use 4-space indentation
- Add comment-based help to new public functions (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`)
- Run PSScriptAnalyzer before submitting

## Testing

- Add unit tests for new functions in `Tests/`
- Integration tests require Ollama running locally
- Use tags to categorize tests:
  - No tag: Unit tests (always run)
  - `Integration`: Requires external services
  - `Generative`: AI response validation (optional)

Quick test run (excludes integration tests):
```powershell
Invoke-Pester ./Tests -ExcludeTag Integration -Output Detailed
```

## Reporting Issues

- Use GitHub Issues to report bugs or request features
- Include PowerShell version (`$PSVersionTable`)
- Include steps to reproduce for bugs
- Include error messages if applicable

## Questions?

Open an issue for questions about contributing.
