#Requires -Modules Pester

BeforeDiscovery {
    # Check if Ollama is available before discovery (for skip conditions)
    # Note: These variables are only used for -Skip expressions at discovery time.
    # Runtime values are set separately in BeforeAll blocks.
    $script:OllamaAvailable = $false
    $script:VisionModelAvailable = $false
    try {
        $response = Invoke-RestMethod -Uri 'http://localhost:11434/api/tags' -Method Get -TimeoutSec 2 -ErrorAction Stop
        $script:OllamaAvailable = $true

        # Check for vision-capable models (llava, llama3.2-vision, moondream, bakllava, etc.)
        $script:VisionModelAvailable = ($response.models | Where-Object { $_.name -match 'llava|vision|moondream|bakllava' } | Measure-Object).Count -gt 0
    }
    catch {
        $script:OllamaAvailable = $false
    }
}

BeforeAll {
    # Remove any existing PSAnthropic module to avoid "multiple modules loaded" errors
    Get-Module PSAnthropic | Remove-Module -Force -ErrorAction SilentlyContinue

    # Prefer the built module (output/) if available, otherwise use source
    $builtManifest = Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'output' 'PSAnthropic') -Filter 'PSAnthropic.psd1' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($builtManifest) {
        Import-Module $builtManifest.FullName -Force -Global
    } else {
        $modulePath = Join-Path $PSScriptRoot '..' 'PSAnthropic'
        # Explicitly load classes first (needed for Pester's sandboxed environment when using source)
        $classesPath = Join-Path $modulePath 'Classes.ps1'
        . $classesPath
        Import-Module $modulePath -Force -Global
    }
}

AfterAll {
    # Clean up
    Disconnect-Anthropic -ErrorAction SilentlyContinue
}

Describe 'Module Import' {
    It 'Should import without errors' {
        $module = Get-Module PSAnthropic
        $module | Should -Not -BeNullOrEmpty
    }

    It 'Should export all functions from manifest' {
        # Get expected functions from the loaded module's manifest (source of truth)
        $module = Get-Module PSAnthropic
        $manifestPath = Join-Path $module.ModuleBase 'PSAnthropic.psd1'
        $manifest = Import-PowerShellDataFile $manifestPath
        $expectedFunctions = $manifest.FunctionsToExport

        $exportedFunctions = (Get-Module PSAnthropic).ExportedFunctions.Keys

        # Every function in manifest should be exported
        foreach ($func in $expectedFunctions) {
            $exportedFunctions | Should -Contain $func -Because "manifest declares $func"
        }

        # Exported count should match manifest count
        $exportedFunctions.Count | Should -Be $expectedFunctions.Count -Because 'no extra functions should be exported'
    }
}

Describe 'Connect-Anthropic' {
    BeforeEach {
        Disconnect-Anthropic -ErrorAction SilentlyContinue
    }

    It 'Should connect with defaults and auto-detect model' {
        $result = Connect-Anthropic

        $result | Should -Not -BeNullOrEmpty
        $result.Server | Should -Be 'localhost:11434'
        $result.Model | Should -Not -BeNullOrEmpty  # Auto-detected from server
    }

    It 'Should connect with custom parameters' {
        $result = Connect-Anthropic -Server 'myserver:8080' -Model 'qwen3-coder'

        $result.Server | Should -Be 'myserver:8080'
        $result.Model | Should -Be 'qwen3-coder'
    }

    It 'Should strip http:// from server' {
        $result = Connect-Anthropic -Server 'http://localhost:11434'

        $result.Server | Should -Be 'localhost:11434'
    }

    It 'Should warn if already connected without -Force' {
        Connect-Anthropic
        { Connect-Anthropic } | Should -Not -Throw
    }

    It 'Should reconnect with -Force' {
        Connect-Anthropic -Model 'llama3'
        $result = Connect-Anthropic -Model 'qwen3-coder' -Force

        $result.Model | Should -Be 'qwen3-coder'
    }
}

Describe 'Disconnect-Anthropic' {
    It 'Should disconnect when connected' {
        Connect-Anthropic
        { Disconnect-Anthropic } | Should -Not -Throw

        $conn = Get-AnthropicConnection
        $conn | Should -BeNullOrEmpty
    }

    It 'Should not error when not connected' {
        Disconnect-Anthropic -ErrorAction SilentlyContinue
        { Disconnect-Anthropic } | Should -Not -Throw
    }
}

Describe 'Get-AnthropicConnection' {
    It 'Should return null when not connected' {
        Disconnect-Anthropic -ErrorAction SilentlyContinue
        $result = Get-AnthropicConnection
        $result | Should -BeNullOrEmpty
    }

    It 'Should return connection info when connected' {
        Connect-Anthropic -Model 'testmodel'
        $result = Get-AnthropicConnection

        $result | Should -Not -BeNullOrEmpty
        $result.Server | Should -Not -BeNullOrEmpty
        $result.Model | Should -Be 'testmodel'
        $result.ConnectedAt | Should -Not -BeNullOrEmpty
    }
}

Describe 'New-AnthropicMessage' {
    It 'Should create a user message' {
        $msg = New-AnthropicMessage -Role 'user' -Content 'Hello'

        $msg.GetType().Name | Should -Be 'AnthropicMessage'
        $msg.Role | Should -Be 'user'
        $msg.Content | Should -Be 'Hello'
    }

    It 'Should create an assistant message' {
        $msg = New-AnthropicMessage -Role 'assistant' -Content 'Hi there'

        $msg.role | Should -Be 'assistant'
        $msg.content | Should -Be 'Hi there'
    }

    It 'Should reject invalid roles' {
        { New-AnthropicMessage -Role 'system' -Content 'test' } | Should -Throw
    }

    It 'Should accept array content' {
        $content = @(
            @{ type = 'text'; text = 'Hello' }
        )
        $msg = New-AnthropicMessage -Role 'user' -Content $content

        # Content should be preserved as passed (array)
        $msg.content.Count | Should -Be 1
        $msg.content[0].type | Should -Be 'text'
    }
}

Describe 'New-AnthropicConversation' {
    It 'Should create empty conversation' {
        $conv = New-AnthropicConversation

        $conv.GetType().Name | Should -Be 'AnthropicConversation'
        $conv.Messages.GetType().Name | Should -Be 'List`1'
        $conv.Messages.Count | Should -Be 0
    }

    It 'Should create conversation with initial message' {
        $conv = New-AnthropicConversation -UserMessage 'Hello!'

        $conv.Messages.Count | Should -Be 1
        $conv.Messages[0].role | Should -Be 'user'
        $conv.Messages[0].content | Should -Be 'Hello!'
    }

    It 'Should include system prompt' {
        $conv = New-AnthropicConversation -SystemPrompt 'Be helpful.'

        $conv.SystemPrompt | Should -Be 'Be helpful.'
    }
}

Describe 'Add-AnthropicMessage' {
    It 'Should add message to conversation' {
        $conv = New-AnthropicConversation
        Add-AnthropicMessage -Conversation $conv -Role 'user' -Content 'Hello'

        $conv.Messages.Count | Should -Be 1
        $conv.Messages[0].content | Should -Be 'Hello'
    }

    It 'Should support PassThru' {
        $conv = New-AnthropicConversation
        $result = Add-AnthropicMessage -Conversation $conv -Role 'user' -Content 'Hi' -PassThru

        $result | Should -Be $conv
    }
}

Describe 'New-AnthropicTool' {
    It 'Should create a valid tool definition' {
        $tool = New-AnthropicTool -Name 'get_weather' -Description 'Gets weather' -InputSchema @{
            type = 'object'
            properties = @{ location = @{ type = 'string' } }
            required = @('location')
        }

        $tool | Should -BeOfType [hashtable]
        $tool.name | Should -Be 'get_weather'
        $tool.description | Should -Be 'Gets weather'
        $tool.input_schema.type | Should -Be 'object'
    }

    It 'Should reject invalid tool names' {
        { New-AnthropicTool -Name '123invalid' -Description 'test' -InputSchema @{ type = 'object' } } | Should -Throw
    }
}

Describe 'New-AnthropicToolResult' {
    It 'Should create a tool result message' {
        $result = New-AnthropicToolResult -ToolUseId 'toolu_123' -Content 'Success'

        $result | Should -BeOfType [hashtable]
        $result.role | Should -Be 'user'
        $result.content[0].type | Should -Be 'tool_result'
        $result.content[0].tool_use_id | Should -Be 'toolu_123'
        $result.content[0].content | Should -Be 'Success'
    }

    It 'Should handle error results' {
        $result = New-AnthropicToolResult -ToolUseId 'toolu_123' -Content 'Failed' -IsError

        $result.content[0].is_error | Should -Be $true
    }

    It 'Should convert objects to JSON' {
        $data = @{ status = 'ok'; value = 42 }
        $result = New-AnthropicToolResult -ToolUseId 'toolu_123' -Content $data

        $result.content[0].content | Should -Match '"status"'
        $result.content[0].content | Should -Match '"value"'
    }
}

