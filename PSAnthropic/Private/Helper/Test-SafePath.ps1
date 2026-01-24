function Test-SafePath {
    <#
    .SYNOPSIS
        Validates that a path is within allowed directories and optionally exists.
    .DESCRIPTION
        Security helper that validates file/directory paths against a list of
        allowed root directories. Resolves paths to absolute form to prevent
        directory traversal attacks (e.g., ../../etc/passwd).

        Returns a hashtable with:
        - Valid: $true if path is allowed, $false otherwise
        - ResolvedPath: The resolved absolute path (if valid)
        - Error: Error message (if not valid)
    .PARAMETER Path
        The path to validate.
    .PARAMETER AllowedRoots
        Array of allowed root directories. If empty, all paths are allowed.
    .PARAMETER MustExist
        If specified, the path must exist.
    .PARAMETER AllowDirectory
        If specified, allows directories. Default is to allow both files and directories.
    .PARAMETER AllowFile
        If specified, allows files. Default is to allow both files and directories.
    .EXAMPLE
        Test-SafePath -Path ".\data\file.txt" -AllowedRoots @("C:\Project") -MustExist

        Validates that the path resolves to within C:\Project and exists.
    .EXAMPLE
        Test-SafePath -Path "..\..\etc\passwd" -AllowedRoots @("C:\Project")

        Returns @{ Valid = $false; Error = "Path '..\..\etc\passwd' is outside allowed directories" }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string[]]$AllowedRoots = @(),

        [Parameter()]
        [switch]$MustExist,

        [Parameter()]
        [switch]$AllowDirectory,

        [Parameter()]
        [switch]$AllowFile
    )

    # If neither specified, allow both
    if (-not $AllowDirectory -and -not $AllowFile) {
        $AllowDirectory = $true
        $AllowFile = $true
    }

    try {
        # Resolve to absolute path (handles .., ., etc.)
        # Use GetFullPath which resolves without requiring the path to exist
        $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return @{
            Valid = $false
            Error = "Invalid path format: '$Path'"
        }
    }

    # Check against allowed roots if specified
    if ($AllowedRoots.Count -gt 0) {
        $isAllowed = $false

        foreach ($root in $AllowedRoots) {
            try {
                $resolvedRoot = [System.IO.Path]::GetFullPath($root)
                # Ensure root ends with separator for proper prefix matching
                if (-not $resolvedRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
                    $resolvedRoot += [System.IO.Path]::DirectorySeparatorChar
                }

                # Check if path starts with root (case-insensitive on Windows)
                if ($resolvedPath.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase) -or
                    $resolvedPath.Equals($resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
                    $isAllowed = $true
                    break
                }
            }
            catch {
                # Invalid root path, skip
                continue
            }
        }

        if (-not $isAllowed) {
            return @{
                Valid = $false
                Error = "Path '$Path' is outside allowed directories"
            }
        }
    }

    # Check existence if required
    if ($MustExist) {
        if (-not (Test-Path -LiteralPath $resolvedPath)) {
            return @{
                Valid = $false
                Error = "Path not found: '$Path'"
            }
        }

        # Check type if existence is required
        $item = Get-Item -LiteralPath $resolvedPath -ErrorAction SilentlyContinue
        if ($item) {
            $isDirectory = $item.PSIsContainer
            if ($isDirectory -and -not $AllowDirectory) {
                return @{
                    Valid = $false
                    Error = "Path is a directory but only files are allowed: '$Path'"
                }
            }
            if (-not $isDirectory -and -not $AllowFile) {
                return @{
                    Valid = $false
                    Error = "Path is a file but only directories are allowed: '$Path'"
                }
            }
        }
    }

    return @{
        Valid = $true
        ResolvedPath = $resolvedPath
    }
}
