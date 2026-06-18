---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# New-AnthropicConversation

## SYNOPSIS
Creates a new conversation object for multi-turn interactions.

## SYNTAX

```
New-AnthropicConversation [[-UserMessage] <String>] [[-SystemPrompt] <String>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Initializes a conversation hashtable with a Messages array and optional
SystemPrompt.
Use Add-AnthropicMessage to add messages to the conversation.

## EXAMPLES

### EXAMPLE 1
```
$conv = New-AnthropicConversation -UserMessage 'Hello!' -SystemPrompt 'You are helpful.'
$response = Invoke-AnthropicMessage -Messages $conv.Messages -System $conv.SystemPrompt
```

### EXAMPLE 2
```
$conv = New-AnthropicConversation -SystemPrompt 'You are a pirate.'
Add-AnthropicMessage -Conversation $conv -Role 'user' -Content 'Ahoy!'
```

## PARAMETERS

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -SystemPrompt
Optional system prompt to set the assistant's behavior.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -UserMessage
Optional initial user message to start the conversation.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AnthropicConversation
## NOTES

## RELATED LINKS
