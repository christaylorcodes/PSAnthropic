function Add-AnthropicMessage {
    <#
    .SYNOPSIS
        Adds a message to an existing conversation.
    .DESCRIPTION
        Appends a new message to a conversation's Messages array.
        The conversation is modified in place.
    .PARAMETER Conversation
        The conversation hashtable created by New-AnthropicConversation.
    .PARAMETER Role
        The role of the message sender ('user' or 'assistant').
    .PARAMETER Content
        The message content.
    .PARAMETER Response
        Alternative: Add the text from an API response as an assistant message.
    .PARAMETER PassThru
        Return the updated conversation object.
    .EXAMPLE
        Add-AnthropicMessage -Conversation $conv -Role 'user' -Content 'Hello!'
    .EXAMPLE
        Add-AnthropicMessage -Conversation $conv -Response $response
        # Adds the assistant's response text to the conversation
    .EXAMPLE
        $conv = $conv | Add-AnthropicMessage -Role 'user' -Content 'Hi' -PassThru
    #>
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType('AnthropicConversation')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AnthropicConversation]$Conversation,

        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [AnthropicRole]$Role,

        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [object]$Content,

        [Parameter(Mandatory, ParameterSetName = 'Response')]
        [PSObject]$Response,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Response') {
            # Extract text from response and add as assistant message
            $text = $Response | Get-AnthropicResponseText
            if ($text) {
                $Conversation.AddMessage([AnthropicRole]::assistant, $text)
            }
        }
        else {
            # Add message with specified role and content
            $Conversation.AddMessage($Role, $Content)
        }

        if ($PassThru) {
            $Conversation
        }
    }
}
