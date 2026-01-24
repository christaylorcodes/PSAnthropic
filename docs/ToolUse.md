# Tool Use Guide

This guide covers how to define custom tools and implement tool-calling workflows with the Anthropic Messages API.

> **Note:** Examples use Windows-style paths (`C:\`). Adjust for your platform as needed.

## Overview

Tools (also called functions) allow models to request execution of specific operations. The workflow is:

1. Define tools with names, descriptions, and input schemas
2. Send messages to the model with available tools
3. Model responds with `tool_use` blocks when it wants to call a tool
4. You execute the tool and return results
5. Model continues with the tool results

## Defining Custom Tools

Use `New-AnthropicTool` to create tool definitions:

```powershell
$weatherTool = New-AnthropicTool -Name 'get_weather' `
    -Description 'Get current weather for a location' `
    -InputSchema @{
        type = 'object'
        properties = @{
            location = @{
                type = 'string'
                description = 'City name or coordinates'
            }
            units = @{
                type = 'string'
                enum = @('celsius', 'fahrenheit')
                description = 'Temperature units'
            }
        }
        required = @('location')
    }
```

### Input Schema Format

Tools use JSON Schema to define their inputs:

```powershell
$searchTool = New-AnthropicTool -Name 'search_database' `
    -Description 'Search the product database' `
    -InputSchema @{
        type = 'object'
        properties = @{
            query = @{
                type = 'string'
                description = 'Search query'
            }
            category = @{
                type = 'string'
                enum = @('electronics', 'clothing', 'books')
                description = 'Product category to filter'
            }
            max_results = @{
                type = 'integer'
                description = 'Maximum results to return (1-100)'
                minimum = 1
                maximum = 100
            }
            in_stock = @{
                type = 'boolean'
                description = 'Only show in-stock items'
            }
        }
        required = @('query')
    }
```

## Single Tool Call

```powershell
# Define tool
$timeTool = New-AnthropicTool -Name 'get_time' `
    -Description 'Get current time in a timezone' `
    -InputSchema @{
        type = 'object'
        properties = @{
            timezone = @{ type = 'string'; description = 'Timezone ID' }
        }
        required = @('timezone')
    }

# Send message with tool
$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'What time is it in Tokyo?'
) -Tools @($timeTool)

# Handle tool call
if ($response.stop_reason -eq 'tool_use') {
    $toolUse = $response.content | Where-Object { $_.type -eq 'tool_use' }

    # Execute your tool logic
    $time = Get-Date -Format 'HH:mm:ss'  # Your actual implementation
    $toolResult = New-AnthropicToolResult -ToolUseId $toolUse.id -Content $time

    # Get final response with tool result
    $final = Invoke-AnthropicMessage -Messages @(
        New-AnthropicMessage -Role 'user' -Content 'What time is it in Tokyo?'
        @{ role = 'assistant'; content = $response.content }
        $toolResult
    )

    $final | Get-AnthropicResponseText
}
```

## Multi-Tool Agent Loop

For autonomous agents that may need multiple tool calls:

```powershell
# Define multiple tools
$tools = @(
    (New-AnthropicTool -Name 'read_file' -Description 'Read a file' -InputSchema @{
        type = 'object'
        properties = @{ path = @{ type = 'string' } }
        required = @('path')
    }),
    (New-AnthropicTool -Name 'list_files' -Description 'List directory' -InputSchema @{
        type = 'object'
        properties = @{ path = @{ type = 'string' } }
        required = @('path')
    })
)

# Tool implementations
$toolHandlers = @{
    'read_file' = { param($input) Get-Content -Path $input.path -Raw }
    'list_files' = { param($input) (Get-ChildItem -Path $input.path).Name -join "`n" }
}

# Agent loop
$messages = @(
    New-AnthropicMessage -Role 'user' -Content 'Analyze the scripts in C:\Scripts'
)

$response = Invoke-AnthropicMessage -Messages $messages -Tools $tools
$maxIterations = 10
$iteration = 0

