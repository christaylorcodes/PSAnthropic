# PSAnthropic - Module Demo Script
# Demonstrates all module capabilities from simple to complex
# Requires: PowerShell 7+, Ollama running locally
#
# Usage:
#   .\Demo.ps1                              # Run demo with default model
#   .\Demo.ps1 -Model 'llama3.1-8k'         # Specify a model

param(
    # Default to optimized 8k context model (less VRAM)
    # Options: llama3.1-8k (fast), qwen3-coder-8k (smart), qwen2.5-coder:7b, llama3.1:8b (128k ctx)
    [string]$Model = 'qwen3:8b'
)

# Remove module first to avoid type definition conflicts when reloading
# (PowerShell classes from ScriptsToProcess don't update properly with -Force alone)
Remove-Module PSAnthropic -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\PSAnthropic" -Force

#region 1. Connection & Setup
Write-Host '=== 1. Connection & Setup ===' -ForegroundColor Magenta

# Health check before connecting
Write-Host 'Testing endpoint...' -ForegroundColor Cyan
if (Test-AnthropicEndpoint) {
    Write-Host '[OK] Ollama is running' -ForegroundColor Green
}
else {
    Write-Host "[ERROR] Ollama not available - start it with 'ollama serve'" -ForegroundColor Red
    return
}

# Connect to Ollama with the specified model
Connect-Anthropic -Model $Model
Write-Host "Connected with model: $Model" -ForegroundColor Cyan
Get-AnthropicConnection

# List available models
Write-Host "`nAvailable models:" -ForegroundColor Cyan
Get-AnthropicModel | ForEach-Object { Write-Host "  - $($_.name)" -ForegroundColor Gray }
#endregion

#region 2. Basic Message
Write-Host "`n=== 2. Basic Message ===" -ForegroundColor Magenta

$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'What is PowerShell in one sentence?'
) -Verbose

Write-Host 'Response:' -ForegroundColor Green
$response | Get-AnthropicResponseText
#endregion

#region 3. System Prompt
Write-Host "`n=== 3. System Prompt ===" -ForegroundColor Magenta

$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Explain variables'
) -System 'You are a PowerShell tutor. Give brief answers with one code example.'

$response | Get-AnthropicResponseText
#endregion

#region 4. Generation Parameters
Write-Host "`n=== 4. Generation Parameters ===" -ForegroundColor Magenta

# High temperature = more creative/random
$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Give me one random word.'
) -Temperature 1.0 -MaxTokens 20

Write-Host 'Random word (temp=1.0):' -ForegroundColor Cyan
$response | Get-AnthropicResponseText
#endregion

#region 4b. Extended Thinking Mode (Ollama Feature)
Write-Host "`n=== 4b. Extended Thinking Mode ===" -ForegroundColor Magenta
Write-Host "Note: Extended thinking allows the model to 'think' before responding" -ForegroundColor Yellow

# With thinking enabled, model includes reasoning in response
$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'What is 15% of 85? Show your work.'
) -Thinking -ThinkingBudget 1024

Write-Host 'Response with thinking:' -ForegroundColor Cyan

# Check for thinking blocks in response
$thinkingBlocks = $response.content | Where-Object { $_.type -eq 'thinking' }
if ($thinkingBlocks) {
    Write-Host "  [Thinking]: $($thinkingBlocks.thinking)" -ForegroundColor DarkGray
}

$response | Get-AnthropicResponseText
#endregion

#region 5. Streaming
Write-Host "`n=== 5. Streaming Response ===" -ForegroundColor Magenta

Write-Host 'Streaming: ' -ForegroundColor Cyan -NoNewline
Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Write a haiku about coding.'
) -Stream | ForEach-Object {
    if ($_.type -eq 'content_block_delta') {
        Write-Host $_.delta.text -NoNewline
    }
}
Write-Host ''
#endregion

#region 6. Multi-turn Conversation
Write-Host "`n=== 6. Multi-turn Conversation ===" -ForegroundColor Magenta

