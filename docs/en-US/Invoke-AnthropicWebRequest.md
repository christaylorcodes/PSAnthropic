---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# Invoke-AnthropicWebRequest

## SYNOPSIS
Core HTTP handler for Anthropic API requests.

## SYNTAX

```
Invoke-AnthropicWebRequest [-Uri] <String> [[-Method] <String>] [[-Body] <Object>] [[-ContentType] <String>]
 [[-Headers] <Hashtable>] [[-TimeoutSec] <Int32>] [[-MaxRetry] <Int32>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Handles all HTTP communication with the Anthropic-compatible API.
Includes connection validation, header injection, error handling,
and retry logic for transient failures.

## EXAMPLES

### EXAMPLE 1
```
Invoke-AnthropicWebRequest -Uri 'http://localhost:11434/v1/messages' -Method POST -Body $body
```

## PARAMETERS

### -Body
The request body (will be converted to JSON if hashtable).

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ContentType
The content type.
Defaults to 'application/json'.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: Application/json
Accept pipeline input: False
Accept wildcard characters: False
```

### -Headers
Additional headers to include (merged with connection headers).

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: @{}
Accept pipeline input: False
Accept wildcard characters: False
```

### -MaxRetry
Maximum retry attempts for 5xx errors.
Defaults to 3.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 7
Default value: 3
Accept pipeline input: False
Accept wildcard characters: False
```

### -Method
The HTTP method (GET, POST, etc.).
Defaults to GET.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: GET
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

### -TimeoutSec
Request timeout in seconds.
Defaults to 300.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: 300
Accept pipeline input: False
Accept wildcard characters: False
```

### -Uri
The full URI to request.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### Microsoft.PowerShell.Commands.WebResponseObject
## NOTES

## RELATED LINKS
