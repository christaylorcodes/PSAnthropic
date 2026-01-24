function Invoke-AnthropicStandardTool {
    <#
    .SYNOPSIS
        Executes a standard tool based on a tool_use response from the model.
    .DESCRIPTION
        Takes a tool_use object from the model's response and executes the corresponding
        standard tool, returning the result as a string.

        Shell commands (pwsh tool) are executed in an isolated, constrained runspace for security.
        This prevents code injection, .NET type abuse, and restricts available commands to a
        curated safe list.

    .PARAMETER ToolUse
        The tool_use object from the model's response containing name and input.
    .PARAMETER AllowWrite
        Allow write operations (create, str_replace, insert). Default is $false for safety.
    .PARAMETER AllowShell
        Allow shell command execution. Default is $false for safety.
    .PARAMETER AllowWeb
        Allow web fetch operations. Default is $false for safety.
    .PARAMETER Unsafe
        WARNING: Disables all sandboxing for shell commands, using Invoke-Expression directly.
        Only use for testing in controlled environments where you trust all input.
    .PARAMETER InvokeMode
        Controls how tool execution is handled:
        - Auto: Execute tools automatically without prompting (default)
        - Confirm: Prompt user for confirmation before each tool execution
        - None: Do not execute tools, return description of what would be executed
    .PARAMETER TimeoutSeconds
        Maximum execution time for shell commands in seconds. Default is 30.
    .PARAMETER MaxOutputLength
        Maximum length of output to return (default: 10000 characters).
    .PARAMETER AllowedPaths
        Array of allowed root directories for file operations. Paths outside these
        directories will be rejected. Defaults to current directory for security.
        Use -AllowAllPaths to disable path restrictions.
    .PARAMETER AllowAllPaths
        Disables path restrictions, allowing file operations on any accessible path.
        Use with caution - this allows the model to read/write files anywhere.
    .PARAMETER MaxFileSizeBytes
        Maximum file size in bytes for read operations. Default is 10MB.
    .PARAMETER MaxRecursionDepth
        Maximum directory recursion depth for search operations. Default is 10.
    .EXAMPLE
        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell
    .EXAMPLE
        # In a tool use loop with shell access
        $toolUse = $response.content | Where-Object { $_.type -eq 'tool_use' }
        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell
    .EXAMPLE
        # With user confirmation before each execution
        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell -InvokeMode Confirm
    .EXAMPLE
        # Dry-run mode - see what would be executed without running it
        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell -InvokeMode None
    .EXAMPLE
        # UNSAFE: No restrictions - for testing only!
        $result = Invoke-AnthropicStandardTool -ToolUse $toolUse -AllowShell -Unsafe
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$ToolUse,

        [Parameter()]
        [switch]$AllowWrite,

        [Parameter()]
        [switch]$AllowShell,

        [Parameter()]
        [switch]$AllowWeb,

        [Parameter()]
        [switch]$Unsafe,

        [Parameter()]
        [ValidateSet('Auto', 'Confirm', 'None')]
        [string]$InvokeMode = 'Auto',

        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30,

        [Parameter()]
        [int]$MaxOutputLength = 10000,

        [Parameter()]
        [string[]]$AllowedPaths = @((Get-Location).Path),

        [Parameter()]
        [switch]$AllowAllPaths,

        [Parameter()]
        [int]$MaxFileSizeBytes = 10MB,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MaxRecursionDepth = 10
    )

    process {
        $name = $ToolUse.name
        $toolInput = $ToolUse.input

        # Determine effective allowed paths
        $effectiveAllowedPaths = if ($AllowAllPaths) { @() } else { $AllowedPaths }

        # Helper function for path validation
        $validatePath = {
            param([string]$Path, [switch]$MustExist, [switch]$IsDirectory)
            if ($effectiveAllowedPaths.Count -eq 0) {
                # No restrictions
                if ($MustExist -and -not (Test-Path -LiteralPath $Path)) {
                    return @{ Valid = $false; Error = "Path not found: '$Path'" }
                }
                return @{ Valid = $true; ResolvedPath = $Path }
            }
            $params = @{ Path = $Path; AllowedRoots = $effectiveAllowedPaths }
            if ($MustExist) { $params.MustExist = $true }
            if ($IsDirectory) { $params.AllowDirectory = $true; $params.AllowFile = $false }
            return Test-SafePath @params
        }

        # Handle non-Auto modes (only compute description when needed)
        if ($InvokeMode -ne 'Auto') {
            $toolDescription = switch ($name) {
                'pwsh'             { "Execute shell command: $($toolInput.command)" }
                'str_replace_editor' {
                    switch ($toolInput.command) {
                        'view'        { "View file: $($toolInput.path)" }
                        'create'      { "Create file: $($toolInput.path)" }
                        'str_replace' { "Replace text in: $($toolInput.path)" }
                        'insert'      { "Insert at line $($toolInput.insert_line): $($toolInput.path)" }
                        default       { "Editor: $($toolInput.path)" }
                    }
                }
                'read_file'        { "Read: $($toolInput.path)" }
                'list_directory'   { "List: $($toolInput.path)" }
                'search_files'     { "Find '$($toolInput.pattern)' in: $($toolInput.path)" }
                'search_content'   { "Grep '$($toolInput.pattern)' in: $($toolInput.path)" }
                'get_current_time' { "Get current time" }
                'web_fetch'        { "Fetch URL: $($toolInput.url)" }
                default            { "Execute: $name" }
            }

            if ($InvokeMode -eq 'None') {
                return "[DRY RUN] Would execute: $toolDescription"
            }

            # Confirm mode
            $inputJson = $toolInput | ConvertTo-Json -Compress -Depth 3
            if (-not $PSCmdlet.ShouldContinue("Tool: $name`nInput: $inputJson", "Execute tool '$name'?")) {
                return "[SKIPPED] User declined: $toolDescription"
            }
        }

        try {
            $result = switch ($name) {
                'pwsh' {
                    if (-not $AllowShell) {
                        "Error: Shell execution is disabled. Use -AllowShell to enable."
                        break
                    }

                    if ($Unsafe) {
                        # WARNING: Unsafe mode - no restrictions, uses Invoke-Expression directly
                        # Only use for testing in controlled environments!
                        if (-not $PSCmdlet.ShouldProcess(
                            "Execute '$($toolInput.command)' with NO security restrictions",
                            "DANGEROUS: This bypasses all sandboxing and uses Invoke-Expression directly. Only use in controlled testing environments.",
                            "Unsafe Shell Command Execution"
                        )) {
                            "Unsafe command execution cancelled by user"
                            break
                        }
                        Write-Warning "UNSAFE MODE: Executing command with no security restrictions at $(Get-Date -Format 'o')"
                        Write-Warning "Command: $($toolInput.command)"
                        Invoke-PwshToolUnsafe -Command $toolInput.command -WorkingDirectory $toolInput.working_directory
                    }
                    else {
                        Invoke-SafeCommand -Command $toolInput.command `
                            -WorkingDirectory $toolInput.working_directory `
                            -TimeoutSeconds $TimeoutSeconds
                    }
                }

                'str_replace_editor' {
                    # Validate path before editor operations
                    $isCreate = $toolInput.command -eq 'create'
                    $pathCheck = & $validatePath -Path $toolInput.path -MustExist:(-not $isCreate)
                    if (-not $pathCheck.Valid) {
                        $pathCheck.Error
                        break
                    }
                    Invoke-EditorTool -ToolInput $toolInput -AllowWrite:$AllowWrite -ResolvedPath $pathCheck.ResolvedPath
                }

                'read_file' {
                    # Validate path before reading
                    $pathCheck = & $validatePath -Path $toolInput.path -MustExist
                    if (-not $pathCheck.Valid) {
                        $pathCheck.Error
                        break
                    }
                    Invoke-ReadFileTool -Path $pathCheck.ResolvedPath -MaxLines $toolInput.max_lines -MaxFileSizeBytes $MaxFileSizeBytes
                }

                'list_directory' {
                    # Validate directory path
                    $pathCheck = & $validatePath -Path $toolInput.path -MustExist -IsDirectory
                    if (-not $pathCheck.Valid) {
                        $pathCheck.Error
                        break
                    }
                    Invoke-ListDirectoryTool -Path $pathCheck.ResolvedPath -Pattern $toolInput.pattern -Recursive:$toolInput.recursive -MaxDepth $MaxRecursionDepth
                }

                'search_files' {
                    # Validate directory path
                    $pathCheck = & $validatePath -Path $toolInput.path -MustExist -IsDirectory
                    if (-not $pathCheck.Valid) {
                        $pathCheck.Error
                        break
                    }
                    Invoke-SearchFilesTool -Path $pathCheck.ResolvedPath -Pattern $toolInput.pattern -MaxResults ($toolInput.max_results ?? 50) -MaxDepth $MaxRecursionDepth
                }

                'search_content' {
                    # Validate directory path
                    $pathCheck = & $validatePath -Path $toolInput.path -MustExist -IsDirectory
                    if (-not $pathCheck.Valid) {
                        $pathCheck.Error
                        break
                    }
                    Invoke-SearchContentTool -Path $pathCheck.ResolvedPath -Pattern $toolInput.pattern -FilePattern $toolInput.file_pattern -MaxResults ($toolInput.max_results ?? 50) -MaxDepth $MaxRecursionDepth
                }

                'get_current_time' {
                    Invoke-GetTimeTool -Timezone $toolInput.timezone -Format $toolInput.format
                }

                'web_fetch' {
                    if (-not $AllowWeb) {
                        "Error: Web fetch is disabled. Use -AllowWeb to enable."
                        break
                    }
                    Invoke-WebFetchTool -Url $toolInput.url -MaxLength ($toolInput.max_length ?? 50000) -IncludeHeaders:$toolInput.include_headers
                }

                default {
                    "Error: Unknown tool '$name'. Available tools: pwsh, str_replace_editor, read_file, list_directory, search_files, search_content, get_current_time, web_fetch"
                }
            }

            # Truncate if too long
            if ($result.Length -gt $MaxOutputLength) {
                $result = $result.Substring(0, $MaxOutputLength) + "`n... [truncated at $MaxOutputLength characters]"
            }

            return $result
        }
        catch {
            return "Error executing tool '$name': $_"
        }
    }
}

