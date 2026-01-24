# PSAnthropic Type Definitions
# These classes and enums provide type safety for core module structures

#region Enums

enum AnthropicRole {
    user
    assistant
}

#endregion

#region Classes

class AnthropicConnection {
    [string]$Server
    [string]$Model
    hidden [hashtable]$Headers  # Hidden to prevent accidental API key exposure
    [datetime]$ConnectedAt
    [bool]$HasApiKey

    AnthropicConnection() { }

    AnthropicConnection([string]$server, [string]$model, [hashtable]$headers) {
        $this.Server = $server
        $this.Model = $model
        $this.Headers = $headers
        $this.ConnectedAt = Get-Date
        $this.HasApiKey = [bool]$headers['X-Api-Key']
    }

    [string] ToString() {
        return "$($this.Server) [$($this.Model)]"
    }
}

class AnthropicMessage {
    [AnthropicRole]$Role
    [object]$Content

    AnthropicMessage() { }

    AnthropicMessage([AnthropicRole]$role, [object]$content) {
        $this.Role = $role
        $this.Content = $content
    }

    AnthropicMessage([string]$role, [object]$content) {
        $this.Role = [AnthropicRole]$role
        $this.Content = $content
    }

    [hashtable] ToHashtable() {
        return @{
            role    = $this.Role.ToString()
            content = $this.Content
        }
    }

    [string] ToString() {
        $preview = if ([string]::IsNullOrEmpty($this.Content)) {
            '[empty]'
        } elseif ($this.Content -is [string]) {
            if ($this.Content.Length -le 50) { $this.Content } else { $this.Content.Substring(0, 50) + '...' }
        } else {
            '[complex content]'
        }
        return "[$($this.Role)] $preview"
    }
}

class AnthropicConversation {
    [System.Collections.Generic.List[AnthropicMessage]]$Messages
    [string]$SystemPrompt

    AnthropicConversation() {
        $this.Messages = [System.Collections.Generic.List[AnthropicMessage]]::new()
    }

    AnthropicConversation([string]$systemPrompt) {
        $this.Messages = [System.Collections.Generic.List[AnthropicMessage]]::new()
        $this.SystemPrompt = $systemPrompt
    }

    [void] AddMessage([AnthropicRole]$role, [object]$content) {
        $this.Messages.Add([AnthropicMessage]::new($role, $content))
    }

    [void] AddMessage([AnthropicMessage]$message) {
        $this.Messages.Add($message)
    }

    [hashtable[]] GetMessagesAsHashtables() {
        return $this.Messages | ForEach-Object { $_.ToHashtable() }
    }

    [string] ToString() {
        return "Conversation: $($this.Messages.Count) messages"
    }
}

#endregion

#region Exception Classes

class AnthropicApiException : System.Exception {
    [int]$StatusCode
    [string]$ErrorType
    [object]$ResponseBody

    AnthropicApiException([string]$message) : base($message) { }
    AnthropicApiException([string]$message, [System.Exception]$inner) : base($message, $inner) { }
    AnthropicApiException([string]$message, [int]$statusCode) : base($message) { $this.StatusCode = $statusCode }
    AnthropicApiException([string]$message, [int]$statusCode, [string]$errorType, [object]$responseBody) : base($message) {
        $this.StatusCode = $statusCode
        $this.ErrorType = $errorType
        $this.ResponseBody = $responseBody
    }
    AnthropicApiException([string]$message, [int]$statusCode, [string]$errorType, [object]$responseBody, [System.Exception]$inner) : base($message, $inner) {
        $this.StatusCode = $statusCode
        $this.ErrorType = $errorType
        $this.ResponseBody = $responseBody
    }
}

class AnthropicBadRequestException : AnthropicApiException {
    AnthropicBadRequestException([string]$message, [object]$responseBody) : base($message, 400, 'bad_request', $responseBody) { }
}

class AnthropicAuthenticationException : AnthropicApiException {
    AnthropicAuthenticationException([string]$message, [object]$responseBody) : base($message, 401, 'authentication_error', $responseBody) { }
}

class AnthropicPermissionException : AnthropicApiException {
    AnthropicPermissionException([string]$message, [object]$responseBody) : base($message, 403, 'permission_error', $responseBody) { }
}

class AnthropicNotFoundException : AnthropicApiException {
    AnthropicNotFoundException([string]$message, [object]$responseBody) : base($message, 404, 'not_found', $responseBody) { }
}

class AnthropicRateLimitException : AnthropicApiException {
    [int]$RetryAfterSeconds
    AnthropicRateLimitException([string]$message, [int]$retryAfter, [object]$responseBody) : base($message, 429, 'rate_limit_error', $responseBody) {
        $this.RetryAfterSeconds = $retryAfter
    }
}

class AnthropicOverloadedException : AnthropicApiException {
    AnthropicOverloadedException([string]$message, [object]$responseBody) : base($message, 529, 'overloaded_error', $responseBody) { }
}

class AnthropicServerException : AnthropicApiException {
    AnthropicServerException([string]$message, [int]$statusCode, [object]$responseBody) : base($message, $statusCode, 'server_error', $responseBody) { }
}

class AnthropicConnectionException : AnthropicApiException {
    AnthropicConnectionException([string]$message) : base($message, -1) { $this.ErrorType = 'connection_error' }
    AnthropicConnectionException([string]$message, [System.Exception]$inner) : base($message, $inner) {
        $this.StatusCode = -1
        $this.ErrorType = 'connection_error'
    }
}

#endregion
