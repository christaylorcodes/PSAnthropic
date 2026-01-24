function Write-AnthropicRouterLog {
    <#
    .SYNOPSIS
        Logs routing decisions for analysis.
    .DESCRIPTION
        Internal function to log model routing decisions to file and/or console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskType,

        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter()]
        [string]$MessagePreview = '',

        [Parameter()]
        [string]$Reason = ''
    )

    $config = $script:AnthropicRouterConfig
    if (-not $config) { return }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Console logging
    if ($config.LogToConsole) {
        Write-Host "[Router] " -ForegroundColor Cyan -NoNewline
        Write-Host "$TaskType " -ForegroundColor Yellow -NoNewline
        Write-Host "-> " -ForegroundColor DarkGray -NoNewline
        Write-Host "$Model" -ForegroundColor Green -NoNewline
        Write-Host " ($Reason)" -ForegroundColor DarkGray
    }

    # File logging (CSV format)
    if ($config.LogPath) {
        # Escape CSV fields and prevent CSV injection (formulas starting with =, +, -, @)
        $escapedPreview = $MessagePreview
        if ($escapedPreview -match '^[=+\-@]') {
            $escapedPreview = "'" + $escapedPreview
        }
        $escapedPreview = $escapedPreview -replace '"', '""'

        $escapedReason = $Reason
        if ($escapedReason -match '^[=+\-@]') {
            $escapedReason = "'" + $escapedReason
        }
        $escapedReason = $escapedReason -replace '"', '""'

        $logLine = "$timestamp,$TaskType,$Model,`"$escapedPreview`",`"$escapedReason`""

        # Use mutex to prevent concurrent write corruption
        $mutex = $null
        try {
            # Create named mutex for cross-process file locking
            $mutexName = "PSAnthropic_RouterLog_" + ($config.LogPath -replace '[\\/:*?"<>|]', '_')
            $mutex = [System.Threading.Mutex]::new($false, $mutexName)

            # Wait up to 5 seconds for lock
            if ($mutex.WaitOne(5000)) {
                try {
                    $logLine | Out-File -FilePath $config.LogPath -Append -Encoding UTF8
                }
                finally {
                    $mutex.ReleaseMutex()
                }
            }
            else {
                Write-Warning "Timeout waiting for router log mutex - log entry skipped"
            }
        }
        catch {
            Write-Warning "Failed to write to router log: $_"
        }
        finally {
            if ($mutex) { $mutex.Dispose() }
        }
    }
}
