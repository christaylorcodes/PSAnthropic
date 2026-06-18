function Register-AnthropicArgumentCompleters {
    <#
    .SYNOPSIS
        Registers argument completers for PSAnthropic commands.
    .DESCRIPTION
        Provides dynamic tab-completion for Model parameters by discovering models
        from the connected backend (Anthropic Cloud /v1/models or Ollama /api/tags)
        via Get-AnthropicModel, which is cache-backed. No model names are hardcoded:
        when not connected, completion simply offers nothing rather than suggesting
        stale or retired model IDs.
    #>
    [CmdletBinding()]
    param()

    # Model completer - discovers live from the connected backend (no hardcoded list)
    $modelCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $models = @()

        # Discover from the connected backend (cache-backed; returns nothing if not connected)
        if ($script:AnthropicConnection) {
            try {
                $discovered = Get-AnthropicModel -ErrorAction SilentlyContinue
                if ($discovered) {
                    $models = @($discovered | ForEach-Object {
                            if ($_.Name) { $_.Name } elseif ($_.model) { $_.model } else { $_ }
                        })
                }
            }
            catch { }
        }

        $models | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object -Unique | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }

    # Register for commands with -Model parameter
    @('Connect-Anthropic', 'Invoke-AnthropicMessage', 'Invoke-AnthropicRouted') | ForEach-Object {
        Register-ArgumentCompleter -CommandName $_ -ParameterName 'Model' -ScriptBlock $modelCompleter
    }
}
