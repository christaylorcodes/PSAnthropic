function Invoke-AnthropicWebRequest {
    <#
    .SYNOPSIS
        Core HTTP handler for Anthropic API requests.
    .DESCRIPTION
        Handles all HTTP communication with the Anthropic-compatible API.
        Includes connection validation, header injection, error handling,
        and retry logic for transient failures.
    .PARAMETER Uri
        The full URI to request.
    .PARAMETER Method
        The HTTP method (GET, POST, etc.). Defaults to GET.
    .PARAMETER Body
        The request body (will be converted to JSON if hashtable).
    .PARAMETER ContentType
        The content type. Defaults to 'application/json'.
    .PARAMETER Headers
        Additional headers to include (merged with connection headers).
    .PARAMETER TimeoutSec
        Request timeout in seconds. Defaults to 300.
    .PARAMETER MaxRetry
        Maximum retry attempts for 5xx errors. Defaults to 3.
    .EXAMPLE
        Invoke-AnthropicWebRequest -Uri 'http://localhost:11434/v1/messages' -Method POST -Body $body
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.PowerShell.Commands.WebResponseObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [string]$ContentType = 'application/json',

        [Parameter()]
        [hashtable]$Headers = @{},

        [Parameter()]
        [int]$TimeoutSec = 300,

        [Parameter()]
        [int]$MaxRetry = 3
    )

    # Validate connection (throws if not connected for consistent error handling)
    Assert-AnthropicConnection

    # Merge headers with connection headers
    $requestHeaders = @{}
    foreach ($key in $script:AnthropicConnection.Headers.Keys) {
        $requestHeaders[$key] = $script:AnthropicConnection.Headers[$key]
    }
    foreach ($key in $Headers.Keys) {
        $requestHeaders[$key] = $Headers[$key]
    }

    # Build request arguments
    $requestArgs = @{
        Uri         = $Uri
        Method      = $Method
        Headers     = $requestHeaders
        ContentType = $ContentType
        TimeoutSec  = $TimeoutSec
    }

    # Add body if provided
    if ($Body) {
        if ($Body -is [string]) {
            $requestArgs.Body = $Body
        }
        else {
            $requestArgs.Body = $Body | ConvertTo-Json -Depth 20 -Compress
        }
    }

    # Make request with retry logic
    $retry = 0
    $result = $null

    do {
        try {
            Write-Verbose "Request: $Method $Uri"
            if ($requestArgs.Body) {
                $bodyPreview = if ($requestArgs.Body.Length -gt 500) {
                    "$($requestArgs.Body.Substring(0, 500))..."
                } else {
                    $requestArgs.Body
                }
                Write-Verbose "Body: $bodyPreview"
            }

            $result = Invoke-WebRequest @requestArgs -UseBasicParsing -ErrorAction Stop

            # Success - break out of retry loop
            break
        }
        catch {
            $statusCode = $null
            $errorBody = $null

            # Try to get status code and error body
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode

                $errorStream = $null
                $reader = $null
                try {
                    $errorStream = $_.Exception.Response.GetResponseStream()
                    $reader = [System.IO.StreamReader]::new($errorStream)
                    $errorBody = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
                }
                catch {
                    # Ignore errors reading error body
                }
                finally {
                    if ($reader) { $reader.Dispose() }
                    if ($errorStream) { $errorStream.Dispose() }
                }
            }

            # Handle specific error codes with typed exceptions
            $errorMessage = if ($errorBody.error.message) { $errorBody.error.message } else { $_.Exception.Message }
            $typedException = $null

            switch ($statusCode) {
                400 {
                    $msg = "Bad Request: $errorMessage"
                    $typedException = [AnthropicBadRequestException]::new($msg, $errorBody)
                }
                401 {
                    $msg = "Authentication failed: $errorMessage. Check your API key or run 'Connect-Anthropic -Force'."
                    $typedException = [AnthropicAuthenticationException]::new($msg, $errorBody)
                }
                403 {
                    $msg = "Permission denied: $errorMessage"
                    $typedException = [AnthropicPermissionException]::new($msg, $errorBody)
                }
                404 {
                    $msg = "Not found: $errorMessage. Ensure Ollama is running and the model is pulled."
                    $typedException = [AnthropicNotFoundException]::new($msg, $errorBody)
                }
                429 {
                    # Rate limited - retry with exponential backoff respecting Retry-After
                    $retryAfter = 0
                    $retryHeader = $_.Exception.Response.Headers['Retry-After']
                    if ($retryHeader) {
                        [int]::TryParse($retryHeader, [ref]$retryAfter) | Out-Null
                    }

                    $retry++
                    if ($retry -lt $MaxRetry) {
                        # Use Retry-After if provided, otherwise exponential backoff
                        $waitSeconds = if ($retryAfter -gt 0) { $retryAfter } else { [Math]::Pow(2, $retry) }
                        Write-Warning "Rate limited (429), retry $retry/$MaxRetry, waiting ${waitSeconds}s..."
                        Start-Sleep -Seconds $waitSeconds
                        continue
                    }

                    $msg = "Rate limited: $errorMessage"
                    if ($retryAfter -gt 0) { $msg += " Retry after $retryAfter seconds." }
                    $typedException = [AnthropicRateLimitException]::new($msg, $retryAfter, $errorBody)
                }
                529 {
                    $msg = "API overloaded: $errorMessage. Try again later."
                    $typedException = [AnthropicOverloadedException]::new($msg, $errorBody)
                }
                { $_ -ge 500 } {
                    # Server error - retry
                    $retry++
                    if ($retry -lt $MaxRetry) {
                        $wait = [Math]::Pow(2, $retry) * 100  # Exponential backoff in ms
                        Write-Warning "Server error ($statusCode), retry $retry/$MaxRetry, waiting ${wait}ms..."
                        Start-Sleep -Milliseconds $wait
                        continue
                    }
                    else {
                        $msg = "Server error (HTTP $statusCode) after $MaxRetry retries: $errorMessage"
                        $typedException = [AnthropicServerException]::new($msg, $statusCode, $errorBody)
                    }
                }
                default {
                    if ($statusCode) {
                        $msg = "API error (HTTP $statusCode): $errorMessage"
                        $typedException = [AnthropicApiException]::new($msg, $statusCode)
                    }
                    else {
                        # No status code - likely connection error
                        $typedException = [AnthropicConnectionException]::new("Connection error to ${Uri}: $($_.Exception.Message)")
                    }
                }
            }

            # Throw or write error with typed exception
            if ($typedException) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $typedException,
                    "AnthropicApi.$($typedException.GetType().Name -replace 'Exception$', '')",
                    [System.Management.Automation.ErrorCategory]::NotSpecified,
                    $Uri
                )
                $PSCmdlet.WriteError($errorRecord)
                return
            }

            # Unknown error
            Write-Error "Request failed: $_"
            return
        }
    } while ($retry -lt $MaxRetry)

    # Return result
    $result
}
