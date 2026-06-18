function Get-AnthropicTokenCount {
    <#
    .SYNOPSIS
        Counts the input tokens a request would use (Anthropic Cloud).
    .DESCRIPTION
        Calls POST /v1/messages/count_tokens to get the exact input-token count for
        a set of messages (plus optional system prompt and tools), without running
        a completion. Useful for cost estimation and context budgeting.

        This is an Anthropic Cloud feature. On Ollama/Generic backends, token counts
        are approximations (and the beta count_tokens path can hang some servers), so
        this function warns and returns nothing rather than calling them.
    .PARAMETER Messages
        Array of message hashtables or AnthropicMessage objects (same shapes
        Invoke-AnthropicMessage accepts). Supports pipeline input.
    .PARAMETER Model
        The model to count against. Defaults to the connection's model. Token counts
        are model-specific, so pass the model you will actually call.
    .PARAMETER System
        Optional system prompt to include in the count.
    .PARAMETER Tools
        Optional tool definitions to include in the count.
    .PARAMETER TimeoutSec
        Request timeout in seconds. Defaults to 60.
    .EXAMPLE
        $msgs = @(New-AnthropicMessage -Role user -Content 'Explain quantum tunneling')
        Get-AnthropicTokenCount -Messages $msgs -Model 'claude-opus-4-8'
        # Returns the input token count, e.g. 14
    .EXAMPLE
        $conversation.Messages | Get-AnthropicTokenCount
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object[]]$Messages,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$System,

        [Parameter()]
        [hashtable[]]$Tools,

        [Parameter()]
        [int]$TimeoutSec = 60
    )

    begin {
        $allMessages = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($msg in $Messages) {
            $allMessages.Add($msg)
        }
    }

    end {
        if ($allMessages.Count -eq 0) {
            throw "No messages provided. Supply messages via -Messages parameter or pipeline."
        }

        Assert-AnthropicConnection

        if ($script:AnthropicConnection.Provider -ne 'Anthropic') {
            Write-Warning "Token counting (/v1/messages/count_tokens) is an Anthropic Cloud feature; '$($script:AnthropicConnection.Provider)' backends report only approximations and may not support it. Skipping."
            return
        }

        $apiMessages = ConvertTo-AnthropicApiMessage -Messages $allMessages

        $resolvedModel = if ($Model) { $Model } else { $script:AnthropicConnection.Model }
        if (-not $resolvedModel) {
            throw "No model specified. Provide -Model or set a default with Connect-Anthropic."
        }

        $body = @{
            model    = $resolvedModel
            messages = @($apiMessages)
        }
        if ($System) { $body.system = $System }
        if ($Tools) { $body.tools = $Tools }

        $uri = New-AnthropicUrl -Endpoint '/v1/messages/count_tokens'
        $result = Invoke-AnthropicWebRequest -Uri $uri -Method POST -Body $body -TimeoutSec $TimeoutSec

        if ($result -and $result.Content) {
            ($result.Content | ConvertFrom-Json).input_tokens
        }
    }
}
