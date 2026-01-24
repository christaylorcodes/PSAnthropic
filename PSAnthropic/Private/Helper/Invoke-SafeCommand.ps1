# Script-scoped runspace cache for performance
if (-not $script:RunspaceCache) {
    $script:RunspaceCache = $null
}

function Get-CachedRunspace {
    <#
    .SYNOPSIS
        Gets or creates a cached runspace.
    .DESCRIPTION
        Reuses a runspace to avoid the overhead of creating a new one per command.
        If the cached runspace is broken or closed, creates a new one.
    #>

    # Check if we have a valid cached runspace
    if ($script:RunspaceCache) {
        if ($script:RunspaceCache.RunspaceStateInfo.State -eq 'Opened') {
            return $script:RunspaceCache
        }
        else {
            # Dispose broken runspace
            try { $script:RunspaceCache.Dispose() } catch { }
            $script:RunspaceCache = $null
        }
    }

    # Create new runspace and cache it
    $runspace = New-SafeRunspace
    $script:RunspaceCache = $runspace
    return $runspace
}

function Clear-RunspaceCache {
    <#
    .SYNOPSIS
        Clears the cached runspace. Call when done with safe command execution.
    #>
    if ($script:RunspaceCache) {
        try {
            if ($script:RunspaceCache.RunspaceStateInfo.State -eq 'Opened') {
                $script:RunspaceCache.Close()
            }
            $script:RunspaceCache.Dispose()
        }
        catch { }
        $script:RunspaceCache = $null
    }
}

function Invoke-SafeCommand {
    <#
    .SYNOPSIS
        Executes a PowerShell command in an isolated, constrained runspace.
    .DESCRIPTION
        Safely executes PowerShell commands using an isolated runspace with
        security restrictions. This is much more secure than using
        Invoke-Expression with blocklists.

        The command runs in a separate runspace with:
        - ConstrainedLanguage mode (prevents .NET type abuse)
        - Whitelisted commands only
        - Automatic timeout protection
        - Runspace caching for performance

    .PARAMETER Command
        The PowerShell command or script to execute.
    .PARAMETER WorkingDirectory
        Optional working directory for the command.
    .PARAMETER TimeoutSeconds
        Maximum execution time in seconds. Default is 30.
    .PARAMETER AdditionalCommands
        Additional command names to allow beyond the defaults.
    .PARAMETER NoCache
        If specified, creates a fresh runspace instead of using cache.
    .EXAMPLE
        Invoke-SafeCommand -Command 'Get-ChildItem C:\Temp'
    .EXAMPLE
        Invoke-SafeCommand -Command 'Get-Process | Select-Object -First 5' -TimeoutSeconds 10
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter()]
        [string]$WorkingDirectory,

        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30,

        [Parameter()]
        [string[]]$AdditionalCommands = @(),

        [Parameter()]
        [switch]$NoCache
    )

    $runspace = $null
    $ownedRunspace = $false
    $powershell = $null
    $asyncResult = $null

    try {
        # Get or create runspace
        if ($NoCache -or $AdditionalCommands.Count -gt 0) {
            # Create a fresh runspace if NoCache or custom commands
            $runspace = New-SafeRunspace -AdditionalCommands $AdditionalCommands
            $ownedRunspace = $true
        }
        else {
            # Use cached runspace for performance
            $runspace = Get-CachedRunspace
            $ownedRunspace = $false
        }

        # Set working directory if specified
        if ($WorkingDirectory) {
            if (Test-Path -Path $WorkingDirectory -PathType Container) {
                try {
                    $runspace.SessionStateProxy.Path.SetLocation($WorkingDirectory) | Out-Null
                }
                catch {
                    # SetLocation may fail if FileSystem provider not available
                    # This is not fatal - command will just run from default location
                    Write-Verbose "Could not set working directory: $_"
                }
            }
            else {
                return "Error: Working directory not found: '$WorkingDirectory'"
            }
        }

        # Create PowerShell instance attached to the runspace
        $powershell = [System.Management.Automation.PowerShell]::Create()
        $powershell.Runspace = $runspace

        # Add the command
        $powershell.AddScript($Command) | Out-Null

        # Collections for output
        $outputCollection = [System.Collections.Generic.List[object]]::new()
        $errorCollection = [System.Collections.Generic.List[object]]::new()

        # Begin async invocation with timeout support
        $asyncResult = $powershell.BeginInvoke()

        # Wait for completion with timeout
        $completed = $asyncResult.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))

        if (-not $completed) {
            # Timeout occurred
            $powershell.Stop()
            return "Error: Command timed out after $TimeoutSeconds seconds"
        }

        # Get the results
        try {
            $results = $powershell.EndInvoke($asyncResult)
            foreach ($item in $results) {
                $outputCollection.Add($item)
            }
        }
        catch {
            $errorCollection.Add($_)
        }

        # Collect errors from streams after execution completes
        foreach ($err in $powershell.Streams.Error) {
            $errorCollection.Add($err)
        }

        # Build output string
        $outputBuilder = [System.Text.StringBuilder]::new()

        # Add regular output
        if ($outputCollection.Count -gt 0) {
            $outputText = $outputCollection | Out-String
            $outputBuilder.Append($outputText.TrimEnd()) | Out-Null
        }

        # Add errors if any
        if ($errorCollection.Count -gt 0) {
            if ($outputBuilder.Length -gt 0) {
                $outputBuilder.AppendLine() | Out-Null
                $outputBuilder.AppendLine() | Out-Null
            }
            $outputBuilder.AppendLine("--- Errors ---") | Out-Null
            foreach ($err in $errorCollection) {
                $outputBuilder.AppendLine($err.ToString()) | Out-Null
            }
        }

        # Add warnings if any
        if ($powershell.Streams.Warning.Count -gt 0) {
            if ($outputBuilder.Length -gt 0) { $outputBuilder.AppendLine() | Out-Null }
            $outputBuilder.AppendLine("--- Warnings ---") | Out-Null
            foreach ($warn in $powershell.Streams.Warning) {
                $outputBuilder.AppendLine("WARNING: $warn") | Out-Null
            }
        }

        # Add information stream (with null check)
        if ($powershell.Streams.Information.Count -gt 0) {
            if ($outputBuilder.Length -gt 0) { $outputBuilder.AppendLine() | Out-Null }
            foreach ($info in $powershell.Streams.Information) {
                if ($null -ne $info.MessageData) {
                    $outputBuilder.AppendLine($info.MessageData.ToString()) | Out-Null
                }
            }
        }

        $output = $outputBuilder.ToString().TrimEnd()

        if ([string]::IsNullOrWhiteSpace($output)) {
            return "(Command completed successfully with no output)"
        }

        return $output
    }
    catch {
        return "Error executing command: $_"
    }
    finally {
        # Clean up PowerShell instance
        if ($asyncResult -and -not $asyncResult.IsCompleted) {
            try { $powershell.Stop() } catch { }
        }

        if ($powershell) {
            try { $powershell.Dispose() } catch { }
        }

        # Only dispose runspace if we own it (not cached)
        if ($ownedRunspace -and $runspace) {
            try {
                if ($runspace.RunspaceStateInfo.State -eq 'Opened') {
                    $runspace.Close()
                }
                $runspace.Dispose()
            }
            catch { }
        }
    }
}
