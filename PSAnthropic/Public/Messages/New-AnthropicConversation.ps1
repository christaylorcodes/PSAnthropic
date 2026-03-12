function New-AnthropicConversation {
    <#
    .SYNOPSIS
        Creates a new conversation object for multi-turn interactions.
    .DESCRIPTION
        Initializes a conversation hashtable with a Messages array and optional
        SystemPrompt. Use Add-AnthropicMessage to add messages to the conversation.
    .PARAMETER UserMessage
        Optional initial user message to start the conversation.
    .PARAMETER SystemPrompt
        Optional system prompt to set the assistant's behavior.
    .EXAMPLE
        $conv = New-AnthropicConversation -UserMessage 'Hello!' -SystemPrompt 'You are helpful.'
        $response = Invoke-AnthropicMessage -Messages $conv.Messages -System $conv.SystemPrompt
    .EXAMPLE
        $conv = New-AnthropicConversation -SystemPrompt 'You are a pirate.'
        Add-AnthropicMessage -Conversation $conv -Role 'user' -Content 'Ahoy!'
    #>
    [CmdletBinding()]
    [OutputType('AnthropicConversation')]
    param(
        [Parameter()]
        [string]$UserMessage,

        [Parameter()]
        [string]$SystemPrompt
    )

    $conversation = [AnthropicConversation]::new($SystemPrompt)

    if ($UserMessage) {
        $conversation.AddMessage([AnthropicRole]::user, $UserMessage)
    }

    $conversation
}
