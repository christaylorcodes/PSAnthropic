# Standard Tools

PSAnthropic includes pre-built standard tools that provide common file system, editing, and shell capabilities. These are similar to Anthropic's built-in tools and work automatically with `Invoke-AnthropicStandardTool`.

> **Note:** Examples use Windows-style paths (`C:\`). Adjust for your platform as needed.

## Quick Start

```powershell
# Get all standard tools
$tools = Get-AnthropicStandardTools

# Send a message with tools
$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'List the files in C:\Projects'
) -Tools $tools

# Execute tool calls from the model
if ($response.stop_reason -eq 'tool_use') {
    $toolUse = $response.content | Where-Object { $_.type -eq 'tool_use' }
    $result = Invoke-AnthropicStandardTool -ToolUse $toolUse
}
```

## Available Tools

| Tool | Description |
|------|-------------|
| `pwsh` | Execute PowerShell commands |
| `str_replace_editor` | Text editor with view/create/replace/insert |
| `read_file` | Read file contents |
| `list_directory` | List directory contents |
| `search_files` | Search for files by name pattern |
| `search_content` | Search for text content within files |
| `get_current_time` | Get current date/time |
| `web_fetch` | Fetch and parse content from URLs |

## Tool Sets

You can request specific subsets of tools:

```powershell
# All tools (default)
$tools = Get-AnthropicStandardTools -ToolSet All

# File system only (read_file, list_directory, search_files, search_content)
$tools = Get-AnthropicStandardTools -ToolSet FileSystem

# Editor only (str_replace_editor)
$tools = Get-AnthropicStandardTools -ToolSet Editor

# Shell only (pwsh, get_current_time)
$tools = Get-AnthropicStandardTools -ToolSet Shell

# Web only (web_fetch)
$tools = Get-AnthropicStandardTools -ToolSet Web
```

## Executing Tools

`Invoke-AnthropicStandardTool` executes tool calls from the model's response:

```powershell
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse
```

### Security Switches

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-AllowWrite` | `$false` | Enable write operations (create, str_replace, insert) |
| `-AllowShell` | `$false` | Enable shell command execution |
| `-AllowWeb` | `$false` | Enable web_fetch for fetching URL content |
| `-TimeoutSeconds` | 30 | Maximum execution time for shell commands |
| `-MaxOutputLength` | 10000 | Maximum output length (truncates if exceeded) |

### Example: Read-Only Agent

```powershell
# Safe exploration - no writes, no shell
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse
```

### Example: Full Access Agent

```powershell
# Full access with write and shell capabilities
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWrite -AllowShell
```

## Shell Security

Shell commands (`pwsh` tool) run in a sandboxed environment by default when `-AllowShell` is enabled.

### Sandboxed Mode (default)

When you use `-AllowShell`, commands execute in a constrained runspace with:

- **ConstrainedLanguage mode** - Blocks direct .NET type access (e.g., `[System.IO.File]::ReadAllText()`)
- **Curated command whitelist** - Only safe commands are available:
  - Output: `Write-Output`, `Write-Host`, `Write-Warning`, `Write-Error`, `Out-String`, `Out-Null`
  - Filtering: `Select-Object`, `Where-Object`, `ForEach-Object`, `Sort-Object`, `Group-Object`
  - Formatting: `Format-Table`, `Format-List`, `Format-Wide`, `Format-Custom`
  - Filesystem (read-only): `Get-Content`, `Get-ChildItem`, `Get-Item`, `Test-Path`, `Join-Path`
  - Conversion: `ConvertTo-Json`, `ConvertFrom-Json`, `ConvertTo-Csv`, `ConvertFrom-Csv`
  - System: `Get-Process`, `Get-Service`, `Get-Help`, `Get-Command`, `Get-Member`
  - Utilities: `Get-Date`, `Get-Random`, `Measure-Object`, `Select-String`, `Start-Sleep`
- **Timeout protection** - Commands are killed after the timeout period

### Unsafe Mode

The `-Unsafe` switch bypasses all sandboxing and uses `Invoke-Expression` directly.

**WARNING: Only use for testing in controlled environments where you trust all input.**

