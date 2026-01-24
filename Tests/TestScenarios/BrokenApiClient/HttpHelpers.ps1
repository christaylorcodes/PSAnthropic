# HttpHelpers.ps1 - HTTP utility functions
# Dependencies: None (but has its own bugs)

function Join-ApiUrl {
    param(
        [Parameter(Mandatory)]
        [string]$Base,

        [Parameter(Mandatory)]
        [string]$Path
    )

    # BUG 1: Doesn't handle trailing slash on Base
    # BUG 2: Doesn't handle leading slash on Path
    # Results in URLs like "https://api.example.com/v1//users"
    return "$Base$Path"
}

function Send-HttpRequest {
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [string]$Method = 'GET',

        [hashtable]$Headers = @{},

        [hashtable]$Body
    )

    # BUG: Content-Type not set for POST/PUT with body
    $params = @{
        Uri     = $Url
        Method  = $Method
        Headers = $Headers
    }

    if ($Body -and $Method -in @('POST', 'PUT')) {
        # BUG: Body converted to JSON but Content-Type not set
        $params['Body'] = $Body | ConvertTo-Json -Depth 10
        # Missing: $params['ContentType'] = 'application/json'
    }

    try {
        # Simulate HTTP response for testing
        return [PSCustomObject]@{
            StatusCode = 200
            Content    = '{"id": 1, "name": "test"}'
            Headers    = @{ 'Content-Type' = 'application/json' }
        }
    }
    catch {
        # BUG: Wraps exception in another exception, losing stack trace
        throw [System.Exception]::new("HTTP request failed", $_.Exception)
    }
}

function Test-UrlValid {
    param([string]$Url)

    # BUG: Regex is too permissive - allows invalid URLs
    return $Url -match '^https?://'
}

function Get-UrlParameters {
    param([string]$Url)

    # BUG: Doesn't handle URL encoding
    # BUG: Doesn't handle multiple values for same key
    if ($Url -notmatch '\?') { return @{} }

    $queryString = $Url.Split('?')[1]
    $params = @{}

    foreach ($pair in $queryString.Split('&')) {
        $key, $value = $pair.Split('=')
        $params[$key] = $value  # BUG: Overwrites if key appears twice
    }

    return $params
}

function ConvertTo-QueryString {
    param([hashtable]$Parameters)

    if (-not $Parameters -or $Parameters.Count -eq 0) {
        return ''
    }

    # BUG: Doesn't URL-encode values
    $pairs = $Parameters.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$($_.Value)"  # Should use [uri]::EscapeDataString
    }

    return '?' + ($pairs -join '&')
}
