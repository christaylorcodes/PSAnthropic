#Requires -Modules Pester

BeforeAll {
    . $PSScriptRoot\Calculator.ps1
}

Describe 'Calculator Operations' {
    Context 'Addition' {
        It 'Should add 2 + 3 = 5' {
            $result = Invoke-Calculator -NumberA 2 -NumberB 3 -Operation Add
            $result | Should -Be 5  # FAILS: Returns 6 due to bug
        }

        It 'Should add negative numbers' {
            $result = Invoke-Calculator -NumberA -5 -NumberB -3 -Operation Add
            $result | Should -Be -8  # FAILS: Returns -7
        }
    }

    Context 'Subtraction' {
        It 'Should subtract 10 - 3 = 7' {
            $result = Invoke-Calculator -NumberA 10 -NumberB 3 -Operation Subtract
            $result | Should -Be 7  # FAILS: Returns -7 (swapped)
        }
    }

    Context 'Division' {
        It 'Should divide 10 / 3 = 3.33' {
            $result = Invoke-Calculator -NumberA 10 -NumberB 3 -Operation Divide
            $result | Should -BeGreaterThan 3.3  # FAILS: Returns 3 (integer division)
        }

        It 'Should handle division by zero' {
            { Invoke-Calculator -NumberA 10 -NumberB 0 -Operation Divide } | Should -Throw
            # FAILS: No zero check
        }
    }

    Context 'Multiplication' {
        It 'Should multiply 4 * 5 = 20' {
            $result = Invoke-Calculator -NumberA 4 -NumberB 5 -Operation Multiply
            $result | Should -Be 20  # PASSES: Only correct operation
        }
    }
}

Describe 'MathOperations Helpers' {
    Context 'Get-Factorial' {
        It 'Should calculate 5! = 120' {
            $result = Get-Factorial -N 5
            $result | Should -Be 120  # PASSES
        }

        It 'Should calculate 0! = 1' {
            $result = Get-Factorial -N 0
            $result | Should -Be 1  # FAILS: Infinite recursion
        }
    }

    Context 'Get-Percentage' {
        It 'Should calculate 25 of 100 = 25%' {
            $result = Get-Percentage -Part 25 -Whole 100
            $result | Should -Be 25  # FAILS: Returns 400
        }
    }

    Context 'Get-Average' {
        It 'Should handle empty array' {
            { Get-Average -Numbers @() } | Should -Not -Throw
            # FAILS: Division by zero
        }
    }
}

Describe 'Validation Functions' {
    Context 'Test-CalculatorInput' {
        It 'Should reject out of range values' {
            $result = Test-CalculatorInput -A 2000000 -B 1
            $result | Should -Be $false  # FAILS: Always returns $true
        }
    }

    Context 'Test-IsPositive' {
        It 'Should return false for zero' {
            $result = Test-IsPositive -Number 0
            $result | Should -Be $false  # FAILS: Returns $true
        }
    }

    Context 'Test-ArrayNotEmpty' {
        It 'Should handle null gracefully' {
            { Test-ArrayNotEmpty -Items $null } | Should -Not -Throw
            # FAILS: Throws null reference error
        }
    }
}

Describe 'Configuration' {
    Context 'Get-CalculatorConfig' {
        It 'Should have Precision key' {
            $config = Get-CalculatorConfig
            $config.ContainsKey('Precision') | Should -Be $true
            # FAILS: Key is misspelled as 'Prcision'
        }

        It 'Should have numeric MaxValue' {
            $config = Get-CalculatorConfig
            $config.MaxValue | Should -BeOfType [int]
            # FAILS: MaxValue is a string
        }
    }

    Context 'Reset-CalculatorConfig' {
        It 'Should restore original values' {
            Reset-CalculatorConfig
            $config = Get-CalculatorConfig
            $config.Prcision | Should -Be 2
            # FAILS: Reset uses different key name 'Precision'
        }
    }
}
