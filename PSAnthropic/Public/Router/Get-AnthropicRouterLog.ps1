function Get-AnthropicRouterLog {
    <#
    .SYNOPSIS
        Reads and analyzes the router log.
    .DESCRIPTION
        Retrieves routing decisions from the log file with optional filtering and statistics.
    .PARAMETER Path
        Path to the log file. If not specified, uses the configured LogPath.
    .PARAMETER Last
        Return only the last N entries.
    .PARAMETER Summary
        Return summary statistics instead of raw log entries.
    .EXAMPLE
        Get-AnthropicRouterLog -Last 10
    .EXAMPLE
        Get-AnthropicRouterLog -Summary
    .EXAMPLE
        # Get stats programmatically
        $stats = Get-AnthropicRouterLog -Summary
        $stats.ByModel['qwen3-coder-8k']  # Count for this model
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter()]
        [int]$Last = 0,

        [Parameter()]
        [switch]$Summary
    )

    # Resolve path
    $logPath = if ($Path) { $Path }
               elseif ($script:AnthropicRouterConfig -and $script:AnthropicRouterConfig.LogPath) {
                   $script:AnthropicRouterConfig.LogPath
               }
               else { throw "No log path specified and router not configured with LogPath" }

    if (-not (Test-Path $logPath)) {
        Write-Warning "Log file not found: $logPath"
        return
    }

    # Read log
    $entries = Import-Csv -Path $logPath

    if (-not $entries -or $entries.Count -eq 0) {
        Write-Warning "Log file is empty: $logPath"
        return
    }

    if ($Last -gt 0) {
        $entries = $entries | Select-Object -Last $Last
    }

    if ($Summary) {
        # Generate statistics with proper hashtable structure
        $byTaskType = @{}
        $entries | Group-Object TaskType | ForEach-Object {
            $byTaskType[$_.Name] = $_.Count
        }

        $byModel = @{}
        $entries | Group-Object Model | ForEach-Object {
            $byModel[$_.Name] = $_.Count
        }

        $stats = @{
            TotalRequests = $entries.Count
            ByTaskType    = $byTaskType
            ByModel       = $byModel
            FirstEntry    = ($entries | Select-Object -First 1).Timestamp
            LastEntry     = ($entries | Select-Object -Last 1).Timestamp
        }

        # Pretty print
        Write-Host "`n=== Router Log Summary ===" -ForegroundColor Cyan
        Write-Host "Total Requests: $($stats.TotalRequests)" -ForegroundColor White
        Write-Host "`nBy Task Type:" -ForegroundColor Yellow
        $entries | Group-Object TaskType | Sort-Object Count -Descending | ForEach-Object {
            Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Gray
        }
        Write-Host "`nBy Model:" -ForegroundColor Yellow
        $entries | Group-Object Model | Sort-Object Count -Descending | ForEach-Object {
            Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Gray
        }
        Write-Host "`nTime Range: $($stats.FirstEntry) to $($stats.LastEntry)" -ForegroundColor DarkGray

        return $stats
    }

    return $entries
}