# Create conversation with system prompt
$conv = New-AnthropicConversation -UserMessage 'Hello! My name is Alex.' -SystemPrompt 'You are friendly. Be brief.'

# First exchange
$response = Invoke-AnthropicMessage -Messages $conv.Messages -System $conv.SystemPrompt
Write-Host 'User: Hello! My name is Alex.' -ForegroundColor Cyan
Write-Host "Assistant: $($response | Get-AnthropicResponseText)" -ForegroundColor Green

# Add response and continue
Add-AnthropicMessage -Conversation $conv -Response $response
Add-AnthropicMessage -Conversation $conv -Role 'user' -Content 'What is my name?'

# Second exchange
$response = Invoke-AnthropicMessage -Messages $conv.Messages -System $conv.SystemPrompt
Write-Host 'User: What is my name?' -ForegroundColor Cyan
Write-Host "Assistant: $($response | Get-AnthropicResponseText)" -ForegroundColor Green
#endregion

#region 7. Image Content (Vision)
Write-Host "`n=== 7. Image Content (Vision) ===" -ForegroundColor Magenta

# Switch to vision model
$originalModel = (Get-AnthropicConnection).Model
Connect-Anthropic -Model 'llama3.2-vision:11b' -Force
Write-Host 'Switched to vision model: llama3.2-vision:11b' -ForegroundColor Cyan

# Create a simple test image (1x1 red pixel PNG)
$demoBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=='
$imageContent = New-AnthropicImageContent -Base64 $demoBase64 -MediaType 'image/png'

Write-Host 'Created image content:' -ForegroundColor Gray
Write-Host "  Type: $($imageContent.type)" -ForegroundColor Gray
Write-Host "  Media: $($imageContent.source.media_type)" -ForegroundColor Gray

# Send image to vision model
Write-Host "`nAsking vision model to describe the image..." -ForegroundColor Cyan
$response = Invoke-AnthropicMessage -Messages @(@{
        role    = 'user'
        content = @(
            @{ type = 'text'; text = 'What color is this image? Answer in one word.' }
            $imageContent
        )
    })

Write-Host "Vision response: $($response | Get-AnthropicResponseText)" -ForegroundColor Green

# Switch back to original model
Connect-Anthropic -Model $originalModel -Force
Write-Host "Switched back to: $originalModel" -ForegroundColor Gray
#endregion

#region 8. Simple Tool Use
Write-Host "`n=== 8. Simple Tool Use ===" -ForegroundColor Magenta

# Define a tool
$timeTool = New-AnthropicTool -Name 'get_time' -Description 'Get current time' -InputSchema @{
    type       = 'object'
    properties = @{
        timezone = @{ type = 'string'; description = 'Timezone (e.g., UTC, EST)' }
    }
    required   = @('timezone')
}

# Send message with tool
$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'What time is it in UTC?'
) -Tools @($timeTool)

# Handle tool call
if ($response.stop_reason -eq 'tool_use') {
    $toolUse = $response.content | Where-Object { $_.type -eq 'tool_use' }
    Write-Host "Model called: $($toolUse.name)" -ForegroundColor Yellow
    Write-Host "Input: $($toolUse.input | ConvertTo-Json -Compress)" -ForegroundColor Gray

    # Execute tool and return result
    $timeResult = Get-Date -Format 'HH:mm:ss'
    $toolResult = New-AnthropicToolResult -ToolUseId $toolUse.id -Content $timeResult

    # Get final response
    $final = Invoke-AnthropicMessage -Messages @(
        New-AnthropicMessage -Role 'user' -Content 'What time is it in UTC?'
        @{ role = 'assistant'; content = $response.content }
        $toolResult
    )
    Write-Host "Response: $($final | Get-AnthropicResponseText)" -ForegroundColor Green
}
#endregion

#region 8b. Auto-Generate Tool from Command
Write-Host "`n=== 8b. Auto-Generate Tool from PowerShell Command ===" -ForegroundColor Magenta
Write-Host 'New-AnthropicToolFromCommand creates tool definitions from existing cmdlets' -ForegroundColor Cyan

