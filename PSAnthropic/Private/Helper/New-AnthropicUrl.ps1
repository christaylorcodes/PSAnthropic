function New-AnthropicUrl {
    <#
    .SYNOPSIS
        Builds the full API URL from connection settings and endpoint.
    .DESCRIPTION
        Constructs the complete URL for Anthropic API requests using the
        server from the current connection and the specified endpoint.
    .PARAMETER Endpoint
        The API endpoint path (e.g., '/v1/messages').
    .EXAMPLE
        New-AnthropicUrl -Endpoint '/v1/messages'
        # Returns: http://localhost:11434/v1/messages
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint
    )

    Assert-AnthropicConnection

    $baseUrl = Get-NormalizedServerUrl -Server $script:AnthropicConnection.Server
    Join-Url -Path $baseUrl -ChildPath $Endpoint
}
