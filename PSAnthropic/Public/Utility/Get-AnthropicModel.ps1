function Get-AnthropicModel {
    <#
    .SYNOPSIS
        Lists available models from the Ollama server.
    .DESCRIPTION
        Queries the Ollama /api/tags endpoint to list all available models.
        Note: This is Ollama-specific and won't work with Anthropic's cloud API.
    .PARAMETER Filter
        Optional filter string to match model names.
    .EXAMPLE
        Get-AnthropicModel
        # Lists all available models
    .EXAMPLE
        Get-AnthropicModel -Filter 'llama'
        # Lists models containing 'llama' in the name
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [string]$Filter
    )

    Assert-AnthropicConnection

    # Build URL for Ollama tags endpoint
    $baseUrl = Get-NormalizedServerUrl -Server $script:AnthropicConnection.Server
    $uri = Join-Url -Path $baseUrl -ChildPath '/api/tags'

    try {
        $result = Invoke-RestMethod -Uri $uri -Method GET -TimeoutSec 30 -ErrorAction Stop

        $models = $result.models | ForEach-Object {
            [PSCustomObject]@{
                Name       = $_.name
                Size       = [math]::Round($_.size / 1GB, 2)
                SizeGB     = "$([math]::Round($_.size / 1GB, 2)) GB"
                ModifiedAt = $_.modified_at
                Family     = $_.details.family
                Parameters = $_.details.parameter_size
                Quantization = $_.details.quantization_level
            }
        }

        # Apply filter if specified
        if ($Filter) {
            $models = $models | Where-Object { $_.Name -like "*$Filter*" }
        }

        $models | Sort-Object Name
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
