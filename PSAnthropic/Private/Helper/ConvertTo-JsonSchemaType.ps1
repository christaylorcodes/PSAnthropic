function ConvertTo-JsonSchemaType {
    <#
    .SYNOPSIS
        Converts a PowerShell parameter to a JSON Schema property definition.
    .DESCRIPTION
        Enhanced conversion that extracts:
        - Type mapping to JSON Schema
        - Default values
        - Validation constraints (Set, Range, Pattern, Length, Count, NotNull, Script)
        - Descriptions from multiple sources (HelpMessage attribute, help content)
        - Parameter aliases
        - Example values (when requested)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Parameter,  # Can be CommandParameterInfo or ParameterMetadata

        [Parameter()]
        $HelpContent,

        [Parameter()]
        [switch]$IncludeExamples
    )

    $property = [ordered]@{}
    $paramType = $Parameter.ParameterType
    $typeName = $paramType.Name
    $constraints = [System.Collections.Generic.List[string]]::new()
    $aliases = @()
    $helpMessage = $null

    # Handle nullable types
    if ($paramType.IsGenericType -and
        $paramType.GetGenericTypeDefinition() -eq [Nullable`1]) {
        $typeName = $paramType.GenericTypeArguments[0].Name
    }

    # Map PowerShell types to JSON Schema types
    switch -Regex ($typeName) {
        '^String$' {
            $property.type = 'string'
        }
        '^(String\[\]|ArrayList|List`1)$' {
            $property.type = 'array'
            $property.items = @{ type = 'string' }
        }
        '^(Int32|Int64|Int16|Byte|UInt32|UInt64|UInt16)$' {
            $property.type = 'integer'
        }
        '^(Int32\[\]|Int64\[\])$' {
            $property.type = 'array'
            $property.items = @{ type = 'integer' }
        }
        '^(Double|Single|Decimal|Float)$' {
            $property.type = 'number'
        }
        '^(Boolean|SwitchParameter)$' {
            $property.type = 'boolean'
        }
        '^DateTime$' {
            $property.type = 'string'
            $property.format = 'date-time'
        }
        '^TimeSpan$' {
            $property.type = 'string'
            $property.format = 'duration'
        }
        '^Guid$' {
            $property.type = 'string'
            $property.format = 'uuid'
        }
        '^(FileInfo|DirectoryInfo)$' {
            $property.type = 'string'
            $constraints.Add('File or directory path')
        }
        '^Uri$' {
            $property.type = 'string'
            $property.format = 'uri'
        }
        '^IPAddress$' {
            $property.type = 'string'
            $property.format = 'ipv4'
        }
        '^MailAddress$' {
            $property.type = 'string'
            $property.format = 'email'
        }
        '^Hashtable$' {
            $property.type = 'object'
        }
        '^(PSCredential|SecureString)$' {
            $property.type = 'string'
            $constraints.Add('Sensitive credential value')
        }
        '^ScriptBlock$' {
            $property.type = 'string'
            $constraints.Add('PowerShell script block')
        }
        '^Object\[\]$' {
            $property.type = 'array'
        }
        default {
            # Check if it's an enum
            if ($paramType.IsEnum) {
                $property.type = 'string'
                $property.enum = @([Enum]::GetNames($paramType))
            }
            else {
                # Default to string for unknown types
                $property.type = 'string'
            }
        }
    }

    # Process all attributes for validation, aliases, and help
    foreach ($attr in $Parameter.Attributes) {
        switch ($attr.GetType().Name) {
            'ValidateSetAttribute' {
                $property.enum = @($attr.ValidValues)
                if ($IncludeExamples -and $attr.ValidValues.Count -gt 0) {
                    $property.examples = @($attr.ValidValues | Select-Object -First 3)
                }
            }
            'ValidateRangeAttribute' {
                if ($null -ne $attr.MinRange) {
                    $property.minimum = $attr.MinRange
                }
                if ($null -ne $attr.MaxRange) {
                    $property.maximum = $attr.MaxRange
                }
                if ($IncludeExamples -and $null -ne $attr.MinRange -and $null -ne $attr.MaxRange) {
                    $mid = [math]::Floor(($attr.MinRange + $attr.MaxRange) / 2)
                    $property.examples = @($attr.MinRange, $mid, $attr.MaxRange)
                }
            }
            'ValidatePatternAttribute' {
                $property.pattern = $attr.RegexPattern
            }
            'ValidateLengthAttribute' {
                if ($null -ne $attr.MinLength -and $attr.MinLength -gt 0) {
                    $property.minLength = $attr.MinLength
                }
                if ($null -ne $attr.MaxLength -and $attr.MaxLength -lt [int]::MaxValue) {
                    $property.maxLength = $attr.MaxLength
                }
            }
            'ValidateCountAttribute' {
                if ($property.type -eq 'array') {
                    if ($null -ne $attr.MinLength -and $attr.MinLength -gt 0) {
                        $property.minItems = $attr.MinLength
                    }
                    if ($null -ne $attr.MaxLength -and $attr.MaxLength -lt [int]::MaxValue) {
                        $property.maxItems = $attr.MaxLength
                    }
                }
            }
            'ValidateNotNullAttribute' {
                $constraints.Add('Cannot be null')
            }
            'ValidateNotNullOrEmptyAttribute' {
                $constraints.Add('Cannot be null or empty')
            }
            'ValidateScriptAttribute' {
                $constraints.Add('Must pass custom validation')
            }
            'AliasAttribute' {
                $aliases += $attr.AliasNames
            }
            'ParameterAttribute' {
                # Extract HelpMessage from Parameter attribute
                if ($attr.HelpMessage) {
                    $helpMessage = $attr.HelpMessage
                }
            }
        }
    }

    # Extract default value if available
    # Note: DefaultValue property exists on CommandParameterInfo from parameter sets
    if ($Parameter.PSObject.Properties.Name -contains 'DefaultValue' -and
        $null -ne $Parameter.DefaultValue -and
        $Parameter.DefaultValue -ne [System.DBNull]::Value) {
        $defaultVal = $Parameter.DefaultValue
        # Only include serializable defaults (not script blocks or complex objects)
        if ($defaultVal -is [string] -or $defaultVal -is [int] -or
            $defaultVal -is [bool] -or $defaultVal -is [double] -or
            $defaultVal.GetType().IsEnum) {
            $property.default = $defaultVal
        }
    }

    # Build description from multiple sources (priority order)
    $descParts = [System.Collections.Generic.List[string]]::new()

    # 1. HelpMessage attribute (highest priority for parameter-specific help)
    if ($helpMessage) {
        $descParts.Add($helpMessage)
    }

    # 2. Help documentation (avoid duplicating HelpMessage)
    if ($HelpContent -and $HelpContent.parameters -and $HelpContent.parameters.parameter) {
        $paramHelp = $HelpContent.parameters.parameter | Where-Object { $_.name -eq $Parameter.Name }
        if ($paramHelp -and $paramHelp.description) {
            $descText = ($paramHelp.description | ForEach-Object { $_.Text }) -join ' '
            $descText = $descText.Trim()
            if ($descText -and $descText -ne $helpMessage) {
                $descParts.Add($descText)
            }
        }
    }

    # 3. Add constraints
    if ($constraints.Count -gt 0) {
        $descParts.Add("($($constraints -join '; '))")
    }

    # 4. Add aliases if present
    if ($aliases.Count -gt 0) {
        $descParts.Add("[Alias: $($aliases -join ', ')]")
    }

    # Combine description parts
    if ($descParts.Count -gt 0) {
        $property.description = $descParts -join ' '
    }

    # Generate examples based on type heuristics if requested
    if ($IncludeExamples -and -not $property.Contains('examples')) {
        $examples = Get-TypeExamples -TypeName $typeName -ParameterName $Parameter.Name -Format ($property.format)
        if ($examples) {
            $property.examples = $examples
        }
    }

    return $property
}

