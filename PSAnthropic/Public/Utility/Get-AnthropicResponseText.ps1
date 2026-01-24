function Get-AnthropicResponseText {
    <#
    .SYNOPSIS
        Extracts text content from an Anthropic API response.
    .DESCRIPTION
        Convenience function to extract the text from a response object.
        Handles responses with multiple content blocks by concatenating all text.
    .PARAMETER Response
        The response object from Invoke-AnthropicMessage.
    .EXAMPLE
        $response = Invoke-AnthropicMessage -Messages @(New-AnthropicMessage -Role 'user' -Content 'Hello')
        $response | Get-AnthropicResponseText
    .EXAMPLE
        Get-AnthropicResponseText -Response $response
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSObject]$Response
    )

    process {
        if (-not $Response.content) {
            Write-Warning "Response has no content"
            return $null
        }

        # Extract all text blocks and join them
        $textBlocks = $Response.content | Where-Object { $_.type -eq 'text' }

        if (-not $textBlocks) {
            Write-Verbose "Response has no text content blocks"
            return $null
        }

        ($textBlocks | ForEach-Object { $_.text }) -join ''
    }
}
