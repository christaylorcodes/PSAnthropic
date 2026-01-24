function Join-Url {
    <#
    .SYNOPSIS
        Safely joins URL path segments using proper URI handling.
    .DESCRIPTION
        Combines URL path segments using .NET's Uri class for proper URL parsing
        and validation. Handles leading/trailing slashes automatically.
    .PARAMETER Path
        The base URL path.
    .PARAMETER ChildPath
        The path segment to append.
    .PARAMETER QueryParameters
        Optional hashtable of query string parameters to append.
    .EXAMPLE
        Join-Url 'https://localhost:11434' '/v1/messages'
        # Returns: https://localhost:11434/v1/messages
    .EXAMPLE
        Join-Url 'https://localhost:11434/api' 'models' -QueryParameters @{ filter = 'llama' }
        # Returns: https://localhost:11434/api/models?filter=llama
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ChildPath,

        [Parameter()]
        [hashtable]$QueryParameters
    )

    # Use Uri class to properly combine paths
    $baseUri = [Uri]::new($Path.TrimEnd('/') + '/')
    $combinedUri = [Uri]::new($baseUri, $ChildPath.TrimStart('/'))

    if ($QueryParameters -and $QueryParameters.Count -gt 0) {
        # Build query string manually (PowerShell 7+ compatible, no System.Web dependency)
        $builder = [System.UriBuilder]::new($combinedUri)
        $queryParts = [System.Collections.Generic.List[string]]::new()

        foreach ($key in $QueryParameters.Keys) {
            $encodedKey = [System.Net.WebUtility]::UrlEncode($key)
            $encodedValue = [System.Net.WebUtility]::UrlEncode($QueryParameters[$key])
            $queryParts.Add("$encodedKey=$encodedValue")
        }

        $builder.Query = $queryParts -join '&'
        return $builder.Uri.AbsoluteUri
    }

    $combinedUri.AbsoluteUri
}
