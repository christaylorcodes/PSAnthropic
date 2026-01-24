# Model Router

The model router automatically selects the appropriate model based on task type, enabling intelligent model switching without manual intervention.

## Quick Start

```powershell
# First, establish a connection
Connect-Anthropic -Model 'llama3.1-8k'

# Configure router with task-to-model mappings
Set-AnthropicRouterConfig -Models @{
    Default = 'llama3.1-8k'
    Code    = 'qwen3-coder-8k'
    Vision  = 'llama3.2-vision:11b'
}

# Send messages with automatic routing
$response = Invoke-AnthropicRouted -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Write a PowerShell function'
) -TaskType Code

# Get the response
$response | Get-AnthropicResponseText
```

## Router Functions

| Function | Description |
|----------|-------------|
| `Set-AnthropicRouterConfig` | Configure task-to-model mappings and logging |
| `Get-AnthropicRouterConfig` | View current router configuration |
| `Clear-AnthropicRouterConfig` | Reset router configuration |
| `Invoke-AnthropicRouted` | Send messages with automatic model routing |
| `Get-AnthropicRouterLog` | View routing decision history |

## Configuration

### Basic Setup

```powershell
Set-AnthropicRouterConfig -Models @{
    Default = 'llama3.1-8k'      # Required - fallback for unknown task types
    Code    = 'qwen3-coder-8k'   # Optional - for coding tasks
}
```

### Common Task Types

| Task Type | Description | Suggested Model |
|-----------|-------------|-----------------|
| `Default` | General purpose (required) | Fast, balanced model |
| `Code` | Programming tasks | Code-optimized model |
| `Vision` | Image analysis | Vision-capable model |
| `Complex` | Multi-step reasoning | Larger, smarter model |
| `Fast` | Quick responses | Smaller, faster model |
| `Creative` | Creative writing | Higher temperature model |

### Enable Logging

```powershell
# Log to file
Set-AnthropicRouterConfig -Models @{
    Default = 'llama3.1-8k'
    Code    = 'qwen3-coder-8k'
} -LogPath './router.log'

# Log to console (verbose output)
Set-AnthropicRouterConfig -Models @{
    Default = 'llama3.1-8k'
    Code    = 'qwen3-coder-8k'
} -LogToConsole

# Both file and console
Set-AnthropicRouterConfig -Models @{
    Default = 'llama3.1-8k'
    Code    = 'qwen3-coder-8k'
} -LogPath './router.log' -LogToConsole
```

## Routing Messages

### Explicit Task Type

```powershell
# Route to code model
$response = Invoke-AnthropicRouted -Messages $messages -TaskType Code

# Route to vision model
$response = Invoke-AnthropicRouted -Messages $messages -TaskType Vision

# Route to default (or omit -TaskType)
$response = Invoke-AnthropicRouted -Messages $messages -TaskType Default
```

### Unknown Task Types

If a task type isn't configured, the router falls back to Default with a warning:

```powershell
# This will use Default model and emit a warning
$response = Invoke-AnthropicRouted -Messages $messages -TaskType UnconfiguredType
```

### Full Parameter Support

`Invoke-AnthropicRouted` supports all standard `Invoke-AnthropicMessage` parameters:

```powershell
$response = Invoke-AnthropicRouted -Messages $messages `
    -TaskType Code `
    -System 'You are a helpful coding assistant.' `
    -MaxTokens 2048 `
    -Temperature 0.3 `
    -Tools $tools
```

## Viewing Configuration

```powershell
# Get current config
$config = Get-AnthropicRouterConfig

# Display model mappings
$config.Models

# Check if logging is enabled
$config.LogPath
$config.LogToConsole
```

## Viewing Logs

```powershell
# Get all routing logs (from log file)
$logs = Get-AnthropicRouterLog

# Get last 10 entries
$logs = Get-AnthropicRouterLog -Last 10

# View log file directly
Get-Content './router.log'
```

Log entries include:
- Timestamp
- Task type
- Selected model
- Message preview (first 100 chars)
- Routing reason

## Clearing Configuration

```powershell
# Clear with confirmation
Clear-AnthropicRouterConfig

# Force clear without confirmation
Clear-AnthropicRouterConfig -Force
```

## Example: Multi-Model Workflow

```powershell
# Configure multiple specialized models
Set-AnthropicRouterConfig -Models @{
    Default  = 'llama3.1-8k'
    Code     = 'qwen3-coder-8k'
    Vision   = 'llama3.2-vision:11b'
    Complex  = 'qwen2.5-coder:14b'
} -LogToConsole

# General question -> Default model
$response = Invoke-AnthropicRouted -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'What is the capital of France?'
)

# Code task -> Code model
$response = Invoke-AnthropicRouted -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Write a PowerShell script to backup files'
) -TaskType Code

# Image analysis -> Vision model
$response = Invoke-AnthropicRouted -Messages @(
    @{
        role = 'user'
        content = @(
            @{ type = 'text'; text = 'What is in this image?' }
            (New-AnthropicImageContent -Path './photo.jpg')
        )
    }
) -TaskType Vision

# Complex reasoning -> Complex model
$response = Invoke-AnthropicRouted -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Design a microservices architecture for an e-commerce platform'
) -TaskType Complex

# Clean up
Clear-AnthropicRouterConfig -Force
```

## Best Practices

1. **Always define Default** - The `Default` key is required and serves as the fallback
2. **Match models to tasks** - Use code-optimized models for `Code`, vision models for `Vision`
3. **Enable logging during development** - Helps debug routing decisions
4. **Use consistent task types** - Define a standard set for your application
5. **Clean up when done** - Call `Clear-AnthropicRouterConfig` to reset state
