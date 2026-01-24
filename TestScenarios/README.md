# Test Scenarios for LLM Debugging

This directory contains intentionally buggy code for testing LLM tool use and debugging capabilities.

## BuggyCalculator

A multi-file PowerShell project with various bugs across 4 files:

### File Structure
```
BuggyCalculator/
├── Calculator.ps1      # Main entry point (3 bugs)
├── MathOperations.ps1  # Math functions (7 bugs)
├── Validation.ps1      # Input validation (7 bugs)
├── Config.ps1          # Configuration (6 bugs)
└── Calculator.Tests.ps1 # Pester tests (most fail)
```

### Bug Summary

| File | Bug Type | Description |
|------|----------|-------------|
| Calculator.ps1 | Logic | Validation result is ignored |
| Calculator.ps1 | Logic | MaxValue from config never enforced |
| Calculator.ps1 | Typo | `Prcision` instead of `Precision` |
| MathOperations.ps1 | Off-by-one | Add-Numbers adds 1 extra |
| MathOperations.ps1 | Logic | Subtract-Numbers has swapped params |
| MathOperations.ps1 | Type | Divide-Numbers uses integer division |
| MathOperations.ps1 | Edge case | Divide-Numbers no zero check |
| MathOperations.ps1 | Recursion | Get-Factorial missing base case for 0 |
| MathOperations.ps1 | Edge case | Get-Average no empty array check |
| MathOperations.ps1 | Logic | Get-Percentage formula inverted |
| Validation.ps1 | Logic | Comparison operators swapped |
| Validation.ps1 | Typo | $b vs $B variable name |
| Validation.ps1 | Logic | Returns $true even with errors |
| Validation.ps1 | Edge case | Zero not handled in IsPositive |
| Validation.ps1 | Edge case | Null not handled in ArrayNotEmpty |
| Validation.ps1 | String | Format-ValidationError missing bracket |
| Config.ps1 | Typo | Key misspelled `Prcision` |
| Config.ps1 | Type | MaxValue is string not number |
| Config.ps1 | Type | EnableLogging is "true" not $true |
| Config.ps1 | Logic | Set-Config doesn't validate keys |
| Config.ps1 | Logic | Reset-Config uses different values |
| Config.ps1 | Coercion | Test-ConfigValue uses -eq coercion |

### Testing with LLM Tools

Use these scenarios to test tool capabilities:

1. **read_file** - Read each file to understand the code
2. **search_content** - Search for patterns like "BUG" comments
3. **list_directory** - Explore the file structure
4. **str_replace_editor** - View specific line ranges
5. **pwsh** - Run the Pester tests to see failures

### Example Prompts

```
"Read Calculator.ps1 and find all the bugs"

"Search for 'BUG' comments in the BuggyCalculator folder"

"Run the Pester tests and explain why they fail"

"What's wrong with the Add-Numbers function in MathOperations.ps1?"

"Trace through Invoke-Calculator and identify all issues across files"

"Compare the config keys between Config.ps1 and Calculator.ps1"
```

### Running Tests

```powershell
cd TestScenarios/BuggyCalculator
Invoke-Pester Calculator.Tests.ps1 -Output Detailed
# Most tests will fail due to intentional bugs
```

---

## BrokenApiClient

A more complex multi-file scenario simulating an API client with chained dependencies:

### File Structure
```
BrokenApiClient/
├── ApiClient.ps1     # Main client (4 bugs)
├── HttpHelpers.ps1   # HTTP utilities (6 bugs)
├── JsonParser.ps1    # JSON handling (8 bugs)
└── AuthManager.ps1   # Authentication (10 bugs)
```

### Bug Categories

**Cross-File Issues:**
- ApiClient gets auth token but never uses it
- URL joining creates double slashes
- JSON parsing doesn't handle edge cases

**Security Issues (AuthManager.ps1):**
- Tokens stored in plain text
- Credentials not using SecureString
- Weak token validation
- Sensitive data returned from functions

**Logic Bugs:**
- Off-by-one in retry loop
- Wrong comparison operators
- Missing null checks
- Shallow object merging

**Dependency Chain:**
```
ApiClient.ps1
├── HttpHelpers.ps1 (URL building broken)
├── JsonParser.ps1 (parsing issues)
└── AuthManager.ps1 (auth not applied)
```

### Example Debug Prompts

```
"Trace how authentication flows from ApiClient through AuthManager"

"Why isn't the auth token being sent in API requests?"

"Find all security issues in AuthManager.ps1"

"What happens when Invoke-ApiRequest retries 3 times?"

"Compare how Join-ApiUrl handles URLs vs how ApiClient uses it"

"List all places where null/empty checks are missing"
```

### Challenge Tasks

1. **Easy**: Find the typo in Config.ps1 that breaks Calculator.ps1
2. **Medium**: Trace why Add-Numbers returns wrong result
3. **Hard**: Identify all the auth token flow bugs
4. **Expert**: Find all 28+ bugs across both projects
