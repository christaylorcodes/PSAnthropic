function Get-AnthropicConnection {
    <#
    .SYNOPSIS
        Shows the current Anthropic API connection settings.
    .DESCRIPTION
        Returns information about the current connection, including server,
        model, and when the connection was established.
        Does not expose the API key for security.
    .EXAMPLE
        Get-AnthropicConnection

        Server      : localhost:11434
        Model       : llama3
        ConnectedAt : 1/23/2026 10:30:00 AM
    #>
    [CmdletBinding()]
    [OutputType('AnthropicConnection')]
    param()

    if (-not $script:AnthropicConnection) {
        Write-Warning "Not connected. Run 'Connect-Anthropic' first."
        return $null
    }

    $script:AnthropicConnection
}
