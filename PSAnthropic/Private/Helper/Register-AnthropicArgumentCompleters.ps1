function Register-AnthropicArgumentCompleters {
    <#
    .SYNOPSIS
        Registers argument completers for PSAnthropic commands.
    .DESCRIPTION
        Provides dynamic tab-completion for Model parameters that fetches available
        models from the connected Ollama server, with fallback to common model names.
    #>
    [CmdletBinding()]
    param()

    # Model completer - dynamically fetches from server or uses fallback list
    $modelCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $models = @()

        # Try to get models from connected server
        if ($script:AnthropicConnection) {
            try {
                $ollamaModels = Get-AnthropicModel -ErrorAction SilentlyContinue
                if ($ollamaModels) {
                    $models = @($ollamaModels | ForEach-Object {
                        if ($_.name) { $_.name } elseif ($_.model) { $_.model } else { $_ }
                    })
                }
            }
            catch { }
        }

        # Fallback to common models
        if ($models.Count -eq 0) {
            $models = @(
                'llama3.3', 'llama3.2', 'llama3.1', 'llama3', 'mistral', 'mixtral',
                'codellama', 'deepseek-coder', 'qwen2.5', 'qwen2.5-coder', 'phi3', 'gemma2',
                'claude-3-5-sonnet-20241022', 'claude-3-5-haiku-20241022', 'claude-3-opus-20240229'
            )
        }

        $models | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }

    # Register for commands with -Model parameter
    @('Connect-Anthropic', 'Invoke-AnthropicMessage', 'Invoke-AnthropicRouted') | ForEach-Object {
        Register-ArgumentCompleter -CommandName $_ -ParameterName 'Model' -ScriptBlock $modelCompleter
    }
}