```powershell
# Sandboxed (default) - safe for untrusted input
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell

# Unsafe - for testing only!
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell -Unsafe
```

## Tool Use Loop Pattern

A common pattern for autonomous agents (see also [ToolUse.md](ToolUse.md) for custom tool patterns):

```powershell
$tools = Get-AnthropicStandardTools
$messages = @(
    New-AnthropicMessage -Role 'user' -Content 'Analyze the project structure'
)

$response = Invoke-AnthropicMessage -Messages $messages -Tools $tools
$maxIterations = 10
$iteration = 0

while ($response.stop_reason -eq 'tool_use' -and $iteration -lt $maxIterations) {
    $iteration++
    $toolUses = @($response.content | Where-Object { $_.type -eq 'tool_use' })

    $toolResults = @()
    foreach ($tu in $toolUses) {
        Write-Host "Executing: $($tu.name)" -ForegroundColor Yellow
        $result = Invoke-AnthropicStandardTool -ToolUse $tu
        $toolResults += New-AnthropicToolResult -ToolUseId $tu.id -Content $result
    }

    # Add assistant response and tool results to conversation
    $messages += @{ role = 'assistant'; content = $response.content }
    foreach ($tr in $toolResults) { $messages += $tr }

    # Continue the conversation
    $response = Invoke-AnthropicMessage -Messages $messages -Tools $tools
}

Write-Host "Final response:" -ForegroundColor Green
$response | Get-AnthropicResponseText
```

## Individual Tool Reference

### pwsh

Execute PowerShell commands:

```json
{
  "name": "pwsh",
  "input": {
    "command": "Get-Process | Select-Object -First 5",
    "working_directory": "C:\\Projects"
  }
}
```

### str_replace_editor

Text editor with multiple commands:

**View file:**
```json
{
  "name": "str_replace_editor",
  "input": {
    "command": "view",
    "path": "C:\\Projects\\script.ps1",
    "view_range": [1, 20]
  }
}
```

**Create file:**
```json
{
  "name": "str_replace_editor",
  "input": {
    "command": "create",
    "path": "C:\\Projects\\new.ps1",
    "file_text": "# New script\nWrite-Host 'Hello'"
  }
}
```

**Replace text:**
```json
{
  "name": "str_replace_editor",
  "input": {
    "command": "str_replace",
    "path": "C:\\Projects\\script.ps1",
    "old_str": "Write-Host 'Hello'",
    "new_str": "Write-Host 'Hello World'"
  }
}
```

### read_file

Read file contents:

```json
{
  "name": "read_file",
  "input": {
    "path": "C:\\Projects\\README.md",
    "max_lines": 50
  }
}
```

### list_directory

List directory contents:

```json
{
  "name": "list_directory",
  "input": {
    "path": "C:\\Projects",
    "pattern": "*.ps1",
    "recursive": false
  }
}
```

### search_files

Search for files by name:

```json
{
  "name": "search_files",
  "input": {
    "path": "C:\\Projects",
    "pattern": "*.Tests.ps1",
    "max_results": 20
  }
}
```

### search_content

Search for text in files:

```json
{
  "name": "search_content",
  "input": {
    "path": "C:\\Projects",
    "pattern": "function\\s+Get-",
    "file_pattern": "*.ps1",
    "max_results": 50
  }
}
```

### get_current_time

Get current date/time:

```json
{
  "name": "get_current_time",
  "input": {
    "timezone": "UTC",
    "format": "yyyy-MM-dd HH:mm:ss"
  }
}
```

### web_fetch

Fetch content from a URL:

```json
{
  "name": "web_fetch",
  "input": {
    "url": "https://example.com/api/docs",
    "max_length": 50000,
    "include_headers": false
  }
}
```

**Features:**

- Automatically converts HTML to readable plain text (headings, lists, paragraphs preserved)
- JSON responses are formatted for readability
- HTTP response headers can optionally be included
- Content is truncated at `max_length` to prevent token overflow

**Use cases:**

- Fetching API documentation
- Retrieving reference material
- Reading public web content for context (RAG)

**Example with web access:**

```powershell
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb
```
