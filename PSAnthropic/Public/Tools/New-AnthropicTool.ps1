function New-AnthropicTool {
    <#
    .SYNOPSIS
        Creates a tool definition for the Anthropic Tools API.
    .DESCRIPTION
        Creates a properly structured tool definition hashtable that can be passed
        to Invoke-AnthropicMessage's -Tools parameter for function calling.
    .PARAMETER Name
        The name of the tool. Should be a valid identifier (letters, numbers, underscores).
    .PARAMETER Description
        A description of what the tool does. The model uses this to decide when to call it.
    .PARAMETER InputSchema
        A JSON Schema object defining the tool's parameters. Must be type 'object'.
    .EXAMPLE
        $tool = New-AnthropicTool -Name 'get_weather' -Description 'Get weather for a location' -InputSchema @{
            type = 'object'
            properties = @{
                location = @{ type = 'string'; description = 'City name' }
                unit = @{ type = 'string'; enum = @('celsius', 'fahrenheit') }
            }
            required = @('location')
        }
    .EXAMPLE
        # Simple tool with no parameters
        $tool = New-AnthropicTool -Name 'get_time' -Description 'Get current time' -InputSchema @{
            type = 'object'
            properties = @{}
        }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-zA-Z_][a-zA-Z0-9_]*$')]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [hashtable]$InputSchema
    )

    # Validate input schema has type 'object'
    if ($InputSchema.type -ne 'object') {
        Write-Warning "InputSchema should have type 'object'. Got: $($InputSchema.type)"
    }

    @{
        name         = $Name
        description  = $Description
        input_schema = $InputSchema
    }
}
