@{
    # Module manifest for PSAnthropic
    # PowerShell client for the Anthropic Messages API

    # Script module or binary module file associated with this manifest.
    RootModule = 'PSAnthropic.psm1'

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # This ensures classes/enums are available to module consumers.
    ScriptsToProcess = @('Classes.ps1')

    # Version number of this module.
    ModuleVersion = '0.1.0'

    # ID used to uniquely identify this module
    GUID = 'a7b8c9d0-e1f2-3a4b-5c6d-7e8f9a0b1c2d'

    # Author of this module
    Author = 'Chris Taylor'

    # Company or vendor of this module
    CompanyName = 'ChrisTaylorCodes'

    # Copyright statement for this module
    Copyright = '(c) 2026 Chris Taylor. MIT License.'

    # Description of the functionality provided by this module
    Description = 'PowerShell client for the Anthropic Messages API. Works with Ollama, Anthropic Cloud, and any compatible endpoint. Supports messages, streaming, tools, and images.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module - explicit list (no wildcards)
    FunctionsToExport = @(
        # Authentication
        'Connect-Anthropic'
        'Disconnect-Anthropic'

        # Invoke
        'Invoke-AnthropicWebRequest'
        'Invoke-AnthropicMessage'

        # Messages
        'New-AnthropicMessage'
        'New-AnthropicConversation'
        'Add-AnthropicMessage'

        # Tools
        'New-AnthropicTool'
        'New-AnthropicToolFromCommand'
        'New-AnthropicToolResult'
        'Get-AnthropicStandardTools'
        'Invoke-AnthropicStandardTool'

        # Content
        'New-AnthropicImageContent'

        # Utility
        'Get-AnthropicConnection'
        'Get-AnthropicModel'
        'Get-AnthropicResponseText'
        'Test-AnthropicEndpoint'
        'Clear-AnthropicRunspaceCache'

        # Router
        'Set-AnthropicRouterConfig'
        'Get-AnthropicRouterConfig'
        'Clear-AnthropicRouterConfig'
        'Invoke-AnthropicRouted'
        'Get-AnthropicRouterLog'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for discoverability
            Tags = @('Anthropic', 'Ollama', 'LLM', 'AI', 'API', 'Messages', 'Claude', 'LocalLLM')

            # License URI
            LicenseUri = 'https://github.com/christaylorcodes/PSAnthropic/blob/main/LICENSE'

            # Project URI
            ProjectUri = 'https://github.com/christaylorcodes/PSAnthropic'

            # Release notes
            ReleaseNotes = @'
## 0.1.0 - Initial Release
- Core messaging via POST /v1/messages
- Streaming support with SSE parsing
- Tool/function calling support
- Base64 image content support
- Conversation helpers
- Connection management following CWM patterns
'@
        }
    }
}
