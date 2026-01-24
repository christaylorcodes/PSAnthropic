# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PSAnthropic is a PowerShell 7+ client for the Anthropic Messages API. It works with Ollama (via its Anthropic compatibility layer), Anthropic Cloud, and any Anthropic-compatible endpoint.

## Development Commands

```powershell
# Import module for development
Import-Module ./PSAnthropic/PSAnthropic -Force

# Run all tests
Invoke-Pester ./Tests -Output Detailed

# Run specific test
Invoke-Pester ./Tests -Filter "Test Name" -Output Detailed

# Run integration tests (requires Ollama running)
Invoke-Pester ./Tests -Tag Integration -Output Detailed

# Skip integration tests
Invoke-Pester ./Tests -ExcludeTag Integration -Output Detailed
```

## Architecture

### Module Structure

The module follows standard PowerShell module conventions:
- **PSAnthropic.psd1** - Module manifest with metadata and exported functions
- **PSAnthropic.psm1** - Root module that dot-sources all .ps1 files from Public/ and Private/ folders

### Function Organization

Functions are organized by category in `PSAnthropic/Public/`:

- **Authentication/** - `Connect-Anthropic`, `Disconnect-Anthropic`
- **Invoke/** - `Invoke-AnthropicWebRequest` (HTTP handler), `Invoke-AnthropicMessage` (main API)
- **Messages/** - `New-AnthropicMessage`, `New-AnthropicConversation`, `Add-AnthropicMessage`
- **Tools/** - `New-AnthropicTool`, `New-AnthropicToolFromCommand`, `New-AnthropicToolResult`, `Get-AnthropicStandardTools`, `Invoke-AnthropicStandardTool`
- **Content/** - `New-AnthropicImageContent`
- **Utility/** - `Get-AnthropicConnection`, `Get-AnthropicModel`, `Get-AnthropicResponseText`, `Test-AnthropicEndpoint`
- **Router/** - `Set-AnthropicRouterConfig`, `Get-AnthropicRouterConfig`, `Clear-AnthropicRouterConfig`, `Invoke-AnthropicRouted`, `Get-AnthropicRouterLog`

Private helpers in `PSAnthropic/Private/`:

- **Helper/** - URL building, validation, and safe execution utilities
  - `Assert-AnthropicConnection.ps1` - Validates connection exists (throws if not)
  - `Get-NormalizedServerUrl.ps1` - Normalizes server addresses with protocol
  - `Join-Url.ps1` - URL path joining using .NET Uri class
  - `New-AnthropicUrl.ps1` - Builds API URLs from connection settings
  - `Invoke-SafeCommand.ps1` - Sandboxed PowerShell command execution
  - `New-SafeRunspace.ps1` - Creates constrained runspaces for shell safety
  - `Register-AnthropicArgumentCompleters.ps1` - Tab completion for model names
- **Invoke/** - Internal request handlers
  - `Invoke-AnthropicStreamRequest.ps1` - SSE streaming implementation
- **Router/** - Router logging utilities
  - `Write-AnthropicRouterLog.ps1` - Logs routing decisions

### Connection State

Connection info is stored in the script-scoped variable `$script:AnthropicConnection`. This hashtable contains:

- `Server` - API server address (without protocol)
- `Model` - Default model name
- `Headers` - Auth headers including `X-Api-Key` and `anthropic-version`
- `ConnectedAt` - Connection timestamp

Router config is stored in `$script:AnthropicRouterConfig` when configured.

All API-calling functions validate this connection exists before making requests.

### Streaming Implementation

Streaming uses `System.Net.Http.HttpClient` directly (in `Invoke-AnthropicStreamRequest`) to parse Server-Sent Events (SSE). Events are output as they arrive, not buffered.

## Key Patterns

- Functions use `Connect-Anthropic` connection state; check `$script:AnthropicConnection` before API calls
- Parameter resolution order: explicit parameter → environment variable → default
- Environment variables: `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`
- Retry logic with exponential backoff for 5xx errors in `Invoke-AnthropicWebRequest`
- All exported functions listed explicitly in the manifest (no wildcards)

## Documentation

Detailed feature documentation in `docs/`:

- `docs/ToolUse.md` - Custom tool definitions or tool-calling patterns
- `docs/StandardTools.md` - Built-in standard tools and shell execution
- `docs/Router.md` - Model router configuration and usage
- `docs/Troubleshooting.md` - Common errors and solutions

## Types and Return Values

### Module Classes (Classes.ps1)

**AnthropicConnection** - Returned by `Get-AnthropicConnection`

```text
Server      : string    # API server address
Model       : string    # Default model name
Headers     : hashtable # (hidden) Auth headers
ConnectedAt : datetime  # Connection timestamp
HasApiKey   : bool      # Whether API key is set
```

**AnthropicMessage** - Created by `New-AnthropicMessage`

```text
Role    : AnthropicRole  # 'user' or 'assistant'
Content : object         # String or array of content blocks
```

**AnthropicConversation** - Created by `New-AnthropicConversation`

```text
Messages     : List[AnthropicMessage]  # Conversation history
SystemPrompt : string                  # System prompt
```

**Exception Classes** (for error handling):

- `AnthropicApiException` - Base exception with StatusCode, ErrorType, ResponseBody
- `AnthropicBadRequestException` (400), `AnthropicAuthenticationException` (401)
- `AnthropicRateLimitException` (429) with RetryAfterSeconds property
- `AnthropicConnectionException` - Network/connection failures

### API Response Structure

**Invoke-AnthropicMessage** returns a PSCustomObject:

```text
id           : string      # Response ID (e.g., "msg_xxx")
type         : string      # Always "message"
role         : string      # Always "assistant"
content      : array       # Array of content blocks
model        : string      # Model used
stop_reason  : string      # "end_turn", "tool_use", "max_tokens"
usage        : object      # Token counts
  input_tokens  : int
  output_tokens : int
```

**Content block types:**

```json
// Text block
{ "type": "text", "text": "response text" }

// Tool use block (when model wants to call a tool)
{ "type": "tool_use", "id": "toolu_xxx", "name": "tool_name", "input": {} }

// Thinking block (with -Thinking parameter)
{ "type": "thinking", "thinking": "model reasoning" }
```

**Response enrichment properties:** Responses include convenience properties:

- `.Answer` - Extracted text content as string (same as `Get-AnthropicResponseText`)
- `.History` - Complete message history including this response (for conversation continuation)
- `.ToolUse` - Array of tool_use blocks if present (for checking `$response.ToolUse[0].name`)

### Tool Definitions

**New-AnthropicTool** returns:

```text
name         : string    # Tool name
description  : string    # What the tool does
input_schema : hashtable # JSON Schema for parameters
```

**New-AnthropicToolResult** returns a hashtable:

```text
role    : "user"
content : @(
    @{ type = "tool_result"; tool_use_id = "toolu_xxx"; content = "result" }
)
```

### Standard Tools

**Get-AnthropicStandardTools** returns array of 8 tools:

- `pwsh` - Shell execution
- `str_replace_editor` - File editor
- `read_file` - Read files
- `list_directory` - List directories
- `search_files` - Find files by name
- `search_content` - Search in files
- `get_current_time` - Current time
- `web_fetch` - Fetch and parse URL content

### Router Config

**Get-AnthropicRouterConfig** returns:

```text
Models       : hashtable  # TaskType -> ModelName mappings
LogPath      : string     # Log file path (optional)
LogToConsole : bool       # Console logging enabled
CreatedAt    : datetime   # Config creation time
```

## Common Workflows

### Basic Message

```powershell
Connect-Anthropic -Model 'llama3'
$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Hello'
)
$response | Get-AnthropicResponseText
```

### Conversation Continuation (using .History)

```powershell
# First message
$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'My name is Alice'
)

# Continue using .History property
$response = Invoke-AnthropicMessage -Messages ($response.History + @(
    New-AnthropicMessage -Role 'user' -Content 'What is my name?'
))
```

### Tool Use Loop

```powershell
$tools = Get-AnthropicStandardTools
$messages = @(New-AnthropicMessage -Role 'user' -Content 'Task')
$response = Invoke-AnthropicMessage -Messages $messages -Tools $tools

while ($response.stop_reason -eq 'tool_use') {
    $toolUse = $response.content | Where-Object { $_.type -eq 'tool_use' }
    $result = Invoke-AnthropicStandardTool -ToolUse $toolUse
    $messages += @{ role = 'assistant'; content = $response.content }
    $messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $result
    $response = Invoke-AnthropicMessage -Messages $messages -Tools $tools
}
```

## Ollama Compatibility Notes

Per Ollama's Anthropic compatibility layer:

- **Supported:** Messages API, streaming, tools, base64 images, system prompts, temperature/top_p/top_k
- **Not Supported:** Token counting, URL-based images, cache control, batches API, PDFs

---

## AI Assistant Reference

This section helps AI assistants understand patterns, avoid mistakes, and generate correct code.

### Quick Reference Table

| Need to... | Use | Returns |
|------------|-----|---------|
| Start a session | `Connect-Anthropic` | void (sets `$script:AnthropicConnection`) |
| Send a message | `Invoke-AnthropicMessage -Messages $msgs` | PSCustomObject (API response) |
| Extract text from response | `$response.Answer` or `Get-AnthropicResponseText` | string |
| Continue conversation | `$response.History + @(New-AnthropicMessage ...)` | array for next call |
| Create a user/assistant message | `New-AnthropicMessage -Role 'user' -Content 'text'` | AnthropicMessage |
| Give model tools | `-Tools (Get-AnthropicStandardTools)` | - |
| Execute tool request | `Invoke-AnthropicStandardTool -ToolUse $response.ToolUse` | string (result) |
| Check if model wants tools | `$response.stop_reason -eq 'tool_use'` | bool |
| Create tool from cmdlet | `New-AnthropicToolFromCommand -CommandName 'Get-Process'` | hashtable (tool def) |
| Send tool result back | `New-AnthropicToolResult -ToolUseId $id -Content $result` | hashtable (message) |

### Common Mistakes

#### ❌ Wrong: Inline hashtables instead of New-AnthropicMessage

```powershell
# WRONG - missing required structure, may fail silently
Invoke-AnthropicMessage -Messages @{ role = 'user'; content = 'Hi' }

# CORRECT - always use New-AnthropicMessage for input
Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Hi'
)
```

#### ❌ Wrong: Ignoring tool_use stop_reason

```powershell
# WRONG - $response.Answer may be empty when model wants to use tools!
$response = Invoke-AnthropicMessage -Messages $msgs -Tools $tools
Write-Output $response.Answer

# CORRECT - always check stop_reason when using tools
if ($response.stop_reason -eq 'tool_use') {
    # Handle tool call
} else {
    Write-Output $response.Answer
}
```

#### ❌ Wrong: Not connecting before API calls

```powershell
# WRONG - throws AnthropicConnectionException
$response = Invoke-AnthropicMessage -Messages $msgs

# CORRECT - connect first (or set environment variables)
Connect-Anthropic -Server 'localhost:11434' -Model 'llama3'
$response = Invoke-AnthropicMessage -Messages $msgs
```

#### ❌ Wrong: Assigning streaming output to variable

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

#### ❌ Wrong: Forgetting assistant message in tool loop

```powershell
# WRONG - missing assistant message, breaks conversation structure
$messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $result

# CORRECT - include both assistant response AND tool result
$messages += @{ role = 'assistant'; content = $response.content }
$messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $result
```

#### ❌ Wrong: Using wrong ToolUseId

```powershell
# WRONG - $toolUse is an array when model calls multiple tools
$result = New-AnthropicToolResult -ToolUseId $toolUse.id -Content $output

# CORRECT - iterate or index into the array
foreach ($tool in $response.ToolUse) {
    $result = Invoke-AnthropicStandardTool -ToolUse $tool
    $messages += New-AnthropicToolResult -ToolUseId $tool.id -Content $result
}
```

### Parameter Interactions

| Parameter | Interaction Notes |
|-----------|-------------------|
| `-Stream` | Returns event stream, not single response. Cannot use `.Answer`/`.History` properties. |
| `-Thinking` | Requires Claude 3+ models. Silently ignored on Ollama/incompatible models. |
| `-MaxTokens` | Defaults vary by provider. Always set explicitly for consistent behavior. |
| `-Tools` + `-ToolChoice` | `ToolChoice = 'any'` forces tool use. `'auto'` lets model decide. |
| `-Unsafe` | Bypasses sandboxing for shell commands. Uses Invoke-Expression directly. FOR TESTING ONLY. |
| `-AllowShell` | Enables shell command execution. Uses sandboxed runspace by default. |
| `-AllowWeb` | Enables web_fetch tool for fetching URL content. Disabled by default for security. |

### Design Decisions

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

### Error Handling Patterns

```powershell
# Rate limiting with retry
try {
    $response = Invoke-AnthropicMessage -Messages $msgs
}
catch [AnthropicRateLimitException] {
    Write-Warning "Rate limited. Waiting $($_.Exception.RetryAfterSeconds) seconds..."
    Start-Sleep -Seconds $_.Exception.RetryAfterSeconds
    $response = Invoke-AnthropicMessage -Messages $msgs  # Retry
}

# Connection failures
catch [AnthropicConnectionException] {
    Write-Error "Cannot reach API. Check: 1) Server running? 2) URL correct? 3) Network?"
    # Use Test-AnthropicEndpoint to diagnose
}

# Bad request (usually malformed messages)
catch [AnthropicBadRequestException] {
    Write-Error "Invalid request: $($_.Exception.Message)"
    # Check message structure, tool definitions
}

# Authentication
catch [AnthropicAuthenticationException] {
    Write-Error "API key invalid or missing"
}
```

### Testing Patterns

See `Tests/CLAUDE.md` for detailed testing guidance including:

- Pester BeforeDiscovery vs BeforeAll scoping gotchas
- Mocking patterns
- Integration test requirements
- Test image locations

```powershell
# Mock API responses in Pester tests
Mock Invoke-AnthropicWebRequest -ModuleName PSAnthropic {
    @{
        StatusCode = 200
        Content = '{"id":"msg_test","content":[{"type":"text","text":"mocked"}],"stop_reason":"end_turn"}'
    }
}

# Test tool execution with safe directory
It 'Should restrict file access' {
    $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowedPaths @($TestDrive)
}
```

### Auto-Generating Tool Definitions

`New-AnthropicToolFromCommand` uses PowerShell reflection to create Anthropic tool definitions from any cmdlet or function:

```powershell
# Generate tool from built-in cmdlet
$tool = New-AnthropicToolFromCommand -CommandName 'Get-Process' -Strict

# Generate from custom function with validation
function Get-Weather {
    param(
        [Parameter(Mandatory, HelpMessage = 'City name')]
        [string]$Location,

        [ValidateSet('celsius', 'fahrenheit')]
        [string]$Unit = 'celsius'
    )
}
$tool = New-AnthropicToolFromCommand -CommandName 'Get-Weather'
# Automatically extracts: parameters, types, ValidateSet as enum, HelpMessage as description

# Use generated tools
$tools = 'Get-Process', 'Stop-Process' | ForEach-Object {
    New-AnthropicToolFromCommand -CommandName $_ -Strict
}
$response = Invoke-AnthropicMessage -Messages $msgs -Tools $tools
```

The function extracts: parameter types → JSON Schema types, `[ValidateSet]` → `enum`, `[ValidateRange]` → `minimum`/`maximum`, `[Parameter(HelpMessage)]` → `description`, mandatory → `required`.

### File Layout Reference

```
PSAnthropic/
├── PSAnthropic.psd1          # Manifest - lists all exported functions
├── PSAnthropic.psm1          # Loader - dot-sources Public/ and Private/
├── Classes.ps1               # Type definitions (load first for Pester)
├── Public/                   # Exported functions (25 total)
│   ├── Authentication/       # Connect-Anthropic, Disconnect-Anthropic
│   ├── Content/              # New-AnthropicImageContent
│   ├── Invoke/               # Invoke-AnthropicMessage, Invoke-AnthropicWebRequest
│   ├── Messages/             # New-AnthropicMessage, New-AnthropicConversation, Add-AnthropicMessage
│   ├── Router/               # Set/Get/Clear-AnthropicRouterConfig, Invoke-AnthropicRouted
│   ├── Tools/                # New-AnthropicTool*, Get/Invoke-AnthropicStandardTool*
│   └── Utility/              # Get-AnthropicConnection/Model, Test-AnthropicEndpoint
└── Private/                  # Internal helpers
    ├── Helper/               # URL building, validation, safe execution
    ├── Invoke/               # Invoke-AnthropicStreamRequest (SSE)
    └── Router/               # Write-AnthropicRouterLog
```

### Checklist for Modifications

When modifying this module:

- [ ] Update `PSAnthropic.psd1` FunctionsToExport if adding/removing public functions
- [ ] Add comment-based help (.SYNOPSIS, .PARAMETER, .EXAMPLE) to new functions
- [ ] Use `Assert-AnthropicConnection` at start of functions that need connection
- [ ] Add `[OutputType()]` attribute to functions
- [ ] Run `Invoke-Pester ./Tests -ExcludeTag Integration` before committing
- [ ] Update this CLAUDE.md if adding new patterns or workflows
