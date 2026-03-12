# AGENTS.md

This file provides context for AI coding agents (Claude Code, GitHub Copilot, Cursor, Windsurf, Codex, and others) working in this repository.

## Project Overview

**PSAnthropic** is a PowerShell module that provides a client for the Anthropic Messages API, hosted at <https://github.com/christaylorcodes/PSAnthropic>.

- **Language**: PowerShell 7.0+
- **Build System**: Sampler + ModuleBuilder
- **Test Framework**: Pester 5.6+
- **Linter**: PSScriptAnalyzer
- **License**: MIT

Works with Ollama (via Anthropic compatibility layer), Anthropic Cloud, and any Anthropic-compatible endpoint.

## Quick Start

```powershell
# Bootstrap dependencies (required first time)
./build-sampler.ps1 -ResolveDependency -Tasks noop

# Run full pipeline (build + test)
./build-sampler.ps1

# Local pre-push validation (build + analyze + test)
./test-local.ps1
```

## Build Commands

All commands require **PowerShell 7.0+** and use Sampler as the task runner.

```powershell
# Individual tasks
./build-sampler.ps1 -Tasks build       # Build module to output/
./build-sampler.ps1 -Tasks test        # Run Pester tests
./build-sampler.ps1 -Tasks pack        # Package as .nupkg

# Documentation
./build-docs.ps1                        # Generate/update platyPS docs

# Local validation (build + analyze + test)
./test-local.ps1
```

## Architecture

### Directory Layout

```
PSAnthropic/
  PSAnthropic/
    PSAnthropic.psd1          # Module manifest (lists all exported functions)
    PSAnthropic.psm1          # Root module (dot-sources Public/ and Private/)
    Classes.ps1               # Type definitions (loaded via ScriptsToProcess)
    Public/                   # Exported functions (25 total)
      Authentication/         # Connect-Anthropic, Disconnect-Anthropic
      Content/                # New-AnthropicImageContent
      Invoke/                 # Invoke-AnthropicMessage, Invoke-AnthropicWebRequest
      Messages/               # New-AnthropicMessage, New-AnthropicConversation, Add-AnthropicMessage
      Router/                 # Set/Get/Clear-AnthropicRouterConfig, Invoke-AnthropicRouted, Get-AnthropicRouterLog
      Tools/                  # New-AnthropicTool*, Get/Invoke-AnthropicStandardTool*
      Utility/                # Get-AnthropicConnection/Model, Test-AnthropicEndpoint, Clear-AnthropicRunspaceCache
    Private/                  # Internal helpers (not exported)
      Helper/                 # URL building, validation, safe execution
      Invoke/                 # Invoke-AnthropicStreamRequest (SSE)
      Router/                 # Write-AnthropicRouterLog
  Tests/
    PSAnthropic.Tests.ps1     # Main test suite (91+ tests)
    TestImages/               # Test images for vision tests
    TestScenarios/            # Complex test scenarios
  docs/                       # Documentation and cmdlet help
    en-US/                    # Auto-generated cmdlet help (24 .md files)
  Example/                    # Usage examples
  output/                     # Build output (gitignored)
```

### Module Loading Order

The `.psm1` loads `Classes.ps1` first (also via `ScriptsToProcess` in manifest), then dot-sources `Private/*.ps1` and `Public/*.ps1` recursively. Only Public functions are exported via `Export-ModuleMember`. Argument completers are registered at load time.

### Connection State

Connection info is stored in `$script:AnthropicConnection`. This hashtable contains Server, Model, Headers (auth), and ConnectedAt. Router config is stored in `$script:AnthropicRouterConfig` when configured.

All API-calling functions validate the connection exists via `Assert-AnthropicConnection`.

### Streaming Implementation

Streaming uses `System.Net.Http.HttpClient` directly (in `Invoke-AnthropicStreamRequest`) to parse Server-Sent Events (SSE). Events are output as they arrive, not buffered. PowerShell's `Invoke-RestMethod` buffers the entire response, which is why HttpClient is used directly.

### Build System

- `build-sampler.ps1` — entry point, resolves dependencies via Sampler
- `build.yaml` — ModuleBuilder + Sampler task configuration
- `RequiredModules.psd1` — build dependency specifications
- Build output goes to `output/PSAnthropic/{version}/`

