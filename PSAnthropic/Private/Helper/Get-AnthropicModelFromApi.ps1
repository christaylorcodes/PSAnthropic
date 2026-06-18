function Get-AnthropicModelFromApi {
    <#
    .SYNOPSIS
        Lists models from the Anthropic Cloud GET /v1/models endpoint.
    .DESCRIPTION
        Internal helper for Get-AnthropicModel. Queries the Anthropic Models API,
        following pagination, and normalizes the result. Uses
        Invoke-AnthropicWebRequest so connection headers (auth, version) are applied.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $baseUrl = Get-NormalizedServerUrl -Server $script:AnthropicConnection.Server
    $afterId = $null

    do {
        $query = @{ limit = '1000' }
        if ($afterId) { $query['after_id'] = $afterId }
        $uri = Join-Url -Path $baseUrl -ChildPath '/v1/models' -QueryParameters $query

        $response = Invoke-AnthropicWebRequest -Uri $uri -Method GET
        if (-not $response -or -not $response.Content) { break }

        $page = $response.Content | ConvertFrom-Json
        foreach ($model in @($page.data)) {
            [PSCustomObject]@{
                Name        = $model.id
                DisplayName = $model.display_name
                CreatedAt   = $model.created_at
                Type        = $model.type
                Provider    = 'Anthropic'
            }
        }

        $afterId = $page.last_id
        $hasMore = [bool]$page.has_more
    } while ($hasMore)
}
