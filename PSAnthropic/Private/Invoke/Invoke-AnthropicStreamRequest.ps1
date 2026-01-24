# Module-scoped HttpClient for connection reuse
$script:StreamHttpClient = $null
$script:StreamHttpHandler = $null

function Get-StreamHttpClient {
    <#
    .SYNOPSIS
        Gets or creates a module-scoped HttpClient for streaming requests.
    #>
    [CmdletBinding()]
    [OutputType([System.Net.Http.HttpClient])]
    param(
        [Parameter()]
        [int]$TimeoutSec = 300
    )

    if ($null -eq $script:StreamHttpClient) {
        $script:StreamHttpHandler = [System.Net.Http.HttpClientHandler]::new()
        $script:StreamHttpClient = [System.Net.Http.HttpClient]::new($script:StreamHttpHandler)
        # Set a long default timeout - actual timeout handled via CancellationToken
        $script:StreamHttpClient.Timeout = [TimeSpan]::FromMinutes(30)
    }

    return $script:StreamHttpClient
}

function Invoke-AnthropicStreamRequest {
    <#
    .SYNOPSIS
        Internal function to handle streaming requests.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [hashtable]$Body,

        [Parameter()]
        [int]$TimeoutSec = 300
    )

    Assert-AnthropicConnection

    $jsonBody = $Body | ConvertTo-Json -Depth 20 -Compress

    $request = $null
    $response = $null
    $stream = $null
    $reader = $null
    $cts = $null

    try {
        # Get module-scoped HttpClient for connection reuse
        $client = Get-StreamHttpClient -TimeoutSec $TimeoutSec

        # Create cancellation token for per-request timeout (avoids race condition on shared client)
        $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($TimeoutSec))

        # Build request
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $Uri)
        $request.Content = [System.Net.Http.StringContent]::new($jsonBody, [System.Text.Encoding]::UTF8, 'application/json')

        # Add headers
        foreach ($key in $script:AnthropicConnection.Headers.Keys) {
            if ($key -ne 'Content-Type') {
                $request.Headers.TryAddWithoutValidation($key, $script:AnthropicConnection.Headers[$key]) | Out-Null
            }
        }

        # Send request and get response stream with cancellation token
        try {
            $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cts.Token).GetAwaiter().GetResult()
        }
        catch [System.OperationCanceledException] {
            throw [AnthropicConnectionException]::new("Request timed out after $TimeoutSec seconds")
        }

        if (-not $response.IsSuccessStatusCode) {
            $errorContent = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $errorBody = $null
            try { $errorBody = $errorContent | ConvertFrom-Json } catch { }

            $statusCode = [int]$response.StatusCode
            $typedException = switch ($statusCode) {
                400 { [AnthropicBadRequestException]::new("Bad request: $errorContent", $errorBody) }
                401 { [AnthropicAuthenticationException]::new("Authentication failed: $errorContent", $errorBody) }
                403 { [AnthropicApiException]::new("Access forbidden: $errorContent", $statusCode, "forbidden", $errorBody) }
                404 { [AnthropicApiException]::new("Resource not found: $errorContent", $statusCode, "not_found", $errorBody) }
                429 {
                    $retryAfter = 0
                    $retryHeader = $response.Headers.RetryAfter
                    if ($retryHeader -and $retryHeader.Delta) {
                        $retryAfter = [int]$retryHeader.Delta.TotalSeconds
                    }
                    [AnthropicRateLimitException]::new("Rate limited: $errorContent", $retryAfter, $errorBody)
                }
                { $_ -ge 500 } { [AnthropicApiException]::new("Server error: $errorContent", $statusCode, "server_error", $errorBody) }
                default { [AnthropicApiException]::new("Request failed: $errorContent", $statusCode, "unknown", $errorBody) }
            }
            throw $typedException
        }

        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $reader = [System.IO.StreamReader]::new($stream)

        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()

            # Skip empty lines
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            # Parse SSE data lines
            if ($line.StartsWith('data: ')) {
                $data = $line.Substring(6)

                # Skip [DONE] marker
                if ($data -eq '[DONE]') {
                    continue
                }

                # Parse and output event
                try {
                    $sseEvent = $data | ConvertFrom-Json
                    Write-Output $sseEvent
                }
                catch {
                    Write-Verbose "Failed to parse SSE event: $data"
                }
            }
        }
    }
    finally {
        # Dispose per-request resources (HttpClient is module-scoped and reused)
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        if ($request) { $request.Dispose() }
        if ($cts) { $cts.Dispose() }
    }
}
