# Config.ps1 - Calculator configuration
# Contains configuration issues

$script:CalculatorConfig = @{
    # BUG 1: Typo in key name (Prcision vs Precision)
    Prcision  = 2

    # BUG 2: MaxValue is a string, not a number
    MaxValue  = "999999"

    # BUG 3: Boolean stored as string
    EnableLogging = "true"

    # Correct values for reference
    Version   = "1.0.0"
    Author    = "Test"
}

function Get-CalculatorConfig {
    <#
    .SYNOPSIS
        Returns the calculator configuration.
    .DESCRIPTION
        Note: This config has intentional issues:
        - Prcision is misspelled
        - MaxValue is a string
        - EnableLogging is a string "true" not $true
    #>
    return $script:CalculatorConfig
}

function Set-CalculatorConfig {
    param(
        [hashtable]$NewConfig
    )

    # BUG: Doesn't validate config keys before merging
    foreach ($key in $NewConfig.Keys) {
        $script:CalculatorConfig[$key] = $NewConfig[$key]
    }

    # BUG: Doesn't return the updated config
}

function Reset-CalculatorConfig {
    # BUG: Hardcoded values don't match original $script:CalculatorConfig
    $script:CalculatorConfig = @{
        Precision = 3      # Spelled correctly here but wrong elsewhere
        MaxValue  = 100000 # Different value than original
        EnableLogging = $false
    }
}

function Test-ConfigValue {
    param(
        [string]$Key,
        [object]$ExpectedValue
    )

    # BUG: Uses -eq which does type coercion ("true" -eq $true is $true)
    return $script:CalculatorConfig[$Key] -eq $ExpectedValue
}