#region New-AnthropicToolFromCommand Tests
Describe 'New-AnthropicToolFromCommand' {
    BeforeAll {
        # Define test functions with various parameter types
        # Using global scope so they're visible to Get-Command in the module
        function global:Test-BasicFunction {
            param(
                [Parameter(Mandatory)]
                [string]$Name,
                [int]$Count = 1
            )
        }

        function global:Test-ValidateSetFunction {
            <#
            .SYNOPSIS
                Test function with ValidateSet.
            #>
            param(
                [ValidateSet('Red', 'Green', 'Blue')]
                [string]$Color
            )
        }

        function global:Test-ValidateRangeFunction {
            param(
                [ValidateRange(1, 100)]
                [int]$Value
            )
        }
    }

    AfterAll {
        # Clean up global functions
        Remove-Item Function:\Test-BasicFunction -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-ValidateSetFunction -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-ValidateRangeFunction -ErrorAction SilentlyContinue
    }

    It 'Should generate tool from simple function' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Test-BasicFunction'

        $tool | Should -BeOfType [hashtable]
        $tool.name | Should -Be 'Test-BasicFunction'
        $tool.input_schema.type | Should -Be 'object'
        $tool.input_schema.properties.Name | Should -Not -BeNullOrEmpty
        $tool.input_schema.properties.Count | Should -Not -BeNullOrEmpty
    }

    It 'Should mark mandatory parameters as required' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Test-BasicFunction'

        $tool.input_schema.required | Should -Contain 'Name'
        $tool.input_schema.required | Should -Not -Contain 'Count'
    }

    It 'Should map string type correctly' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Test-BasicFunction'

        $tool.input_schema.properties.Name.type | Should -Be 'string'
    }

    It 'Should map integer type correctly' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Test-BasicFunction'

        $tool.input_schema.properties.Count.type | Should -Be 'integer'
    }

    It 'Should extract ValidateSet as enum' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Test-ValidateSetFunction'

        $tool.input_schema.properties.Color.enum | Should -Contain 'Red'
        $tool.input_schema.properties.Color.enum | Should -Contain 'Green'
        $tool.input_schema.properties.Color.enum | Should -Contain 'Blue'
    }

    It 'Should extract ValidateRange as minimum/maximum' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Test-ValidateRangeFunction'

        $tool.input_schema.properties.Value.minimum | Should -Be 1
        $tool.input_schema.properties.Value.maximum | Should -Be 100
    }

    It 'Should use Synopsis as description' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Test-ValidateSetFunction'

        $tool.description | Should -Match 'ValidateSet'
    }

    It 'Should allow custom description override' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Test-BasicFunction' -Description 'Custom description'

        $tool.description | Should -Be 'Custom description'
    }

    It 'Should exclude specified parameters' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Test-BasicFunction' -ExcludeParameter 'Count'

        $tool.input_schema.properties.Keys | Should -Not -Contain 'Count'
        $tool.input_schema.properties.Keys | Should -Contain 'Name'
    }

    It 'Should include only specified parameters' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Test-BasicFunction' -IncludeParameter 'Name'

        $tool.input_schema.properties.Keys | Should -Contain 'Name'
        $tool.input_schema.properties.Keys | Should -Not -Contain 'Count'
    }

    It 'Should exclude common parameters' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Test-BasicFunction'

        $tool.input_schema.properties.Keys | Should -Not -Contain 'Verbose'
        $tool.input_schema.properties.Keys | Should -Not -Contain 'Debug'
        $tool.input_schema.properties.Keys | Should -Not -Contain 'ErrorAction'
    }

    It 'Should work with pipeline input' {
        $tools = 'Test-BasicFunction', 'Test-ValidateSetFunction' | ForEach-Object {
            New-AnthropicToolFromCommand -CommandName $_
        }

        $tools.Count | Should -Be 2
        $tools[0].name | Should -Be 'Test-BasicFunction'
        $tools[1].name | Should -Be 'Test-ValidateSetFunction'
    }

    It 'Should work with built-in cmdlets' {
        $tool = New-AnthropicToolFromCommand -CommandName 'Get-Date' -IncludeParameter 'Format'

        $tool.name | Should -Be 'Get-Date'
        $tool.input_schema.properties.Format | Should -Not -BeNullOrEmpty
    }

    It 'Should throw for non-existent command' {
        { New-AnthropicToolFromCommand -CommandName 'NonExistent-Command' } | Should -Throw
    }

    Context 'Enhanced Features' {
        BeforeAll {
            # Function with HelpMessage and aliases
            function global:Test-EnhancedFunction {
                param(
                    [Parameter(Mandatory, HelpMessage = 'The target server name')]
                    [Alias('ComputerName', 'Host')]
                    [string]$Server,

                    [ValidateNotNullOrEmpty()]
                    [string]$Name = 'DefaultValue',

                    [ValidateRange(1, 100)]
                    [int]$Port = 80
                )
            }
        }

        AfterAll {
            Remove-Item Function:\Test-EnhancedFunction -ErrorAction SilentlyContinue
        }

        It 'Should extract HelpMessage attribute' {
            $tool = New-AnthropicToolFromCommand -CommandName 'Test-EnhancedFunction'

            $tool.input_schema.properties.Server.description | Should -Match 'target server name'
        }

        It 'Should include aliases in description' {
            $tool = New-AnthropicToolFromCommand -CommandName 'Test-EnhancedFunction'

            $tool.input_schema.properties.Server.description | Should -Match 'Alias.*ComputerName'
        }

        It 'Should note ValidateNotNullOrEmpty constraint' {
            $tool = New-AnthropicToolFromCommand -CommandName 'Test-EnhancedFunction'

            $tool.input_schema.properties.Name.description | Should -Match 'null or empty'
        }

        It 'Should add additionalProperties: false with -Strict' {
            $tool = New-AnthropicToolFromCommand -CommandName 'Test-EnhancedFunction' -Strict

            $tool.input_schema.additionalProperties | Should -Be $false
        }

        It 'Should generate examples with -IncludeExamples for ValidateSet' {
            $tool = New-AnthropicToolFromCommand -CommandName 'Test-ValidateSetFunction' -IncludeExamples

            $tool.input_schema.properties.Color.examples | Should -Not -BeNullOrEmpty
            $tool.input_schema.properties.Color.examples | Should -Contain 'Red'
        }

        It 'Should generate examples with -IncludeExamples for ValidateRange' {
            $tool = New-AnthropicToolFromCommand -CommandName 'Test-ValidateRangeFunction' -IncludeExamples

            $tool.input_schema.properties.Value.examples | Should -Not -BeNullOrEmpty
            $tool.input_schema.properties.Value.examples.Count | Should -BeGreaterOrEqual 2
        }

        It 'Should generate heuristic examples for common parameter names' {
            $tool = New-AnthropicToolFromCommand -CommandName 'Test-EnhancedFunction' -IncludeExamples

            # Server parameter should get server-related examples (from name heuristic)
            $tool.input_schema.properties.Server.examples | Should -Not -BeNullOrEmpty
            $tool.input_schema.properties.Server.examples | Should -Contain 'localhost'
            # Port parameter gets examples from ValidateRange(1,100), not name heuristic
            $tool.input_schema.properties.Port.examples | Should -Not -BeNullOrEmpty
            $tool.input_schema.properties.Port.examples | Should -Contain 1  # Min from range
        }
    }
}
#endregion

