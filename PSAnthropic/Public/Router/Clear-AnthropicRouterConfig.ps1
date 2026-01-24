function Clear-AnthropicRouterConfig {
    <#
    .SYNOPSIS
        Clears the router configuration and disables routing.
    .DESCRIPTION
        Removes the router configuration, disabling automatic model routing.
        After clearing, Invoke-AnthropicRouted will fail until Set-AnthropicRouterConfig
        is called again.
    .PARAMETER Force
        Clear without confirmation.
    .EXAMPLE
        Clear-AnthropicRouterConfig
    .EXAMPLE
        Clear-AnthropicRouterConfig -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()]
        [switch]$Force
    )

    if (-not $script:AnthropicRouterConfig) {
        Write-Verbose "Router config is already cleared."
        return
    }

    if ($Force -or $PSCmdlet.ShouldProcess('AnthropicRouterConfig', 'Clear router configuration')) {
        $script:AnthropicRouterConfig = $null
        Write-Verbose "Router configuration cleared."
    }
}
