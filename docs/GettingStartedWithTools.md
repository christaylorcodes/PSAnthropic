# Getting Started with Tool Use

A step-by-step guide to giving your AI assistant tools to use.

## What You'll Learn

- How to give the AI tools it can request
- Understanding when the AI requests a tool
- Executing tool requests and sending results back
- Building a complete tool-using conversation

## Prerequisites

- PSAnthropic module installed and imported
- Ollama running locally (or Anthropic API key)
- Basic PowerShell knowledge

## What Are Tools?

Tools are functions the AI can request you to execute. Instead of making up information, the AI can ask for real data:

- "What time is it?" → AI requests `get_current_time` tool
- "Read this file" → AI requests `read_file` tool
- "List directory contents" → AI requests `list_directory` tool

You provide the tool definitions, the AI decides when to use them, and you execute them.

## The Tool Loop

When you give an AI tools, the conversation follows this pattern:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Send message   │────▶│   AI responds   │────▶│  Check          │
│  with tools     │     │   with request  │     │  stop_reason    │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                        ┌────────────────────────────────┘
                        │
                  ┌─────▼─────┐
                  │ tool_use? │──Yes──▶ Execute tool ──▶ Send result ──▶ Loop
                  └─────┬─────┘
                        │ No (end_turn)
                        ▼
                  Done! Show .Answer
```

## Understanding stop_reason

When the AI responds, check `$response.stop_reason` to know what to do next:

| stop_reason | Meaning | Action |
|-------------|---------|--------|
| `end_turn` | AI finished responding | Show `$response.Answer` to user |
| `tool_use` | AI wants to call a tool | Execute the tool, send result back |
| `max_tokens` | Response was cut off | Increase `-MaxTokens` or continue conversation |

## Step 1: Connect and Get Tools

```powershell
# Connect to your LLM server
Connect-Anthropic -Server 'localhost:11434' -Model 'llama3'

# Get the built-in standard tools
$tools = Get-AnthropicStandardTools

# See what tools are available
$tools | ForEach-Object { $_.name }
# Output: pwsh, str_replace_editor, read_file, list_directory,
#         search_files, search_content, get_current_time, web_fetch
```

## Step 2: Send a Message That Might Need a Tool

```powershell
# Ask something that requires a tool
$messages = @(
    New-AnthropicMessage -Role 'user' -Content 'What time is it in UTC?'
)

$response = Invoke-AnthropicMessage -Messages $messages -Tools $tools -MaxTokens 500
```

## Step 3: Check the stop_reason

This is the critical step many people miss:

```powershell
# ALWAYS check stop_reason when using tools
if ($response.stop_reason -eq 'tool_use') {
    Write-Host "AI wants to use a tool!"
    # Handle tool request (Step 4)
}
else {
    # AI responded directly without needing a tool
    Write-Host $response.Answer
}
```

## Step 4: Execute the Tool

When `stop_reason` is `tool_use`, the AI has requested a tool. Find and execute it:

```powershell
# Get the tool request from the response
$toolUse = $response.ToolUse[0]  # .ToolUse is a convenience property

Write-Host "Tool requested: $($toolUse.name)"
Write-Host "With input: $($toolUse.input | ConvertTo-Json -Compress)"

# Execute the standard tool
$toolResult = Invoke-AnthropicStandardTool -ToolUse $toolUse
Write-Host "Result: $toolResult"
```

## Step 5: Send the Result Back

This is where people often make mistakes. You must send **both**:
1. The assistant's message (containing the tool request)
2. The tool result

```powershell
# Add the assistant's response to messages (REQUIRED)
$messages += @{ role = 'assistant'; content = $response.content }

# Add the tool result
$messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $toolResult

