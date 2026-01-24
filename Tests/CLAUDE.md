# Tests CLAUDE.md

Testing guidance for PSAnthropic.

## Running Tests

```powershell
# All tests
Invoke-Pester ./Tests -Output Detailed

# Skip integration tests (no Ollama needed)
Invoke-Pester ./Tests -ExcludeTag Integration -Output Detailed

# Only integration tests
Invoke-Pester ./Tests -Tag Integration -Output Detailed
```

## Test Structure

- **Unit tests** - Mock API responses, test parameter validation, output structure
- **Integration tests** - Require Ollama running on `localhost:11434`
- **Generative tests** - Use LLM to explore edge cases (tagged `Integration, Generative`)

## Pester BeforeDiscovery vs BeforeAll

**Critical gotcha:** Variables set in `BeforeDiscovery` are only available for `-Skip` expressions during test discovery. They do NOT persist to test runtime.

### The Problem

```powershell
BeforeDiscovery {
    $script:VisionModel = 'llama3.2-vision:11b'  # Set here
}

It 'test' -Skip:(-not $script:VisionModel) {  # Works for skip
    Connect-Anthropic -Model $script:VisionModel  # FAILS - $script:VisionModel is empty!
}
```

### The Solution

If a test needs both conditional skip AND runtime access to a value, detect in both places:

```powershell
BeforeDiscovery {
    # For -Skip expressions only (evaluated at discovery time)
    $script:VisionModelAvailable = $false
    try {
        $response = Invoke-RestMethod -Uri 'http://localhost:11434/api/tags' -TimeoutSec 2
        $script:VisionModelAvailable = ($response.models | Where-Object { $_.name -match 'vision' }).Count -gt 0
    } catch { }
}

Describe 'Integration Tests' {
    BeforeAll {
        # For test runtime - must detect again here
        $script:VisionModel = $null
        $response = Invoke-RestMethod -Uri 'http://localhost:11434/api/tags' -ErrorAction SilentlyContinue
        if ($response) {
            $match = $response.models | Where-Object { $_.name -match 'vision' } | Select-Object -First 1
            $script:VisionModel = $match.name  # Now available in tests
        }
    }

    It 'Should process image' -Skip:(-not $script:VisionModelAvailable) {
        # $script:VisionModel is available here (set in BeforeAll)
        Connect-Anthropic -Model $script:VisionModel -Force
    }
}
```

### Why This Happens

Pester 5 evaluates `-Skip` expressions during **discovery phase** (before any BeforeAll runs). The discovery phase and run phase have separate variable scopes. BeforeDiscovery runs during discovery; BeforeAll runs during execution.

## Test Images

Located in `Tests/TestImages/`:

| File | Content | Used For |
|------|---------|----------|
| `cat.jpg` | Orange/white cat | Single animal detection |
| `dog.jpg` | Beagle | Single animal detection |
| `cat-and-dog.jpg` | Cat and corgi together | Multiple animal detection |

Vision tests auto-skip if no vision model is installed. Detection pattern: `llava|vision|moondream|bakllava`

## Mocking Patterns

```powershell
# Mock the HTTP layer
Mock Invoke-AnthropicWebRequest -ModuleName PSAnthropic {
    @{
        StatusCode = 200
        Content = '{"id":"msg_test","content":[{"type":"text","text":"mocked"}],"stop_reason":"end_turn"}'
    }
}

# Mock for tool use response
Mock Invoke-AnthropicWebRequest -ModuleName PSAnthropic {
    @{
        StatusCode = 200
        Content = '{"id":"msg_test","content":[{"type":"tool_use","id":"toolu_123","name":"get_current_time","input":{}}],"stop_reason":"tool_use"}'
    }
}
```

## Integration Test Requirements

- Ollama running on `localhost:11434`
- At least one model pulled (tests auto-detect available models)
- For image tests: a vision model (`ollama pull llama3.2-vision`)

## Common Test Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| All integration tests skipped | Ollama not running | Start Ollama |
| Image tests skipped | No vision model | `ollama pull llava` or `llama3.2-vision` |
| "Cannot convert type" errors | Module reloaded mid-test | Use `-Force` on Import-Module |
| Vision model empty at runtime | BeforeDiscovery/BeforeAll scoping | Set variable in both places |
| LLM test flaky | Non-deterministic responses | Use flexible assertions (`-Match` with alternatives) |

