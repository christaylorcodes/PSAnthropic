---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# Get-AnthropicRouterConfig

## SYNOPSIS
Gets the current router configuration.

## SYNTAX

```
Get-AnthropicRouterConfig [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Returns the current model routing configuration and logging settings.

## EXAMPLES

### EXAMPLE 1
```
Get-AnthropicRouterConfig
```

### EXAMPLE 2
```
# Check if router is configured
if (Get-AnthropicRouterConfig) { "Router ready" }
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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Collections.Hashtable
## NOTES

## RELATED LINKS
