function Connect-Anthropic {
    <#
    .SYNOPSIS
        Establishes a connection to an Anthropic-compatible API endpoint.
    .DESCRIPTION
        Initializes the connection settings for communicating with an
        Anthropic-compatible API (Ollama, Anthropic Cloud, or any compatible
        endpoint). Stores connection info in a script-scoped variable.

        The backend is detected automatically and stored on the connection as
        .Provider so the rest of the module can shape requests to what each
        backend supports (see Get-AnthropicProvider). Override with -Provider.

        Parameters are checked in order:
        1. Explicit parameters
        2. Environment variables (ANTHROPIC_BASE_URL, ANTHROPIC_API_KEY, ANTHROPIC_MODEL)
        3. Auto-detection (Ollama: queries /api/tags for available models)
        4. Defaults (localhost:11434, "ollama"; Ollama falls back to "llama3")
    .PARAMETER Server
        The server address (e.g., 'localhost:11434' or 'http://localhost:11434').
        Defaults to $env:ANTHROPIC_BASE_URL or 'localhost:11434'.
    .PARAMETER ApiKey
        The API key for authentication. For Ollama, use 'ollama' (accepted but not validated).
        Defaults to $env:ANTHROPIC_API_KEY or 'ollama'.
    .PARAMETER Model
        The default model to use for requests.
        Defaults to $env:ANTHROPIC_MODEL, then (Ollama only) auto-detects from
        the server, then 'llama3'. Discover available models with Get-AnthropicModel.
    .PARAMETER Provider
        Which backend this endpoint is. 'Auto' (default) detects from the server
        address. Set explicitly to 'Anthropic', 'Ollama', or 'Generic' to override
        detection (e.g. an Anthropic-compatible proxy on a non-standard host).
    .PARAMETER AnthropicVersion
        Value for the 'anthropic-version' header. Defaults to '2023-06-01'
        (current for both Anthropic Cloud and Ollama).
    .PARAMETER Beta
        One or more beta feature identifiers sent in the 'anthropic-beta' header
        (Anthropic Cloud), e.g. 'context-1m-2025-08-07'. Ollama ignores this.
    .PARAMETER Force
        Reconnect even if already connected.
    .EXAMPLE
        Connect-Anthropic
        # Connects to local Ollama with defaults (localhost:11434, ollama, auto-detected model)
    .EXAMPLE
        Connect-Anthropic -Server 'localhost:11434' -Model 'qwen3-coder'
        # Connects with a specific Ollama model
    .EXAMPLE
        Connect-Anthropic -Server 'api.anthropic.com' -ApiKey $realApiKey -Model 'claude-opus-4-8'
        # Connects to Anthropic's cloud API (Provider auto-detects as 'Anthropic')
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('AnthropicConnection')]
    param(
        [Parameter()]
        [string]$Server,

        [Parameter()]
        [string]$ApiKey,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [ValidateSet('Auto', 'Anthropic', 'Ollama', 'Generic')]
        [string]$Provider = 'Auto',

        [Parameter()]
        [string]$AnthropicVersion = '2023-06-01',

        [Parameter()]
        [string[]]$Beta,

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

    # Resolve provider: explicit overrides auto-detection from the server address
    $resolvedProvider = if ($Provider -ne 'Auto') {
        $Provider
    }
    else {
        Get-AnthropicProvider -Server $resolvedServer
    }
    Write-Verbose "Provider for $resolvedServer resolved to '$resolvedProvider'"

    # Model resolution: explicit > env var > provider-aware auto-detect/fallback
    $resolvedModel = @($Model, $env:ANTHROPIC_MODEL).Where({ -not [string]::IsNullOrEmpty($_) })[0]

    # Auto-detect model if none specified. Only Ollama exposes /api/tags; never
    # fall back to a hardcoded Anthropic model (it would 404 or pick the wrong one).
    if ([string]::IsNullOrEmpty($resolvedModel)) {
        if ($resolvedProvider -in @('Ollama', 'Generic')) {
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

            # Last-resort default for Ollama only (a sensible well-known tag, not a capability assumption)
            if ([string]::IsNullOrEmpty($resolvedModel) -and $resolvedProvider -eq 'Ollama') {
                $resolvedModel = 'llama3'
                Write-Warning "Could not auto-detect model. Defaulting to '$resolvedModel'. Use -Model to specify."
            }
        }

        if ([string]::IsNullOrEmpty($resolvedModel)) {
            Write-Warning "No default model set. Pass -Model, or discover options with Get-AnthropicModel."
        }
    }

    # Store the server exactly as supplied so the user's scheme is preserved.
    # New-AnthropicUrl normalizes lazily via Get-NormalizedServerUrl, which keeps an
    # existing http://|https:// scheme and only defaults to http:// when none is present.
    # Stripping here would lose https:// and silently downgrade requests to http (issue #1).

    # Assemble request headers. anthropic-version is configurable but defaults to
    # the current value; anthropic-beta is added only when beta features are requested.
    $headers = @{
        'Content-Type'      = 'application/json'
        'anthropic-version' = $AnthropicVersion
        'X-Api-Key'         = $resolvedApiKey
    }
    if ($Beta) {
        $headers['anthropic-beta'] = ($Beta -join ',')
    }

    # Build connection object (with ShouldProcess for -WhatIf support)
    if ($PSCmdlet.ShouldProcess("$resolvedServer with model $resolvedModel", 'Connect to Anthropic API')) {
        $script:AnthropicConnection = [AnthropicConnection]::new(
            $resolvedServer,
            $resolvedModel,
            $headers,
            $resolvedProvider
        )

        Write-Verbose "Connected to $resolvedServer ($resolvedProvider) with model $resolvedModel"

        $script:AnthropicConnection
    }
}