function Get-TypeExamples {
    <#
    .SYNOPSIS
        Generates example values based on type and parameter name heuristics.
    #>
    [CmdletBinding()]
    param(
        [string]$TypeName,
        [string]$ParameterName,
        [string]$Format
    )

    # Format-based examples (use static values for reproducibility)
    if ($Format) {
        switch ($Format) {
            'date-time' { return @('2024-01-15T10:30:00Z', '2024-06-01T14:00:00Z') }
            'uri' { return @('https://example.com', 'https://api.example.com/v1') }
            'email' { return @('user@example.com') }
            'uuid' { return @('550e8400-e29b-41d4-a716-446655440000') }
            'ipv4' { return @('192.168.1.1', '10.0.0.1') }
            'duration' { return @('00:30:00', '01:00:00') }
        }
    }

    # Name-based heuristics
    $nameLower = $ParameterName.ToLower()
    switch -Regex ($nameLower) {
        'path|file|directory|folder' { return @('C:\Users\Example\file.txt', '/home/user/file.txt') }
        'name' { return @('example', 'my-item') }
        'id' { return @('12345', 'abc-123') }
        'count|limit|max|min' { return @(1, 10, 100) }
        'port' { return @(80, 443, 8080) }
        'host|server|computer' { return @('localhost', 'server01') }
        'url|uri|endpoint' { return @('https://example.com/api') }
        'email|mail' { return @('user@example.com') }
        'user|username' { return @('admin', 'user01') }
        'password|secret|key|token' { return @('***') }  # Placeholder for sensitive
        'timeout|interval|delay' { return @(30, 60, 300) }
    }

    # Type-based fallbacks
    switch ($TypeName) {
        'String' { return @('value', 'example') }
        'Int32' { return @(1, 10) }
        'Int64' { return @(1, 1000) }
        'Double' { return @(1.0, 3.14) }
        'Boolean' { return @($true, $false) }
    }

    return $null
}