#region Private Tool Implementations

function Invoke-PwshToolUnsafe {
    <#
    .SYNOPSIS
        UNSAFE: Executes PowerShell commands with no restrictions.
    .DESCRIPTION
        WARNING: This function uses Invoke-Expression directly with no safety measures.
        Only use for testing in controlled environments where you trust all input.

        This is the original implementation preserved for testing scenarios where
        the constrained runspace approach causes issues or you need full access.
    #>
    param(
        [string]$Command,
        [string]$WorkingDirectory
    )

    try {
        $originalLocation = Get-Location
        if ($WorkingDirectory -and (Test-Path $WorkingDirectory -PathType Container)) {
            Set-Location $WorkingDirectory
        }

        $output = Invoke-Expression $Command 2>&1 | Out-String

        if ($WorkingDirectory) {
            Set-Location $originalLocation
        }

        if ([string]::IsNullOrWhiteSpace($output)) {
            return "(Command completed successfully with no output)"
        }
        return $output.Trim()
    }
    catch {
        return "Error executing command: $_"
    }
}

function Invoke-EditorTool {
    param(
        [object]$ToolInput,
        [switch]$AllowWrite,
        [string]$ResolvedPath
    )

    $command = $ToolInput.command
    # Use resolved path if provided (already validated), otherwise use original
    $path = if ($ResolvedPath) { $ResolvedPath } else { $ToolInput.path }

    switch ($command) {
        'view' {
            if (-not (Test-Path $path)) {
                return "Error: File not found at '$path'"
            }

            if ($ToolInput.view_range -and $ToolInput.view_range.Count -eq 2) {
                # Optimized: Use -TotalCount to avoid reading entire file
                $startLine = [Math]::Max(1, $ToolInput.view_range[0])
                $endLine = $ToolInput.view_range[1]

                # Read only up to the end line needed
                $allLines = @(Get-Content -Path $path -TotalCount $endLine -ErrorAction Stop)

                if ($allLines.Count -lt $startLine) {
                    return "Error: File has only $($allLines.Count) lines, but view_range starts at line $startLine"
                }

                # Slice to get the requested range (convert to 0-based index)
                $content = $allLines[($startLine - 1)..($allLines.Count - 1)]
                $lineNum = $startLine
            }
            else {
                # Read entire file
                $content = @(Get-Content -Path $path -ErrorAction Stop)
                $lineNum = 1
            }

            # Return with line numbers
            $numbered = $content | ForEach-Object { "{0,4}: {1}" -f $lineNum++, $_ }
            return $numbered -join "`n"
        }

        'create' {
            if (-not $AllowWrite) {
                return "Error: Write operations are disabled. Use -AllowWrite to enable."
            }
            if (Test-Path $path) {
                return "Error: File already exists at '$path'. Use str_replace to modify existing files."
            }
            $parentDir = Split-Path $path -Parent
            if ($parentDir -and -not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            Set-Content -Path $path -Value $ToolInput.file_text -ErrorAction Stop
            return "File created successfully at '$path'"
        }

        'str_replace' {
            if (-not $AllowWrite) {
                return "Error: Write operations are disabled. Use -AllowWrite to enable."
            }
            if (-not (Test-Path $path)) {
                return "Error: File not found at '$path'"
            }
            $content = Get-Content -Path $path -Raw -ErrorAction Stop
            if (-not $content.Contains($ToolInput.old_str)) {
                return "Error: old_str not found in file. Make sure the text matches exactly (including whitespace)."
            }
            $occurrences = ([regex]::Matches($content, [regex]::Escape($ToolInput.old_str))).Count
            if ($occurrences -gt 1) {
                return "Error: old_str found $occurrences times. It must be unique. Add more context to make it unique."
            }
            $newContent = $content.Replace($ToolInput.old_str, $ToolInput.new_str)
            Set-Content -Path $path -Value $newContent -NoNewline -ErrorAction Stop
            return "Successfully replaced text in '$path'"
        }

        'insert' {
            if (-not $AllowWrite) {
                return "Error: Write operations are disabled. Use -AllowWrite to enable."
            }
            if (-not (Test-Path $path)) {
                return "Error: File not found at '$path'"
            }
            $lines = @(Get-Content -Path $path -ErrorAction Stop)
            $insertAt = [Math]::Max(0, [Math]::Min($lines.Count, $ToolInput.insert_line - 1))
            # Handle boundary cases: PowerShell [0..-1] wraps around instead of returning empty
            $before = if ($insertAt -gt 0) { @($lines[0..($insertAt-1)]) } else { @() }
            $after = if ($insertAt -lt $lines.Count) { @($lines[$insertAt..($lines.Count-1)]) } else { @() }
            $newLines = $before + $ToolInput.new_str_for_insert + $after
            Set-Content -Path $path -Value ($newLines -join "`n") -ErrorAction Stop
            return "Successfully inserted text at line $($ToolInput.insert_line) in '$path'"
        }

        default {
            return "Error: Unknown editor command '$command'. Use: view, create, str_replace, or insert"
        }
    }
}

function Invoke-ReadFileTool {
    param(
        [string]$Path,
        [int]$MaxLines,
        [int]$MaxFileSizeBytes = 10MB
    )

    if (-not (Test-Path $Path)) {
        return "Error: File not found at '$Path'"
    }

    # Check file size before reading
    $fileInfo = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($fileInfo -and $fileInfo.Length -gt $MaxFileSizeBytes) {
        $sizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        $maxMB = [math]::Round($MaxFileSizeBytes / 1MB, 2)
        return "Error: File too large (${sizeMB}MB). Maximum allowed: ${maxMB}MB"
    }

    try {
        if ($MaxLines -gt 0) {
            # Use -TotalCount for efficient reading (stops after N lines)
            # Read one extra line to detect if file has more
            $lines = @(Get-Content -Path $Path -TotalCount ($MaxLines + 1) -ErrorAction Stop)

            if ($lines.Count -gt $MaxLines) {
                # File has more lines than requested
                $content = ($lines | Select-Object -First $MaxLines) -join "`n"
                $content += "`n... [truncated at $MaxLines lines]"
            }
            else {
                $content = $lines -join "`n"
            }
        }
        else {
            $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        }
        return $content
    }
    catch {
        return "Error reading file: $_"
    }
}

function Invoke-ListDirectoryTool {
    param(
        [string]$Path,
        [string]$Pattern,
        [switch]$Recursive,
        [int]$MaxDepth = 10
    )

    if (-not (Test-Path $Path -PathType Container)) {
        return "Error: Directory not found at '$Path'"
    }

    try {
        $params = @{
            Path = $Path
            ErrorAction = 'SilentlyContinue'
        }
        if ($Pattern) { $params.Filter = $Pattern }
        if ($Recursive) {
            $params.Recurse = $true
            $params.Depth = $MaxDepth
        }

        $items = Get-ChildItem @params |
            Select-Object @{N='Name';E={if($Recursive){$_.FullName.Replace($Path,'.').TrimStart('.\/')}else{$_.Name}}},
                         @{N='Type';E={if($_.PSIsContainer){'Dir'}else{'File'}}},
                         @{N='Size';E={if(-not $_.PSIsContainer){'{0:N0}' -f $_.Length}}},
                         LastWriteTime |
            Format-Table -AutoSize |
            Out-String

        if ([string]::IsNullOrWhiteSpace($items)) {
            return "Directory is empty or no items match the pattern"
        }
        return $items.Trim()
    }
    catch {
        return "Error listing directory: $_"
    }
}

function Invoke-SearchFilesTool {
    param(
        [string]$Path,
        [string]$Pattern,
        [int]$MaxResults = 50,
        [int]$MaxDepth = 10
    )

    if (-not (Test-Path $Path -PathType Container)) {
        return "Error: Directory not found at '$Path'"
    }

    try {
        $files = Get-ChildItem -Path $Path -Filter $Pattern -Recurse -Depth $MaxDepth -File -ErrorAction SilentlyContinue |
            Select-Object -First $MaxResults |
            ForEach-Object { $_.FullName }

        if (-not $files -or $files.Count -eq 0) {
            return "No files found matching pattern '$Pattern'"
        }

        $result = "Found $($files.Count) file(s):`n" + ($files -join "`n")
        return $result
    }
    catch {
        return "Error searching files: $_"
    }
}

function Invoke-SearchContentTool {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$FilePattern,
        [int]$MaxResults = 50,
        [int]$MaxDepth = 10
    )

    if (-not (Test-Path $Path -PathType Container)) {
        return "Error: Directory not found at '$Path'"
    }

    try {
        $fileParams = @{
            Path = $Path
            Recurse = $true
            Depth = $MaxDepth
            File = $true
            ErrorAction = 'SilentlyContinue'
        }
        if ($FilePattern) { $fileParams.Filter = $FilePattern }

        $files = Get-ChildItem @fileParams

        $results = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $files) {
            if ($results.Count -ge $MaxResults) { break }

            $searchMatches = Select-String -Path $file.FullName -Pattern $Pattern -ErrorAction SilentlyContinue |
                Select-Object -First ($MaxResults - $results.Count)

            foreach ($searchMatch in $searchMatches) {
                $results.Add("{0}:{1}: {2}" -f $searchMatch.Path, $searchMatch.LineNumber, $searchMatch.Line.Trim())
            }
        }

        if ($results.Count -eq 0) {
            return "No matches found for pattern '$Pattern'"
        }

        return "Found $($results.Count) match(es):`n" + ($results -join "`n")
    }
    catch {
        return "Error searching content: $_"
    }
}

