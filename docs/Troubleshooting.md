# Troubleshooting

Common issues and solutions when using PSAnthropic.

> **Note:** Error messages shown below are representative. Actual messages may vary slightly.

## Connection Issues

### "Not connected. Call Connect-Anthropic first."

**Cause:** No active connection to an API endpoint.

**Solution:**
```powershell
# Connect to local Ollama
Connect-Anthropic -Model 'llama3'

# Verify connection
Get-AnthropicConnection
```

### "Connection refused" or "Unable to connect"

**Cause:** Ollama is not running or not accessible.

**Solutions:**

1. Start Ollama:
   ```bash
   ollama serve
   ```

2. Check if Ollama is running:
   ```powershell
   Test-AnthropicEndpoint
   # Returns $true if healthy
   ```

3. Verify the server address:
   ```powershell
   # Default is localhost:11434
   Connect-Anthropic -Server 'localhost:11434' -Model 'llama3'
   ```

### "404 Not Found" on /v1/messages

**Cause:** Ollama version doesn't support Anthropic compatibility or endpoint is wrong.

**Solutions:**

1. Update Ollama to the latest version (Anthropic compatibility requires a recent release)
2. Verify the API path is `/v1/messages`
3. Check Ollama logs for more details

## Model Issues

### "Model not found" or "Unknown model"

**Cause:** The specified model isn't pulled/available.

**Solutions:**

1. List available models:
   ```powershell
   Get-AnthropicModel
   ```

2. Pull the model in Ollama:
   ```bash
   ollama pull llama3
   ```

3. Use an available model:
   ```powershell
   $models = Get-AnthropicModel
   Connect-Anthropic -Model $models[0].name
   ```

### "Model does not support vision" or image errors

**Cause:** Using image content with a non-vision model.

**Solution:** Use a vision-capable model:
```powershell
Connect-Anthropic -Model 'llava' -Force
# or
Connect-Anthropic -Model 'llama3.2-vision:11b' -Force
```

## Tool Use Issues

### "Shell execution is disabled"

**Cause:** Trying to use `pwsh` tool without `-AllowShell`.

**Solution:**
```powershell
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell
```

### "Write operations are disabled"

**Cause:** Trying to use `str_replace_editor` create/edit without `-AllowWrite`.

**Solution:**
```powershell
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWrite
```

### Shell command not in whitelist

**Cause:** The command is not in the curated list of safe commands allowed in the sandboxed environment.

**Solutions:**

1. Check if an alternative whitelisted command can accomplish the task. Common whitelisted commands include:
   - Filesystem: `Get-Content`, `Get-ChildItem`, `Get-Item`, `Test-Path`
   - Data: `ConvertTo-Json`, `ConvertFrom-Json`, `Select-String`
   - System: `Get-Process`, `Get-Service`, `Get-Date`

2. Use `-Unsafe` for testing only (bypasses sandboxing):

   ```powershell
   # WARNING: Only use in controlled environments
   $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell -Unsafe
   ```

3. See [StandardTools.md](StandardTools.md) for the full list of allowed commands.

### "Cannot invoke method" in ConstrainedLanguage

**Cause:** Direct .NET type access blocked by ConstrainedLanguage mode.

**Example blocked code:**
```powershell
[System.IO.File]::ReadAllText('file.txt')  # Blocked
```

**Solution:** Use PowerShell cmdlets instead:
```powershell
Get-Content -Path 'file.txt' -Raw  # Works
```

### Tool use loop never ends

**Cause:** Model keeps requesting tools without completing.

**Solution:** Always set a maximum iteration limit:
```powershell
$maxIterations = 10
$iteration = 0

while ($response.stop_reason -eq 'tool_use' -and $iteration -lt $maxIterations) {
    $iteration++
    # ... execute tools
}

if ($iteration -ge $maxIterations) {
    Write-Warning "Max iterations reached"
}
```

## Router Issues

### "Router not configured"

**Cause:** Called `Invoke-AnthropicRouted` before configuring the router.

**Solution:**
```powershell
Set-AnthropicRouterConfig -Models @{
    Default = 'llama3'
    Code    = 'qwen3-coder'
}
```

### "TaskType not found, using Default"

**Cause:** Requested task type not in router configuration.

**Solutions:**

1. Add the task type to configuration:
   ```powershell
   Set-AnthropicRouterConfig -Models @{
       Default = 'llama3'
       Code    = 'qwen3-coder'
       Vision  = 'llava'  # Add missing type
   }
   ```

2. Use a configured task type or 'Default'.

## Streaming Issues

### Streaming output not appearing

**Cause:** Not processing stream events correctly.

**Solution:**
```powershell
Invoke-AnthropicMessage -Messages $messages -Stream | ForEach-Object {
    if ($_.type -eq 'content_block_delta') {
        Write-Host $_.delta.text -NoNewline
    }
}
Write-Host ""  # Newline at end
```

### Streaming hangs or times out

**Cause:** Large response or slow model.

**Solution:** Increase timeout:
```powershell
Invoke-AnthropicMessage -Messages $messages -Stream -TimeoutSec 600
```

## Response Issues

### Empty response or "No text content found"

**Cause:** Response contains non-text content (tool_use, thinking, etc.).

**Solution:** Check response content type:
```powershell
$response.content | ForEach-Object {
    Write-Host "Type: $($_.type)"
    if ($_.type -eq 'text') { Write-Host $_.text }
    if ($_.type -eq 'tool_use') { Write-Host "Tool: $($_.name)" }
    if ($_.type -eq 'thinking') { Write-Host "Thinking: $($_.thinking)" }
}
```

### Response truncated

**Cause:** Hit `MaxTokens` limit.

**Solution:** Increase token limit:
```powershell
Invoke-AnthropicMessage -Messages $messages -MaxTokens 8192
```

## Performance Issues

### Slow responses

**Solutions:**

1. Use a smaller/faster model:
   ```powershell
   Connect-Anthropic -Model 'llama3.1:8b' -Force
   ```

2. Reduce context window (Ollama-specific):
   ```powershell
   Invoke-AnthropicMessage -Messages $messages -NumCtx 4096
   ```

3. Lower max tokens:
   ```powershell
   Invoke-AnthropicMessage -Messages $messages -MaxTokens 1024
   ```

### High memory usage

**Cause:** Large context window or model size.

**Solutions:**

1. Use smaller context:
   ```powershell
   Invoke-AnthropicMessage -Messages $messages -NumCtx 2048
   ```

2. Use quantized models (e.g., `llama3:8b-q4_0`)

## Getting Help

### View function documentation
```powershell
Get-Help Connect-Anthropic -Full
Get-Help Invoke-AnthropicMessage -Examples
```

### Check module version
```powershell
Get-Module PSAnthropic | Select-Object Name, Version
```

### Report issues
Open an issue at: https://github.com/christaylorcodes/PSAnthropic/issues
