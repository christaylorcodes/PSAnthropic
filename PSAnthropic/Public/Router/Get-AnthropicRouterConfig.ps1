function Get-AnthropicRouterConfig {
    <#
    .SYNOPSIS
        Gets the current router configuration.
    .DESCRIPTION
        Returns the current model routing configuration and logging settings.
    .EXAMPLE
        Get-AnthropicRouterConfig
    .EXAMPLE
        # Check if router is configured
        if (Get-AnthropicRouterConfig) { "Router ready" }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not $script:AnthropicRouterConfig) {
        Write-Warning "Router not configured. Use Set-AnthropicRouterConfig first."
        return $null
    }

    return $script:AnthropicRouterConfig
}
