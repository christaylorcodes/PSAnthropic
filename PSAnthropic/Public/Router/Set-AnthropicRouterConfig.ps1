function Set-AnthropicRouterConfig {
    <#
    .SYNOPSIS
        Configures the model router with task-to-model mappings.
    .DESCRIPTION
        Sets up routing rules that map task types to specific models.
        Also configures logging for routing decisions.
    .PARAMETER Models
        Hashtable mapping task types to model names.
        Required keys: Default. Optional: Code, Vision, Complex, Fast, Creative.
    .PARAMETER LogPath
        Path to log file for routing decisions. If not specified, no file logging.
    .PARAMETER LogToConsole
        Write routing decisions to console (verbose).
    .EXAMPLE
        Set-AnthropicRouterConfig -Models @{
            Default = 'llama3.1-8k'
            Code    = 'qwen3-coder-8k'
            Vision  = 'llama3.2-vision:11b'
        }
    .EXAMPLE
        Set-AnthropicRouterConfig -Models @{
            Default = 'llama3.1-8k'
            Code    = 'qwen3-coder-8k'
        } -LogPath './router.log' -LogToConsole
    .EXAMPLE
        # Test with -WhatIf
        Set-AnthropicRouterConfig -Models @{ Default = 'llama3' } -LogPath './test.log' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            if (-not $_.ContainsKey('Default')) {
                throw "Models hashtable must contain a 'Default' key"
            }
            foreach ($key in $_.Keys) {
                if ([string]::IsNullOrWhiteSpace($_[$key])) {
                    throw "Model name for task '$key' cannot be empty"
                }
                if ($_[$key] -isnot [string]) {
                    throw "Model name for task '$key' must be a string, got: $($_[$key].GetType().Name)"
                }
            }
            $true
        })]
        [hashtable]$Models,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [switch]$LogToConsole
    )

    # Initialize or update router config
    $newConfig = @{
        Models       = $Models
        LogPath      = $LogPath
        LogToConsole = $LogToConsole.IsPresent
        CreatedAt    = Get-Date
    }

    # Create log file with header if specified
    if ($LogPath) {
        $logDir = Split-Path $LogPath -Parent
        if (-not [string]::IsNullOrEmpty($logDir) -and -not (Test-Path $logDir)) {
            if ($PSCmdlet.ShouldProcess($logDir, 'Create log directory')) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
        }

        if (-not (Test-Path $LogPath)) {
            if ($PSCmdlet.ShouldProcess($LogPath, 'Create router log file with CSV header')) {
                $header = "Timestamp,TaskType,Model,MessagePreview,Reason"
                $header | Out-File -FilePath $LogPath -Encoding UTF8
            }
        }
    }

    if ($PSCmdlet.ShouldProcess('AnthropicRouterConfig', 'Set router configuration')) {
        # Initialize thread-safe lock if not already created
        if (-not $script:RouterConfigLock) {
            $script:RouterConfigLock = [System.Threading.ReaderWriterLockSlim]::new()
        }

        # Thread-safe config update
        $script:RouterConfigLock.EnterWriteLock()
        try {
            $script:AnthropicRouterConfig = $newConfig
        }
        finally {
            $script:RouterConfigLock.ExitWriteLock()
        }

        $modelMappings = $Models.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
        Write-Verbose "Router configured with $($Models.Count) mappings: $($modelMappings -join ', ')"

        return $script:AnthropicRouterConfig
    }
}
