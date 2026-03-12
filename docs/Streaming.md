# Streaming Responses

Stream AI responses as they're generated, showing text immediately instead of waiting for the complete response.

## When to Use Streaming

Use streaming when:

- **Long responses** - Show progress as text is generated
- **Interactive applications** - Reduce perceived latency
- **Real-time display** - Text appears as the AI "types"

Use non-streaming when:

- **Processing responses programmatically** - Easier to work with single response object
- **Using `.Answer` or `.History`** - These convenience properties aren't available in streaming mode
- **Tool loops** - Standard tool loop pattern uses non-streaming

## Basic Usage

Add `-Stream` to `Invoke-AnthropicMessage`:

```powershell
Connect-Anthropic -Server 'localhost:11434'

Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Write a haiku about PowerShell'
) -Stream | ForEach-Object {
    if ($_.type -eq 'content_block_delta') {
        Write-Host $_.delta.text -NoNewline
    }
}
Write-Host ""  # Final newline
```

## Event Types Reference

Streaming returns a sequence of Server-Sent Events (SSE). Each event is a PowerShell object with a `type` property.

| Event Type | When Emitted | Key Properties |
|------------|--------------|----------------|
| `message_start` | Stream begins | `message.id`, `message.model`, `message.role` |
| `content_block_start` | New content block begins | `index`, `content_block.type` |
| `content_block_delta` | Content chunk received | `index`, `delta.type`, `delta.text` |
| `content_block_stop` | Content block complete | `index` |
| `message_delta` | Message-level updates | `delta.stop_reason`, `usage.output_tokens` |
| `message_stop` | Stream complete | (none) |

### Event Sequence Example

A typical text response produces this sequence:

```
message_start        → { message: { id: "msg_123", model: "llama3" } }
content_block_start  → { index: 0, content_block: { type: "text" } }
content_block_delta  → { index: 0, delta: { type: "text_delta", text: "Hello" } }
content_block_delta  → { index: 0, delta: { type: "text_delta", text: " world" } }
content_block_delta  → { index: 0, delta: { type: "text_delta", text: "!" } }
content_block_stop   → { index: 0 }
message_delta        → { delta: { stop_reason: "end_turn" }, usage: { output_tokens: 3 } }
message_stop         → {}
```

## Processing Events

### Show Text as It Arrives

```powershell
Invoke-AnthropicMessage -Messages $msgs -Stream | ForEach-Object {
    switch ($_.type) {
        'content_block_delta' {
            if ($_.delta.type -eq 'text_delta') {
                Write-Host $_.delta.text -NoNewline
            }
        }
        'message_stop' {
            Write-Host ""  # Newline at end
        }
    }
}
```

### Accumulate Full Response

```powershell
$fullText = ""

Invoke-AnthropicMessage -Messages $msgs -Stream | ForEach-Object {
    if ($_.type -eq 'content_block_delta' -and $_.delta.type -eq 'text_delta') {
        $fullText += $_.delta.text
        Write-Host $_.delta.text -NoNewline
    }
}

Write-Host ""
# $fullText now contains the complete response
```

### Track Usage and Stop Reason

```powershell
$stopReason = $null
$outputTokens = 0

Invoke-AnthropicMessage -Messages $msgs -Stream | ForEach-Object {
    switch ($_.type) {
        'content_block_delta' {
            Write-Host $_.delta.text -NoNewline
        }
        'message_delta' {
            $stopReason = $_.delta.stop_reason
            $outputTokens = $_.usage.output_tokens
        }
    }
}

Write-Host "`n`nStop reason: $stopReason"
Write-Host "Tokens used: $outputTokens"
```

## Error Handling

Streaming errors can occur during the stream, not just at the start:

```powershell
try {
    Invoke-AnthropicMessage -Messages $msgs -Stream -TimeoutSec 60 | ForEach-Object {
        if ($_.type -eq 'content_block_delta') {
            Write-Host $_.delta.text -NoNewline
        }
    }
    Write-Host ""
}
catch [AnthropicConnectionException] {
    Write-Error "Stream interrupted: $($_.Exception.Message)"
}
catch {
    Write-Error "Unexpected error: $_"
}
```

