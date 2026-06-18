---
external help file: PSAnthropic-help.xml
Module Name: PSAnthropic
online version:
schema: 2.0.0
---

# New-AnthropicImageContent

## SYNOPSIS
Creates an image content block for the Anthropic Messages API.

## SYNTAX

### Path (Default)
```
New-AnthropicImageContent -Path <String> [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### Base64
```
New-AnthropicImageContent -Base64 <String> -MediaType <String> [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Creates a base64-encoded image content block that can be included in messages.
Ollama only supports base64 images (not URL-based).
Supported formats: JPEG, PNG, GIF, WebP

## EXAMPLES

### EXAMPLE 1
```
# From file path
$imageBlock = New-AnthropicImageContent -Path 'C:\images\screenshot.png'
```

### EXAMPLE 2
```
# From base64 string
$imageBlock = New-AnthropicImageContent -Base64 $encodedData -MediaType 'image/jpeg'
```

### EXAMPLE 3
```
# Use in a message with text
$response = Invoke-AnthropicMessage -Messages @(
    @{
        role = 'user'
        content = @(
            @{ type = 'text'; text = 'What is in this image?' }
            (New-AnthropicImageContent -Path './photo.jpg')
        )
    }
) -Model 'llava'
```

### EXAMPLE 4
```
# Batch process multiple images via pipeline
$imageBlocks = Get-ChildItem *.png | New-AnthropicImageContent
```

## PARAMETERS

### -Base64
Base64-encoded image data.
Must also specify -MediaType.

```yaml
Type: String
Parameter Sets: Base64
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -MediaType
The MIME type of the image (e.g., 'image/png').
Required when using -Base64.

```yaml
Type: String
Parameter Sets: Base64
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Path
Path to an image file.
The media type is auto-detected from the extension.
Supports pipeline input via FullName property (e.g., from Get-ChildItem).

```yaml
Type: String
Parameter Sets: Path
Aliases: FullName

Required: True
Position: Named
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
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

### System.Collections.Hashtable
## NOTES

## RELATED LINKS