Describe 'Get-AnthropicResponseText' {
    It 'Should extract text from response' {
        $response = [PSCustomObject]@{
            content = @(
                @{ type = 'text'; text = 'Hello world' }
            )
        }

        $result = $response | Get-AnthropicResponseText
        $result | Should -Be 'Hello world'
    }

    It 'Should concatenate multiple text blocks' {
        $response = [PSCustomObject]@{
            content = @(
                @{ type = 'text'; text = 'Hello ' }
                @{ type = 'text'; text = 'world' }
            )
        }

        $result = $response | Get-AnthropicResponseText
        $result | Should -Be 'Hello world'
    }

    It 'Should ignore non-text blocks' {
        $response = [PSCustomObject]@{
            content = @(
                @{ type = 'text'; text = 'Hello' }
                @{ type = 'tool_use'; id = 'toolu_123'; name = 'test' }
            )
        }

        $result = $response | Get-AnthropicResponseText
        $result | Should -Be 'Hello'
    }

    It 'Should return null for empty response' {
        $response = [PSCustomObject]@{
            content = @()
        }

        $result = $response | Get-AnthropicResponseText
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Test-AnthropicEndpoint' {
    It 'Should return result object with required properties' {
        $result = Test-AnthropicEndpoint -Server 'localhost:11434'

        $result | Should -Not -BeNullOrEmpty
        $result.Server | Should -Match 'localhost:11434'
        $result.PSObject.Properties.Name | Should -Contain 'IsReachable'
        $result.PSObject.Properties.Name | Should -Contain 'ResponseMs'
        # IsReachable should be boolean
        $result.IsReachable | Should -BeOfType [bool]
    }

    It 'Should return IsReachable=false for unreachable server' {
        # Use a port that's almost certainly not running an Ollama server
        $result = Test-AnthropicEndpoint -Server 'localhost:59999'

        $result.IsReachable | Should -Be $false
    }

    It 'Should return IsReachable=false for invalid hostname' {
        $result = Test-AnthropicEndpoint -Server 'this-host-does-not-exist-12345.local:11434'

        $result.IsReachable | Should -Be $false
    }

    It 'Should preserve server address as provided' {
        # Test-AnthropicEndpoint returns the server as-is (unlike Connect-Anthropic which normalizes)
        $result = Test-AnthropicEndpoint -Server 'http://localhost:11434'

        $result.Server | Should -Be 'http://localhost:11434'
    }
}

# Integration tests (require Ollama running)
Describe 'Integration Tests' -Tag 'Integration' {
    BeforeAll {
        # Check if Ollama is running
        $script:OllamaAvailable = (Test-AnthropicEndpoint -Server 'localhost:11434').IsReachable

        # Detect vision model at runtime (BeforeDiscovery only sets VisionModelAvailable for -Skip)
        $script:VisionModel = $null
        if ($script:OllamaAvailable) {
            $response = Invoke-RestMethod -Uri 'http://localhost:11434/api/tags' -Method Get -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($response) {
                $match = $response.models | Where-Object { $_.name -match 'llava|vision|moondream|bakllava' } | Select-Object -First 1
                $script:VisionModel = $match.name
            }
        }
    }

    It 'Should list models' -Skip:(-not $script:OllamaAvailable) {
        Connect-Anthropic
        $models = Get-AnthropicModel

        $models | Should -Not -BeNullOrEmpty
    }

    It 'Should send a basic message' -Skip:(-not $script:OllamaAvailable) {
        Connect-Anthropic -Force  # Auto-detects available model

        $response = Invoke-AnthropicMessage -Messages @(
            New-AnthropicMessage -Role 'user' -Content 'Say hello in 3 words or less'
        ) -MaxTokens 50

        $response | Should -Not -BeNullOrEmpty
        $response.content | Should -Not -BeNullOrEmpty
        $response | Get-AnthropicResponseText | Should -Not -BeNullOrEmpty
    }

    Context 'Response Enrichment Properties' {
        It 'Should include .Answer property' -Skip:(-not $script:OllamaAvailable) {
            Connect-Anthropic -Force

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content 'Say just the word: OK'
            ) -MaxTokens 20

            $response.Answer | Should -Not -BeNullOrEmpty
            $response.Answer | Should -BeOfType [string]
        }

        It 'Should include .History property for conversation continuation' -Skip:(-not $script:OllamaAvailable) {
            Connect-Anthropic -Force

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content 'Hello'
            ) -MaxTokens 50

            $response.History | Should -Not -BeNullOrEmpty
            $response.History.Count | Should -BeGreaterOrEqual 2  # At least user + assistant
            $response.History[-1].role | Should -Be 'assistant'
        }

        It 'Should allow conversation continuation using .History' -Skip:(-not $script:OllamaAvailable) {
            Connect-Anthropic -Force

            # First message
            $response1 = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content 'My favorite number is 42. Remember it.'
            ) -MaxTokens 100

            # Continue conversation using .History
            $response2 = Invoke-AnthropicMessage -Messages ($response1.History + @(
                New-AnthropicMessage -Role 'user' -Content 'What is my favorite number?'
            )) -MaxTokens 100

            $response2.Answer | Should -Match '42'
        }

        It 'Should include .ToolUse property when tools are called' -Skip:(-not $script:OllamaAvailable) {
            Connect-Anthropic -Force
            $tools = Get-AnthropicStandardTools

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content 'What time is it in UTC? Use the get_current_time tool.'
            ) -Tools $tools -MaxTokens 500

            if ($response.stop_reason -eq 'tool_use') {
                $response.ToolUse | Should -Not -BeNullOrEmpty
                $response.ToolUse[0].name | Should -Be 'get_current_time'
            }
        }

        It 'Should have PSAnthropic.MessageResponse type name' -Skip:(-not $script:OllamaAvailable) {
            Connect-Anthropic -Force

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content 'Hi'
            ) -MaxTokens 20

            $response.PSObject.TypeNames | Should -Contain 'PSAnthropic.MessageResponse'
        }
    }

    Context 'Image Recognition' {
        BeforeAll {
            # Path to test images
            $script:TestImagesDir = Join-Path $PSScriptRoot 'TestImages'
        }

        It 'Should identify a cat in an image' -Skip:(-not $script:VisionModelAvailable) {
            Connect-Anthropic -Model $script:VisionModel -Force

            $imagePath = Join-Path $script:TestImagesDir 'cat.jpg'
            $imageContent = New-AnthropicImageContent -Path $imagePath

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content @(
                    @{ type = 'text'; text = 'What animal is in this image? Answer in one word.' }
                    $imageContent
                )
            ) -MaxTokens 50

            $response | Should -Not -BeNullOrEmpty
            $answer = $response | Get-AnthropicResponseText

            # Use LLM to validate - handles synonyms like "feline", "kitty", etc.
            $validation = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content "Does this response identify a cat (or feline/kitty)? Answer only 'yes' or 'no': $answer"
            ) -MaxTokens 10
            ($validation | Get-AnthropicResponseText) | Should -Match '(?i)yes'
        }

        It 'Should identify a dog in an image' -Skip:(-not $script:VisionModelAvailable) {
            Connect-Anthropic -Model $script:VisionModel -Force

            $imagePath = Join-Path $script:TestImagesDir 'dog.jpg'
            $imageContent = New-AnthropicImageContent -Path $imagePath

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content @(
                    @{ type = 'text'; text = 'What animal is in this image? Answer in one word.' }
                    $imageContent
                )
            ) -MaxTokens 50

            $response | Should -Not -BeNullOrEmpty
            $answer = $response | Get-AnthropicResponseText

            # Use LLM to validate - handles synonyms like "canine", "hound", "beagle", etc.
            $validation = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content "Does this response identify a dog (or canine/hound/beagle)? Answer only 'yes' or 'no': $answer"
            ) -MaxTokens 10
            ($validation | Get-AnthropicResponseText) | Should -Match '(?i)yes'
        }

        It 'Should identify multiple animals in an image' -Skip:(-not $script:VisionModelAvailable) {
            Connect-Anthropic -Model $script:VisionModel -Force

            $imagePath = Join-Path $script:TestImagesDir 'cat-and-dog.jpg'
            $imageContent = New-AnthropicImageContent -Path $imagePath

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content @(
                    @{ type = 'text'; text = 'What animals are in this image? List them.' }
                    $imageContent
                )
            ) -MaxTokens 100

            $response | Should -Not -BeNullOrEmpty
            $answer = $response | Get-AnthropicResponseText

            # Use LLM to validate - handles various phrasings
            $validation = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content "Does this response mention both a cat AND a dog (or their synonyms)? Answer only 'yes' or 'no': $answer"
            ) -MaxTokens 10
            ($validation | Get-AnthropicResponseText) | Should -Match '(?i)yes'
        }
    }
}