# Continue the conversation
$response = Invoke-AnthropicMessage -Messages $messages -Tools $tools -MaxTokens 500
```

## Step 6: Complete the Loop

The AI might request more tools or finish. Loop until done:

```powershell
while ($response.stop_reason -eq 'tool_use') {
    $toolUse = $response.ToolUse[0]
    $toolResult = Invoke-AnthropicStandardTool -ToolUse $toolUse

    # Add assistant message + tool result
    $messages += @{ role = 'assistant'; content = $response.content }
    $messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $toolResult

    # Continue
    $response = Invoke-AnthropicMessage -Messages $messages -Tools $tools -MaxTokens 500
}

# Done - show final answer
Write-Host $response.Answer
```

## Complete Working Example

Copy and paste this to try it yourself:

```powershell
# Setup
Connect-Anthropic -Server 'localhost:11434' -Force
$tools = Get-AnthropicStandardTools

# Initial message
$messages = @(
    New-AnthropicMessage -Role 'user' -Content 'What time is it in UTC right now?'
)

# First request
$response = Invoke-AnthropicMessage -Messages $messages -Tools $tools -MaxTokens 500

# Tool loop
$maxIterations = 5
$iteration = 0

while ($response.stop_reason -eq 'tool_use' -and $iteration -lt $maxIterations) {
    $iteration++
    $toolUse = $response.ToolUse[0]

    Write-Host "[$iteration] Tool: $($toolUse.name)" -ForegroundColor Yellow

    # Execute tool
    $toolResult = Invoke-AnthropicStandardTool -ToolUse $toolUse
    Write-Host "    Result: $toolResult" -ForegroundColor DarkGray

    # Build next request
    $messages += @{ role = 'assistant'; content = $response.content }
    $messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $toolResult

    # Continue
    $response = Invoke-AnthropicMessage -Messages $messages -Tools $tools -MaxTokens 500
}

# Show final answer
Write-Host "`nFinal Answer:" -ForegroundColor Green
Write-Host $response.Answer
```

## Common Mistakes

### Mistake 1: Ignoring stop_reason

```powershell
# WRONG - .Answer may be empty when AI wants to use tools!
$response = Invoke-AnthropicMessage -Messages $msgs -Tools $tools
Write-Host $response.Answer  # Could be empty!
```

```powershell
# CORRECT - Always check stop_reason
if ($response.stop_reason -eq 'tool_use') {
    # Handle tool request
} else {
    Write-Host $response.Answer
}
```

### Mistake 2: Forgetting the Assistant Message

```powershell
# WRONG - Missing assistant message breaks conversation structure
$messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $result
```

```powershell
# CORRECT - Include both assistant message AND tool result
$messages += @{ role = 'assistant'; content = $response.content }
$messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $result
```

### Mistake 3: Using Wrong ToolUseId

```powershell
# WRONG - When AI calls multiple tools, $response.ToolUse is an array
$result = New-AnthropicToolResult -ToolUseId $response.ToolUse.id  # Error!
```

```powershell
# CORRECT - Handle each tool use separately
foreach ($tool in $response.ToolUse) {
    $result = Invoke-AnthropicStandardTool -ToolUse $tool
    $messages += New-AnthropicToolResult -ToolUseId $tool.id -Content $result
}
```

### Mistake 4: Infinite Loop Without Max Iterations

```powershell
# WRONG - Could loop forever if AI keeps requesting tools
while ($response.stop_reason -eq 'tool_use') {
    # ...
}
```

```powershell
# CORRECT - Always have a safety limit
$maxIterations = 10
$iteration = 0
while ($response.stop_reason -eq 'tool_use' -and $iteration -lt $maxIterations) {
    $iteration++
    # ...
}
```

## Security Notes

The standard tools have security controls:

```powershell
# By default, shell and write operations are disabled
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse

# Enable specific capabilities as needed
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell  # Enable pwsh tool
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWrite  # Enable file writes
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb    # Enable web_fetch
```

## Next Steps

- [Custom Tool Definitions](ToolUse.md) - Create your own tools
- [Standard Tools Reference](StandardTools.md) - Full reference for built-in tools
- [Troubleshooting](Troubleshooting.md) - Common errors and solutions