# Generate tool from Get-Date (shows type mapping and validation constraints)
Write-Host "`nGenerating tool from Get-Date:" -ForegroundColor Yellow
$dateTool = New-AnthropicToolFromCommand -CommandName 'Get-Date' -IncludeParameter @('Year', 'Month', 'Day', 'Format')

Write-Host "  Name: $($dateTool.name)" -ForegroundColor Gray
Write-Host "  Description: $($dateTool.description)" -ForegroundColor Gray
Write-Host '  Parameters:' -ForegroundColor Gray
$dateTool.input_schema.properties.GetEnumerator() | ForEach-Object {
    $reqMark = if ($_.Key -in $dateTool.input_schema.required) { '*' } else { '' }
    $rangeInfo = if ($_.Value.minimum -and $_.Value.maximum) { " [$($_.Value.minimum)-$($_.Value.maximum)]" } else { '' }
    Write-Host "    - $($_.Key)$reqMark : $($_.Value.type)$rangeInfo" -ForegroundColor DarkGray
}

# Enhanced features demo with Get-Process
Write-Host "`nEnhanced features (-Strict -IncludeExamples):" -ForegroundColor Yellow
$processTool = New-AnthropicToolFromCommand -CommandName 'Get-Process' -IncludeParameter @('Name', 'Id') -Strict -IncludeExamples -Description 'List running processes'

Write-Host "  Name: $($processTool.name)" -ForegroundColor Gray
Write-Host "  Description: $($processTool.description)" -ForegroundColor Gray
Write-Host "  additionalProperties: $($processTool.input_schema.additionalProperties)" -ForegroundColor Cyan
Write-Host "  Parameters: $($processTool.input_schema.properties.Keys -join ', ')" -ForegroundColor Gray
if ($processTool.input_schema.properties.Name.examples) {
    Write-Host "  Examples for Name: $($processTool.input_schema.properties.Name.examples -join ', ')" -ForegroundColor Cyan
}

# Pipeline example - generate multiple tools at once
Write-Host "`nPipeline: Generate multiple tools at once:" -ForegroundColor Yellow
$multiTools = 'Get-Date', 'Get-Location', 'Get-Random' | ForEach-Object { New-AnthropicToolFromCommand -CommandName $_ }
$multiTools | ForEach-Object { Write-Host "  - $($_.name): $($_.description)" -ForegroundColor DarkGray }
#endregion

#region 8c. Response Object Enrichment
Write-Host "`n=== 8c. Response Object Enrichment ===" -ForegroundColor Magenta
Write-Host 'Responses now include convenience properties for easier access' -ForegroundColor Cyan

$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'What is 2+2? Answer briefly.'
)

Write-Host "`nResponse properties:" -ForegroundColor Yellow
Write-Host '  .Answer  : Quick access to text content' -ForegroundColor Gray
Write-Host "    Value  : $($response.Answer)" -ForegroundColor Green
Write-Host '  .History : Messages including this response (for continuation)' -ForegroundColor Gray
Write-Host "    Count  : $($response.History.Count) messages" -ForegroundColor DarkGray
Write-Host '  .ToolUse : Tool use blocks if present (null here)' -ForegroundColor Gray
Write-Host "    Value  : $(if($response.ToolUse) { $response.ToolUse.Count } else { 'None' })" -ForegroundColor DarkGray

# Show .History in action
Write-Host "`nUsing .History for conversation continuation:" -ForegroundColor Yellow
$followUp = Invoke-AnthropicMessage -Messages ($response.History + @(
        New-AnthropicMessage -Role 'user' -Content 'Now multiply that by 3.'
    ))
Write-Host "  Follow-up answer: $($followUp.Answer)" -ForegroundColor Green
#endregion

#region 9. Standard Tools (Module Built-in)
Write-Host "`n=== 9. Standard Tools ===" -ForegroundColor Magenta

# Get pre-defined tools from module
$standardTools = Get-AnthropicStandardTools
Write-Host 'Available standard tools:' -ForegroundColor Cyan
$standardTools | ForEach-Object { Write-Host "  - $($_.name)" -ForegroundColor Gray }

