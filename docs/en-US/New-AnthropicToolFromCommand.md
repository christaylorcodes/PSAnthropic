---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# New-AnthropicToolFromCommand

## SYNOPSIS
Auto-generates an Anthropic tool definition from a PowerShell command.

## SYNTAX

```
New-AnthropicToolFromCommand [-CommandName] <String> [-Description <String>] [-ParameterSetName <String>]
 [-ExcludeParameter <String[]>] [-IncludeParameter <String[]>] [-Strict] [-IncludeExamples]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Uses PowerShell reflection to extract parameter metadata from a cmdlet or function
and generates an Anthropic-compatible tool definition.
This saves you from manually
defining JSON schemas for tools.

The function extracts:
- Parameter names and types (mapped to JSON Schema types)
- Parameter descriptions from multiple sources (HelpMessage, help content, comments)
- Default values (becomes 'default' in schema)
- Mandatory parameters (become 'required' in schema)
- ValidateSet values (become 'enum' in schema)
- ValidateRange values (become minimum/maximum)
- ValidatePattern (becomes 'pattern')
- ValidateLength (becomes minLength/maxLength)
- ValidateCount (becomes minItems/maxItems for arrays)
- ValidateNotNull/ValidateNotNullOrEmpty (noted in description)
- Parameter aliases (noted in description)

## EXAMPLES

### EXAMPLE 1
```
# Generate tool from a built-in cmdlet
$tool = New-AnthropicToolFromCommand -CommandName 'Get-Process'
```

### EXAMPLE 2
```
# Generate tool with custom description
$tool = New-AnthropicToolFromCommand -CommandName 'Get-ChildItem' -Description 'List files and folders'
```

### EXAMPLE 3
```
# Generate strict tool for Claude's strict mode
$tool = New-AnthropicToolFromCommand -CommandName 'Get-Process' -Strict -IncludeExamples
```

### EXAMPLE 4
```
# Generate tool from a custom function
function Get-Weather {
    param(
        [Parameter(Mandatory, HelpMessage = 'City or region name')]
        [string]$Location,
```

\[ValidateSet('celsius', 'fahrenheit')\]
        \[string\]$Unit = 'celsius'
    )
    # Implementation...
}
$tool = New-AnthropicToolFromCommand -CommandName 'Get-Weather'

### EXAMPLE 5
```
# Register multiple functions as tools
$tools = 'Get-Process', 'Get-Service', 'Get-Date' | ForEach-Object {
    New-AnthropicToolFromCommand -CommandName $_
}
```

## PARAMETERS

### -CommandName
The name of the PowerShell command to convert to a tool definition.

```yaml
Type: String
Parameter Sets: (All)
Aliases: Name, Command

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: False
```

### -Description
Override the tool description.
If not provided, uses the command's Synopsis from Get-Help.

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

### -ExcludeParameter
Parameter names to exclude from the tool definition (in addition to common parameters).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -IncludeExamples
Include example values in the schema based on type and validation attributes.

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

### -IncludeParameter
If specified, only include these parameters (still excludes common parameters).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ParameterSetName
Which parameter set to use when the command has multiple.
Defaults to the default parameter set.

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

### -Strict
Generate strict schema with additionalProperties: false.
Recommended for Claude's strict mode.

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

### System.Collections.Hashtable
## NOTES

## RELATED LINKS
