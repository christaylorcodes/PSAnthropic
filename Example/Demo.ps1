# PSAnthropic - Module Demo Script
#
# A guided, progressive tour of the module. Each region builds on the previous
# one, moving from a single request up to autonomous, multi-tool agents. Read it
# top to bottom as a tutorial - the "builds on" line in each region shows the path.
#
# Learning arc:
#   1 / 1b   Connect & adapt     - open a connection; the module discovers the
#                                  backend and shapes each request to its capabilities
#   2 - 4    Single requests     - message in / reply out, system prompts, sampling
#   4b / 5   Richer requests     - extended thinking, streaming
#   6        State across turns  - multi-turn conversations
#   7        Multimodal          - images / vision
#   8 - 8c   Tools & ergonomics  - define/handle a tool, auto-generate tools,
#                                  response convenience properties
#   9 - 9c   Tools, safely       - the built-in tool set + loop, sandboxing, run modes
#   10 / 10b Agents & routing    - autonomous tool loop; per-task model routing
#   11 / 12  Operations          - switch models, disconnect cleanly
#
# Requires: PowerShell 7+, and Ollama running locally (or any Anthropic-compatible endpoint)
#
# Usage:
#   .\Demo.ps1                    # Run with the default model
#   .\Demo.ps1 -Model 'qwen3:8b'  # Run with a specific model

param(
    # Model to use. If it isn't installed on the backend, region 1 falls back to
    # the first model the backend reports - so the demo runs on whatever you have.
    [string]$Model = 'qwen3:8b'
)

# Remove module first to avoid type definition conflicts when reloading
# (PowerShell classes from ScriptsToProcess don't update properly with -Force alone)
Remove-Module PSAnthropic -Force -ErrorAction SilentlyContinue
# Module lives at the repo root (one level up from this Example folder)
Import-Module "$PSScriptRoot\..\PSAnthropic" -Force

# Repo root holds README.md and other project files (this script lives in Example/)
$repoRoot = Split-Path -Path $PSScriptRoot -Parent

#region 1. Connection & Setup
# ----------------------------------------------------------
# 1. CONNECTION & SETUP   (start here)
#   Learn : open a connection and discover what the backend offers.
#   Uses  : Test-AnthropicEndpoint, Connect-Anthropic, Get-AnthropicConnection,
#           Get-AnthropicModel
#   Why   : every later region needs a live connection; the detected Provider
#           and the model list drive everything that follows.
# ----------------------------------------------------------
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
$conn = Get-AnthropicConnection
Write-Host "Connected with model: $Model" -ForegroundColor Cyan
# The backend is auto-detected and stored as .Provider (Ollama / Anthropic / Generic),
# which drives how each request is shaped (see region 1b).
Write-Host "Backend detected (Provider): $($conn.Provider)" -ForegroundColor Cyan
$conn

# List available models - discovered live from the backend (/api/tags on Ollama,
# /v1/models on Anthropic Cloud), cached on the connection. Use -Refresh to re-query.
Write-Host "`nAvailable models:" -ForegroundColor Cyan
$installedModels = Get-AnthropicModel | Select-Object -ExpandProperty name
$installedModels | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }

# Resolve to models actually installed on this Ollama instance so later regions
# use what's present instead of hard-coded names.
if ($Model -notin $installedModels) {
    $fallback = $installedModels | Select-Object -First 1
    Write-Host "Model '$Model' not installed; using '$fallback' instead." -ForegroundColor Yellow
    $Model = $fallback
    Connect-Anthropic -Model $Model -Force
}
$visionModel = $installedModels | Where-Object { $_ -match 'vision|llava' } | Select-Object -First 1
$coderModel = $installedModels | Where-Object { $_ -match 'coder|code' } | Select-Object -First 1
if (-not $coderModel) { $coderModel = $installedModels | Where-Object { $_ -ne $Model } | Select-Object -First 1 }
if (-not $coderModel) { $coderModel = $Model }
#endregion

