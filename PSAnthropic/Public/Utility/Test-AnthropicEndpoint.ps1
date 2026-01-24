function Test-AnthropicEndpoint {
    <#
    .SYNOPSIS
        Tests connectivity to the Anthropic-compatible endpoint.
    .DESCRIPTION
        Verifies that the server is reachable and responding.
        Uses Ollama's root endpoint to check if the server is running.
    .PARAMETER Server
        Server to test. Defaults to the connected server or localhost:11434.
    .EXAMPLE
        Test-AnthropicEndpoint
        # Tests the currently connected server
    .EXAMPLE
        Test-AnthropicEndpoint -Server 'localhost:11434'
        # Tests a specific server
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Server
    )

    # Resolve server
    $serverAddress = if ($Server) {
        $Server
    }
    elseif ($script:AnthropicConnection) {
        $script:AnthropicConnection.Server
    }
    else {
        'localhost:11434'
    }

    # Normalize URL
    $testServer = Get-NormalizedServerUrl -Server $serverAddress

    $result = [PSCustomObject]@{
        Server      = $testServer
        IsReachable = $false
        StatusCode  = $null
        Response    = $null
        Error       = $null
        ResponseMs  = $null
    }

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Try Ollama root endpoint (returns "Ollama is running")
        $response = Invoke-WebRequest -Uri $testServer -Method GET -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop

        $stopwatch.Stop()
        $result.ResponseMs = $stopwatch.ElapsedMilliseconds
        $result.IsReachable = $true
        $result.StatusCode = $response.StatusCode
        $result.Response = $response.Content.Trim()
    }
    catch {
        $stopwatch.Stop()
        $result.ResponseMs = $stopwatch.ElapsedMilliseconds
        $result.Error = $_.Exception.Message

        if ($_.Exception.Response) {
            $result.StatusCode = [int]$_.Exception.Response.StatusCode
        }
    }

    $result
}
