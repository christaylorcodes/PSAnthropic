---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# Invoke-AnthropicStandardTool

## SYNOPSIS
Executes a standard tool based on a tool_use response from the model.

## SYNTAX

```
Invoke-AnthropicStandardTool [-ToolUse] <Object> [-AllowWrite] [-AllowShell] [-AllowWeb] [-Unsafe]
 [[-InvokeMode] <String>] [[-TimeoutSeconds] <Int32>] [[-MaxOutputLength] <Int32>] [[-AllowedPaths] <String[]>]
 [-AllowAllPaths] [[-MaxFileSizeBytes] <Int32>] [[-MaxRecursionDepth] <Int32>]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Takes a tool_use object from the model's response and executes the corresponding
standard tool, returning the result as a string.

Shell commands (pwsh tool) are executed in an isolated, constrained runspace for security.
This prevents code injection, .NET type abuse, and restricts available commands to a
curated safe list.

## EXAMPLES

### EXAMPLE 1
```
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell
```

### EXAMPLE 2
```
# In a tool use loop with shell access
$toolUse = $response.content | Where-Object { $_.type -eq 'tool_use' }
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell
```

### EXAMPLE 3
```
# With user confirmation before each execution
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell -InvokeMode Confirm
```

### EXAMPLE 4
```
# Dry-run mode - see what would be executed without running it
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell -InvokeMode None
```

### EXAMPLE 5
```
# UNSAFE: No restrictions - for testing only!
$result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell -Unsafe
```

## PARAMETERS

### -ToolUse
The tool_use object from the model's response containing name and input.

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

### -AllowWrite
Allow write operations (create, str_replace, insert).
Default is $false for safety.

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

### -AllowShell
Allow shell command execution.
Default is $false for safety.

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

### -AllowWeb
Allow web fetch operations.
Default is $false for safety.

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

### -Unsafe
WARNING: Disables all sandboxing for shell commands, using Invoke-Expression directly.
Only use for testing in controlled environments where you trust all input.

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

### -InvokeMode
Controls how tool execution is handled:
- Auto: Execute tools automatically without prompting (default)
- Confirm: Prompt user for confirmation before each tool execution
- None: Do not execute tools, return description of what would be executed

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: Auto
Accept pipeline input: False
Accept wildcard characters: False
```

### -TimeoutSeconds
Maximum execution time for shell commands in seconds.
Default is 30.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: 30
Accept pipeline input: False
Accept wildcard characters: False
```

### -MaxOutputLength
Maximum length of output to return (default: 10000 characters).

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: 10000
Accept pipeline input: False
Accept wildcard characters: False
```

### -AllowedPaths
Array of allowed root directories for file operations.
Paths outside these
directories will be rejected.
Defaults to current directory for security.
Use -AllowAllPaths to disable path restrictions.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: @((Get-Location).Path)
Accept pipeline input: False
Accept wildcard characters: False
```

### -AllowAllPaths
Disables path restrictions, allowing file operations on any accessible path.
Use with caution - this allows the model to read/write files anywhere.

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

### -MaxFileSizeBytes
Maximum file size in bytes for read operations.
Default is 10MB.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: 10485760
Accept pipeline input: False
Accept wildcard characters: False
```

### -MaxRecursionDepth
Maximum directory recursion depth for search operations.
Default is 10.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 7
Default value: 10
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
Determines how the cmdlet responds to progress updates generated by a command. See the ProgressAction common parameter for more information.

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

### System.String
## NOTES

## RELATED LINKS

[https://github.com/christaylorcodes/PSAnthropic](https://github.com/christaylorcodes/PSAnthropic)

[https://christaylor.codes](https://christaylor.codes)