#region 1b. Backend Capability Awareness
# ----------------------------------------------------------
# 1b. BACKEND CAPABILITY AWARENESS   (builds on: 1)
#   Learn : the module tailors each request to the connected backend.
#   Uses  : Invoke-AnthropicMessage with Anthropic-only options + -WarningVariable
#   Why   : the SAME script works on Ollama or Anthropic Cloud - options the backend
#           can't handle (caching, effort, tool_choice, metadata) are dropped with a
#           warning instead of erroring.
# ----------------------------------------------------------
Write-Host "`n=== 1b. Backend Capability Awareness ===" -ForegroundColor Magenta
Write-Host 'The module shapes each request to what the connected backend supports.' -ForegroundColor Cyan
Write-Host 'Anthropic-Cloud-only fields are dropped (with a warning) on Ollama instead of erroring,' -ForegroundColor Yellow
Write-Host 'so the same script works against either backend.' -ForegroundColor Yellow

# Ask one question while requesting several Anthropic-Cloud-only options. Against Ollama
# these are gracefully omitted; against Anthropic Cloud the same call would use them.
$capArgs = @{
    MaxTokens    = 20
    CacheControl = $true                  # prompt caching (Anthropic only)
    Effort       = 'high'                 # output_config.effort (Anthropic only)
    ToolChoice   = 'auto'                 # tool_choice (Ollama does not support)
    Metadata     = @{ user_id = 'demo' }  # metadata (Anthropic only)
}
$capResponse = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Reply with just the word: ready'
) @capArgs -WarningVariable capWarnings -WarningAction SilentlyContinue

$provider = (Get-AnthropicConnection).Provider
Write-Host "`nFields dropped for this backend ($provider):" -ForegroundColor Yellow
if ($capWarnings) {
    $capWarnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
}
else {
    Write-Host '  (none - this backend supports all of them)' -ForegroundColor DarkGray
}
Write-Host "Call still succeeded: $($capResponse.Answer)" -ForegroundColor Green
#endregion

#region 2. Basic Message
# ----------------------------------------------------------
# 2. BASIC MESSAGE   (builds on: 1)
#   Learn : send one prompt, read one reply.
#   Uses  : New-AnthropicMessage -> Invoke-AnthropicMessage -> Get-AnthropicResponseText
#   Why   : this request/response pair is the foundation every later region builds on.
#           (-Verbose prints the actual HTTP request the module sends.)
# ----------------------------------------------------------
Write-Host "`n=== 2. Basic Message ===" -ForegroundColor Magenta

$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'What is PowerShell in one sentence?'
) -Verbose

Write-Host 'Response:' -ForegroundColor Green
$response | Get-AnthropicResponseText
#endregion

#region 3. System Prompt
# ----------------------------------------------------------
# 3. SYSTEM PROMPT   (builds on: 2)
#   Learn : steer the model's persona and rules with a system prompt.
#   Uses  : Invoke-AnthropicMessage -System
#   Why   : separates "how to answer" (system) from "what to answer" (user turn).
# ----------------------------------------------------------
Write-Host "`n=== 3. System Prompt ===" -ForegroundColor Magenta

$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Explain variables'
) -System 'You are a PowerShell tutor. Give brief answers with one code example.'

$response | Get-AnthropicResponseText
#endregion

#region 4. Generation Parameters
# ----------------------------------------------------------
# 4. GENERATION PARAMETERS   (builds on: 2)
#   Learn : tune how a reply is sampled.
#   Uses  : -Temperature (creativity vs determinism), -MaxTokens (length cap)
#   Why   : the same prompt can be made more focused or more varied.
# ----------------------------------------------------------
Write-Host "`n=== 4. Generation Parameters ===" -ForegroundColor Magenta

# High temperature = more creative/random
$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Give me one random word.'
) -Temperature 1.0 -MaxTokens 20

Write-Host 'Random word (temp=1.0):' -ForegroundColor Cyan
$response | Get-AnthropicResponseText
#endregion

