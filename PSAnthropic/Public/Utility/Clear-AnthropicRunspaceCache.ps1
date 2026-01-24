function Clear-AnthropicRunspaceCache {
    <#
    .SYNOPSIS
        Clears the cached runspaces used by safe command execution.
    .DESCRIPTION
        The PSAnthropic module caches constrained runspaces for performance when
        executing tool commands. This function disposes all cached runspaces and
        clears the cache.

        Call this function when:
        - You want to reclaim memory from cached runspaces
        - You need to reset the execution environment
        - Before unloading the module in long-running sessions

        Note: The module automatically cleans up runspaces when it is removed
        via Remove-Module. This function is for manual cleanup during active use.
    .EXAMPLE
        Clear-AnthropicRunspaceCache

        Clears all cached runspaces.
    .EXAMPLE
        # Clean up after intensive tool usage
        $tools = Get-AnthropicStandardTools
        # ... execute many tool calls ...
        Clear-AnthropicRunspaceCache

        Explicitly reclaims memory after heavy tool usage.
    #>
    [CmdletBinding()]
    param()

    # Call the internal Clear-RunspaceCache function
    Clear-RunspaceCache
    Write-Verbose "Runspace cache cleared"
}
