# Validation.ps1 - Input validation functions
# Contains bugs related to validation logic

function Test-CalculatorInput {
    param(
        [double]$A,
        [double]$B
    )

    $errors = @()

    # BUG 1: Logic error - should be -gt not -lt
    if ($A -lt -1000000 -or $A -gt 1000000) {
        $errors += "Number A ($A) is out of range"
    }

    # BUG 2: Typo in variable name ($B vs $b)
    if ($b -lt -1000000 -or $B -gt 1000000) {
        $errors += "Number B ($B) is out of range"
    }

    # BUG 3: Returns $true even if there are errors
    if ($errors.Count -gt 0) {
        Write-Warning ($errors -join "`n")
        return $true  # Should return $false
    }

    return $true
}

function Test-IsPositive {
    param([double]$Number)

    # BUG: Doesn't handle zero correctly (0 is not positive)
    return $Number -ge 0  # Should be -gt 0
}

function Test-IsInteger {
    param([double]$Number)

    # BUG: Truncation comparison is wrong
    return $Number -eq [int]$Number  # This fails for large numbers
}

function Test-IsInRange {
    param(
        [double]$Number,
        [double]$Min,
        [double]$Max
    )

    # BUG: Parameters Min and Max can be swapped without error
    return $Number -ge $Min -and $Number -le $Max
}

function Test-ArrayNotEmpty {
    param([array]$Items)

    # BUG: Null check is missing - will throw on $null
    return $Items.Count -gt 0
}

function Format-ValidationError {
    param(
        [string]$FieldName,
        [string]$Message,
        [string]$Value
    )

    # BUG: Missing closing bracket in format string
    return "[$FieldName Error: $Message (value=$Value"
}
