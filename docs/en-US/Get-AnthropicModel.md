---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# Get-AnthropicModel

## SYNOPSIS
Lists available models from the Ollama server.

## SYNTAX

```
Get-AnthropicModel [[-Filter] <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Queries the Ollama /api/tags endpoint to list all available models.
Note: This is Ollama-specific and won't work with Anthropic's cloud API.

## EXAMPLES

### EXAMPLE 1
```
Get-AnthropicModel
# Lists all available models
```

### EXAMPLE 2
```
Get-AnthropicModel -Filter 'llama'
# Lists models containing 'llama' in the name
```

## PARAMETERS

### -Filter
Optional filter string to match model names.

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

### System.Management.Automation.PSObject[]
## NOTES

## RELATED LINKS
