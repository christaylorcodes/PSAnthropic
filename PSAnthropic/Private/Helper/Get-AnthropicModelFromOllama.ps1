function Get-AnthropicModelFromOllama {
    <#
    .SYNOPSIS
        Lists models from the Ollama /api/tags endpoint.
    .DESCRIPTION
        Internal helper for Get-AnthropicModel. Queries the Ollama-native
        /api/tags endpoint (no auth required) and normalizes the result.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $baseUrl = Get-NormalizedServerUrl -Server $script:AnthropicConnection.Server
    $uri = Join-Url -Path $baseUrl -ChildPath '/api/tags'

    try {
        $result = Invoke-RestMethod -Uri $uri -Method GET -TimeoutSec 30 -ErrorAction Stop

        $result.models | ForEach-Object {
            [PSCustomObject]@{
                Name         = $_.name
                DisplayName  = $_.name
                Size         = [math]::Round($_.size / 1GB, 2)
                SizeGB       = "$([math]::Round($_.size / 1GB, 2)) GB"
                ModifiedAt   = $_.modified_at
                Family       = $_.details.family
                Parameters   = $_.details.parameter_size
                Quantization = $_.details.quantization_level
                Provider     = 'Ollama'
            }
        }
    }
    catch {
        if ($_.Exception.Message -like '*404*' -or $_.Exception.Message -like '*No such host*') {
            Write-Warning "Could not reach Ollama at $uri. Is Ollama running?"
        }
        else {
            Write-Error "Failed to get models: $_"
        }
    }
}