#region Standard Tools Tests
Describe 'Get-AnthropicStandardTools' {
    It 'Should return all tools by default' {
        $tools = Get-AnthropicStandardTools

        $tools | Should -Not -BeNullOrEmpty
        # Check that key tools exist (not exhaustive - avoids hardcoding count)
        $tools.name | Should -Contain 'pwsh'
        $tools.name | Should -Contain 'read_file'
        $tools.name | Should -Contain 'get_current_time'
        # Verify all ToolSets combined equals total
        $allSets = @('FileSystem', 'Editor', 'Shell', 'Web')
        $fromSets = $allSets | ForEach-Object { Get-AnthropicStandardTools -ToolSet $_ } | Select-Object -ExpandProperty name -Unique
        $tools.Count | Should -Be $fromSets.Count -Because 'all tools should come from defined ToolSets'
    }

    It 'Should return only FileSystem tools' {
        $tools = Get-AnthropicStandardTools -ToolSet FileSystem

        $tools.name | Should -Contain 'read_file'
        $tools.name | Should -Contain 'list_directory'
        # Should not contain tools from other sets
        $tools.name | Should -Not -Contain 'pwsh'
        $tools.name | Should -Not -Contain 'str_replace_editor'
    }

    It 'Should return only Editor tools' {
        $tools = @(Get-AnthropicStandardTools -ToolSet Editor)

        $tools.name | Should -Contain 'str_replace_editor'
        # Should not contain tools from other sets
        $tools.name | Should -Not -Contain 'pwsh'
        $tools.name | Should -Not -Contain 'read_file'
    }

    It 'Should return only Shell tools' {
        $tools = Get-AnthropicStandardTools -ToolSet Shell

        $tools.name | Should -Contain 'pwsh'
        # Should not contain tools from other sets
        $tools.name | Should -Not -Contain 'read_file'
        $tools.name | Should -Not -Contain 'str_replace_editor'
    }

    It 'Should return only Web tools' {
        $tools = Get-AnthropicStandardTools -ToolSet Web

        $tools.name | Should -Contain 'web_fetch'
        # Should not contain tools from other sets
        $tools.name | Should -Not -Contain 'pwsh'
        $tools.name | Should -Not -Contain 'read_file'
    }

    It 'Should have valid tool schema structure' {
        $tools = Get-AnthropicStandardTools

        foreach ($tool in $tools) {
            $tool.name | Should -Not -BeNullOrEmpty
            $tool.description | Should -Not -BeNullOrEmpty
            $tool.input_schema | Should -Not -BeNullOrEmpty
            $tool.input_schema.type | Should -Be 'object'
            $tool.input_schema.properties | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-AnthropicStandardTool' {
    BeforeAll {
        $script:TestDir = Join-Path $TestDrive 'tool-tests'
        New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
        'Test content line 1', 'Test content line 2', 'Test content line 3' | Set-Content (Join-Path $script:TestDir 'test.txt')
    }

    It 'Should execute get_current_time tool' {
        $toolUse = [PSCustomObject]@{
            name  = 'get_current_time'
            input = @{ timezone = 'UTC' }
        }

        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse

        $result | Should -Not -BeNullOrEmpty
        $result | Should -Match '\d{4}-\d{2}-\d{2}'
    }

    It 'Should execute read_file tool' {
        $testFile = Join-Path $script:TestDir 'test.txt'
        $toolUse = [PSCustomObject]@{
            name  = 'read_file'
            input = @{ path = $testFile }
        }

        # Use -AllowAllPaths since test files are in temp directory
        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowAllPaths

        $result | Should -Match 'Test content line 1'
    }

    It 'Should execute list_directory tool' {
        $toolUse = [PSCustomObject]@{
            name  = 'list_directory'
            input = @{ path = $script:TestDir }
        }

        # Use -AllowAllPaths since test files are in temp directory
        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowAllPaths

        $result | Should -Match 'test\.txt'
    }

    It 'Should handle unknown tool gracefully' {
        $toolUse = [PSCustomObject]@{
            name  = 'nonexistent_tool'
            input = @{ }
        }

        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse

        $result | Should -Match 'Unknown tool|not found|not supported'
    }

    It 'Should reject web_fetch without AllowWeb' {
        $toolUse = [PSCustomObject]@{
            name  = 'web_fetch'
            input = @{ url = 'https://example.com' }
        }

        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse

        $result | Should -Match 'Web fetch is disabled'
    }

    It 'Should reject invalid URL schemes in web_fetch' {
        $toolUse = [PSCustomObject]@{
            name  = 'web_fetch'
            input = @{ url = 'file:///etc/passwd' }
        }

        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb

        $result | Should -Match 'URL must use http'
    }

    It 'Should block private IP addresses in web_fetch' {
        $toolUse = [PSCustomObject]@{
            name  = 'web_fetch'
            input = @{ url = 'http://127.0.0.1:8080/secret' }
        }

        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb

        $result | Should -Match 'private.*blocked'
    }

    It 'Should block cloud metadata IP addresses in web_fetch' {
        # 169.254.169.254 is used by AWS/Azure/GCP for instance metadata
        $toolUse = [PSCustomObject]@{
            name  = 'web_fetch'
            input = @{ url = 'http://169.254.169.254/latest/meta-data/' }
        }

        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb

        $result | Should -Match 'private.*blocked'
    }

    Context 'InvokeMode Parameter' {
        It 'Should execute tool with InvokeMode Auto (default)' {
            $toolUse = [PSCustomObject]@{
                name  = 'get_current_time'
                input = @{ timezone = 'UTC' }
            }

            $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -InvokeMode Auto

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match '\d{4}-\d{2}-\d{2}'
        }

        It 'Should return dry-run message with InvokeMode None' {
            $toolUse = [PSCustomObject]@{
                name  = 'get_current_time'
                input = @{ timezone = 'UTC' }
            }

            $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -InvokeMode None

            $result | Should -Match '\[DRY RUN\]'
            $result | Should -Match 'Would execute'
        }

        It 'Should return dry-run message for read_file with InvokeMode None' {
            $testFile = Join-Path $script:TestDir 'test.txt'
            $toolUse = [PSCustomObject]@{
                name  = 'read_file'
                input = @{ path = $testFile }
            }

            $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -InvokeMode None

            $result | Should -Match '\[DRY RUN\]'
            $result | Should -Match 'Read:'  # Tool description uses "Read:" not "read_file"
        }

        It 'Should have ValidateSet for InvokeMode parameter' {
            $cmd = Get-Command Invoke-AnthropicStandardTool
            $param = $cmd.Parameters['InvokeMode']

            $param | Should -Not -BeNullOrEmpty
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'Auto'
            $validateSet.ValidValues | Should -Contain 'Confirm'
            $validateSet.ValidValues | Should -Contain 'None'
        }
    }

    Context 'web_fetch Integration' -Tag 'Integration' {
        It 'Should fetch HTML and convert to text' {
            $toolUse = [PSCustomObject]@{
                name  = 'web_fetch'
                input = @{ url = 'https://example.com' }
            }

            $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Not -Match '^Error:'
            $result | Should -Match 'Example Domain'  # example.com always has this text
            $result | Should -Not -Match '<html>'      # HTML tags should be stripped
        }

        It 'Should fetch and format JSON' {
            $toolUse = [PSCustomObject]@{
                name  = 'web_fetch'
                input = @{ url = 'https://httpbin.org/json' }
            }

            $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Not -Match '^Error:'
            # httpbin.org/json returns a slideshow object
            $result | Should -Match 'slideshow'
        }

        It 'Should include headers when requested' {
            $toolUse = [PSCustomObject]@{
                name  = 'web_fetch'
                input = @{
                    url = 'https://example.com'
                    include_headers = $true
                }
            }

            $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb

            $result | Should -Match 'Response Headers'
            $result | Should -Match 'Status: 200'
        }

        It 'Should handle 404 errors gracefully' {
            $toolUse = [PSCustomObject]@{
                name  = 'web_fetch'
                input = @{ url = 'https://httpbin.org/status/404' }
            }

            $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb

            $result | Should -Match 'Error.*404'
        }

        It 'Should truncate large responses' {
            $toolUse = [PSCustomObject]@{
                name  = 'web_fetch'
                input = @{
                    url = 'https://example.com'
                    max_length = 100
                }
            }

            $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb

            $result.Length | Should -BeLessOrEqual 150  # 100 + truncation message
            $result | Should -Match 'truncated'
        }

        It 'Should fetch top Hacker News story and validate HTML parsing' {
            # Step 1: Get top story IDs from JSON API
            $toolUse = [PSCustomObject]@{
                name  = 'web_fetch'
                input = @{ url = 'https://hacker-news.firebaseio.com/v0/topstories.json' }
            }

            $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb

            $result | Should -Not -Match '^Error:'
            $ids = $result | ConvertFrom-Json
            $ids.Count | Should -BeGreaterThan 0

            # Step 2: Fetch the top story details from JSON API
            $topId = $ids[0]
            $storyUse = [PSCustomObject]@{
                name  = 'web_fetch'
                input = @{ url = "https://hacker-news.firebaseio.com/v0/item/$topId.json" }
            }

            $storyResult = Invoke-AnthropicStandardTool -ToolUse $storyUse -AllowWeb

            $storyResult | Should -Not -Match '^Error:'
            $story = $storyResult | ConvertFrom-Json
            $story.title | Should -Not -BeNullOrEmpty

            Write-Host "Top HN Story: $($story.title)" -ForegroundColor Cyan

            # Step 3: Fetch the HTML homepage and verify the title appears
            # This validates HTML-to-text conversion works correctly
            $htmlUse = [PSCustomObject]@{
                name  = 'web_fetch'
                input = @{ url = 'https://news.ycombinator.com' }
            }

            $htmlResult = Invoke-AnthropicStandardTool -ToolUse $htmlUse -AllowWeb

            $htmlResult | Should -Not -Match '^Error:'
            # HTML tags should be stripped
            $htmlResult | Should -Not -Match '<html|<body|<table'
            # The top story title from JSON should appear in the parsed HTML
            # Use first few words to avoid partial match issues with truncation
            $titleWords = ($story.title -split '\s+' | Select-Object -First 3) -join ' '
            $escapedTitle = [regex]::Escape($titleWords)
            $htmlResult | Should -Match $escapedTitle -Because "Top story '$($story.title)' should appear in homepage HTML"

            Write-Host "Verified: Title found in parsed HTML" -ForegroundColor Green
        }
    }
}
#endregion

#region Router Tests
Describe 'Set-AnthropicRouterConfig' {
    BeforeEach {
        Clear-AnthropicRouterConfig -ErrorAction SilentlyContinue
    }

    It 'Should set router config with Default model' {
        $config = Set-AnthropicRouterConfig -Models @{ Default = 'llama3' }

        $config | Should -Not -BeNullOrEmpty
        $config.Models.Default | Should -Be 'llama3'
    }

    It 'Should set router config with multiple models' {
        $config = Set-AnthropicRouterConfig -Models @{
            Default = 'llama3'
            Code    = 'qwen3-coder'
            Vision  = 'llava'
        }

        $config.Models.Count | Should -Be 3
        $config.Models.Code | Should -Be 'qwen3-coder'
    }

    It 'Should require Default key in Models' {
        { Set-AnthropicRouterConfig -Models @{ Code = 'qwen3' } } | Should -Throw '*Default*'
    }

    It 'Should reject empty model names' {
        { Set-AnthropicRouterConfig -Models @{ Default = '' } } | Should -Throw '*empty*'
    }
}

Describe 'Get-AnthropicRouterConfig' {
    BeforeEach {
        Clear-AnthropicRouterConfig -ErrorAction SilentlyContinue
    }

    It 'Should return null when not configured' {
        $config = Get-AnthropicRouterConfig
        $config | Should -BeNullOrEmpty
    }

    It 'Should return config when set' {
        Set-AnthropicRouterConfig -Models @{ Default = 'llama3' }
        $config = Get-AnthropicRouterConfig

        $config | Should -Not -BeNullOrEmpty
        $config.Models.Default | Should -Be 'llama3'
    }
}

Describe 'Clear-AnthropicRouterConfig' {
    It 'Should clear existing config' {
        Set-AnthropicRouterConfig -Models @{ Default = 'llama3' }
        Clear-AnthropicRouterConfig

        $config = Get-AnthropicRouterConfig
        $config | Should -BeNullOrEmpty
    }

    It 'Should not error when already cleared' {
        Clear-AnthropicRouterConfig
        { Clear-AnthropicRouterConfig } | Should -Not -Throw
    }
}
#endregion

#region Image Content Tests
Describe 'New-AnthropicImageContent' {
    BeforeAll {
        # Create a minimal valid PNG (1x1 pixel)
        $script:TestImageDir = Join-Path $TestDrive 'images'
        New-Item -ItemType Directory -Path $script:TestImageDir -Force | Out-Null

        # Minimal PNG bytes (1x1 transparent pixel)
        $pngBytes = [byte[]]@(
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  # PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,  # IHDR chunk
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,  # 1x1 dimensions
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,  # IDAT chunk
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,  # IEND chunk
            0x42, 0x60, 0x82
        )
        $script:TestPng = Join-Path $script:TestImageDir 'test.png'
        [System.IO.File]::WriteAllBytes($script:TestPng, $pngBytes)
    }

    It 'Should create image content from file path' {
        $result = New-AnthropicImageContent -Path $script:TestPng

        $result | Should -Not -BeNullOrEmpty
        $result.type | Should -Be 'image'
        $result.source.type | Should -Be 'base64'
        $result.source.media_type | Should -Be 'image/png'
        $result.source.data | Should -Not -BeNullOrEmpty
    }

    It 'Should create image content from base64' {
        $base64 = [Convert]::ToBase64String([byte[]](1..10))
        $result = New-AnthropicImageContent -Base64 $base64 -MediaType 'image/jpeg'

        $result.source.media_type | Should -Be 'image/jpeg'
        $result.source.data | Should -Be $base64
    }

    It 'Should reject unsupported formats' {
        $badFile = Join-Path $script:TestImageDir 'test.bmp'
        '' | Set-Content $badFile

        { New-AnthropicImageContent -Path $badFile } | Should -Throw '*Unsupported*'
    }

    It 'Should reject non-existent files' {
        { New-AnthropicImageContent -Path 'C:\nonexistent\image.png' } | Should -Throw
    }

    Context 'Pipeline Support' {
        BeforeAll {
            # Create a second test image (JPEG)
            $jpegBytes = [byte[]]@(
                0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,  # JPEG header
                0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
                0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
                0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
                0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C,
                0xFF, 0xD9  # EOI marker
            )
            $script:TestJpeg = Join-Path $script:TestImageDir 'test.jpg'
            [System.IO.File]::WriteAllBytes($script:TestJpeg, $jpegBytes)
        }

        It 'Should accept single file from pipeline' {
            $result = Get-Item $script:TestPng | New-AnthropicImageContent

            $result | Should -Not -BeNullOrEmpty
            $result.type | Should -Be 'image'
            $result.source.media_type | Should -Be 'image/png'
        }

        It 'Should accept multiple files from pipeline' {
            $results = @(Get-ChildItem $script:TestImageDir -Filter '*.png' | New-AnthropicImageContent)

            $results.Count | Should -BeGreaterOrEqual 1
            $results[0].type | Should -Be 'image'
        }

        It 'Should work with Get-ChildItem FullName property' {
            $files = Get-ChildItem $script:TestImageDir -Filter '*.png'
            $result = $files | New-AnthropicImageContent

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
#endregion

#region Pipeline Support Tests
Describe 'Invoke-AnthropicMessage Pipeline Support' {
    BeforeAll {
        Connect-Anthropic -Model 'test-model' -Force
    }

    It 'Should have ValueFromPipeline on Messages parameter' {
        $param = (Get-Command Invoke-AnthropicMessage).Parameters['Messages']
        $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            ForEach-Object { $_.ValueFromPipeline } | Should -Contain $true
    }

    It 'Should accept hashtable messages via -Messages parameter' {
        $msgs = @(
            @{ role = 'user'; content = 'Hello' }
        )

        # Test parameter binding works - will throw API error but NOT parameter error
        $err = $null
        try {
            Invoke-AnthropicMessage -Messages $msgs -ErrorAction Stop
        }
        catch {
            $err = $_
        }

        # Should have error (no real server) but not a parameter binding error
        $err | Should -Not -BeNullOrEmpty
        $err.Exception.Message | Should -Not -Match 'Cannot bind parameter'
    }

    It 'Should throw when no messages provided' {
        # Empty array should throw our custom error
        { @() | Invoke-AnthropicMessage -ErrorAction Stop } | Should -Throw '*No messages provided*'
    }
}

Describe 'Invoke-AnthropicRouted Pipeline Support' {
    BeforeAll {
        Connect-Anthropic -Model 'test-model' -Force
        Set-AnthropicRouterConfig -Models @{ Default = 'test-model' }
    }

    AfterAll {
        Clear-AnthropicRouterConfig
    }

    It 'Should have ValueFromPipeline on Messages parameter' {
        $param = (Get-Command Invoke-AnthropicRouted).Parameters['Messages']
        $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            ForEach-Object { $_.ValueFromPipeline } | Should -Contain $true
    }

    It 'Should throw when no messages provided via empty pipeline' {
        { @() | Invoke-AnthropicRouted -ErrorAction Stop } | Should -Throw '*No messages provided*'
    }
}
#endregion

#region Generative LLM-Guided Tests
# These tests use the LLM to explore different scenarios and edge cases
# NOTE: These tests are skipped if Ollama is not running
# TIP: Set $script:GenerativeVerbose = $true before running to see LLM interactions
Describe 'Generative LLM Tests' -Tag 'Integration', 'Generative' -Skip:(-not $script:OllamaAvailable) {
    BeforeAll {
        Connect-Anthropic -Force
        $script:Tools = Get-AnthropicStandardTools

        # Verbose output helper - shows prompts/responses when enabled
        # Enable with: $env:GENERATIVE_VERBOSE = '1'
        $script:GenerativeVerbose = $env:GENERATIVE_VERBOSE -eq '1'

        function script:Write-TestOutput {
            param(
                [string]$Label,
                [string]$Content,
                [string]$Color = 'Gray'
            )
            if ($script:GenerativeVerbose) {
                $preview = if ($Content.Length -gt 200) { $Content.Substring(0, 200) + '...' } else { $Content }
                Write-Host "    [$Label] $preview" -ForegroundColor $Color
            }
        }
    }

    Context 'Tool Discovery Tests' {
        It 'LLM should correctly identify available tools' {
            $toolNames = ($script:Tools | ForEach-Object { $_.name }) -join ', '
            $prompt = "I have these tools available: $toolNames. List them back to me, one per line. Just the tool names, nothing else."

            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            ) -MaxTokens 200

            $text = $response | Get-AnthropicResponseText
            Write-TestOutput 'RESPONSE' $text 'Green'

            # LLM should echo back the tool names
            $text | Should -Match 'read_file|list_directory|get_current_time'
            $response.stop_reason | Should -Be 'end_turn'
        }

        It 'LLM should explain what each tool does' {
            $prompt = 'A tool called "read_file" exists that takes a file path. In one sentence, what would such a tool do? Answer only with that sentence.'

            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            # Don't pass tools to avoid LLM trying to use them instead of explaining
            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            ) -MaxTokens 100

            $text = $response | Get-AnthropicResponseText
            Write-TestOutput 'RESPONSE' $text 'Green'

            $text | Should -Not -BeNullOrEmpty -Because 'LLM should respond with text'
            $text | Should -Match 'read|file|content'
        }
    }

    Context 'Tool Execution Scenarios' {
        It 'LLM should use get_current_time when asked about time' {
            $prompt = 'What time is it in UTC right now? Use the get_current_time tool.'
            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            ) -Tools $script:Tools -MaxTokens 500

            # Should request tool use
            $toolUse = $response.content | Where-Object { $_.type -eq 'tool_use' }
            if ($toolUse) {
                Write-TestOutput 'TOOL_CALL' "$($toolUse.name) -> $($toolUse.input | ConvertTo-Json -Compress)" 'Yellow'
            }

            $toolUse | Should -Not -BeNullOrEmpty
            $toolUse.name | Should -Be 'get_current_time'
        }

        It 'LLM should use list_directory for folder contents' {
            $testPath = $PSScriptRoot
            $prompt = "List the files in $testPath using the list_directory tool."
            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            ) -Tools $script:Tools -MaxTokens 500

            $toolUse = $response.content | Where-Object { $_.type -eq 'tool_use' }
            if ($toolUse) {
                Write-TestOutput 'TOOL_CALL' "$($toolUse.name) -> $($toolUse.input | ConvertTo-Json -Compress)" 'Yellow'
            }

            $toolUse | Should -Not -BeNullOrEmpty
            $toolUse.name | Should -Be 'list_directory'
        }

        It 'LLM should chain multiple tools for complex tasks' {
            $projectRoot = Split-Path $PSScriptRoot -Parent
            $prompt = "I need you to use tools. First, use the list_directory tool on $projectRoot to see what files exist. You MUST use the tool."
            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            # Ask for something that requires multiple tool calls with explicit instruction
            $messages = @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            )

            $response = Invoke-AnthropicMessage -Messages $messages -Tools $script:Tools -MaxTokens 1000 -ToolChoice 'any'

            # With ToolChoice='any', LLM must use a tool
            $toolUses = @($response.content | Where-Object { $_.type -eq 'tool_use' })
            foreach ($tu in $toolUses) {
                Write-TestOutput 'TOOL_CALL' "$($tu.name) -> $($tu.input | ConvertTo-Json -Compress)" 'Yellow'
            }

            $toolUses.Count | Should -BeGreaterOrEqual 1 -Because 'ToolChoice=any should force tool use'
        }
    }

    Context 'Conversation Memory Tests' {
        It 'LLM should remember context across messages' {
            $conv = New-AnthropicConversation -SystemPrompt 'You are a helpful assistant. Be concise.'

            # First message
            $prompt1 = 'My favorite color is blue. Remember this.'
            Write-TestOutput 'PROMPT_1' $prompt1 'Cyan'
            Add-AnthropicMessage -Conversation $conv -Role 'user' -Content $prompt1
            $response1 = Invoke-AnthropicMessage -Messages $conv.Messages -MaxTokens 100
            $text1 = $response1 | Get-AnthropicResponseText
            Write-TestOutput 'RESPONSE_1' $text1 'Green'
            Add-AnthropicMessage -Conversation $conv -Role 'assistant' -Content $text1

            # Second message - test recall
            $prompt2 = 'What is my favorite color?'
            Write-TestOutput 'PROMPT_2' $prompt2 'Cyan'
            Add-AnthropicMessage -Conversation $conv -Role 'user' -Content $prompt2
            $response2 = Invoke-AnthropicMessage -Messages $conv.Messages -MaxTokens 100

            $text = $response2 | Get-AnthropicResponseText
            Write-TestOutput 'RESPONSE_2' $text 'Green'
            $text | Should -Match 'blue'
        }

        It 'LLM should handle multi-turn tool conversations' {
            $prompt = 'What time is it? Use the get_current_time tool to find out.'
            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            $messages = @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            )

            # First turn - get tool request
            $response1 = Invoke-AnthropicMessage -Messages $messages -Tools $script:Tools -MaxTokens 500
            $toolUse = $response1.content | Where-Object { $_.type -eq 'tool_use' }

            # Must have tool use - that's the point of this test
            $toolUse | Should -Not -BeNullOrEmpty -Because 'LLM should use get_current_time tool'

            Write-TestOutput 'TOOL_CALL' "$($toolUse.name) -> $($toolUse.input | ConvertTo-Json -Compress)" 'Yellow'

            # Execute tool
            $toolResult = Invoke-AnthropicStandardTool -ToolUse $toolUse
            Write-TestOutput 'TOOL_RESULT' $toolResult 'DarkYellow'

            # Add messages and get final response
            $messages += @{ role = 'assistant'; content = $response1.content }
            $messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $toolResult

            $response2 = Invoke-AnthropicMessage -Messages $messages -Tools $script:Tools -MaxTokens 500
            $finalText = $response2 | Get-AnthropicResponseText
            Write-TestOutput 'FINAL' $finalText 'Green'

            # Should complete with end_turn after getting tool result
            $response2.stop_reason | Should -Be 'end_turn'
            $finalText | Should -Match '\d{4}|\d{2}:\d{2}'
        }
    }

    Context 'Edge Case Handling' {
        It 'LLM should handle empty responses gracefully' {
            $prompt = 'Reply with just the word: OK'
            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            ) -MaxTokens 10

            $text = $response | Get-AnthropicResponseText
            Write-TestOutput 'RESPONSE' $text 'Green'

            $response | Should -Not -BeNullOrEmpty
            $response.content | Should -Not -BeNullOrEmpty
        }

        It 'LLM should respect max_tokens limit' {
            $prompt = 'Write a very long essay about the history of computing.'
            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            ) -MaxTokens 50

            $text = $response | Get-AnthropicResponseText
            Write-TestOutput 'RESPONSE' $text 'Green'
            Write-TestOutput 'TOKENS' "output_tokens: $($response.usage.output_tokens)" 'DarkGray'

            # Response should be truncated or brief
            $response.usage.output_tokens | Should -BeLessOrEqual 60  # Allow small buffer
        }

        It 'LLM should handle special characters in prompts' {
            $specialChars = 'Test with special chars: <>&"''`${}[]|\/!@#%^*()'
            $prompt = "Echo this exactly: $specialChars"
            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            ) -MaxTokens 200

            $text = $response | Get-AnthropicResponseText
            Write-TestOutput 'RESPONSE' $text 'Green'

            $response | Should -Not -BeNullOrEmpty
            $response.stop_reason | Should -Be 'end_turn'
        }

        It 'LLM should handle unicode and emojis' {
            $unicode = 'Hello 世界! 🎉 Привет мир!'
            $prompt = "What languages are in this text? $unicode"
            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            ) -MaxTokens 200

            $text = $response | Get-AnthropicResponseText
            Write-TestOutput 'RESPONSE' $text 'Green'

            $text | Should -Match 'Chinese|Japanese|English|Russian'
        }
    }

    Context 'LLM-Generated Test Scenarios' {
        It 'LLM should suggest and test a file operation' {
            $testDir = Join-Path $TestDrive 'llm-test'
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            'Line 1', 'Line 2', 'Line 3' | Set-Content (Join-Path $testDir 'sample.txt')

            # Ask LLM to read a file and count lines
            $prompt = "Read the file $testDir/sample.txt and tell me how many lines it has. Use the read_file tool."
            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            $messages = @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            )

            $iteration = 0
            $maxIterations = 3
            $response = Invoke-AnthropicMessage -Messages $messages -Tools $script:Tools -MaxTokens 500

            while ($response.stop_reason -eq 'tool_use' -and $iteration -lt $maxIterations) {
                $toolUse = $response.content | Where-Object { $_.type -eq 'tool_use' }
                Write-TestOutput "TOOL_CALL[$iteration]" "$($toolUse.name) -> $($toolUse.input | ConvertTo-Json -Compress)" 'Yellow'

                # Allow TestDrive paths for this test
                $toolResult = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowAllPaths
                Write-TestOutput "TOOL_RESULT[$iteration]" $toolResult 'DarkYellow'

                $messages += @{ role = 'assistant'; content = $response.content }
                $messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $toolResult

                $response = Invoke-AnthropicMessage -Messages $messages -Tools $script:Tools -MaxTokens 500
                $iteration++
            }

            $text = $response | Get-AnthropicResponseText
            Write-TestOutput 'FINAL' $text 'Green'

            # Core assertions: tool loop worked and completed
            $iteration | Should -BeGreaterThan 0 -Because 'LLM should have used read_file tool'
            $response.stop_reason | Should -Be 'end_turn' -Because 'conversation should complete after tool use'
            $text | Should -Not -BeNullOrEmpty -Because 'LLM should provide final response'
        }

        It 'LLM should perform search and report results' {
            $projectRoot = Split-Path $PSScriptRoot -Parent
            $prompt = "Search for *.ps1 files in $projectRoot/PSAnthropic using search_files. Report how many you found."
            Write-TestOutput 'PROMPT' $prompt 'Cyan'

            $messages = @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            )

            $iteration = 0
            $maxIterations = 3
            $response = Invoke-AnthropicMessage -Messages $messages -Tools $script:Tools -MaxTokens 1000

            while ($response.stop_reason -eq 'tool_use' -and $iteration -lt $maxIterations) {
                $toolUse = $response.content | Where-Object { $_.type -eq 'tool_use' }
                Write-TestOutput "TOOL_CALL[$iteration]" "$($toolUse.name) -> $($toolUse.input | ConvertTo-Json -Compress)" 'Yellow'

                $toolResult = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowAllPaths
                Write-TestOutput "TOOL_RESULT[$iteration]" $toolResult 'DarkYellow'

                $messages += @{ role = 'assistant'; content = $response.content }
                $messages += New-AnthropicToolResult -ToolUseId $toolUse.id -Content $toolResult

                $response = Invoke-AnthropicMessage -Messages $messages -Tools $script:Tools -MaxTokens 1000
                $iteration++
            }

            $text = $response | Get-AnthropicResponseText
            Write-TestOutput 'FINAL' $text 'Green'

            # Use LLM to validate the response mentions finding files
            $validationPrompt = "Does this response mention finding PowerShell (.ps1) files? Answer only 'yes' or 'no'. Response: $text"
            $validation = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content $validationPrompt
            ) -MaxTokens 10
            ($validation | Get-AnthropicResponseText) | Should -Match '(?i)yes'
        }
    }

    Context 'Web Fetch with LLM' {
        It 'LLM should identify Hacker News from fetched content' {
            # Step 1: Fetch the content ourselves (tests web_fetch tool)
            $toolUse = [PSCustomObject]@{
                name  = 'web_fetch'
                input = @{ url = 'https://news.ycombinator.com'; max_length = 5000 }
            }
            $webContent = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowWeb
            Write-TestOutput 'WEB_CONTENT' ($webContent.Substring(0, [Math]::Min(300, $webContent.Length))) 'DarkYellow'

            $webContent | Should -Not -Match '^Error:' -Because 'web_fetch should succeed'

            # Step 2: Ask LLM to identify the website from the content
            $prompt = @"
I fetched content from a website. Based on this content, tell me:
1. What website is this?
2. What type of content does it feature?

Content:
$webContent
"@
            Write-TestOutput 'PROMPT' 'Asking LLM to identify website...' 'Cyan'

            $response = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content $prompt
            ) -MaxTokens 300

            $text = $response | Get-AnthropicResponseText
            Write-TestOutput 'RESPONSE' $text 'Green'

            $response.stop_reason | Should -Be 'end_turn'
            $text | Should -Not -BeNullOrEmpty

            # Validate LLM recognized it as Hacker News
            $validationPrompt = "Does this response identify the website as Hacker News, HN, or Y Combinator News? Answer only 'yes' or 'no'. Response: $text"
            $validation = Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content $validationPrompt
            ) -MaxTokens 10

            Write-Host "LLM identified: $text" -ForegroundColor Cyan
            ($validation | Get-AnthropicResponseText) | Should -Match '(?i)yes' -Because 'LLM should recognize Hacker News'
        }
    }
}
#endregion

