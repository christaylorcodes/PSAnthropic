# ApiClient.ps1 - Main API client
# This file has dependency issues with other files

. $PSScriptRoot\HttpHelpers.ps1
. $PSScriptRoot\JsonParser.ps1
. $PSScriptRoot\AuthManager.ps1

$script:ApiConfig = @{
    BaseUrl = 'https://api.example.com/v1'
    Timeout = 30
    RetryCount = 3
}

function Invoke-ApiRequest {
    <#
    .SYNOPSIS
        Makes an API request with authentication and retry logic.
    .DESCRIPTION
        BUG 1: Auth token is fetched but never used in headers
        BUG 2: Retry logic has off-by-one (retries RetryCount+1 times)
        BUG 3: Response parsing can fail silently
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [hashtable]$Body,

        [hashtable]$Headers = @{}
    )

    # Get auth token (BUG: Token is fetched but never added to Headers)
    $token = Get-AuthToken
    Write-Verbose "Got auth token: $($token.Substring(0, 10))..."
    # Missing: $Headers['Authorization'] = "Bearer $token"

    $url = Join-ApiUrl -Base $script:ApiConfig.BaseUrl -Path $Endpoint

    # Retry logic (BUG: Loop runs RetryCount+1 times, should be RetryCount)
    $attempt = 0
    $lastError = $null

    while ($attempt -le $script:ApiConfig.RetryCount) {  # BUG: Should be -lt
        $attempt++
        try {
            Write-Verbose "Attempt $attempt of $($script:ApiConfig.RetryCount)"

            $response = Send-HttpRequest -Url $url -Method $Method -Headers $Headers -Body $Body

            # BUG: Doesn't check if response is valid before parsing
            $parsed = ConvertFrom-ApiJson -JsonString $response.Content

            return [PSCustomObject]@{
                Success    = $true
                StatusCode = $response.StatusCode
                Data       = $parsed
                Attempt    = $attempt
            }
        }
        catch {
            $lastError = $_
            Write-Verbose "Attempt $attempt failed: $_"

            # BUG: Always waits, even on last attempt
            Start-Sleep -Milliseconds (500 * $attempt)
        }
    }

    # Return error result
    return [PSCustomObject]@{
        Success    = $false
        StatusCode = 0
        Error      = $lastError.Exception.Message
        Attempt    = $attempt
    }
}

function Get-ApiResource {
    param(
        [Parameter(Mandatory)]
        [string]$ResourceType,

        [string]$Id
    )

    $endpoint = if ($Id) {
        "/$ResourceType/$Id"  # BUG: Double slash if ResourceType starts with /
    } else {
        "/$ResourceType"
    }

    return Invoke-ApiRequest -Endpoint $endpoint -Method GET
}

function New-ApiResource {
    param(
        [Parameter(Mandatory)]
        [string]$ResourceType,

        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    # BUG: Doesn't validate $Data before sending
    return Invoke-ApiRequest -Endpoint "/$ResourceType" -Method POST -Body $Data
}
