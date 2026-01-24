# MathOperations.ps1 - Math helper functions
# Contains bugs that affect Calculator.ps1

function Add-Numbers {
    param([double]$A, [double]$B)

    # BUG: Off-by-one error (adds 1 extra)
    return $A + $B + 1
}

function Subtract-Numbers {
    param([double]$A, [double]$B)

    # BUG: Parameters are swapped (B - A instead of A - B)
    return $B - $A
}

function Multiply-Numbers {
    param([double]$A, [double]$B)

    # This one is correct
    return $A * $B
}

function Divide-Numbers {
    param([double]$A, [double]$B)

    # BUG 1: No zero division check
    # BUG 2: Integer division issue (casting to int truncates)
    return [int]($A / $B)
}

function Get-Factorial {
    param([int]$N)

    # BUG: Infinite recursion - missing base case for N = 0
    if ($N -eq 1) { return 1 }
    return $N * (Get-Factorial -N ($N - 1))
}

function Get-Average {
    param([double[]]$Numbers)

    # BUG: Doesn't handle empty array
    $sum = ($Numbers | Measure-Object -Sum).Sum
    return $sum / $Numbers.Count  # Division by zero if empty
}

function Get-Percentage {
    param(
        [double]$Part,
        [double]$Whole
    )

    # BUG: Formula is inverted (gives wrong percentage)
    return ($Whole / $Part) * 100  # Should be Part / Whole
}
