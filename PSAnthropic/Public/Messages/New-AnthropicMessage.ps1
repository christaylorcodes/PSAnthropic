function New-AnthropicMessage {
    <#
    .SYNOPSIS
        Creates a message hashtable for the Anthropic Messages API.
    .DESCRIPTION
        Creates a properly structured message object for use with Invoke-AnthropicMessage.
        Messages can contain text content or an array of content blocks (for images, etc.).
    .PARAMETER Role
        The role of the message sender. Must be 'user' or 'assistant'.
    .PARAMETER Content
        The message content. Can be a string or an array of content blocks.
    .EXAMPLE
        New-AnthropicMessage -Role 'user' -Content 'Hello, how are you?'
        # Creates a simple user message
    .EXAMPLE
        New-AnthropicMessage -Role 'assistant' -Content 'I am doing well, thank you!'
        # Creates an assistant message (for conversation history)
    .EXAMPLE
        $content = @(
            @{ type = 'text'; text = 'What is in this image?' }
            (New-AnthropicImageContent -Path './image.png')
        )
        New-AnthropicMessage -Role 'user' -Content $content
        # Creates a message with text and image content
    #>
    [CmdletBinding()]
    [OutputType('AnthropicMessage')]
    param(
        [Parameter(Mandatory)]
        [AnthropicRole]$Role,

        [Parameter(Mandatory)]
        [object]$Content
    )

    [AnthropicMessage]::new($Role, $Content)
}