# Use standard tools with automatic execution
Write-Host "`nAsking model to read a file..." -ForegroundColor Cyan

$messages = @(
    New-AnthropicMessage -Role 'user' -Content "Read the file at $PSScriptRoot\README.md and summarize it in 2 sentences."
)

$response = Invoke-AnthropicMessage -Messages $messages -Tools $standardTools

# Tool use loop
while ($response.stop_reason -eq 'tool_use') {
    $toolUses = @($response.content | Where-Object { $_.type -eq 'tool_use' })

    $toolResults = @()
    foreach ($tu in $toolUses) {
        Write-Host "  Tool: $($tu.name)" -ForegroundColor Yellow
        # Execute using module's standard tool executor
        $result = Invoke-AnthropicStandardTool -ToolUse $tu
        $toolResults += New-AnthropicToolResult -ToolUseId $tu.id -Content $result
    }

    $messages += @{ role = 'assistant'; content = $response.content }
    foreach ($tr in $toolResults) { $messages += $tr }

    $response = Invoke-AnthropicMessage -Messages $messages -Tools $standardTools
}

Write-Host 'Summary:' -ForegroundColor Green
$response | Get-AnthropicResponseText
#endregion

#region 9b. Shell Safety Demo
Write-Host "`n=== 9b. Shell Safety (Sandboxed vs Unsafe) ===" -ForegroundColor Magenta
Write-Host 'Shell commands run in a constrained runspace by default for security.' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Sandboxed mode (default):' -ForegroundColor Yellow
Write-Host '  - ConstrainedLanguage mode (blocks .NET type abuse)' -ForegroundColor Gray
Write-Host '  - Curated whitelist of safe commands' -ForegroundColor Gray
Write-Host '  - Timeout protection' -ForegroundColor Gray
Write-Host ''
Write-Host 'Unsafe mode (-Unsafe switch):' -ForegroundColor DarkRed
Write-Host '  - No restrictions, uses Invoke-Expression directly' -ForegroundColor Gray
Write-Host '  - FOR TESTING ONLY!' -ForegroundColor Gray
Write-Host ''

# Create a mock tool use object to demonstrate
$mockToolUse = @{
    name  = 'pwsh'
    input = @{
        command = 'Get-Date -Format "yyyy-MM-dd HH:mm:ss"'
    }
}

Write-Host "Testing command: Get-Date -Format 'yyyy-MM-dd HH:mm:ss'" -ForegroundColor Cyan
Write-Host ''

Write-Host '  [Sandboxed]: ' -ForegroundColor Yellow -NoNewline
$resultSandboxed = Invoke-AnthropicStandardTool -ToolUse $mockToolUse -AllowShell -TimeoutSeconds 5
Write-Host $resultSandboxed -ForegroundColor $(if ($resultSandboxed -match '^Error:') { 'Red' }else { 'Green' })

Write-Host '  [Unsafe]:    ' -ForegroundColor Yellow -NoNewline
$resultUnsafe = Invoke-AnthropicStandardTool -ToolUse $mockToolUse -AllowShell -Unsafe -TimeoutSeconds 5
Write-Host $resultUnsafe -ForegroundColor $(if ($resultUnsafe -match '^Error:') { 'Red' }else { 'Green' })

Write-Host ''

# Demonstrate blocking dangerous .NET access with ConstrainedLanguage
Write-Host 'Testing .NET type access (blocked by ConstrainedLanguage):' -ForegroundColor Cyan
$dangerousToolUse = @{
    name  = 'pwsh'
    input = @{
        command = '[System.IO.File]::Exists("C:\Windows\System32\cmd.exe")'
    }
}

Write-Host '  Command: [System.IO.File]::Exists(...)' -ForegroundColor Gray
Write-Host '  [Sandboxed]: ' -ForegroundColor Yellow -NoNewline
$resultSandboxed = Invoke-AnthropicStandardTool -ToolUse $dangerousToolUse -AllowShell -TimeoutSeconds 5
Write-Host $resultSandboxed -ForegroundColor $(if ($resultSandboxed -match 'Error|not allowed') { 'Green' }else { 'Red' })

