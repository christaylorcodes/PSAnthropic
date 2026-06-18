function Get-AnthropicModel {
    <#
    .SYNOPSIS
        Lists available models from the connected backend.
    .DESCRIPTION
        Discovers models from whichever backend the connection points at, so the
        module never relies on a hardcoded model list:

        - Anthropic Cloud (Provider 'Anthropic'): queries GET /v1/models (paginated).
        - Ollama / Generic: queries the Ollama /api/tags endpoint.

        Results are cached on the connection for a few minutes; use -Refresh to
        force a live re-query.
    .PARAMETER Filter
        Optional filter string to match model names (substring, case-insensitive).
    .PARAMETER Refresh
        Bypass the cache and re-query the backend.
    .EXAMPLE
        Get-AnthropicModel
        # Lists all available models for the connected backend
    .EXAMPLE
        Get-AnthropicModel -Filter 'opus'
        # Lists models whose name contains 'opus'
    .EXAMPLE
        Get-AnthropicModel -Refresh
        # Forces a fresh query, bypassing the cache
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [switch]$Refresh
    )

    Assert-AnthropicConnection

    $connection = $script:AnthropicConnection
    if (-not $connection.Cache) { $connection.Cache = @{} }
    $cache = $connection.Cache
    $cacheTtl = [timespan]::FromMinutes(5)

    # Serve from cache when fresh
    if (-not $Refresh -and $cache.ContainsKey('models') -and $cache.ContainsKey('models_at') -and
        ((Get-Date) - $cache['models_at']) -lt $cacheTtl) {
        $models = $cache['models']
    }
    else {
        $models = if ($connection.Provider -eq 'Anthropic') {
            Get-AnthropicModelFromApi
        }
        else {
            Get-AnthropicModelFromOllama
        }

        if ($null -ne $models) {
            $cache['models'] = @($models)
            $cache['models_at'] = Get-Date
        }
    }

    if (-not $models) { return }

    # Apply filter if specified
    if ($Filter) {
        $models = $models | Where-Object { $_.Name -like "*$Filter*" }
    }

    $models | Sort-Object Name
}
