function New-AnthropicImageContent {
    <#
    .SYNOPSIS
        Creates an image content block for the Anthropic Messages API.
    .DESCRIPTION
        Creates a base64-encoded image content block that can be included in messages.
        Ollama only supports base64 images (not URL-based).
        Supported formats: JPEG, PNG, GIF, WebP
    .PARAMETER Path
        Path to an image file. The media type is auto-detected from the extension.
        Supports pipeline input via FullName property (e.g., from Get-ChildItem).
    .PARAMETER Base64
        Base64-encoded image data. Must also specify -MediaType.
    .PARAMETER MediaType
        The MIME type of the image (e.g., 'image/png'). Required when using -Base64.
    .EXAMPLE
        # From file path
        $imageBlock = New-AnthropicImageContent -Path 'C:\images\screenshot.png'
    .EXAMPLE
        # From base64 string
        $imageBlock = New-AnthropicImageContent -Base64 $encodedData -MediaType 'image/jpeg'
    .EXAMPLE
        # Use in a message with text
        $response = Invoke-AnthropicMessage -Messages @(
            @{
                role = 'user'
                content = @(
                    @{ type = 'text'; text = 'What is in this image?' }
                    (New-AnthropicImageContent -Path './photo.jpg')
                )
            }
        ) -Model 'llava'
    .EXAMPLE
        # Batch process multiple images via pipeline
        $imageBlocks = Get-ChildItem *.png | New-AnthropicImageContent
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([hashtable])]
    param(
        # Supports pipeline input for batch image processing (e.g., Get-ChildItem *.png | New-AnthropicImageContent)
        [Parameter(Mandatory, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Base64')]
        [string]$Base64,

        [Parameter(Mandatory, ParameterSetName = 'Base64')]
        [ValidateSet('image/jpeg', 'image/png', 'image/gif', 'image/webp')]
        [string]$MediaType
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            # Get absolute path
            $absolutePath = Resolve-Path $Path -ErrorAction Stop

            # Detect media type from extension
            $extension = [System.IO.Path]::GetExtension($absolutePath).ToLower()
            $MediaType = switch ($extension) {
                '.jpg'  { 'image/jpeg' }
                '.jpeg' { 'image/jpeg' }
                '.png'  { 'image/png' }
                '.gif'  { 'image/gif' }
                '.webp' { 'image/webp' }
                default {
                    throw "Unsupported image format: $extension. Supported: .jpg, .jpeg, .png, .gif, .webp"
                }
            }

            # Validate file size before reading (Anthropic limit ~20MB, use 20MB as safe limit)
            $maxSizeBytes = 20MB
            $fileInfo = Get-Item -LiteralPath $absolutePath
            if ($fileInfo.Length -gt $maxSizeBytes) {
                $sizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
                $maxMB = [math]::Round($maxSizeBytes / 1MB, 2)
                throw [AnthropicBadRequestException]::new(
                    "Image file too large: ${sizeMB}MB. Maximum allowed: ${maxMB}MB. Consider resizing the image.",
                    $null
                )
            }

            # Read and encode file
            $bytes = [System.IO.File]::ReadAllBytes($absolutePath)
            $Base64 = [Convert]::ToBase64String($bytes)

            Write-Verbose "Loaded image from $absolutePath ($($bytes.Length) bytes, $MediaType)"
        }

        # Build image content block
        @{
            type   = 'image'
            source = @{
                type       = 'base64'
                media_type = $MediaType
                data       = $Base64
            }
        }
    }
}