Write-Host '  [Unsafe]:    ' -ForegroundColor Yellow -NoNewline
$resultUnsafe = Invoke-AnthropicStandardTool -ToolUse $dangerousToolUse -AllowShell -Unsafe -TimeoutSeconds 5
Write-Host $resultUnsafe -ForegroundColor $(if ($resultUnsafe -eq 'True' -or $resultUnsafe -eq 'False') { 'DarkYellow' }else { 'Gray' })

Write-Host ''
Write-Host 'ConstrainedLanguage mode prevents direct .NET type access for security.' -ForegroundColor DarkGray
#endregion

#region 9c. InvokeMode Parameter Demo
Write-Host "`n=== 9c. Tool InvokeMode (Confirm/None/Auto) ===" -ForegroundColor Magenta
Write-Host 'Control how tools execute: Auto (default), Confirm (ask user), or None (dry-run)' -ForegroundColor Cyan

$mockToolUse = @{
    name  = 'read_file'
    input = @{
        path      = "$PSScriptRoot\README.md"
        max_lines = 5
    }
}

# InvokeMode: None (dry run - shows what would happen without executing)
Write-Host "`n[InvokeMode: None] - Dry run mode:" -ForegroundColor Yellow
$dryRunResult = Invoke-AnthropicStandardTool -ToolUse $mockToolUse -InvokeMode None
Write-Host "  $dryRunResult" -ForegroundColor DarkGray

# InvokeMode: Auto (default - executes immediately)
Write-Host "`n[InvokeMode: Auto] - Executes immediately (default):" -ForegroundColor Yellow
$autoResult = Invoke-AnthropicStandardTool -ToolUse $mockToolUse -InvokeMode Auto
$preview = ($autoResult -split "`n" | Select-Object -First 3) -join "`n"
Write-Host "  Result preview: $preview..." -ForegroundColor Green

# InvokeMode: Confirm - would prompt user (skip in automated demo)
Write-Host "`n[InvokeMode: Confirm] - Would prompt for confirmation (skipped in demo)" -ForegroundColor Yellow
Write-Host "  Usage: Invoke-AnthropicStandardTool -ToolUse `$toolUse -InvokeMode Confirm" -ForegroundColor DarkGray
#endregion

#region 10. Multi-Tool Agent
Write-Host "`n=== 10. Multi-Tool Agent ===" -ForegroundColor Magenta
Write-Host 'Letting model explore the codebase autonomously...' -ForegroundColor Cyan

$messages = @(
    New-AnthropicMessage -Role 'user' -Content "Explore $PSScriptRoot. Find all .ps1 files and tell me what this project does."
)

$response = Invoke-AnthropicMessage -Messages $messages -Tools $standardTools
$iterations = 0
$maxIterations = 10

while ($response.stop_reason -eq 'tool_use' -and $iterations -lt $maxIterations) {
    $iterations++
    $toolUses = @($response.content | Where-Object { $_.type -eq 'tool_use' })

    Write-Host "  [$iterations] Tools: $($toolUses.name -join ', ')" -ForegroundColor Yellow

    $toolResults = @()
    foreach ($tu in $toolUses) {
        $result = Invoke-AnthropicStandardTool -ToolUse $tu
        $toolResults += New-AnthropicToolResult -ToolUseId $tu.id -Content $result
    }

    $messages += @{ role = 'assistant'; content = $response.content }
    foreach ($tr in $toolResults) { $messages += $tr }

    $response = Invoke-AnthropicMessage -Messages $messages -Tools $standardTools
}

Write-Host "`nAgent Analysis:" -ForegroundColor Green
$response | Get-AnthropicResponseText
#endregion

#region 10b. Model Router Demo
Write-Host "`n=== 10b. Model Router ===" -ForegroundColor Magenta
Write-Host 'Demonstrating automatic model routing based on task type' -ForegroundColor Cyan