### Test Framework

- Pester 5.6+ with tag-based test filtering
- Tags: (none) = unit tests, `Integration` = requires Ollama, `Generative` = AI response validation
- Test results: NUnit format to `output/testResults/testResults.xml`

### CI/CD

- `ci.yml` — Build, Test (Ubuntu + Windows matrix), Analyze, Publish on tag push
- `pr-validation.yml` — CHANGELOG.md update check on PRs

## Key Patterns

- Functions use `Connect-Anthropic` connection state; check `$script:AnthropicConnection` before API calls
- Parameter resolution order: explicit parameter → environment variable → default
- Environment variables: `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`
- Retry logic with exponential backoff for 5xx errors in `Invoke-AnthropicWebRequest`
- All exported functions listed explicitly in the manifest (no wildcards)
- Response enrichment: `.Answer`, `.History`, `.ToolUse` convenience properties on API responses

## Code Conventions

Enforced by PSScriptAnalyzer (`PSScriptAnalyzerSettings.psd1`) and `.editorconfig`:

- 4-space indentation (spaces, not tabs)
- Open braces on same line (`if ($true) {`)
- Single quotes for constants, double quotes only for interpolation
- Approved verbs only (`Get-Verb`)
- Comment-based help required before all exported functions
- `[CmdletBinding()]` and `[OutputType()]` on all functions

### Git Commit Style

- Present tense, imperative mood ("Add feature" not "Added feature")
- Max 72 characters on first line
- Reference issues with `#123` after the first line

## Adding New Functions

1. Create the function file in `PSAnthropic/Public/Category/Verb-Noun.ps1`
2. Add comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`)
3. Use `Assert-AnthropicConnection` at start of functions that call the API
4. Add `[CmdletBinding()]` and `[OutputType()]` attributes
5. Update `PSAnthropic.psd1` FunctionsToExport list
6. Add tests in `Tests/PSAnthropic.Tests.ps1`
7. Run `./test-local.ps1` before committing

## Testing Workflow

```powershell
# Import module for development
Import-Module ./PSAnthropic/PSAnthropic -Force

# Run all unit tests
Invoke-Pester ./Tests -ExcludeTag Integration -Output Detailed

# Run specific test
Invoke-Pester ./Tests -Filter "Test Name" -Output Detailed

# Run integration tests (requires Ollama running)
Invoke-Pester ./Tests -Tag Integration -Output Detailed

# Full pipeline
./test-local.ps1
```

## Common Mistakes

### Wrong: Inline hashtables instead of New-AnthropicMessage

```powershell
# WRONG - missing required structure, may fail silently
Invoke-AnthropicMessage -Messages @{ role = 'user'; content = 'Hi' }

# CORRECT - always use New-AnthropicMessage for input
Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Hi'
)
```

### Wrong: Ignoring tool_use stop_reason

```powershell
# WRONG - $response.Answer may be empty when model wants to use tools
$response = Invoke-AnthropicMessage -Messages $msgs -Tools $tools
Write-Output $response.Answer

# CORRECT - always check stop_reason when using tools
if ($response.stop_reason -eq 'tool_use') {
    # Handle tool call
} else {
    Write-Output $response.Answer
}
```

### Wrong: Not connecting before API calls

```powershell
# WRONG - throws AnthropicConnectionException
$response = Invoke-AnthropicMessage -Messages $msgs

# CORRECT - connect first
Connect-Anthropic -Server 'localhost:11434' -Model 'llama3'
$response = Invoke-AnthropicMessage -Messages $msgs
```

### Wrong: Assigning streaming output to variable

```powershell
# WRONG - $response contains all events, not a single response object
$response = Invoke-AnthropicMessage -Messages $msgs -Stream

# CORRECT - process events as they arrive
Invoke-AnthropicMessage -Messages $msgs -Stream | ForEach-Object {
    if ($_.type -eq 'content_block_delta') {
        Write-Host $_.delta.text -NoNewline
    }
}
```

### Wrong: Forgetting assistant message in tool loop

```powershell
# WRONG - missing assistant message, breaks conversation structure
$messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $result

