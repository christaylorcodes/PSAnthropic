function ConvertTo-AnthropicApiMessage {
    <#
    .SYNOPSIS
        Normalizes assorted message inputs into API-shaped hashtables.
    .DESCRIPTION
        Internal helper that converts AnthropicMessage objects, hashtables with
        'role'/'content', or PSCustomObjects with Role/Content properties into the
        @{ role = ...; content = ... } hashtables the API expects. Shared by
        Invoke-AnthropicMessage and Get-AnthropicTokenCount.
    .PARAMETER Messages
        The messages to normalize.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Messages
    )

    for ($i = 0; $i -lt $Messages.Count; $i++) {
        $msg = $Messages[$i]

        if ($msg -is [hashtable]) {
            if (-not $msg.ContainsKey('role') -or -not $msg.ContainsKey('content')) {
                throw "Messages[$i]: Hashtable must contain 'role' and 'content' keys."
            }
            $msg
        }
        elseif ($null -ne $msg -and $msg.PSObject.Methods.Name -contains 'ToHashtable') {
            $msg.ToHashtable()
        }
        elseif ($null -ne $msg.Role -and $null -ne $msg.Content) {
            @{
                role    = $msg.Role.ToString()
                content = $msg.Content
            }
        }
        else {
            throw "Messages[$i]: Invalid message. Expected AnthropicMessage, hashtable with 'role'/'content', or object with Role/Content properties. Got: $($msg.GetType().Name)"
        }
    }
}