# Define router models
$routerModels = @{
    Default = 'llama3.1-8k:latest'        # Fast general model
    Code    = 'qwen3-coder-8k:latest'     # Coding tasks
}

# Verify required models exist
$availableModels = Get-AnthropicModel | Select-Object -ExpandProperty name
$missingModels = $routerModels.Values | Where-Object { $_ -notin $availableModels }

if ($missingModels) {
    Write-Warning "Router demo skipped - missing models: $($missingModels -join ', ')"
    Write-Host '  Create optimized models with: docker exec ollama ollama create <name> -f /tmp/Modelfile' -ForegroundColor DarkGray
}
else {
    # Configure the router
    $logPath = Join-Path $PSScriptRoot 'router-demo.log'
    Set-AnthropicRouterConfig -Models $routerModels -LogPath $logPath -LogToConsole

    Write-Host "`nRouter configured:" -ForegroundColor Green
    $config = Get-AnthropicRouterConfig
    $config.Models.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key) -> $($_.Value)" -ForegroundColor Gray
    }

    # Demo 1: Default routing (general question)
    Write-Host "`n--- Default Task ---" -ForegroundColor Yellow
    $response = Invoke-AnthropicRouted -Messages @(
        New-AnthropicMessage -Role 'user' -Content 'What is 2 + 2? Answer briefly.'
    )
    Write-Host "Response: $($response | Get-AnthropicResponseText)" -ForegroundColor Green

    # Demo 2: Code task routing (switches to coding model)
    Write-Host "`n--- Code Task ---" -ForegroundColor Yellow
    $response = Invoke-AnthropicRouted -Messages @(
        New-AnthropicMessage -Role 'user' -Content 'Write a one-line PowerShell command to list files.'
    ) -TaskType Code
    Write-Host "Response: $($response | Get-AnthropicResponseText)" -ForegroundColor Green

    # Demo 3: Unknown task type (falls back to Default with warning)
    Write-Host "`n--- Unknown Task (fallback demo) ---" -ForegroundColor Yellow
    $response = Invoke-AnthropicRouted -Messages @(
        New-AnthropicMessage -Role 'user' -Content 'Say hello.'
    ) -TaskType UnknownTask -WarningAction SilentlyContinue
    Write-Host "Response: $($response | Get-AnthropicResponseText)" -ForegroundColor Green

    # Clean up router config and log file
    Clear-AnthropicRouterConfig -Force
    if (Test-Path $logPath) { Remove-Item $logPath -Force }
    Write-Host "`nRouter cleared and log cleaned up." -ForegroundColor Gray
}
#endregion

#region 11. Switch Models
Write-Host "`n=== 11. Switch Models ===" -ForegroundColor Magenta

# Pick a different model from what we're using
$currentModel = (Get-AnthropicConnection).Model
$availableModels = Get-AnthropicModel | Select-Object -ExpandProperty name
$alternateModel = $availableModels | Where-Object { $_ -ne $currentModel } | Select-Object -First 1

if ($alternateModel) {
    Connect-Anthropic -Model $alternateModel -Force
    Write-Host "Switched to: $((Get-AnthropicConnection).Model)" -ForegroundColor Cyan

    $response = Invoke-AnthropicMessage -Messages @(
        New-AnthropicMessage -Role 'user' -Content 'Say hello in French!'
    )
    $response | Get-AnthropicResponseText
}
else {
    Write-Host 'Only one model available, skipping switch demo' -ForegroundColor Yellow
}
#endregion

#region 12. Cleanup
Write-Host "`n=== 12. Cleanup ===" -ForegroundColor Magenta

# Demonstrate -WhatIf support (PowerShell 7+ best practice)
Write-Host 'Testing -WhatIf support:' -ForegroundColor Cyan
Disconnect-Anthropic -WhatIf

# Actually disconnect
Disconnect-Anthropic
Write-Host 'Disconnected.' -ForegroundColor Green
#endregion

Write-Host "`n=== Demo Complete ===" -ForegroundColor Magenta


$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Give me a number under 1000 that has an "a" in its spelling?'
)
$response | Get-AnthropicResponseText