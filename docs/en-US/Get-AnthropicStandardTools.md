---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# Get-AnthropicStandardTools

## SYNOPSIS
Returns a set of standard tools for common operations.

## SYNTAX

```
Get-AnthropicStandardTools [[-ToolSet] <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Provides pre-defined tools similar to Anthropic's built-in tools:
- pwsh: Execute PowerShell commands (like bash_20241022)
- str_replace_editor: Text editor with view/create/replace (like text_editor_20250124)
- read_file: Read file contents
- list_directory: List directory contents
- search_files: Search for files by pattern
- search_content: Search for text within files
- get_current_time: Get current date/time
- web_fetch: Fetch and parse content from URLs

## EXAMPLES

### EXAMPLE 1
```
$tools = Get-AnthropicStandardTools
Invoke-AnthropicMessage -Messages $messages -Tools $tools
```

### EXAMPLE 2
```
$tools = Get-AnthropicStandardTools -ToolSet FileSystem
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

### -ToolSet
Which set of tools to return: 'All', 'FileSystem', 'Editor', 'Shell'

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: All
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Collections.Hashtable[]
## NOTES

## RELATED LINKS
