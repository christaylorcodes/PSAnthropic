---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# Test-AnthropicEndpoint

## SYNOPSIS
Tests connectivity to the Anthropic-compatible endpoint.

## SYNTAX

```
Test-AnthropicEndpoint [[-Server] <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Verifies that the server is reachable and responding.
Uses Ollama's root endpoint to check if the server is running.

## EXAMPLES

### EXAMPLE 1
```
Test-AnthropicEndpoint
# Tests the currently connected server
```

### EXAMPLE 2
```
Test-AnthropicEndpoint -Server 'localhost:11434'
# Tests a specific server
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

### -Server
Server to test.
Defaults to the connected server or localhost:11434.

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

### System.Management.Automation.PSObject
## NOTES

## RELATED LINKS