#region 4b. Extended Thinking Mode
# ----------------------------------------------------------
# 4b. EXTENDED THINKING   (builds on: 4)
#   Learn : let the model reason before it answers.
#   Uses  : -Thinking, -ThinkingBudget (Ollama)  /  -Effort (Anthropic adaptive)
#   Why   : improves multi-step answers; the reasoning comes back as separate
#           'thinking' content blocks, distinct from the final answer text.
# ----------------------------------------------------------
Write-Host "`n=== 4b. Extended Thinking Mode ===" -ForegroundColor Magenta
Write-Host "Note: Extended thinking lets the model 'think' before responding." -ForegroundColor Yellow
Write-Host '  -ThinkingBudget applies here (Ollama "enabled" thinking). On current Anthropic' -ForegroundColor DarkGray
Write-Host '  models, -Thinking becomes adaptive thinking - steer depth with -Effort instead.' -ForegroundColor DarkGray

# With thinking enabled, model includes reasoning in response (budget used on Ollama;
# ignored on adaptive-thinking Anthropic models, which use -Effort)
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
# ----------------------------------------------------------
# 5. STREAMING   (builds on: 2)
#   Learn : consume a reply incrementally as it is generated.
#   Uses  : Invoke-AnthropicMessage -Stream, piped to ForEach-Object
#   Why   : responsive output for long replies. Note you PROCESS EVENTS as they
#           arrive - do NOT assign -Stream to a variable (you'd collect raw events,
#           not a single response object).
# ----------------------------------------------------------
Write-Host "`n=== 5. Streaming Response ===" -ForegroundColor Magenta

Write-Host 'Streaming: ' -ForegroundColor Cyan -NoNewline
Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Write a haiku about coding.'
) -Stream | ForEach-Object {
    # Each event is a small delta; keep only the text deltas and print without newlines
    if ($_.type -eq 'content_block_delta') {
        Write-Host $_.delta.text -NoNewline
    }
}
Write-Host ''
#endregion

#region 6. Multi-turn Conversation
# ----------------------------------------------------------
# 6. MULTI-TURN CONVERSATION   (builds on: 2, 3)
#   Learn : carry context across turns so the model "remembers".
#   Uses  : New-AnthropicConversation, Add-AnthropicMessage
#   Why   : the API is stateless - you must resend the whole history each turn.
#           A conversation object collects messages so you don't rebuild it by hand.
# ----------------------------------------------------------
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
# ----------------------------------------------------------
# 7. IMAGE CONTENT / VISION   (builds on: 2)
#   Learn : send images alongside text (multimodal input).
#   Uses  : New-AnthropicImageContent, content blocks in a message
#   Why   : same message shape as text, just richer content - requires a
#           vision-capable model, so this region self-skips if none is installed.
# ----------------------------------------------------------
Write-Host "`n=== 7. Image Content (Vision) ===" -ForegroundColor Magenta

if (-not $visionModel) {
    Write-Host 'No vision-capable model installed - skipping vision demo.' -ForegroundColor Yellow
}
else {
    # Switch to vision model
    $originalModel = (Get-AnthropicConnection).Model
    Connect-Anthropic -Model $visionModel -Force
    Write-Host "Switched to vision model: $visionModel" -ForegroundColor Cyan

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
}
#endregion

#region 8. Simple Tool Use
# ----------------------------------------------------------
# 8. SIMPLE TOOL USE   (builds on: 2)
#   Learn : give the model a tool and handle the single call it makes.
#   Uses  : New-AnthropicTool, $response.stop_reason -eq 'tool_use', New-AnthropicToolResult
#   Why   : the manual tool round-trip (model asks -> you run it -> you return the
#           result -> model answers) is the building block for agents in region 10.
# ----------------------------------------------------------
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

    # Send the result back so the model can answer. The history must replay, in order:
    #   1) the original user turn, 2) the assistant's tool_use, 3) the tool_result.
    # Omit the assistant turn and the API rejects the mismatched tool_result.
    $final = Invoke-AnthropicMessage -Messages @(
        New-AnthropicMessage -Role 'user' -Content 'What time is it in UTC?'
        @{ role = 'assistant'; content = $response.content }
        $toolResult
    )
    Write-Host "Response: $($final | Get-AnthropicResponseText)" -ForegroundColor Green
}
#endregion