## Adding New Tests

1. Unit tests go in the main `Describe` blocks (no tag needed)
2. Integration tests need `-Tag 'Integration'` and skip condition
3. Use `$TestDrive` for temporary files
4. Clean up connections in `AfterAll`

## Test Quality Guidelines

### What Makes a Good Test

A good test catches **real bugs** that could break the module. Ask: "If this test fails, does it mean something is actually broken?"

#### ✅ Good Test Patterns

```powershell
# Tests exact structure the API requires
$result.content[0].type | Should -Be 'tool_result'
$result.content[0].tool_use_id | Should -Be 'toolu_123'

# Tests validation logic that prevents bad input
{ New-AnthropicMessage -Role 'system' -Content 'test' } | Should -Throw

# Tests security boundaries
$result | Should -Match 'Web fetch is disabled'

# Tests edge cases that could cause runtime errors
$response = [PSCustomObject]@{ content = @() }
$response | Get-AnthropicResponseText | Should -BeNullOrEmpty
```

#### ❌ Test Theater (Avoid)

```powershell
# Hardcoded counts - breaks when implementation changes
$tools.Count | Should -Be 8  # BAD: fragile

# Only checks property exists, not correctness
$result.PSObject.Properties.Name | Should -Contain 'IsReachable'  # BAD: doesn't test value

# Partial list that gets outdated
$expectedFunctions = @('Connect-Anthropic', ...)  # BAD: incomplete list

# Vague assertions on LLM output
$text | Should -Match 'file'  # BAD: too broad
```

### Writing Robust LLM Tests

LLM responses are non-deterministic. Design tests that:

1. **Test behavior, not exact words**: Check if tool was called, not exact phrasing
2. **Use flexible patterns**: `'(?i)cat|feline|kitty'` instead of `'cat'`
3. **Assert on structure**: `$response.stop_reason -eq 'tool_use'`
4. **Avoid testing content generation**: LLM creativity tests are demos, not regressions

```powershell
# GOOD: Tests that LLM uses the correct tool
$toolUse.name | Should -Be 'get_current_time'

# GOOD: Tests tool loop completes
$response.stop_reason | Should -Be 'end_turn'

# BAD: Tests LLM's word choice (non-deterministic)
$text | Should -Match 'three'  # Could say "3" or "three lines"
```

### Dynamic vs Hardcoded Values

```powershell
# BAD: Hardcoded count
$tools.Count | Should -Be 8

# GOOD: Dynamic based on source of truth
$allTools = Get-AnthropicStandardTools
$shellTools = Get-AnthropicStandardTools -ToolSet Shell
$shellTools.Count | Should -BeLessThan $allTools.Count

# BAD: Partial list of functions
$exportedFunctions | Should -Contain 'Connect-Anthropic'  # Missing 24 others

# GOOD: Get expected from manifest
$manifest = Import-PowerShellDataFile ../PSAnthropic/PSAnthropic.psd1
$manifest.FunctionsToExport | ForEach-Object {
    $exportedFunctions | Should -Contain $_
}
```

### Testing Error Conditions

```powershell
# Test that errors are thrown for invalid input
{ New-AnthropicTool -Name '123invalid' ... } | Should -Throw

# Test error messages are helpful (use -Because for context)
{ Connect-Anthropic -Server '' } | Should -Throw '*cannot be empty*'

# Test graceful handling of edge cases
$result = Invoke-AnthropicStandardTool -ToolUse @{ name = 'nonexistent' }
$result | Should -Match 'Unknown tool'  # Graceful error, not exception
```

### Test Categories

| Category | Purpose | Tag |
| -------- | ------- | --- |
| Unit | Test function logic in isolation | (none) |
| Integration | Test real API interactions | `Integration` |
| Generative | Explore LLM behavior (demo/exploratory) | `Integration, Generative` |

Generative tests are valuable for **discovering** edge cases during development, but shouldn't be the primary regression tests - they're too non-deterministic.
