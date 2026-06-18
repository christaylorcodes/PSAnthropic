function Get-AnthropicProvider {
    <#
    .SYNOPSIS
        Detects which backend a server address points at.
    .DESCRIPTION
        Returns 'Anthropic', 'Ollama', or 'Generic' for a server address so the
        rest of the module can shape requests to what each backend supports.

        Detection order:
        1. Host matches Anthropic cloud (*.anthropic.com) or Claude Platform on AWS
           (*.api.aws) -> 'Anthropic'.
        2. Host is local or uses the default Ollama port 11434 -> 'Ollama'.
        3. Otherwise probe the Ollama-only /api/tags endpoint -> 'Ollama' if it
           responds, else 'Generic'. Skipped when -NoProbe is set.

        'Generic' means "Anthropic-compatible endpoint of unknown capability" -
        the module sends only the conservative, broadly-supported field set and
        the user can override detection with Connect-Anthropic -Provider.
    .PARAMETER Server
        The server address (with or without scheme), e.g. 'localhost:11434' or
        'https://api.anthropic.com'.
    .PARAMETER NoProbe
        Skip the network probe of /api/tags. Detection then relies on host/port
        heuristics only, returning 'Generic' for unknown hosts.
    .EXAMPLE
        Get-AnthropicProvider -Server 'api.anthropic.com'
        # Returns: Anthropic
    .EXAMPLE
        Get-AnthropicProvider -Server 'localhost:11434'
        # Returns: Ollama
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Server,

        [Parameter()]
        [switch]$NoProbe
    )

    $normalized = Get-NormalizedServerUrl -Server $Server

    try {
        $uri = [Uri]$normalized
        $serverHost = $uri.Host
        $port = $uri.Port
    }
    catch {
        return 'Generic'
    }

    # Anthropic cloud or Claude Platform on AWS
    if ($serverHost -match '(^|\.)anthropic\.com$' -or $serverHost -match '\.api\.aws$') {
        return 'Anthropic'
    }

    # Local host or the standard Ollama port is a strong Ollama signal
    if ($serverHost -in @('localhost', '127.0.0.1', '::1', '[::1]') -or $port -eq 11434) {
        return 'Ollama'
    }

    # Last resort: probe the Ollama-specific /api/tags endpoint
    if (-not $NoProbe) {
        try {
            $tagsUrl = Join-Url -Path $normalized -ChildPath '/api/tags'
            $null = Invoke-RestMethod -Uri $tagsUrl -Method GET -TimeoutSec 2 -ErrorAction Stop
            return 'Ollama'
        }
        catch {
            Write-Verbose "Provider probe of $normalized/api/tags failed: $($_.Exception.Message)"
        }
    }

    return 'Generic'
}