#region 8b. Auto-Generate Tool from Command
# ----------------------------------------------------------
# 8b. AUTO-GENERATE TOOLS   (builds on: 8)
#   Learn : turn an existing cmdlet into a tool definition automatically.
#   Uses  : New-AnthropicToolFromCommand (-Strict, -IncludeExamples)
#   Why   : skip hand-writing JSON schemas - PowerShell parameter types and
#           validation become the tool's input schema. Pipe many cmdlets to make many.
# ----------------------------------------------------------
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
# ----------------------------------------------------------
# 8c. RESPONSE ERGONOMICS   (builds on: 2, 6)
#   Learn : convenience properties the module adds to every response.
#   Uses  : $response.Answer (text), .History (ready-to-continue messages), .ToolUse
#   Why   : less boilerplate - .Answer skips digging into content blocks, and
#           .History lets you continue a conversation without rebuilding it (region 6).
# ----------------------------------------------------------
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
# ----------------------------------------------------------
# 9. STANDARD TOOLS   (builds on: 8)
#   Learn : use the module's built-in tool set with an automatic execution loop.
#   Uses  : Get-AnthropicStandardTools, Invoke-AnthropicStandardTool, a tool loop
#   Why   : region 8 handled ONE call by hand; real tasks need many. This is the
#           loop you repeat until the model stops asking for tools.
# ----------------------------------------------------------
Write-Host "`n=== 9. Standard Tools ===" -ForegroundColor Magenta

# Get pre-defined tools from module
$standardTools = Get-AnthropicStandardTools
Write-Host 'Available standard tools:' -ForegroundColor Cyan
$standardTools | ForEach-Object { Write-Host "  - $($_.name)" -ForegroundColor Gray }

# Use standard tools with automatic execution
Write-Host "`nAsking model to read a file..." -ForegroundColor Cyan

$messages = @(
    New-AnthropicMessage -Role 'user' -Content "Read the file at $repoRoot\README.md and summarize it in 2 sentences."
)

$response = Invoke-AnthropicMessage -Messages $messages -Tools $standardTools

# Tool-use loop: keep going while the model wants tools. Each pass runs every
# requested tool, appends the assistant's tool_use turn + the tool_results, then
# re-sends. It exits when stop_reason is no longer 'tool_use' (the model has answered).
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
# ----------------------------------------------------------
# 9b. SHELL SAFETY   (builds on: 9)
#   Learn : how shell tool calls are sandboxed by default.
#   Uses  : Invoke-AnthropicStandardTool -AllowShell  (vs the -Unsafe escape hatch)
#   Why   : a model running shell commands is dangerous - ConstrainedLanguage,
#           a command whitelist, and a timeout contain it. -Unsafe removes all of that.
# ----------------------------------------------------------
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
# Expected: BLOCKED. ConstrainedLanguage refuses direct .NET type calls - the
# error here is the safety feature working, not a demo failure.
$resultSandboxed = Invoke-AnthropicStandardTool -ToolUse $dangerousToolUse -AllowShell -TimeoutSeconds 5
Write-Host $resultSandboxed -ForegroundColor $(if ($resultSandboxed -match 'Error|not allowed') { 'Green' }else { 'Red' })

Write-Host '  [Unsafe]:    ' -ForegroundColor Yellow -NoNewline
$resultUnsafe = Invoke-AnthropicStandardTool -ToolUse $dangerousToolUse -AllowShell -Unsafe -TimeoutSeconds 5
Write-Host $resultUnsafe -ForegroundColor $(if ($resultUnsafe -eq 'True' -or $resultUnsafe -eq 'False') { 'DarkYellow' }else { 'Gray' })

Write-Host ''
Write-Host 'ConstrainedLanguage mode prevents direct .NET type access for security.' -ForegroundColor DarkGray
#endregion

