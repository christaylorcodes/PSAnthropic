function Connect-Anthropic {
    <#
    .SYNOPSIS
        Establishes a connection to an Anthropic-compatible API endpoint.
    .DESCRIPTION
        Initializes the connection settings for communicating with Ollama's
        Anthropic-compatible API. Stores connection info in a script-scoped variable.

        Parameters are checked in order:
        1. Explicit parameters
        2. Environment variables (ANTHROPIC_BASE_URL, ANTHROPIC_API_KEY, ANTHROPIC_MODEL)
        3. Auto-detection (queries server for available models)
        4. Defaults (localhost:11434, "ollama", "llama3")
    .PARAMETER Server
        The server address (e.g., 'localhost:11434' or 'http://localhost:11434').
        Defaults to $env:ANTHROPIC_BASE_URL or 'localhost:11434'.
    .PARAMETER ApiKey
        The API key for authentication. For Ollama, use 'ollama' (accepted but not validated).
        Defaults to $env:ANTHROPIC_API_KEY or 'ollama'.
    .PARAMETER Model
        The default model to use for requests.
        Defaults to $env:ANTHROPIC_MODEL, then auto-detects from server, then 'llama3'.
    .PARAMETER Force
        Reconnect even if already connected.
    .EXAMPLE
        Connect-Anthropic
        # Connects with defaults (localhost:11434, ollama, llama3)
    .EXAMPLE
        Connect-Anthropic -Server 'localhost:11434' -Model 'qwen3-coder'
        # Connects with a specific model
    .EXAMPLE
        Connect-Anthropic -Server 'api.anthropic.com' -ApiKey $realApiKey -Model 'claude-3-5-sonnet'
        # Connects to Anthropic's cloud API (if needed)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([AnthropicConnection])]
    param(
        [Parameter()]
        [string]$Server,

        [Parameter()]
        [string]$ApiKey,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [switch]$Force
    )

    # Check if already connected
    if ($script:AnthropicConnection -and -not $Force) {
        Write-Warning "Already connected to $($script:AnthropicConnection.Server). Use -Force to reconnect."
        return $script:AnthropicConnection
    }

    # Resolve parameters with fallbacks using null-coalescing (PowerShell 7+)
    # Use proper null/empty string filtering with -not [string]::IsNullOrEmpty()
    $resolvedServer = @($Server, $env:ANTHROPIC_BASE_URL, 'localhost:11434').Where({ -not [string]::IsNullOrEmpty($_) })[0]
    $resolvedApiKey = @($ApiKey, $env:ANTHROPIC_API_KEY, 'ollama').Where({ -not [string]::IsNullOrEmpty($_) })[0]

    # Model resolution: explicit > env var > auto-detect > fallback
    $resolvedModel = @($Model, $env:ANTHROPIC_MODEL).Where({ -not [string]::IsNullOrEmpty($_) })[0]

    # Auto-detect model if none specified
    if ([string]::IsNullOrEmpty($resolvedModel)) {
        $normalizedServer = $resolvedServer -replace '^https?://', ''
        $tagsUrl = "http://$normalizedServer/api/tags"
        try {
            Write-Verbose "No model specified, querying available models from $tagsUrl"
            $tagsResult = Invoke-RestMethod -Uri $tagsUrl -Method GET -TimeoutSec 10 -ErrorAction Stop
            if ($tagsResult.models -and $tagsResult.models.Count -gt 0) {
                $resolvedModel = $tagsResult.models[0].name
                Write-Verbose "Auto-detected model: $resolvedModel"
            }
        }
        catch {
            Write-Verbose "Could not auto-detect model: $_"
        }

        # Final fallback if auto-detect failed
        if ([string]::IsNullOrEmpty($resolvedModel)) {
            $resolvedModel = 'llama3'
            Write-Warning "Could not auto-detect model. Defaulting to '$resolvedModel'. Use -Model to specify."
        }
    }

    # Normalize server URL (strip protocol for storage, we add it back in New-AnthropicUrl)
    $resolvedServer = $resolvedServer -replace '^https?://', ''

    # Build connection object (with ShouldProcess for -WhatIf support)
    if ($PSCmdlet.ShouldProcess("$resolvedServer with model $resolvedModel", 'Connect to Anthropic API')) {
        $script:AnthropicConnection = [AnthropicConnection]::new(
            $resolvedServer,
            $resolvedModel,
            @{
                'Content-Type'      = 'application/json'
                'anthropic-version' = '2023-06-01'
                'X-Api-Key'         = $resolvedApiKey
            }
        )

        Write-Verbose "Connected to $resolvedServer with model $resolvedModel"

        $script:AnthropicConnection
    }
}