function Invoke-GetTimeTool {
    param(
        [string]$Timezone,
        [string]$Format
    )

    try {
        $time = Get-Date

        if ($Timezone) {
            try {
                $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($Timezone)
                $time = [System.TimeZoneInfo]::ConvertTime($time, $tz)
            }
            catch {
                # Try UTC shorthand
                if ($Timezone -eq 'UTC') {
                    $time = $time.ToUniversalTime()
                }
                else {
                    return "Error: Unknown timezone '$Timezone'. Use timezone IDs like 'UTC', 'Pacific Standard Time', 'Eastern Standard Time', etc."
                }
            }
        }

        if ($Format) {
            return $time.ToString($Format)
        }
        else {
            return $time.ToString('yyyy-MM-dd HH:mm:ss') + $(if($Timezone){" ($Timezone)"}else{" (Local)"})
        }
    }
    catch {
        return "Error getting time: $_"
    }
}

function Invoke-WebFetchTool {
    <#
    .SYNOPSIS
        Fetches content from a URL and converts it to readable text.
    .DESCRIPTION
        Retrieves content from HTTP/HTTPS URLs. HTML is converted to plain text,
        JSON is formatted, and other content types are returned as-is.
        Blocks requests to private/internal IP addresses for security.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [int]$MaxLength = 50000,

        [switch]$IncludeHeaders
    )

    try {
        # Validate URL scheme
        $uri = $null
        try {
            $uri = [System.Uri]::new($Url)
        }
        catch {
            return "Error: Invalid URL format"
        }

        if ($uri.Scheme -notin @('http', 'https')) {
            return "Error: URL must use http:// or https://"
        }

        # Block private/internal IP addresses (SSRF protection)
        $urlHost = $uri.Host  # Note: Don't use $host - it's an automatic variable!
        try {
            $addresses = [System.Net.Dns]::GetHostAddresses($urlHost)
            foreach ($addr in $addresses) {
                $bytes = $addr.GetAddressBytes()
                $isPrivate = $false

                if ($addr.AddressFamily -eq 'InterNetwork') {
                    # IPv4 private/reserved ranges:
                    # 0.x.x.x (reserved), 10.x.x.x, 127.x.x.x (loopback)
                    # 169.254.x.x (link-local, cloud metadata), 172.16-31.x.x, 192.168.x.x
                    $isPrivate = ($bytes[0] -eq 0) -or
                                 ($bytes[0] -eq 10) -or
                                 ($bytes[0] -eq 127) -or
                                 ($bytes[0] -eq 169 -and $bytes[1] -eq 254) -or
                                 ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
                                 ($bytes[0] -eq 192 -and $bytes[1] -eq 168)
                }
                elseif ($addr.AddressFamily -eq 'InterNetworkV6') {
                    # IPv6 loopback (::1) or link-local (fe80::)
                    $isPrivate = $addr.IsIPv6LinkLocal -or [System.Net.IPAddress]::IsLoopback($addr)
                }

                if ($isPrivate) {
                    return "Error: Requests to private/internal addresses are blocked"
                }
            }
        }
        catch {
            # DNS resolution failed - let the request fail naturally
        }

        # Fetch content with User-Agent and redirect limit
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 -MaximumRedirection 5 `
            -Headers @{ 'User-Agent' = 'PSAnthropic/1.0 (PowerShell WebFetch Tool)' } -ErrorAction Stop

        $output = [System.Text.StringBuilder]::new()

        # Include headers if requested
        if ($IncludeHeaders) {
            $null = $output.AppendLine("=== Response Headers ===")
            $null = $output.AppendLine("Status: $($response.StatusCode) $($response.StatusDescription)")
            foreach ($header in $response.Headers.Keys) {
                $null = $output.AppendLine("${header}: $($response.Headers[$header])")
            }
            $null = $output.AppendLine("")
            $null = $output.AppendLine("=== Content ===")
        }

        $contentType = $response.Headers['Content-Type'] ?? ''
        $content = $response.Content

        # Reject binary content types
        if ($contentType -match 'image/|audio/|video/|application/octet-stream|application/pdf|application/zip') {
            return "Error: Binary content type '$contentType' is not supported. Only text-based content can be fetched."
        }

        # Process based on content type
        if ($contentType -match 'application/json') {
            # Format JSON for readability
            try {
                $json = $content | ConvertFrom-Json | ConvertTo-Json -Depth 10
                $null = $output.Append($json)
            }
            catch {
                $null = $output.Append($content)
            }
        }
        elseif ($contentType -match 'text/html') {
            # Convert HTML to plain text
            $text = ConvertFrom-Html -Html $content
            $null = $output.Append($text)
        }
        else {
            # Return as-is for other content types
            $null = $output.Append($content)
        }

        $result = $output.ToString()

        # Truncate if too long
        if ($result.Length -gt $MaxLength) {
            $result = $result.Substring(0, $MaxLength) + "`n`n... [truncated at $MaxLength characters]"
        }

        return $result
    }
    catch [System.Net.Http.HttpRequestException] {
        # PowerShell Core uses HttpRequestException
        return "Error: $($_.Exception.Message)"
    }
    catch [System.Net.WebException] {
        # Windows PowerShell uses WebException
        $response = $_.Exception.Response
        if ($response) {
            $statusCode = [int]$response.StatusCode
            return "Error: HTTP $statusCode - $($_.Exception.Message)"
        }
        return "Error: $($_.Exception.Message)"
    }
    catch {
        return "Error fetching URL: $_"
    }
}

function ConvertFrom-Html {
    <#
    .SYNOPSIS
        Converts HTML to readable plain text.
    .DESCRIPTION
        Strips HTML tags, decodes entities, and formats the content for readability.
        Preserves document structure with headings, paragraphs, and lists.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Html
    )

    # Remove script and style blocks entirely (case-insensitive)
    $text = $Html -replace '(?is)<script[^>]*>.*?</script>', ''
    $text = $text -replace '(?is)<style[^>]*>.*?</style>', ''
    $text = $text -replace '(?is)<head[^>]*>.*?</head>', ''
    $text = $text -replace '(?s)<!--.*?-->', ''  # Comments don't need case-insensitive

    # Convert common block elements to newlines
    $text = $text -replace '(?i)<br\s*/?>', "`n"
    $text = $text -replace '(?i)</p>', "`n`n"
    $text = $text -replace '(?i)</div>', "`n"
    $text = $text -replace '(?i)</li>', "`n"
    $text = $text -replace '(?i)<li[^>]*>', '  • '
    $text = $text -replace '(?i)</tr>', "`n"
    $text = $text -replace '(?i)<td[^>]*>', ' | '
    $text = $text -replace '(?i)<th[^>]*>', ' | '

    # Convert headings
    $text = $text -replace '(?i)<h1[^>]*>', "`n`n# "
    $text = $text -replace '(?i)</h1>', "`n"
    $text = $text -replace '(?i)<h2[^>]*>', "`n`n## "
    $text = $text -replace '(?i)</h2>', "`n"
    $text = $text -replace '(?i)<h3[^>]*>', "`n`n### "
    $text = $text -replace '(?i)</h3>', "`n"
    $text = $text -replace '(?i)<h[456][^>]*>', "`n`n#### "
    $text = $text -replace '(?i)</h[456]>', "`n"

    # Remove remaining HTML tags
    $text = $text -replace '<[^>]+>', ''

    # Decode HTML entities
    $text = [System.Net.WebUtility]::HtmlDecode($text)

    # Clean up whitespace
    $text = $text -replace '[ \t]+', ' '           # Collapse horizontal whitespace
    $text = $text -replace '(\r?\n){3,}', "`n`n"   # Collapse multiple blank lines
    $text = $text -replace '(?m)^[ \t]+', ''       # Trim line starts
    $text = $text -replace '(?m)[ \t]+$', ''       # Trim line ends

    return $text.Trim()
}

#endregion
