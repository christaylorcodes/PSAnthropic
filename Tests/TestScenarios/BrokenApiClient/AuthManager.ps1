# AuthManager.ps1 - Authentication management
# Contains security and state management bugs

$script:AuthState = @{
    Token        = $null
    ExpiresAt    = $null
    RefreshToken = $null
    UserId       = $null
}

function Get-AuthToken {
    <#
    .DESCRIPTION
        Returns the current auth token, refreshing if expired.
        BUG 1: Token refresh can cause infinite loop
        BUG 2: Expiration check uses wrong comparison
        BUG 3: Token is stored in plain text (security issue)
    #>

    # Check if we have a token
    if ($null -eq $script:AuthState.Token) {
        # No token - need to login
        # For testing, return a dummy token
        $script:AuthState.Token = "dummy_token_" + (Get-Date).Ticks
        $script:AuthState.ExpiresAt = (Get-Date).AddHours(1)
        return $script:AuthState.Token
    }

    # BUG: Should be -lt (less than), not -gt (greater than)
    if ((Get-Date) -gt $script:AuthState.ExpiresAt) {
        Write-Verbose "Token still valid"
        return $script:AuthState.Token
    }

    # Token expired - refresh
    Write-Verbose "Token expired, refreshing..."

    # BUG: If refresh fails, this can cause infinite recursion
    $refreshed = Update-AuthToken -RefreshToken $script:AuthState.RefreshToken

    if (-not $refreshed) {
        # BUG: Doesn't clear state on failure, may return stale token
        Write-Warning "Token refresh failed"
    }

    return $script:AuthState.Token
}

function Update-AuthToken {
    param(
        [string]$RefreshToken
    )

    # BUG: No validation of RefreshToken
    if ([string]::IsNullOrEmpty($RefreshToken)) {
        # BUG: Still tries to refresh with empty token
        Write-Verbose "No refresh token, attempting refresh anyway"
    }

    try {
        # Simulate token refresh
        $script:AuthState.Token = "refreshed_token_" + (Get-Date).Ticks
        $script:AuthState.ExpiresAt = (Get-Date).AddHours(1)

        # BUG: Doesn't update RefreshToken (it should be rotated)
        return $true
    }
    catch {
        # BUG: Error is swallowed, no logging
        return $false
    }
}

function Test-AuthTokenValid {
    param(
        [string]$Token
    )

    # BUG 1: Token validation is too weak
    # BUG 2: Doesn't verify token signature or issuer
    return -not [string]::IsNullOrEmpty($Token)
}

function Clear-AuthState {
    # BUG: Doesn't use SecureString or secure memory clearing
    $script:AuthState.Token = $null
    $script:AuthState.RefreshToken = $null
    $script:AuthState.ExpiresAt = $null
    $script:AuthState.UserId = $null

    # BUG: Token may still be in memory (not securely zeroed)
}

function Get-AuthHeader {
    $token = Get-AuthToken

    # BUG: Doesn't check if token is valid before returning
    return @{
        'Authorization' = "Bearer $token"
        # BUG: Missing other common auth headers like X-Request-ID
    }
}

function Set-AuthCredentials {
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password  # BUG: Should use SecureString
    )

    # BUG: Credentials stored in plain text
    # BUG: No input validation

    # Simulate authentication
    $script:AuthState = @{
        Token        = "auth_" + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$Username`:$Password"))
        ExpiresAt    = (Get-Date).AddHours(1)
        RefreshToken = "refresh_" + (Get-Random)
        UserId       = $Username  # BUG: Using username as ID
    }

    # BUG: Returns sensitive data
    return $script:AuthState
}
