---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# Get-AnthropicTokenCount

## SYNOPSIS
Counts the input tokens a request would use (Anthropic Cloud).

## SYNTAX

```
Get-AnthropicTokenCount [-Messages] <Object[]> [-Model <String>] [-System <String>] [-Tools <Hashtable[]>]
 [-TimeoutSec <Int32>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Calls POST /v1/messages/count_tokens to get the exact input-token count for
a set of messages (plus optional system prompt and tools), without running
a completion.
Useful for cost estimation and context budgeting.

This is an Anthropic Cloud feature.
On Ollama/Generic backends, token counts
are approximations (and the beta count_tokens path can hang some servers), so
this function warns and returns nothing rather than calling them.

## EXAMPLES

### EXAMPLE 1
```
$msgs = @(New-AnthropicMessage -Role user -Content 'Explain quantum tunneling')
Get-AnthropicTokenCount -Messages $msgs -Model 'claude-opus-4-8'
# Returns the input token count, e.g. 14
```

### EXAMPLE 2
```
$conversation.Messages | Get-AnthropicTokenCount
```

## PARAMETERS

### -Messages
Array of message hashtables or AnthropicMessage objects (same shapes
Invoke-AnthropicMessage accepts).
Supports pipeline input.

```yaml
Type: Object[]
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

### -Model
The model to count against.
Defaults to the connection's model.
Token counts
are model-specific, so pass the model you will actually call.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
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

### -System
Optional system prompt to include in the count.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -TimeoutSec
Request timeout in seconds.
Defaults to 60.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 60
Accept pipeline input: False
Accept wildcard characters: False
```

### -Tools
Optional tool definitions to include in the count.

```yaml
Type: Hashtable[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Int32
## NOTES

## RELATED LINKS
