---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# Get-AnthropicModel

## SYNOPSIS
Lists available models from the connected backend.

## SYNTAX

```
Get-AnthropicModel [[-Filter] <String>] [-Refresh] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Discovers models from whichever backend the connection points at, so the
module never relies on a hardcoded model list:

- Anthropic Cloud (Provider 'Anthropic'): queries GET /v1/models (paginated).
- Ollama / Generic: queries the Ollama /api/tags endpoint.

Results are cached on the connection for a few minutes; use -Refresh to
force a live re-query.

## EXAMPLES

### EXAMPLE 1
```
Get-AnthropicModel
# Lists all available models for the connected backend
```

### EXAMPLE 2
```
Get-AnthropicModel -Filter 'opus'
# Lists models whose name contains 'opus'
```

### EXAMPLE 3
```
Get-AnthropicModel -Refresh
# Forces a fresh query, bypassing the cache
```

## PARAMETERS

### -Filter
Optional filter string to match model names (substring, case-insensitive).

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

### -Refresh
Bypass the cache and re-query the backend.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
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
