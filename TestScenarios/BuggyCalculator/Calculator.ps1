# Calculator.ps1 - Main entry point
# BUG: This file has issues that span multiple files

. $PSScriptRoot\MathOperations.ps1
. $PSScriptRoot\Validation.ps1
. $PSScriptRoot\Config.ps1

function Invoke-Calculator {
    <#
    .SYNOPSIS
        Main calculator function with multiple bugs to debug.
    .DESCRIPTION
        This calculator has intentional bugs across multiple files.
        Use tools to find and understand the issues.
    #>
    param(
        [Parameter(Mandatory)]
        [double]$NumberA,

        [Parameter(Mandatory)]
        [double]$NumberB,

        [Parameter(Mandatory)]
        [ValidateSet('Add', 'Subtract', 'Multiply', 'Divide')]
        [string]$Operation
    )

    # BUG 1: Validation is called but result is ignored
    $validationResult = Test-CalculatorInput -A $NumberA -B $NumberB
    # Missing: if (-not $validationResult) { return }

    # BUG 2: Config is loaded but maxValue is never enforced
    $config = Get-CalculatorConfig
    Write-Verbose "Max value allowed: $($config.MaxValue)"

    # Call the appropriate operation
    $result = switch ($Operation) {
        'Add'      { Add-Numbers -A $NumberA -B $NumberB }
        'Subtract' { Subtract-Numbers -A $NumberA -B $NumberB }
        'Multiply' { Multiply-Numbers -A $NumberA -B $NumberB }
        'Divide'   { Divide-Numbers -A $NumberA -B $NumberB }
    }

    # BUG 3: Result formatting uses wrong precision from config
    return [math]::Round($result, $config.Prcision)  # Typo: Prcision instead of Precision
}

# Export for module use
Export-ModuleMember -Function Invoke-Calculator -ErrorAction SilentlyContinue
