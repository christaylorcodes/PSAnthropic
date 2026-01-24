function Assert-AnthropicConnection {
    <#
    .SYNOPSIS
        Validates that a connection to an Anthropic-compatible API exists.
    .DESCRIPTION
        Throws an error if $script:AnthropicConnection is not set.
        Used internally to validate connection state before API calls.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:AnthropicConnection) {
        throw "Not connected. Run 'Connect-Anthropic' first."
    }
}