while ($response.stop_reason -eq 'tool_use' -and $iteration -lt $maxIterations) {
    $iteration++
    $toolUses = @($response.content | Where-Object { $_.type -eq 'tool_use' })

    $toolResults = @()
    foreach ($tu in $toolUses) {
        Write-Host "Tool: $($tu.name)" -ForegroundColor Yellow

        # Execute the tool
        $handler = $toolHandlers[$tu.name]
        $result = & $handler $tu.input

        $toolResults += New-AnthropicToolResult -ToolUseId $tu.id -Content $result
    }

    # Update conversation
    $messages += @{ role = 'assistant'; content = $response.content }
    foreach ($tr in $toolResults) { $messages += $tr }

    # Continue
    $response = Invoke-AnthropicMessage -Messages $messages -Tools $tools
}

# Final response
$response | Get-AnthropicResponseText
```

## Tool Result Formatting

### Success Response

```powershell
$result = New-AnthropicToolResult -ToolUseId $toolUse.id -Content 'Operation completed successfully'
```

### Structured Data

```powershell
$data = @{
    temperature = 72
    conditions = 'Sunny'
    humidity = 45
}
$result = New-AnthropicToolResult -ToolUseId $toolUse.id -Content ($data | ConvertTo-Json)
```

### Error Response

```powershell
$result = New-AnthropicToolResult -ToolUseId $toolUse.id -Content 'Error: File not found' -IsError
```

## Tool Choice

Control how the model uses tools:

```powershell
# Let model decide (default)
$response = Invoke-AnthropicMessage -Messages $messages -Tools $tools

# Force tool use
$response = Invoke-AnthropicMessage -Messages $messages -Tools $tools -ToolChoice @{
    type = 'any'  # Must use at least one tool
}

# Force specific tool
$response = Invoke-AnthropicMessage -Messages $messages -Tools $tools -ToolChoice @{
    type = 'tool'
    name = 'get_weather'
}

# Disable tools for this call
$response = Invoke-AnthropicMessage -Messages $messages -Tools $tools -ToolChoice @{
    type = 'none'
}
```

## Best Practices

### 1. Clear Descriptions

```powershell
# Good - specific and actionable
$tool = New-AnthropicTool -Name 'send_email' `
    -Description 'Send an email to a recipient. Use when the user explicitly asks to send an email.'

# Bad - vague
$tool = New-AnthropicTool -Name 'send_email' `
    -Description 'Email tool'
```

### 2. Validate Inputs

```powershell
$toolHandlers = @{
    'write_file' = {
        param($input)

        # Validate path
        if ($input.path -match '\.\.') {
            return 'Error: Path traversal not allowed'
        }

        # Validate content
        if ([string]::IsNullOrEmpty($input.content)) {
            return 'Error: Content cannot be empty'
        }

        Set-Content -Path $input.path -Value $input.content
        return 'File written successfully'
    }
}
```

### 3. Limit Iterations

Always set a maximum iteration count to prevent infinite loops:

```powershell
$maxIterations = 10
$iteration = 0

while ($response.stop_reason -eq 'tool_use' -and $iteration -lt $maxIterations) {
    $iteration++
    # ... tool execution
}

if ($iteration -ge $maxIterations) {
    Write-Warning 'Max iterations reached'
}
```

### 4. Handle Errors Gracefully

```powershell
try {
    $result = & $toolHandler $toolUse.input
    $toolResult = New-AnthropicToolResult -ToolUseId $toolUse.id -Content $result
}
catch {
    $toolResult = New-AnthropicToolResult -ToolUseId $toolUse.id -Content "Error: $_" -IsError
}
```

### 5. Truncate Long Outputs

```powershell
$maxLength = 10000
if ($result.Length -gt $maxLength) {
    $result = $result.Substring(0, $maxLength) + '... [truncated]'
}
```

## Using Standard Tools

For common operations, use the built-in standard tools instead of defining your own:

```powershell
# Get pre-built tools
$tools = Get-AnthropicStandardTools

# Execute with automatic handling
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse
```

See [StandardTools.md](StandardTools.md) for details on standard tools and shell security.
