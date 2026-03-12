function New-AnthropicToolFromCommand {
    <#
    .SYNOPSIS
        Auto-generates an Anthropic tool definition from a PowerShell command.
    .DESCRIPTION
        Uses PowerShell reflection to extract parameter metadata from a cmdlet or function
        and generates an Anthropic-compatible tool definition. This saves you from manually
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

    .PARAMETER CommandName
        The name of the PowerShell command to convert to a tool definition.
    .PARAMETER Description
        Override the tool description. If not provided, uses the command's Synopsis from Get-Help.
    .PARAMETER ParameterSetName
        Which parameter set to use when the command has multiple. Defaults to the default parameter set.
    .PARAMETER ExcludeParameter
        Parameter names to exclude from the tool definition (in addition to common parameters).
    .PARAMETER IncludeParameter
        If specified, only include these parameters (still excludes common parameters).
    .PARAMETER Strict
        Generate strict schema with additionalProperties: false. Recommended for Claude's strict mode.
    .PARAMETER IncludeExamples
        Include example values in the schema based on type and validation attributes.
    .EXAMPLE
        # Generate tool from a built-in cmdlet
        $tool = New-AnthropicToolFromCommand -CommandName 'Get-Process'

    .EXAMPLE
        # Generate tool with custom description
        $tool = New-AnthropicToolFromCommand -CommandName 'Get-ChildItem' -Description 'List files and folders'

    .EXAMPLE
        # Generate strict tool for Claude's strict mode
        $tool = New-AnthropicToolFromCommand -CommandName 'Get-Process' -Strict -IncludeExamples

    .EXAMPLE
        # Generate tool from a custom function
        function Get-Weather {
            param(
                [Parameter(Mandatory, HelpMessage = 'City or region name')]
                [string]$Location,

                [ValidateSet('celsius', 'fahrenheit')]
                [string]$Unit = 'celsius'
            )
            # Implementation...
        }
        $tool = New-AnthropicToolFromCommand -CommandName 'Get-Weather'

    .EXAMPLE
        # Register multiple functions as tools
        $tools = 'Get-Process', 'Get-Service', 'Get-Date' | ForEach-Object {
            New-AnthropicToolFromCommand -CommandName $_
        }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'Command')]
        [string]$CommandName,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$ParameterSetName,

        [Parameter()]
        [string[]]$ExcludeParameter,

        [Parameter()]
        [string[]]$IncludeParameter,

        [Parameter()]
        [switch]$Strict,

        [Parameter()]
        [switch]$IncludeExamples
    )

    process {
        # Get command info
        $commandInfo = Get-Command -Name $CommandName -ErrorAction Stop

        # Get help for descriptions
        $help = Get-Help -Name $CommandName -ErrorAction SilentlyContinue

        # Determine description - use explicit, then synopsis, then fallback
        $synopsis = $help.Synopsis
        # Synopsis often contains the command syntax as fallback - detect and skip that
        $isSyntax = $synopsis -and ($synopsis -match "^\s*$CommandName\s+\[" -or $synopsis -eq $CommandName)
        $toolDescription = if ($Description) { $Description }
                           elseif ($synopsis -and -not $isSyntax) { $synopsis.Trim() }
                           else { "Executes the $CommandName PowerShell command" }

        # Common parameters to always exclude
        $commonParams = @(
            'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
            'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable',
            'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm', 'ProgressAction'
        )

        # Determine which parameter set to use
        $parameterSet = if ($ParameterSetName) {
            $commandInfo.ParameterSets | Where-Object { $_.Name -eq $ParameterSetName }
        }
        elseif ($commandInfo.DefaultParameterSet) {
            $commandInfo.ParameterSets | Where-Object { $_.Name -eq $commandInfo.DefaultParameterSet }
        }
        else {
            $commandInfo.ParameterSets | Select-Object -First 1
        }

        if (-not $parameterSet) {
            throw "Parameter set '$ParameterSetName' not found for command '$CommandName'"
        }

        # Build parameter schema
        $properties = [ordered]@{}
        $required = [System.Collections.Generic.List[string]]::new()

        foreach ($param in $parameterSet.Parameters) {
            # Skip common parameters
            if ($param.Name -in $commonParams) { continue }

            # Skip explicitly excluded parameters
            if ($ExcludeParameter -and $param.Name -in $ExcludeParameter) { continue }

            # If IncludeParameter specified, only include those
            if ($IncludeParameter -and $param.Name -notin $IncludeParameter) { continue }

            # Build property definition with enhanced options
            $property = ConvertTo-JsonSchemaType -Parameter $param -HelpContent $help -IncludeExamples:$IncludeExamples

            $properties[$param.Name] = $property

            # Track required parameters
            if ($param.IsMandatory) {
                $required.Add($param.Name)
            }
        }

        # Build the tool definition
        $inputSchema = [ordered]@{
            type       = 'object'
            properties = $properties
        }

        if ($required.Count -gt 0) {
            $inputSchema.required = @($required)
        }

        # Strict mode: prevent additional properties (recommended for Claude)
        if ($Strict) {
            $inputSchema.additionalProperties = $false
        }

        # Return Anthropic tool format
        @{
            name         = $commandInfo.Name
            description  = $toolDescription
            input_schema = $inputSchema
        }
    }
}