#region 9c. InvokeMode Parameter Demo
# ----------------------------------------------------------
# 9c. TOOL INVOKE MODE   (builds on: 9)
#   Learn : control whether and how a tool actually executes.
#   Uses  : Invoke-AnthropicStandardTool -InvokeMode  None | Auto | Confirm
#   Why   : None = dry-run (preview only), Auto = run now, Confirm = ask first.
#           Gate side effects before letting a model trigger them.
# ----------------------------------------------------------
Write-Host "`n=== 9c. Tool InvokeMode (Confirm/None/Auto) ===" -ForegroundColor Magenta
Write-Host 'Control how tools execute: Auto (default), Confirm (ask user), or None (dry-run)' -ForegroundColor Cyan

$mockToolUse = @{
    name  = 'read_file'
    input = @{
        path      = "$repoRoot\README.md"
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
# ----------------------------------------------------------
# 10. MULTI-TOOL AGENT   (builds on: 8, 9)
#   Learn : let the model drive its own multi-step tool loop ("an agent").
#   Uses  : the standard tool set + a BOUNDED while loop (maxIterations)
#   Why   : agent = tools + looping + a stop condition. Same loop as region 9,
#           but the model chooses which tools to chain to reach an open-ended goal.
# ----------------------------------------------------------
Write-Host "`n=== 10. Multi-Tool Agent ===" -ForegroundColor Magenta
Write-Host 'Letting model explore the codebase autonomously...' -ForegroundColor Cyan

$messages = @(
    New-AnthropicMessage -Role 'user' -Content "Explore $PSScriptRoot. Find all .ps1 files and tell me what this project does."
)

$response = Invoke-AnthropicMessage -Messages $messages -Tools $standardTools
$iterations = 0
$maxIterations = 10   # safety cap: stop even if the model keeps asking for tools

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
# ----------------------------------------------------------
# 10b. MODEL ROUTER   (builds on: 1, 10)
#   Learn : route each request to a model chosen by task type.
#   Uses  : Set-AnthropicRouterConfig, Invoke-AnthropicRouted -TaskType
#   Why   : use a small fast model for chat and a stronger one for code, with a
#           Default fallback when a task type isn't mapped.
# ----------------------------------------------------------
Write-Host "`n=== 10b. Model Router ===" -ForegroundColor Magenta
Write-Host 'Demonstrating automatic model routing based on task type' -ForegroundColor Cyan

# Define router models
$routerModels = @{
    Default = $Model         # Fast general model (installed)
    Code    = $coderModel    # Coding tasks (installed substitute)
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
# ----------------------------------------------------------
# 11. SWITCH MODELS   (builds on: 1)
#   Learn : change the active model mid-session.
#   Uses  : Connect-Anthropic -Force
#   Why   : pick the right model on the fly (cost, speed, capability) without
#           tearing down and rebuilding the connection.
# ----------------------------------------------------------
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

# Bonus - one last plain message. Ordering matters: this MUST run before region 12
# disconnects, otherwise the call fails with "Not connected" (the connection is gone).
$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Give me a number under 1000 that has an "a" in its spelling?'
)
$response | Get-AnthropicResponseText

#region 12. Cleanup
# ----------------------------------------------------------
# 12. CLEANUP   (builds on: 1)
#   Learn : tear down the session safely.
#   Uses  : Disconnect-Anthropic  (-WhatIf to preview without acting)
#   Why   : -WhatIf shows what a destructive action WOULD do; always disconnect
#           when finished so no connection state lingers.
# ----------------------------------------------------------
Write-Host "`n=== 12. Cleanup ===" -ForegroundColor Magenta

# Demonstrate -WhatIf support (PowerShell 7+ best practice)
Write-Host 'Testing -WhatIf support:' -ForegroundColor Cyan
Disconnect-Anthropic -WhatIf

# Actually disconnect
Disconnect-Anthropic
Write-Host 'Disconnected.' -ForegroundColor Green
#endregion

Write-Host "`n=== Demo Complete ===" -ForegroundColor Magenta