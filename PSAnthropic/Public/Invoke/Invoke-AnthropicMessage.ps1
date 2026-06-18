function Invoke-AnthropicMessage {
    <#
    .SYNOPSIS
        Sends messages to the Anthropic Messages API (POST /v1/messages).
    .DESCRIPTION
        The primary function for interacting with an Anthropic-compatible API
        (Ollama, Anthropic Cloud, or any compatible endpoint). Sends a conversation
        and returns the assistant's response.

        Request fields are shaped to what the connected backend and model actually
        support (see Get-AnthropicModelCapability): on current Anthropic models
        thinking is sent as adaptive and steered with -Effort, while sampling
        parameters are omitted (they 400 there); on Ollama, thinking is enabled and
        tool_choice/metadata are omitted (unsupported). Unsupported fields are
        dropped with a warning rather than causing an API error.
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
        Enable extended thinking. On current Anthropic models this requests adaptive
        thinking; on Ollama/legacy models it enables thinking with an optional budget.
    .PARAMETER ThinkingBudget
        Maximum tokens for the thinking process (legacy/Ollama 'enabled' thinking only).
        Ignored on models that use adaptive thinking - use -Effort there instead.
    .PARAMETER ThinkingDisplay
        For adaptive thinking, whether reasoning is returned 'summarized' or 'omitted'
        (Anthropic Cloud). Ignored where adaptive thinking is unsupported.
    .PARAMETER Effort
        Reasoning/output effort for models that support it (Anthropic): low, medium,
        high, xhigh, or max. Maps to output_config.effort. Ignored where unsupported.
    .PARAMETER Metadata
        Optional metadata hashtable (e.g. @{ user_id = '...' }) sent on Anthropic Cloud.
        Omitted on backends that don't support it (e.g. Ollama).
    .PARAMETER CacheControl
        Enable prompt caching (Anthropic). Sets top-level cache_control so the API
        auto-caches the last cacheable block. Ignored where caching is unsupported.
    .PARAMETER CacheTtl
        Cache time-to-live when -CacheControl is set: '5m' (default) or '1h'.
    .PARAMETER ResponseSchema
        JSON Schema (hashtable) to constrain the response to valid JSON via
        output_config.format (Anthropic structured outputs). Ignored where unsupported.
    .PARAMETER Beta
        One or more beta feature identifiers for this request, merged into the
        'anthropic-beta' header (non-streaming requests). For streaming, set beta
        features on Connect-Anthropic instead.
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
        [ValidateSet('summarized', 'omitted')]
        [string]$ThinkingDisplay,

        [Parameter()]
        [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')]
        [string]$Effort,

        [Parameter()]
        [hashtable]$Metadata,

        [Parameter()]
        [switch]$CacheControl,

        [Parameter()]
        [ValidateSet('5m', '1h')]
        [string]$CacheTtl = '5m',

        [Parameter()]
        [hashtable]$ResponseSchema,

        [Parameter()]
        [string[]]$Beta,

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
        $apiMessages = ConvertTo-AnthropicApiMessage -Messages $allMessages

        # Resolve model
        $resolvedModel = if ($Model) { $Model } else { $script:AnthropicConnection.Model }
        if (-not $resolvedModel) {
            throw "No model specified. Provide -Model or set a default with Connect-Anthropic."
        }

        # Resolve backend/model capabilities so we only send fields this target accepts
        $capability = Get-AnthropicModelCapability -Model $resolvedModel
        $providerName = $script:AnthropicConnection.Provider

        # Build request body
        $body = @{
            model      = $resolvedModel
            max_tokens = $MaxTokens
            messages   = @($apiMessages)
        }

        if ($System) {
            $body.system = $System
        }

        # Sampling parameters - removed on adaptive-only Anthropic models (they 400)
        if ($PSBoundParameters.ContainsKey('Temperature') -or
            $PSBoundParameters.ContainsKey('TopP') -or
            $PSBoundParameters.ContainsKey('TopK')) {
            if ($capability.SupportsSampling) {
                if ($PSBoundParameters.ContainsKey('Temperature')) { $body.temperature = $Temperature }
                if ($PSBoundParameters.ContainsKey('TopP')) { $body.top_p = $TopP }
                if ($PSBoundParameters.ContainsKey('TopK')) { $body.top_k = $TopK }
            }
            else {
                Write-Warning "Model '$resolvedModel' rejects sampling parameters (temperature/top_p/top_k); they were omitted. Use -Effort to steer reasoning depth."
            }
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

        # tool_choice - not supported by Ollama
        if ($ToolChoice) {
            if ($capability.SupportsToolChoice) {
                $body.tool_choice = if ($ToolChoice -is [string]) { @{ type = $ToolChoice } } else { $ToolChoice }
            }
            else {
                Write-Warning "Provider '$providerName' does not support tool_choice; it was omitted (the model still sees the tools)."
            }
        }

        # metadata - Anthropic only
        if ($PSBoundParameters.ContainsKey('Metadata') -and $Metadata.Count -gt 0) {
            if ($capability.SupportsMetadata) {
                $body.metadata = $Metadata
            }
            else {
                Write-Warning "Provider '$providerName' does not support metadata; it was omitted."
            }
        }

        # Thinking - adaptive on current Anthropic models, enabled+budget on Ollama/legacy
        if ($Thinking) {
            if ($capability.SupportsAdaptiveThinking) {
                $thinkingConfig = @{ type = 'adaptive' }
                if ($PSBoundParameters.ContainsKey('ThinkingDisplay')) {
                    $thinkingConfig.display = $ThinkingDisplay
                }
                if ($PSBoundParameters.ContainsKey('ThinkingBudget')) {
                    Write-Warning "Model '$resolvedModel' uses adaptive thinking; -ThinkingBudget is ignored. Use -Effort to control depth."
                }
                $body.thinking = $thinkingConfig
            }
            elseif ($capability.SupportsEnabledThinking) {
                $thinkingConfig = @{ type = 'enabled' }
                if ($PSBoundParameters.ContainsKey('ThinkingBudget') -and $ThinkingBudget -gt 0) {
                    $thinkingConfig.budget_tokens = $ThinkingBudget
                }
                $body.thinking = $thinkingConfig
            }
            else {
                Write-Warning "Model '$resolvedModel' does not support extended thinking; -Thinking was ignored."
            }
        }

        # output_config (effort + structured-output format) - Anthropic only
        $outputConfig = @{}
        if ($PSBoundParameters.ContainsKey('Effort')) {
            if ($capability.SupportsEffort) {
                $outputConfig.effort = $Effort
            }
            else {
                Write-Warning "Model '$resolvedModel' does not support the effort parameter; -Effort was ignored."
            }
        }
        if ($PSBoundParameters.ContainsKey('ResponseSchema')) {
            if ($capability.SupportsStructuredOutput) {
                $outputConfig.format = @{ type = 'json_schema'; schema = $ResponseSchema }
            }
            else {
                Write-Warning "Model '$resolvedModel' does not support structured outputs; -ResponseSchema was ignored."
            }
        }
        if ($outputConfig.Count -gt 0) {
            $body.output_config = $outputConfig
        }

        # Prompt caching (top-level cache_control auto-caches the last cacheable block) - Anthropic only
        if ($CacheControl) {
            if ($capability.SupportsCaching) {
                $cacheConfig = @{ type = 'ephemeral' }
                if ($CacheTtl -eq '1h') { $cacheConfig.ttl = '1h' }
                $body.cache_control = $cacheConfig
            }
            else {
                Write-Warning "Provider '$providerName' does not support prompt caching; -CacheControl was ignored."
            }
        }

        # Ollama-specific options (context size, etc.) - num_ctx is not an Anthropic Cloud field
        if ($PSBoundParameters.ContainsKey('NumCtx')) {
            if ($providerName -eq 'Anthropic') {
                Write-Warning "Provider '$providerName' does not support -NumCtx (num_ctx is Ollama-specific); it was omitted."
            }
            else {
                $body.options = @{ num_ctx = $NumCtx }
            }
        }

        # Per-request beta features (non-streaming): merge with any connection-level betas
        $extraHeaders = @{}
        if ($Beta) {
            $existingBeta = $script:AnthropicConnection.Headers['anthropic-beta']
            $betaSet = [System.Collections.Generic.List[string]]::new()
            if ($existingBeta) { $existingBeta -split ',' | ForEach-Object { $betaSet.Add($_.Trim()) } }
            $Beta | ForEach-Object { if ($_ -and $betaSet -notcontains $_) { $betaSet.Add($_) } }
            $extraHeaders['anthropic-beta'] = ($betaSet -join ',')
        }

        # Build URL
        $uri = New-AnthropicUrl -Endpoint '/v1/messages'

        if ($Stream) {
            # Streaming request
            Invoke-AnthropicStreamRequest -Uri $uri -Body $body -TimeoutSec $TimeoutSec
        }
        else {
            # Standard request
            $requestParams = @{
                Uri        = $uri
                Method     = 'POST'
                Body       = $body
                TimeoutSec = $TimeoutSec
            }
            if ($extraHeaders.Count -gt 0) { $requestParams.Headers = $extraHeaders }
            $result = Invoke-AnthropicWebRequest @requestParams

            if ($result -and $result.Content) {
                $response = $result.Content | ConvertFrom-Json

                # Enrich response with convenience properties
                if ($response) {
                    $response.PSObject.TypeNames.Insert(0, 'PSAnthropic.MessageResponse')

                    # .Refused - the model declined for safety reasons (stop_reason 'refusal').
                    # content is empty or partial; surface it rather than silently returning blank.
                    $refused = $response.stop_reason -eq 'refusal'
                    $response | Add-Member -NotePropertyName 'Refused' -NotePropertyValue $refused -Force
                    if ($refused) {
                        $category = if ($response.stop_details.category) { " (category: $($response.stop_details.category))" } else { '' }
                        Write-Warning "Request was refused by the model$category. See .stop_details for more."
                    }

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
