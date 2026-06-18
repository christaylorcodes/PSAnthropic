---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# New-AnthropicMessage

## SYNOPSIS
Creates a message hashtable for the Anthropic Messages API.

## SYNTAX

```
New-AnthropicMessage [-Role] <AnthropicRole> [-Content] <Object> [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Creates a properly structured message object for use with Invoke-AnthropicMessage.
Messages can contain text content or an array of content blocks (for images, etc.).

## EXAMPLES

### EXAMPLE 1
```
New-AnthropicMessage -Role 'user' -Content 'Hello, how are you?'
# Creates a simple user message
```

### EXAMPLE 2
```
New-AnthropicMessage -Role 'assistant' -Content 'I am doing well, thank you!'
# Creates an assistant message (for conversation history)
```

### EXAMPLE 3
```
$content = @(
    @{ type = 'text'; text = 'What is in this image?' }
    (New-AnthropicImageContent -Path './image.png')
)
New-AnthropicMessage -Role 'user' -Content $content
# Creates a message with text and image content
```

## PARAMETERS

### -Content
The message content.
Can be a string or an array of content blocks.

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

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

### -Role
The role of the message sender.
Must be 'user' or 'assistant'.

```yaml
Type: AnthropicRole
Parameter Sets: (All)
Aliases:
Accepted values: user, assistant

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AnthropicMessage
## NOTES

## RELATED LINKS
