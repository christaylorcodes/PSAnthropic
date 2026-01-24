function Invoke-AnthropicRouted {
    <#
    .SYNOPSIS
        Sends messages using automatic model routing based on task type.
    .DESCRIPTION
        Routes requests to the appropriate model based on TaskType parameter.
        Logs routing decisions for later analysis.

        Requires Set-AnthropicRouterConfig to be called first.
    .PARAMETER Messages
        Array of message objects. Use New-AnthropicMessage to create.
        Supports pipeline input - messages are accumulated before routing.
    .PARAMETER TaskType
        The type of task to route. Maps to configured models.
        Common types: Default, Code, Vision, Complex, Fast, Creative.
        If not specified, uses 'Default'.
    .PARAMETER System
        System prompt to set context for the conversation.
    .PARAMETER MaxTokens
        Maximum tokens to generate. Defaults to 4096.
    .PARAMETER Temperature
        Sampling temperature (0.0-1.0).
    .PARAMETER Stream
        Enable streaming output.
    .PARAMETER Tools
        Array of tool definitions for function calling.
    .PARAMETER NumCtx
        Context window size (Ollama-specific).
    .PARAMETER TimeoutSec
        Request timeout in seconds. Defaults to 300.
    .EXAMPLE
        # Route to default model
        Invoke-AnthropicRouted -Messages $msgs
    .EXAMPLE
        # Route to code model
        Invoke-AnthropicRouted -Messages $msgs -TaskType Code
    .EXAMPLE
        # Route with tools (auto-selects code model if configured)
        Invoke-AnthropicRouted -Messages $msgs -TaskType Code -Tools $tools
    .EXAMPLE
        # Pipeline input from conversation
        $conversation.Messages | Invoke-AnthropicRouted -TaskType Code
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
        [string]$TaskType = 'Default',

        [Parameter()]
        [string]$System,

        [Parameter()]
        [int]$MaxTokens = 4096,

        [Parameter()]
        [ValidateRange(0.0, 1.0)]
        [double]$Temperature,

        [Parameter()]
        [switch]$Stream,

        [Parameter()]
        [hashtable[]]$Tools,

        [Parameter()]
        [object]$ToolChoice,

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

        # Validate connection exists
        Assert-AnthropicConnection

        # Validate router is configured
        if (-not $script:AnthropicRouterConfig) {
            throw "Router not configured. Call Set-AnthropicRouterConfig first."
        }

        $config = $script:AnthropicRouterConfig

        # Resolve model based on task type
        $resolvedModel = $null
        $routeReason = $null

        if ($config.Models.ContainsKey($TaskType)) {
            $resolvedModel = $config.Models[$TaskType]
            $routeReason = "TaskType '$TaskType' mapped to model"
        }
        else {
            $resolvedModel = $config.Models['Default']
            $routeReason = "TaskType '$TaskType' not found, using Default"
            Write-Warning "TaskType '$TaskType' not configured. Using Default model: $resolvedModel"
        }

        # Get message preview for logging (first user message, truncated)
        $messagePreview = ''
        # Handle both objects with .Role property and hashtables with 'role' key
        $userMsg = $allMessages | Where-Object {
            ($_.Role -eq 'user') -or ($_ -is [hashtable] -and $_['role'] -eq 'user')
        } | Select-Object -First 1

        if ($userMsg) {
            $msgContent = if ($userMsg -is [hashtable]) { $userMsg['content'] } else { $userMsg.Content }

            $content = if ($msgContent -is [string]) {
                $msgContent
            }
            elseif ($msgContent -is [array]) {
                $textBlock = $msgContent | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
                if ($textBlock) { $textBlock.text } else { $null }
            }
            elseif ($null -ne $msgContent) {
                $msgContent.ToString()
            }
            else {
                $null
            }

            if (-not [string]::IsNullOrEmpty($content)) {
                $cleaned = $content -replace '[\r\n]+', ' '
                $previewLength = [Math]::Min(100, $cleaned.Length)
                $messagePreview = $cleaned.Substring(0, $previewLength)
                if ($cleaned.Length -gt 100) { $messagePreview += '...' }
            }
        }

        # Log the routing decision
        Write-AnthropicRouterLog -TaskType $TaskType -Model $resolvedModel -MessagePreview $messagePreview -Reason $routeReason

        # Build parameters for Invoke-AnthropicMessage
        $invokeParams = @{
            Messages   = @($allMessages)
            Model      = $resolvedModel
            MaxTokens  = $MaxTokens
            TimeoutSec = $TimeoutSec
        }

        if ($System) { $invokeParams.System = $System }
        if ($PSBoundParameters.ContainsKey('Temperature')) { $invokeParams.Temperature = $Temperature }
        if ($Stream) { $invokeParams.Stream = $true }
        if ($Tools) { $invokeParams.Tools = $Tools }
        if ($ToolChoice) { $invokeParams.ToolChoice = $ToolChoice }
        if ($PSBoundParameters.ContainsKey('NumCtx')) { $invokeParams.NumCtx = $NumCtx }

        # Invoke the message
        Invoke-AnthropicMessage @invokeParams
    }
}
