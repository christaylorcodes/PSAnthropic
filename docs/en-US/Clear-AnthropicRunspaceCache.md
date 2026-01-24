---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# Clear-AnthropicRunspaceCache

## SYNOPSIS
Clears the cached runspaces used by safe command execution.

## SYNTAX

```
Clear-AnthropicRunspaceCache [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
The PSAnthropic module caches constrained runspaces for performance when
executing tool commands.
This function disposes all cached runspaces and
clears the cache.

Call this function when:
- You want to reclaim memory from cached runspaces
- You need to reset the execution environment
- Before unloading the module in long-running sessions

Note: The module automatically cleans up runspaces when it is removed
via Remove-Module.
This function is for manual cleanup during active use.

## EXAMPLES

### EXAMPLE 1
```
Clear-AnthropicRunspaceCache
```

Clears all cached runspaces.

### EXAMPLE 2
```
# Clean up after intensive tool usage
$tools = Get-AnthropicStandardTools
# ... execute many tool calls ...
Clear-AnthropicRunspaceCache
```

Explicitly reclaims memory after heavy tool usage.

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

## NOTES

## RELATED LINKS
