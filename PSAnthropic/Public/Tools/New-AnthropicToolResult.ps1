function New-AnthropicToolResult {
    <#
    .SYNOPSIS
        Creates a tool result message to send back to the model.
    .DESCRIPTION
        After the model requests a tool call (stop_reason = 'tool_use'),
        execute the tool and send the result back using this function.
        The result is formatted as a user message with tool_result content.
    .PARAMETER ToolUseId
        The ID from the tool_use content block in the model's response.
    .PARAMETER Content
        The result of executing the tool. Can be a string or will be converted to JSON.
    .PARAMETER IsError
        Indicates the tool execution failed. The content should describe the error.
    .EXAMPLE
        # Get tool use from response
        $toolUse = $response.content | Where-Object { $_.type -eq 'tool_use' }

        # Execute tool and get result
        $result = Get-Weather -Location $toolUse.input.location

        # Create tool result message
        $toolResult = New-AnthropicToolResult -ToolUseId $toolUse.id -Content $result
    .EXAMPLE
        # Error case
        $toolResult = New-AnthropicToolResult -ToolUseId $toolUse.id -Content 'API unavailable' -IsError
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ToolUseId,

        [Parameter(Mandatory)]
        [object]$Content,

        [Parameter()]
        [switch]$IsError
    )

    # Convert content to string if needed
    $contentString = if ($Content -is [string]) {
        $Content
    }
    else {
        $Content | ConvertTo-Json -Depth 20 -Compress
    }

    # Build tool result content block
    $toolResultBlock = @{
        type        = 'tool_result'
        tool_use_id = $ToolUseId
        content     = $contentString
    }

    if ($IsError) {
        $toolResultBlock.is_error = $true
    }

    # Return as a user message
    @{
        role    = 'user'
        content = @($toolResultBlock)
    }
}
