---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# Invoke-AnthropicMessage

## SYNOPSIS
Sends messages to the Anthropic Messages API (POST /v1/messages).

## SYNTAX

```
Invoke-AnthropicMessage [-Messages] <Object[]> [-Model <String>] [-MaxTokens <Int32>] [-System <String>]
 [-Temperature <Double>] [-TopP <Double>] [-TopK <Int32>] [-StopSequences <String[]>] [-Stream]
 [-Tools <Hashtable[]>] [-ToolChoice <Object>] [-Thinking] [-ThinkingBudget <Int32>] [-NumCtx <Int32>]
 [-TimeoutSec <Int32>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
The primary function for interacting with Ollama's Anthropic-compatible API.
Sends a conversation and returns the assistant's response.

## EXAMPLES

### EXAMPLE 1
```
$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'What is PowerShell?'
)
$response | Get-AnthropicResponseText
```

### EXAMPLE 2
```
# With system prompt
$response = Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Explain recursion'
) -System 'You are a programming tutor. Be concise.'
```

### EXAMPLE 3
```
# Streaming output
Invoke-AnthropicMessage -Messages @(
    New-AnthropicMessage -Role 'user' -Content 'Write a haiku'
) -Stream | ForEach-Object {
    if ($_.type -eq 'content_block_delta') {
        Write-Host $_.delta.text -NoNewline
    }
}
```

### EXAMPLE 4
```
# Pipeline input from conversation
$conversation.Messages | Invoke-AnthropicMessage
```

### EXAMPLE 5
```
# Pipeline with multiple messages
@(
    New-AnthropicMessage -Role 'user' -Content 'Hello'
    New-AnthropicMessage -Role 'assistant' -Content 'Hi there!'
    New-AnthropicMessage -Role 'user' -Content 'How are you?'
) | Invoke-AnthropicMessage
```

## PARAMETERS

### -Messages
Array of message hashtables or objects.
Each message should have 'role' and 'content' keys.
Use New-AnthropicMessage to create properly formatted messages.
Supports pipeline input - messages are accumulated before the API call is made.

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
The model to use.
Defaults to the model set in Connect-Anthropic.

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

### -MaxTokens
Maximum tokens to generate.
Defaults to 4096.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 4096
Accept pipeline input: False
Accept wildcard characters: False
```

### -System
System prompt to set context for the conversation.

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

### -Temperature
Sampling temperature (0.0-1.0).
Lower values are more deterministic.

```yaml
Type: Double
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -TopP
Nucleus sampling probability threshold.

```yaml
Type: Double
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -TopK
Sample from top K options for each token.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -StopSequences
Array of strings that will stop generation when encountered.

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

### -Stream
Enable streaming output.
Returns events as they arrive.

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

### -Tools
Array of tool definitions for function calling.

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

### -ToolChoice
How to handle tool selection ('auto', 'any', 'tool', or specific tool name).

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Thinking
Enable extended thinking mode.
The model will include its reasoning process.

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

### -ThinkingBudget
Maximum tokens for the thinking process (requires -Thinking).

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -NumCtx
Context window size (Ollama-specific).
Smaller values use less VRAM.
Common values: 2048, 4096, 8192, 16384, 32768.
Default is model-specific.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -TimeoutSec
Request timeout in seconds.
Defaults to 300.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 300
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

### System.Management.Automation.PSObject
## NOTES

## RELATED LINKS

[https://github.com/christaylorcodes/PSAnthropic](https://github.com/christaylorcodes/PSAnthropic)

[https://christaylor.codes](https://christaylor.codes)