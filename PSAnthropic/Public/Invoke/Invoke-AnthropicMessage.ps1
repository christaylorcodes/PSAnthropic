function Invoke-AnthropicMessage {
    <#
    .SYNOPSIS
        Sends messages to the Anthropic Messages API (POST /v1/messages).
    .DESCRIPTION
        The primary function for interacting with Ollama's Anthropic-compatible API.
        Sends a conversation and returns the assistant's response.
    .PARAMETER Messages
        Array of message hashtables or objects. Each message should have 'role' and 'content' keys.
        Use New-AnthropicMessage to create properly formatted messages.
        Supports pipeline input - messages are accumulated before the API call is made.
    .PARAMETER Model
        The model to use. Defaults to the model set in Connect-Anthropic.
    .PARAMETER MaxTokens
        Maximum tokens to generate. Defaults to 4096.
    .PARAMETER System
        System prompt to set context for the conversation.
    .PARAMETER Temperature
        Sampling temperature (0.0-1.0). Lower values are more deterministic.
    .PARAMETER TopP
        Nucleus sampling probability threshold.
    .PARAMETER TopK
        Sample from top K options for each token.
    .PARAMETER StopSequences
        Array of strings that will stop generation when encountered.
    .PARAMETER Stream
        Enable streaming output. Returns events as they arrive.
    .PARAMETER Tools
        Array of tool definitions for function calling.
    .PARAMETER ToolChoice
        How to handle tool selection ('auto', 'any', 'tool', or specific tool name).
    .PARAMETER Thinking
        Enable extended thinking mode. The model will include its reasoning process.
    .PARAMETER ThinkingBudget
        Maximum tokens for the thinking process (requires -Thinking).
    .PARAMETER NumCtx
        Context window size (Ollama-specific). Smaller values use less VRAM.
        Common values: 2048, 4096, 8192, 16384, 32768. Default is model-specific.
    .PARAMETER TimeoutSec
        Request timeout in seconds. Defaults to 300.
    .EXAMPLE
        $response = Invoke-AnthropicMessage -Messages @(
            New-AnthropicMessage -Role 'user' -Content 'What is PowerShell?'
        )
        $response | Get-AnthropicResponseText
    .EXAMPLE
        # With system prompt
        $response = Invoke-AnthropicMessage -Messages @(
            New-AnthropicMessage -Role 'user' -Content 'Explain recursion'
        ) -System 'You are a programming tutor. Be concise.'
    .EXAMPLE
        # Streaming output
        Invoke-AnthropicMessage -Messages @(
            New-AnthropicMessage -Role 'user' -Content 'Write a haiku'
        ) -Stream | ForEach-Object {
            if ($_.type -eq 'content_block_delta') {
                Write-Host $_.delta.text -NoNewline
            }
        }
    .EXAMPLE
        # Pipeline input from conversation
        $conversation.Messages | Invoke-AnthropicMessage
    .EXAMPLE
        # Pipeline with multiple messages
        @(
            New-AnthropicMessage -Role 'user' -Content 'Hello'
            New-AnthropicMessage -Role 'assistant' -Content 'Hi there!'
            New-AnthropicMessage -Role 'user' -Content 'How are you?'
        ) | Invoke-AnthropicMessage
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Using [object[]] to avoid type identity conflicts when module is reloaded
        # Accepts AnthropicMessage objects or hashtables with 'role' and 'content' keys
        # Supports pipeline input for PowerShell 7+ workflows
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object[]]$Messages,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [int]$MaxTokens = 4096,

        [Parameter()]
        [string]$System,

        [Parameter()]
        [ValidateRange(0.0, 1.0)]
        [double]$Temperature,

        [Parameter()]
        [ValidateRange(0.0, 1.0)]
        [double]$TopP,

        [Parameter()]
        [int]$TopK,

        [Parameter()]
        [string[]]$StopSequences,

        [Parameter()]
        [switch]$Stream,

        [Parameter()]
        [hashtable[]]$Tools,

        [Parameter()]
        [object]$ToolChoice,

        [Parameter()]
        [switch]$Thinking,

        [Parameter()]
        [int]$ThinkingBudget,

        [Parameter()]
        [ValidateRange(512, 131072)]
        [int]$NumCtx,

        [Parameter()]
        [int]$TimeoutSec = 300
    )

    begin {
        # Accumulate messages from pipeline
        $allMessages = [System.Collections.Generic.List[object]]::new()
    }

    process {
        # Add each message from pipeline or parameter
        foreach ($msg in $Messages) {
            $allMessages.Add($msg)
        }
    }

    end {
        if ($allMessages.Count -eq 0) {
            throw "No messages provided. Supply messages via -Messages parameter or pipeline."
        }

        Assert-AnthropicConnection

        # Convert messages to hashtables for the API
        # Handles AnthropicMessage objects, hashtables, and PSCustomObjects
        $apiMessages = for ($i = 0; $i -lt $allMessages.Count; $i++) {
            $msg = $allMessages[$i]

            if ($msg -is [hashtable]) {
                if (-not $msg.ContainsKey('role') -or -not $msg.ContainsKey('content')) {
                    throw "Messages[$i]: Hashtable must contain 'role' and 'content' keys."
                }
                $msg
            }
            elseif ($null -ne $msg -and $msg.PSObject.Methods.Name -contains 'ToHashtable') {
                $msg.ToHashtable()
            }
            elseif ($null -ne $msg.Role -and $null -ne $msg.Content) {
                @{
                    role    = $msg.Role.ToString()
                    content = $msg.Content
                }
            }
            else {
                throw "Messages[$i]: Invalid message. Expected AnthropicMessage, hashtable with 'role'/'content', or object with Role/Content properties. Got: $($msg.GetType().Name)"
            }
        }

        # Resolve model
        $resolvedModel = if ($Model) { $Model } else { $script:AnthropicConnection.Model }
        if (-not $resolvedModel) {
            throw "No model specified. Provide -Model or set a default with Connect-Anthropic."
        }

        # Build request body
        $body = @{
            model      = $resolvedModel
            max_tokens = $MaxTokens
            messages   = @($apiMessages)
        }

        # Add optional parameters
        if ($System) {
            $body.system = $System
        }

        if ($PSBoundParameters.ContainsKey('Temperature')) {
            $body.temperature = $Temperature
        }

        if ($PSBoundParameters.ContainsKey('TopP')) {
            $body.top_p = $TopP
        }

        if ($PSBoundParameters.ContainsKey('TopK')) {
            $body.top_k = $TopK
        }

        if ($StopSequences) {
            $body.stop_sequences = $StopSequences
        }

        if ($Stream) {
            $body.stream = $true
        }

        if ($Tools) {
            $body.tools = $Tools
        }

        if ($ToolChoice) {
            if ($ToolChoice -is [string]) {
                $body.tool_choice = @{ type = $ToolChoice }
            }
            else {
                $body.tool_choice = $ToolChoice
            }
        }

        if ($Thinking) {
            $thinkingConfig = @{ type = 'enabled' }
            if ($PSBoundParameters.ContainsKey('ThinkingBudget') -and $ThinkingBudget -gt 0) {
                $thinkingConfig.budget_tokens = $ThinkingBudget
            }
            $body.thinking = $thinkingConfig
        }

        # Ollama-specific options (context size, etc.)
        if ($PSBoundParameters.ContainsKey('NumCtx')) {
            $body.options = @{ num_ctx = $NumCtx }
        }

        # Build URL
        $uri = New-AnthropicUrl -Endpoint '/v1/messages'

        if ($Stream) {
            # Streaming request
            Invoke-AnthropicStreamRequest -Uri $uri -Body $body -TimeoutSec $TimeoutSec
        }
        else {
            # Standard request
            $result = Invoke-AnthropicWebRequest -Uri $uri -Method POST -Body $body -TimeoutSec $TimeoutSec

            if ($result -and $result.Content) {
                $response = $result.Content | ConvertFrom-Json

                # Enrich response with convenience properties
                if ($response) {
                    $response.PSObject.TypeNames.Insert(0, 'PSAnthropic.MessageResponse')

                    # Ensure content array exists for safe processing
                    $contentArray = if ($response.content) { @($response.content) } else { @() }

                    # .Answer - extracted text content
                    $response | Add-Member -NotePropertyName 'Answer' -NotePropertyValue (
                        @($contentArray | Where-Object type -eq 'text' | ForEach-Object text) -join ''
                    ) -Force

                    # .History - messages including this response (for conversation continuation)
                    # For text-only responses, use string content for Ollama compatibility
                    # For tool_use responses, keep array format (required for tool loops)
                    $hasToolUse = ($contentArray | Where-Object type -eq 'tool_use').Count -gt 0
                    $historyContent = if ($hasToolUse) {
                        # Tool use - convert PSCustomObjects to hashtables for clean serialization
                        @($contentArray | ForEach-Object {
                            $block = @{ type = $_.type }
                            switch ($_.type) {
                                'text' { $block.text = $_.text }
                                'tool_use' { $block.id = $_.id; $block.name = $_.name; $block.input = $_.input }
                                'thinking' { $block.thinking = $_.thinking }
                            }
                            $block
                        })
                    }
                    else {
                        # Text only - use string format for broader compatibility
                        ($contentArray | Where-Object type -eq 'text' | ForEach-Object text) -join ''
                    }
                    $response | Add-Member -NotePropertyName 'History' -NotePropertyValue (
                        @($apiMessages) + @{ role = 'assistant'; content = $historyContent }
                    ) -Force

                    # .ToolUse - tool_use blocks if present (for tool loop handling)
                    $toolUse = @($contentArray | Where-Object type -eq 'tool_use')
                    if ($toolUse.Count -gt 0) {
                        $response | Add-Member -NotePropertyName 'ToolUse' -NotePropertyValue $toolUse -Force
                    }

                    # .Thinking - thinking content if present
                    $thinkingBlocks = @($contentArray | Where-Object { $_.type -eq 'thinking' })
                    if ($thinkingBlocks.Count -gt 0) {
                        $thinkingText = ($thinkingBlocks | ForEach-Object { $_.thinking }) -join "`n"
                        $response | Add-Member -NotePropertyName 'Thinking' -NotePropertyValue $thinkingText -Force
                    }
                }

                $response
            }
        }
    }
}
