function Disconnect-Anthropic {
    <#
    .SYNOPSIS
        Clears the current Anthropic API connection.
    .DESCRIPTION
        Removes the stored connection settings, requiring a new Connect-Anthropic
        call before making further API requests.
    .EXAMPLE
        Disconnect-Anthropic
        # Clears the connection
    .EXAMPLE
        Disconnect-Anthropic -WhatIf
        # Shows what would happen without disconnecting
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($script:AnthropicConnection) {
        $server = $script:AnthropicConnection.Server
        if ($PSCmdlet.ShouldProcess($server, 'Disconnect from Anthropic API')) {
            Remove-Variable -Name 'AnthropicConnection' -Scope Script -ErrorAction SilentlyContinue
            Write-Verbose "Disconnected from $server"
        }
    }
    else {
        Write-Verbose "No active connection to disconnect"
    }
}
