# PSAnthropic - PowerShell client for the Anthropic Messages API
# https://github.com/christaylorcodes/PSAnthropic

# Load classes first - must be done before dot-sourcing functions that reference them
# This is also in ScriptsToProcess for consumer access, but needed here for module scope
. "$PSScriptRoot\Classes.ps1"

# Initialize script-scoped state variables
$script:AnthropicConnection = $null
$script:AnthropicRouterConfig = $null

# Get public and private function definition files
$Public = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue -Recurse )
$Private = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue -Recurse )

# Dot source the files
foreach ($import in @($Public + $Private)) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

# Export public functions
Export-ModuleMember -Function $Public.BaseName

# Register argument completers for tab completion
Register-AnthropicArgumentCompleters

# Module cleanup handler - disposes resources when module is removed
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    # Dispose HTTP client resources (from Invoke-AnthropicStreamRequest)
    if ($script:StreamHttpClient) {
        try { $script:StreamHttpClient.Dispose() } catch { }
        $script:StreamHttpClient = $null
    }
    if ($script:StreamHttpHandler) {
        try { $script:StreamHttpHandler.Dispose() } catch { }
        $script:StreamHttpHandler = $null
    }

    # Clear runspace cache (from Invoke-SafeCommand)
    if ($script:RunspaceCache) {
        foreach ($key in @($script:RunspaceCache.Keys)) {
            try {
                $rs = $script:RunspaceCache[$key]
                if ($rs -and $rs.RunspaceStateInfo.State -eq 'Opened') {
                    $rs.Close()
                }
                if ($rs) { $rs.Dispose() }
            }
            catch { }
        }
        $script:RunspaceCache.Clear()
    }

    # Clear router config lock if it exists
    if ($script:RouterConfigLock) {
        try { $script:RouterConfigLock.Dispose() } catch { }
        $script:RouterConfigLock = $null
    }

    # Clear connection and router state
    $script:AnthropicConnection = $null
    $script:AnthropicRouterConfig = $null
}