### Timeout Configuration

```powershell
# Set streaming timeout (default is very long for streaming)
Invoke-AnthropicMessage -Messages $msgs -Stream -TimeoutSec 120 | ForEach-Object {
    # Process events
}
```

## Streaming vs Non-Streaming Comparison

| Aspect | Non-Streaming | Streaming |
|--------|---------------|-----------|
| Return type | Single `PSCustomObject` | Event stream |
| `.Answer` property | Available | Not available |
| `.History` property | Available | Not available |
| `.ToolUse` property | Available | Not available |
| First output | After complete generation | Immediately |
| Error timing | After request completes | During stream |
| Memory usage | Buffered | Per-event |
| Use with tool loops | Recommended | Possible but complex |

## Streaming with Tools

When the AI requests tools during streaming, you'll see `tool_use` content blocks:

```powershell
$toolRequests = @()

Invoke-AnthropicMessage -Messages $msgs -Tools $tools -Stream | ForEach-Object {
    switch ($_.type) {
        'content_block_start' {
            if ($_.content_block.type -eq 'tool_use') {
                Write-Host "Tool requested: $($_.content_block.name)" -ForegroundColor Yellow
                $toolRequests += @{
                    id = $_.content_block.id
                    name = $_.content_block.name
                    input = ""
                }
            }
        }
        'content_block_delta' {
            if ($_.delta.type -eq 'text_delta') {
                Write-Host $_.delta.text -NoNewline
            }
            elseif ($_.delta.type -eq 'input_json_delta') {
                # Accumulate tool input JSON
                $toolRequests[-1].input += $_.delta.partial_json
            }
        }
        'message_delta' {
            if ($_.delta.stop_reason -eq 'tool_use') {
                Write-Host "`nAI wants to use tools" -ForegroundColor Cyan
            }
        }
    }
}
```

**Note:** For tool loops, non-streaming is typically easier. Use streaming with tools only when you need to show the AI's "thinking" text before tool requests.

## Advanced: Custom Event Handler

Create a reusable streaming handler:

```powershell
function Show-StreamingResponse {
    param(
        [Parameter(ValueFromPipeline)]
        [object]$Event,

        [switch]$ShowUsage
    )

    process {
        switch ($Event.type) {
            'message_start' {
                if ($ShowUsage) {
                    Write-Host "Model: $($Event.message.model)" -ForegroundColor DarkGray
                }
            }
            'content_block_delta' {
                if ($Event.delta.type -eq 'text_delta') {
                    Write-Host $Event.delta.text -NoNewline
                }
            }
            'message_delta' {
                if ($ShowUsage -and $Event.usage) {
                    Write-Host "`n[Tokens: $($Event.usage.output_tokens)]" -ForegroundColor DarkGray
                }
            }
            'message_stop' {
                Write-Host ""
            }
        }
    }
}

# Usage
Invoke-AnthropicMessage -Messages $msgs -Stream | Show-StreamingResponse -ShowUsage
```

## Troubleshooting

### No Output Appears

**Problem:** Script runs but nothing is displayed.

**Solution:** Make sure you're processing events in the pipeline:

```powershell
# WRONG - Events are generated but not processed
$result = Invoke-AnthropicMessage -Messages $msgs -Stream

# CORRECT - Process events as they arrive
Invoke-AnthropicMessage -Messages $msgs -Stream | ForEach-Object {
    # Process each event
}
```

### Response Cuts Off

**Problem:** Streaming stops before completion.

**Possible causes:**
1. Timeout - increase `-TimeoutSec`
2. Token limit - check `message_delta` for `stop_reason: max_tokens`
3. Server disconnection - check Ollama logs

### Can't Use .Answer

**Problem:** `.Answer` property is empty or missing on streamed response.

**Solution:** `.Answer` is only available on non-streaming responses. Accumulate text manually when streaming:

```powershell
$fullText = ""
Invoke-AnthropicMessage -Messages $msgs -Stream | ForEach-Object {
    if ($_.type -eq 'content_block_delta' -and $_.delta.text) {
        $fullText += $_.delta.text
    }
}
# Use $fullText instead of .Answer
```
