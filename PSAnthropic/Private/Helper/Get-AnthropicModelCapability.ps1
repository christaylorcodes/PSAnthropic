function Get-AnthropicModelCapability {
    <#
    .SYNOPSIS
        Resolves what request features a given model/backend supports.
    .DESCRIPTION
        Returns a capability hashtable that the request builder uses to decide
        which fields are safe to send, so the module never 400s by sending a
        field a backend rejects - and never relies on a hardcoded model table.

        - Anthropic Cloud: queries GET /v1/models/{id} and reads the live
          capabilities tree (thinking types, effort, structured outputs, vision,
          max output tokens). Fields the API does not expose as flags are derived:
          sampling params (temperature/top_p/top_k) are treated as unsupported on
          adaptive-only models (Opus 4.7+/Fable family, where 'enabled' thinking
          is gone) and supported where 'enabled' thinking remains (Opus 4.6/Sonnet
          4.6). tool_choice/metadata/caching are GA on Anthropic.
        - Ollama / Generic: uses a static provider profile (Ollama supports thinking
          enable/disable and sampling, but not tool_choice/metadata/caching/effort/
          structured outputs).

        Results are cached per-model on the connection; use -Refresh to re-query.
    .PARAMETER Model
        The model id to resolve capabilities for.
    .PARAMETER Refresh
        Bypass the cache and re-query the backend.
    .OUTPUTS
        Hashtable with boolean capability keys plus MaxOutputTokens and Source.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter()]
        [switch]$Refresh
    )

    Assert-AnthropicConnection
    $connection = $script:AnthropicConnection
    if (-not $connection.Cache) { $connection.Cache = @{} }
    $cache = $connection.Cache
    $cacheKey = "cap:$Model"
    $cacheTtl = [timespan]::FromMinutes(30)

    if (-not $Refresh -and $cache.ContainsKey($cacheKey) -and $cache.ContainsKey("$cacheKey`:at") -and
        ((Get-Date) - $cache["$cacheKey`:at"]) -lt $cacheTtl) {
        return $cache[$cacheKey]
    }

    $capability = switch ($connection.Provider) {
        'Anthropic' {
            # Permissive modern defaults, used if the live lookup fails.
            $resolved = @{
                SupportsAdaptiveThinking = $true
                SupportsEnabledThinking  = $false
                SupportsEffort           = $true
                SupportsStructuredOutput = $true
                SupportsVision           = $true
                SupportsSampling         = $false
                SupportsToolChoice       = $true
                SupportsMetadata         = $true
                SupportsCaching          = $true
                MaxOutputTokens          = $null
                Source                   = 'fallback'
            }
            try {
                $baseUrl = Get-NormalizedServerUrl -Server $connection.Server
                $uri = Join-Url -Path $baseUrl -ChildPath "/v1/models/$Model"
                $response = Invoke-AnthropicWebRequest -Uri $uri -Method GET
                if ($response -and $response.Content) {
                    $info = $response.Content | ConvertFrom-Json
                    $caps = $info.capabilities
                    $adaptive = [bool]$caps.thinking.types.adaptive.supported
                    $enabled = [bool]$caps.thinking.types.enabled.supported
                    $resolved = @{
                        SupportsAdaptiveThinking = $adaptive
                        SupportsEnabledThinking  = $enabled
                        SupportsEffort           = [bool]$caps.effort.supported
                        SupportsStructuredOutput = [bool]$caps.structured_outputs.supported
                        SupportsVision           = [bool]$caps.image_input.supported
                        # Derived: sampling params are removed on adaptive-only models.
                        SupportsSampling         = -not ($adaptive -and -not $enabled)
                        SupportsToolChoice       = $true
                        SupportsMetadata         = $true
                        SupportsCaching          = $true
                        MaxOutputTokens          = if ($info.max_tokens) { [int]$info.max_tokens } else { $null }
                        Source                   = 'api'
                    }
                }
            }
            catch {
                Write-Verbose "Capability lookup for '$Model' failed; using modern Anthropic defaults: $($_.Exception.Message)"
            }
            $resolved
        }
        'Ollama' {
            @{
                SupportsAdaptiveThinking = $false
                SupportsEnabledThinking  = $true
                SupportsEffort           = $false
                SupportsStructuredOutput = $false
                SupportsVision           = $true
                SupportsSampling         = $true
                SupportsToolChoice       = $false
                SupportsMetadata         = $false
                SupportsCaching          = $false
                MaxOutputTokens          = $null
                Source                   = 'profile:ollama'
            }
        }
        default {
            # Generic Anthropic-compatible endpoint of unknown capability: allow the
            # broadly-supported basics, withhold advanced fields that could 400.
            @{
                SupportsAdaptiveThinking = $false
                SupportsEnabledThinking  = $true
                SupportsEffort           = $false
                SupportsStructuredOutput = $false
                SupportsVision           = $true
                SupportsSampling         = $true
                SupportsToolChoice       = $true
                SupportsMetadata         = $false
                SupportsCaching          = $false
                MaxOutputTokens          = $null
                Source                   = 'profile:generic'
            }
        }
    }

    $cache[$cacheKey] = $capability
    $cache["$cacheKey`:at"] = Get-Date
    $capability
}
