function Get-NormalizedServerUrl {
    <#
    .SYNOPSIS
        Normalizes a server address to a proper URL with protocol.
    .DESCRIPTION
        Ensures a server address has a proper protocol prefix (http/https).
        If no protocol is specified, defaults to http.
    .PARAMETER Server
        The server address to normalize.
    .EXAMPLE
        Get-NormalizedServerUrl 'localhost:11434'
        # Returns: http://localhost:11434
    .EXAMPLE
        Get-NormalizedServerUrl 'https://api.anthropic.com'
        # Returns: https://api.anthropic.com
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Server
    )

    if ($Server -notmatch '^https?://') {
        return "http://$Server"
    }

    $Server
}