# CORRECT - include both assistant response AND tool result
$messages += @{ role = 'assistant'; content = $response.content }
$messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $result
```

## Quick Reference

| Need to... | Use | Returns |
|------------|-----|---------|
| Start a session | `Connect-Anthropic` | void (sets `$script:AnthropicConnection`) |
| Send a message | `Invoke-AnthropicMessage -Messages $msgs` | PSCustomObject (API response) |
| Extract text | `$response.Answer` or `Get-AnthropicResponseText` | string |
| Continue conversation | `$response.History + @(New-AnthropicMessage ...)` | array |
| Create message | `New-AnthropicMessage -Role 'user' -Content 'text'` | AnthropicMessage |
| Give model tools | `-Tools (Get-AnthropicStandardTools)` | - |
| Execute tool request | `Invoke-AnthropicStandardTool -ToolUse $response.ToolUse` | string |
| Check if model wants tools | `$response.stop_reason -eq 'tool_use'` | bool |
| Create tool from cmdlet | `New-AnthropicToolFromCommand -CommandName 'Get-Process'` | hashtable |
| Send tool result back | `New-AnthropicToolResult -ToolUseId $id -Content $result` | hashtable |

## Design Decisions

**Why `[object[]]` instead of `[AnthropicMessage[]]` in Invoke-AnthropicMessage:**
PowerShell has type identity conflicts when modules are reloaded during development. Using `[object[]]` with runtime validation avoids "cannot convert type" errors during iterative development.

**Why SSE streaming uses HttpClient directly:**
PowerShell's `Invoke-RestMethod` buffers the entire response before returning. We need `System.Net.Http.HttpClient` for byte-level control to parse `data:` prefixed SSE lines as they arrive.

**Why tool results use hashtables not classes:**
The API expects exact JSON structure. Hashtables serialize predictably via `ConvertTo-Json`, while classes may include unwanted properties or have serialization quirks.

**Why runspaces are cached in Invoke-SafeCommand:**
Creating constrained runspaces is expensive (~100ms). We cache the runspace and reuse across tool invocations for performance.

**Why response enrichment adds .History, .Answer, .ToolUse:**
These convenience properties eliminate common boilerplate. Without them, every consumer would need to implement the same extraction logic.

## AI Contribution Workflow

### Finding Work

```powershell
gh issue list --label ai-ready --state open
gh issue list --label "good-first-issue" --state open
```

### Issue Labels

| Label | Meaning |
| ----- | ------- |
| `ai-task` | Issue is structured with acceptance criteria for AI agents |
| `ai-ready` | Task is available — no one is working on it |
| `ai-in-progress` | An agent has claimed this and is actively working |
| `ai-review` | PR submitted, awaiting human review |
| `ai-blocked` | Agent needs human input to proceed |

### Claiming an Issue

```powershell
gh issue edit <number> --add-label ai-in-progress --remove-label ai-ready
```

### Working on an Issue

1. Claim the issue (see above)
2. Create a feature branch: `git checkout -b feature/issue-number-short-description`
3. Read the full issue body, requirements, and acceptance criteria
4. Implement and test
5. Run `./test-local.ps1` to validate
6. Commit with a message referencing the issue: `Add feature X (fixes #123)`
7. Push and open a pull request
8. Update the issue label to `ai-review`

### PR Requirements

- All CI checks must pass (build, test, analyze)
- Tests must cover new or changed functionality
- PSScriptAnalyzer must report zero errors
- PR description must reference the issue being addressed
- CHANGELOG.md updated under `[Unreleased]`

### What AI Agents Should NOT Do

- Do not modify CI workflow files without explicit instruction
- Do not add new dependencies without discussing in an issue first
- Do not commit secrets, credentials, or API keys
- Do not push directly to `main` — always use pull requests

## Modification Checklist

When modifying this module:

- [ ] Update `PSAnthropic.psd1` FunctionsToExport if adding/removing public functions
- [ ] Add comment-based help (`.SYNOPSIS`, `.PARAMETER`, `.EXAMPLE`) to new functions
- [ ] Use `Assert-AnthropicConnection` at start of functions that need connection
- [ ] Add `[CmdletBinding()]` and `[OutputType()]` attributes
- [ ] Run `Invoke-Pester ./Tests -ExcludeTag Integration` before committing
- [ ] Run `./test-local.ps1` for full validation
- [ ] Update CHANGELOG.md under `[Unreleased]`
- [ ] Update this AGENTS.md if adding new patterns or workflows