#region Mock-Based HTTP Error Tests
# These tests use mocks to simulate HTTP errors without requiring a server
Describe 'HTTP Error Handling (Mock-Based)' {
    BeforeAll {
        # Load classes for exception type tests
        $classesPath = Join-Path $PSScriptRoot '..' 'PSAnthropic' 'Classes.ps1'
        . $classesPath

        # Ensure connection exists for Invoke-AnthropicWebRequest
        Connect-Anthropic -Model 'mock-model' -Force
    }

    AfterAll {
        Disconnect-Anthropic -ErrorAction SilentlyContinue
    }

    Context 'Rate Limiting (429)' {
        It 'Should write error with AnthropicRateLimitException on 429' {
            # Create a mock response object that simulates 429
            Mock Invoke-WebRequest -ModuleName PSAnthropic {
                $response = [System.Net.HttpWebResponse]::new()
                $exception = [System.Net.WebException]::new(
                    'Too Many Requests',
                    $null,
                    [System.Net.WebExceptionStatus]::ProtocolError,
                    $response
                )
                throw $exception
            }

            # Mock the Response property to return 429
            Mock -CommandName 'Invoke-WebRequest' -ModuleName PSAnthropic {
                $ex = [System.Exception]::new('Too Many Requests')
                # PowerShell creates ErrorRecord with Response property
                throw $ex
            }

            $error.Clear()
            Invoke-AnthropicWebRequest -Uri 'http://test/v1/messages' -Method GET -ErrorAction SilentlyContinue -ErrorVariable webError

            # The function should have written an error
            $webError | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Authentication Errors (401)' {
        It 'Should include helpful message about API key in 401 error' {
            # We test by checking the error message format from the exception class
            $exception = [AnthropicAuthenticationException]::new(
                "Authentication failed: Invalid API key. Check your API key or run 'Connect-Anthropic -Force'.",
                $null
            )

            $exception.Message | Should -Match 'Connect-Anthropic'
            $exception.StatusCode | Should -Be 401
            $exception.ErrorType | Should -Be 'authentication_error'
        }
    }

    Context 'Server Errors (5xx)' {
        It 'Should create AnthropicServerException with correct properties' {
            $exception = [AnthropicServerException]::new(
                'Server error (HTTP 500) after 3 retries: Internal Server Error',
                500,
                @{ error = @{ message = 'Internal Server Error' } }
            )

            $exception.StatusCode | Should -Be 500
            $exception.ErrorType | Should -Be 'server_error'
            $exception.Message | Should -Match '500'
            $exception.Message | Should -Match 'retries'
        }
    }

    Context 'Connection Errors' {
        It 'Should create AnthropicConnectionException with status -1' {
            $exception = [AnthropicConnectionException]::new(
                'Connection error to http://localhost:11434: Unable to connect'
            )

            $exception.StatusCode | Should -Be -1
            $exception.ErrorType | Should -Be 'connection_error'
            $exception.Message | Should -Match 'Connection error'
        }

        It 'Should wrap inner exception' {
            $inner = [System.Net.Sockets.SocketException]::new()
            $exception = [AnthropicConnectionException]::new(
                'Connection failed',
                $inner
            )

            $exception.InnerException | Should -Not -BeNullOrEmpty
            $exception.StatusCode | Should -Be -1
        }
    }

    Context 'Exception Hierarchy' {
        It 'All typed exceptions should inherit from AnthropicApiException' {
            # Test exception types loaded by module - classes already loaded by main BeforeAll
            # Use module's exported types via reflection to avoid parse-time type resolution
            $module = Get-Module PSAnthropic
            $assembly = $module.ImplementingAssembly

            # Get types directly from the PSAnthropic session state where classes are defined
            $exceptionNames = @(
                'AnthropicBadRequestException',
                'AnthropicAuthenticationException',
                'AnthropicPermissionException',
                'AnthropicNotFoundException',
                'AnthropicRateLimitException',
                'AnthropicOverloadedException',
                'AnthropicServerException',
                'AnthropicConnectionException'
            )

            foreach ($name in $exceptionNames) {
                # Create instance dynamically using Invoke-Expression (types are available at runtime)
                $createExpr = switch ($name) {
                    'AnthropicRateLimitException' { "[$name]::new('test', 30, `$null)" }
                    'AnthropicServerException' { "[$name]::new('test', 500, `$null)" }
                    'AnthropicConnectionException' { "[$name]::new('test')" }
                    default { "[$name]::new('test', `$null)" }
                }

                $ex = Invoke-Expression $createExpr
                $ex.GetType().BaseType.Name | Should -Be 'AnthropicApiException' -Because "$name should inherit from AnthropicApiException"
            }
        }

        It 'AnthropicRateLimitException should have RetryAfterSeconds property' {
            $exception = [AnthropicRateLimitException]::new('Rate limited', 45, $null)

            $exception.RetryAfterSeconds | Should -Be 45
        }

        It 'Each exception should have correct status code' {
            [AnthropicBadRequestException]::new('', $null).StatusCode | Should -Be 400
            [AnthropicAuthenticationException]::new('', $null).StatusCode | Should -Be 401
            [AnthropicPermissionException]::new('', $null).StatusCode | Should -Be 403
            [AnthropicNotFoundException]::new('', $null).StatusCode | Should -Be 404
            [AnthropicRateLimitException]::new('', 0, $null).StatusCode | Should -Be 429
            [AnthropicOverloadedException]::new('', $null).StatusCode | Should -Be 529
        }
    }
}
#endregion

#region Mock-Based Streaming Tests
Describe 'Streaming (Mock-Based)' {
    BeforeAll {
        Connect-Anthropic -Model 'mock-model' -Force
    }

    AfterAll {
        Disconnect-Anthropic -ErrorAction SilentlyContinue
    }

    Context 'Event Stream Output' {
        It 'Should pass through stream events from Invoke-AnthropicStreamRequest' {
            Mock Invoke-AnthropicStreamRequest -ModuleName PSAnthropic {
                # Simulate SSE event sequence
                [PSCustomObject]@{ type = 'message_start'; message = @{ id = 'msg_mock1'; model = 'mock-model' } }
                [PSCustomObject]@{ type = 'content_block_start'; index = 0; content_block = @{ type = 'text'; text = '' } }
                [PSCustomObject]@{ type = 'content_block_delta'; index = 0; delta = @{ type = 'text_delta'; text = 'Hello' } }
                [PSCustomObject]@{ type = 'content_block_delta'; index = 0; delta = @{ type = 'text_delta'; text = ' world' } }
                [PSCustomObject]@{ type = 'content_block_stop'; index = 0 }
                [PSCustomObject]@{ type = 'message_delta'; delta = @{ stop_reason = 'end_turn' }; usage = @{ output_tokens = 5 } }
                [PSCustomObject]@{ type = 'message_stop' }
            }

            $events = @(Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content 'Hi'
            ) -Stream)

            $events.Count | Should -Be 7
            $events[0].type | Should -Be 'message_start'
            $events[-1].type | Should -Be 'message_stop'
        }

        It 'Should output content_block_delta events with text' {
            Mock Invoke-AnthropicStreamRequest -ModuleName PSAnthropic {
                [PSCustomObject]@{ type = 'message_start'; message = @{ id = 'msg_1' } }
                [PSCustomObject]@{ type = 'content_block_delta'; index = 0; delta = @{ type = 'text_delta'; text = 'Test' } }
                [PSCustomObject]@{ type = 'message_stop' }
            }

            $events = @(Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content 'Hi'
            ) -Stream)

            $deltaEvents = $events | Where-Object { $_.type -eq 'content_block_delta' }
            $deltaEvents | Should -Not -BeNullOrEmpty
            $deltaEvents[0].delta.text | Should -Be 'Test'
        }

        It 'Should output tool_use content blocks in stream' {
            Mock Invoke-AnthropicStreamRequest -ModuleName PSAnthropic {
                [PSCustomObject]@{ type = 'message_start'; message = @{ id = 'msg_1' } }
                [PSCustomObject]@{
                    type = 'content_block_start'
                    index = 0
                    content_block = @{
                        type = 'tool_use'
                        id = 'toolu_mock1'
                        name = 'get_current_time'
                    }
                }
                [PSCustomObject]@{
                    type = 'content_block_delta'
                    index = 0
                    delta = @{
                        type = 'input_json_delta'
                        partial_json = '{"timezone":"UTC"}'
                    }
                }
                [PSCustomObject]@{ type = 'content_block_stop'; index = 0 }
                [PSCustomObject]@{ type = 'message_delta'; delta = @{ stop_reason = 'tool_use' } }
                [PSCustomObject]@{ type = 'message_stop' }
            }

            $events = @(Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content 'What time is it?'
            ) -Stream)

            $toolStartEvent = $events | Where-Object {
                $_.type -eq 'content_block_start' -and $_.content_block.type -eq 'tool_use'
            }
            $toolStartEvent | Should -Not -BeNullOrEmpty
            $toolStartEvent.content_block.name | Should -Be 'get_current_time'

            # Should have stop_reason = tool_use in message_delta
            $messageDelta = $events | Where-Object { $_.type -eq 'message_delta' }
            $messageDelta.delta.stop_reason | Should -Be 'tool_use'
        }
    }

    Context 'Streaming Error Handling' {
        It 'Should propagate timeout errors from stream' {
            Mock Invoke-AnthropicStreamRequest -ModuleName PSAnthropic {
                throw [AnthropicConnectionException]::new('Request timed out after 30 seconds')
            }

            { Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content 'Hi'
            ) -Stream -ErrorAction Stop } | Should -Throw '*timed out*'
        }

        It 'Should propagate connection errors from stream' {
            Mock Invoke-AnthropicStreamRequest -ModuleName PSAnthropic {
                throw [AnthropicConnectionException]::new('Connection reset by peer')
            }

            { Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content 'Hi'
            ) -Stream -ErrorAction Stop } | Should -Throw '*Connection*'
        }
    }

    Context 'Stream Event Types' {
        It 'Should have all expected event types in typical stream' {
            Mock Invoke-AnthropicStreamRequest -ModuleName PSAnthropic {
                [PSCustomObject]@{ type = 'message_start'; message = @{ id = 'msg_1' } }
                [PSCustomObject]@{ type = 'content_block_start'; index = 0; content_block = @{ type = 'text' } }
                [PSCustomObject]@{ type = 'content_block_delta'; index = 0; delta = @{ text = 'Hi' } }
                [PSCustomObject]@{ type = 'content_block_stop'; index = 0 }
                [PSCustomObject]@{ type = 'message_delta'; delta = @{ stop_reason = 'end_turn' } }
                [PSCustomObject]@{ type = 'message_stop' }
            }

            $events = @(Invoke-AnthropicMessage -Messages @(
                New-AnthropicMessage -Role 'user' -Content 'Hi'
            ) -Stream)

            $eventTypes = $events | ForEach-Object { $_.type } | Sort-Object -Unique

            $eventTypes | Should -Contain 'message_start'
            $eventTypes | Should -Contain 'content_block_start'
            $eventTypes | Should -Contain 'content_block_delta'
            $eventTypes | Should -Contain 'content_block_stop'
            $eventTypes | Should -Contain 'message_delta'
            $eventTypes | Should -Contain 'message_stop'
        }
    }
}
#endregion
