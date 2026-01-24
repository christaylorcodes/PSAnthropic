<#
    .SYNOPSIS
        Local pre-push validation script.

    .DESCRIPTION
        Run this script before pushing to catch issues early.
        Validates build, code quality, and tests locally.

    .PARAMETER SkipBuild
        Skip the build step.

    .PARAMETER SkipTests
        Skip the Pester tests.

    .PARAMETER SkipAnalyze
        Skip the PSScriptAnalyzer checks.
#>
param(
    [switch]$SkipBuild,
    [switch]$SkipTests,
    [switch]$SkipAnalyze
)

$ErrorActionPreference = 'Stop'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "LOCAL PRE-PUSH VALIDATION" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Add RequiredModules to path if they exist
if (Test-Path "output/RequiredModules") {
    $env:PSModulePath = (Resolve-Path "output/RequiredModules").Path + [IO.Path]::PathSeparator + $env:PSModulePath
}

$stepCount = 3
$currentStep = 0

# 1. BUILD
if (-not $SkipBuild) {
    $currentStep++
    Write-Host "[$currentStep/$stepCount] Building module..." -ForegroundColor Yellow

    try {
        & ./build-sampler.ps1 -Tasks build
        if ($LASTEXITCODE -ne 0) {
            throw "Build returned exit code $LASTEXITCODE"
        }
        Write-Host "BUILD PASSED`n" -ForegroundColor Green
    }
    catch {
        Write-Host "BUILD FAILED: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "[SKIP] Build step skipped`n" -ForegroundColor DarkGray
}

# 2. PSScriptAnalyzer
if (-not $SkipAnalyze) {
    $currentStep++
    Write-Host "[$currentStep/$stepCount] Running PSScriptAnalyzer..." -ForegroundColor Yellow

    try {
        Import-Module PSScriptAnalyzer -ErrorAction Stop

        $analyzerParams = @{
            Path     = 'PSAnthropic'
            Recurse  = $true
        }

        if (Test-Path 'PSScriptAnalyzerSettings.psd1') {
            $analyzerParams.Settings = 'PSScriptAnalyzerSettings.psd1'
        }

        $results = Invoke-ScriptAnalyzer @analyzerParams

        if ($results) {
            $results | Format-Table -AutoSize
            $errors = $results | Where-Object Severity -eq 'Error'

            if ($errors) {
                throw "PSScriptAnalyzer found $($errors.Count) error(s)"
            }
            else {
                Write-Host "PSScriptAnalyzer found $($results.Count) warning(s) (no errors)`n" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "PSScriptAnalyzer PASSED - no issues found`n" -ForegroundColor Green
        }
    }
    catch [System.IO.FileNotFoundException] {
        Write-Host "PSScriptAnalyzer not installed, skipping...`n" -ForegroundColor Yellow
        Write-Host "  Run: Install-Module PSScriptAnalyzer -Scope CurrentUser`n" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "PSScriptAnalyzer FAILED: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "[SKIP] PSScriptAnalyzer step skipped`n" -ForegroundColor DarkGray
}

# 3. TESTS
if (-not $SkipTests) {
    $currentStep++
    Write-Host "[$currentStep/$stepCount] Running Pester tests..." -ForegroundColor Yellow

    try {
        & ./build-sampler.ps1 -Tasks test
        if ($LASTEXITCODE -ne 0) {
            throw "Tests returned exit code $LASTEXITCODE"
        }
        Write-Host "TESTS PASSED`n" -ForegroundColor Green
    }
    catch {
        Write-Host "TESTS FAILED: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "[SKIP] Pester tests skipped`n" -ForegroundColor DarkGray
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "ALL LOCAL CHECKS PASSED!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green
Write-Host "Ready to push to GitHub`n"
