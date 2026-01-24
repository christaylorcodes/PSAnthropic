---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# Get-AnthropicConnection

## SYNOPSIS
Shows the current Anthropic API connection settings.

## SYNTAX

```
Get-AnthropicConnection [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Returns information about the current connection, including server,
model, and when the connection was established.
Does not expose the API key for security.

## EXAMPLES

### EXAMPLE 1
```
Get-AnthropicConnection
```

Server      : localhost:11434
Model       : llama3
ConnectedAt : 1/23/2026 10:30:00 AM

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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AnthropicConnection
## NOTES

## RELATED LINKS
