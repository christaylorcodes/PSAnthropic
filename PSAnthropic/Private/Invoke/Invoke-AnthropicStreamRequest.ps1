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
        [int]$TimeoutSec = 300,

        [Parameter()]
        [int]$MaxRetry = 3
    )

    Assert-AnthropicConnection

    $jsonBody = $Body | ConvertTo-Json -Depth 20 -Compress

    $request = $null
    $response = $null
    $stream = $null
    $reader = $null
    $cts = $null
    $retry = 0

    try {
        # Get module-scoped HttpClient for connection reuse
        $client = Get-StreamHttpClient -TimeoutSec $TimeoutSec

        # Retry loop for transient errors (429, 5xx)
        while ($true) {
            # Create cancellation token for per-request timeout
            # Use CancelAfter() instead of constructor timeout to avoid race condition on disposal
            $cts = [System.Threading.CancellationTokenSource]::new()
            $cts.CancelAfter([TimeSpan]::FromSeconds($TimeoutSec))

            # Build request (must recreate for each retry as content stream is consumed)
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

            if ($response.IsSuccessStatusCode) {
                break  # Success - exit retry loop
            }

            $errorContent = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $errorBody = $null
            try { $errorBody = $errorContent | ConvertFrom-Json } catch { }

            $statusCode = [int]$response.StatusCode

            # Handle retryable errors (429, 5xx)
            if ($statusCode -eq 429) {
                # Extract retry-after from header (used for both retry delay and exception)
                $retryAfter = 0
                $retryHeader = $response.Headers.RetryAfter
                if ($retryHeader -and $retryHeader.Delta) {
                    $retryAfter = [int]$retryHeader.Delta.TotalSeconds
                }

                $retry++
                if ($retry -lt $MaxRetry) {
                    $waitSeconds = if ($retryAfter -gt 0) { $retryAfter } else { [Math]::Pow(2, $retry) }
                    Write-Warning "Rate limited (429), retry $retry/$MaxRetry, waiting ${waitSeconds}s..."
                    Start-Sleep -Seconds $waitSeconds
                    # Clean up before retry
                    if ($response) { $response.Dispose(); $response = $null }
                    if ($request) { $request.Dispose(); $request = $null }
                    if ($cts) { $cts.Dispose(); $cts = $null }
                    continue
                }
                throw [AnthropicRateLimitException]::new("Rate limited: $errorContent", $retryAfter, $errorBody)
            }
            elseif ($statusCode -ge 500) {
                $retry++
                if ($retry -lt $MaxRetry) {
                    $waitMs = [Math]::Pow(2, $retry) * 100  # Exponential backoff: 200ms, 400ms, 800ms
                    Write-Warning "Server error ($statusCode), retry $retry/$MaxRetry, waiting ${waitMs}ms..."
                    Start-Sleep -Milliseconds $waitMs
                    # Clean up before retry
                    if ($response) { $response.Dispose(); $response = $null }
                    if ($request) { $request.Dispose(); $request = $null }
                    if ($cts) { $cts.Dispose(); $cts = $null }
                    continue
                }
                throw [AnthropicApiException]::new("Server error after $MaxRetry retries: $errorContent", $statusCode, "server_error", $errorBody)
            }

            # Non-retryable errors
            $typedException = switch ($statusCode) {
                400 { [AnthropicBadRequestException]::new("Bad request: $errorContent", $errorBody) }
                401 { [AnthropicAuthenticationException]::new("Authentication failed: $errorContent", $errorBody) }
                403 { [AnthropicApiException]::new("Access forbidden: $errorContent", $statusCode, "forbidden", $errorBody) }
                404 { [AnthropicApiException]::new("Resource not found: $errorContent", $statusCode, "not_found", $errorBody) }
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
