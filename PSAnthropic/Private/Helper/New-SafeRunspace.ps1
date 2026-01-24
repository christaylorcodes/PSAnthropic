function New-SafeRunspace {
    <#
    .SYNOPSIS
        Creates an isolated PowerShell runspace with safety restrictions.
    .DESCRIPTION
        Creates a constrained runspace for executing untrusted code safely.
        Uses PowerShell's InitialSessionState to control available commands
        and ConstrainedLanguage mode to prevent .NET type abuse.

        The runspace includes a curated set of safe commands for:
        - Output and formatting (Write-*, Format-*, Out-String)
        - Data manipulation (Select-Object, Where-Object, Sort-Object, etc.)
        - File reading (Get-Content, Get-ChildItem, Test-Path)
        - Conversion (ConvertTo-Json, ConvertFrom-Json, etc.)
        - Inspection (Get-Process, Get-Service, Get-Help, Get-Member)

    .PARAMETER AdditionalCommands
        Additional command names to make available beyond the defaults.
    .EXAMPLE
        $runspace = New-SafeRunspace
        # Use runspace...
        $runspace.Dispose()
    .EXAMPLE
        $runspace = New-SafeRunspace -AdditionalCommands @('Invoke-WebRequest')
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.Runspace])]
    param(
        [Parameter()]
        [string[]]$AdditionalCommands = @()
    )

    # Curated list of safe commands (merged from previous safety levels)
    $allowedCommands = @(
        # Output
        'Write-Output', 'Write-Host', 'Write-Warning', 'Write-Error', 'Write-Information', 'Write-Verbose', 'Write-Debug'
        # Selection and filtering
        'Select-Object', 'Where-Object', 'ForEach-Object', 'Sort-Object', 'Group-Object'
        # Formatting
        'Format-Table', 'Format-List', 'Format-Wide', 'Format-Custom'
        # Measurement
        'Measure-Object', 'Compare-Object', 'Measure-Command'
        # String operations
        'Out-String', 'Out-Null'
        # Basic utilities
        'Get-Date', 'Get-Random', 'New-Guid', 'Get-Host'
        # Variables
        'Get-Variable', 'Set-Variable', 'New-Variable'
        # Filesystem (read-only)
        'Get-Content', 'Get-ChildItem', 'Get-Item', 'Get-ItemProperty'
        'Test-Path', 'Resolve-Path', 'Split-Path', 'Join-Path'
        'Get-Location'
        # Conversion
        'ConvertTo-Json', 'ConvertFrom-Json', 'ConvertTo-Csv', 'ConvertFrom-Csv'
        'ConvertTo-Xml', 'ConvertTo-Html'
        # Text manipulation
        'Select-String'
        # System inspection (read-only)
        'Get-Process', 'Get-Service'
        # Help and discovery
        'Get-Help', 'Get-Command', 'Get-Member', 'Get-Alias'
        # Additional utilities
        'Tee-Object', 'Get-Unique'
        # Timing
        'Start-Sleep'
    )

    try {
        # Start with empty session state
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::Create()

        # Build command set
        $commandSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $commandSet.UnionWith([string[]]$allowedCommands)

        # Add any additional commands requested
        if ($AdditionalCommands) {
            $commandSet.UnionWith([string[]]$AdditionalCommands)
        }

        # Import commands from the current session
        foreach ($cmdName in $commandSet) {
            $cmdInfo = Get-Command -Name $cmdName -ErrorAction SilentlyContinue
            if ($cmdInfo) {
                switch ($cmdInfo.CommandType) {
                    'Cmdlet' {
                        $entry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new(
                            $cmdInfo.Name,
                            $cmdInfo.ImplementingType,
                            $null
                        )
                        $iss.Commands.Add($entry)
                    }
                    'Function' {
                        $entry = [System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new(
                            $cmdInfo.Name,
                            $cmdInfo.Definition
                        )
                        $iss.Commands.Add($entry)
                    }
                    'Alias' {
                        $entry = [System.Management.Automation.Runspaces.SessionStateAliasEntry]::new(
                            $cmdInfo.Name,
                            $cmdInfo.Definition
                        )
                        $iss.Commands.Add($entry)
                    }
                }
            }
        }

        # Add required providers
        try {
            # Variable provider for basic variable operations
            $varProvider = Get-PSProvider -PSProvider Variable -ErrorAction Stop
            $iss.Providers.Add(
                [System.Management.Automation.Runspaces.SessionStateProviderEntry]::new(
                    'Variable',
                    $varProvider.ImplementingType,
                    $null
                )
            )

            # FileSystem provider for Get-ChildItem, Get-Content, etc.
            $fsProvider = Get-PSProvider -PSProvider FileSystem -ErrorAction Stop
            $iss.Providers.Add(
                [System.Management.Automation.Runspaces.SessionStateProviderEntry]::new(
                    'FileSystem',
                    $fsProvider.ImplementingType,
                    $null
                )
            )

            # Environment provider for env: drive
            $envProvider = Get-PSProvider -PSProvider Environment -ErrorAction Stop
            $iss.Providers.Add(
                [System.Management.Automation.Runspaces.SessionStateProviderEntry]::new(
                    'Environment',
                    $envProvider.ImplementingType,
                    $null
                )
            )
        }
        catch {
            Write-Warning "Could not add provider: $_"
        }

        # Set constrained language mode to block .NET type abuse
        $iss.LanguageMode = [System.Management.Automation.PSLanguageMode]::ConstrainedLanguage

        # Create and open the runspace
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $runspace.Open()

        return $runspace
    }
    catch {
        throw "Failed to create safe runspace: $_"
    }
}
