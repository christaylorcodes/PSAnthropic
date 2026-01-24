<#
.SYNOPSIS
    Generates markdown documentation for PSAnthropic using PlatyPS.

.DESCRIPTION
    This script generates markdown help files for all exported functions
    in the PSAnthropic module using PlatyPS.

.PARAMETER OutputPath
    The path where documentation will be generated. Defaults to 'docs/en-US'.

.PARAMETER UpdateExisting
    If specified, updates existing markdown files rather than regenerating.

.EXAMPLE
    ./build-docs.ps1
    Generates fresh documentation in docs/en-US/

.EXAMPLE
    ./build-docs.ps1 -UpdateExisting
    Updates existing documentation files with any changes.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'docs' 'en-US'),

    [switch]$UpdateExisting
)

$ErrorActionPreference = 'Stop'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PLATYPS DOCUMENTATION GENERATION" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Ensure platyPS is available
if (-not (Get-Module -ListAvailable -Name platyPS)) {
    Write-Host "Installing platyPS module..." -ForegroundColor Yellow
    Install-Module -Name platyPS -Force -Scope CurrentUser
}

Import-Module platyPS -Force

# Remove any existing module from session
Get-Module PSAnthropic | Remove-Module -Force -ErrorAction SilentlyContinue

# Load classes first (required for OutputType resolution in Get-Help)
$classesPath = Join-Path $PSScriptRoot 'PSAnthropic' 'Classes.ps1'
Write-Host "Loading classes from: $classesPath" -ForegroundColor Gray
. $classesPath

# Import the source module (not the built one)
$modulePath = Join-Path $PSScriptRoot 'PSAnthropic'
Write-Host "Importing module from: $modulePath" -ForegroundColor Gray
Import-Module $modulePath -Force

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputPath)) {
    Write-Host "Creating output directory: $OutputPath" -ForegroundColor Gray
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$module = Get-Module PSAnthropic
Write-Host "Module loaded: $($module.Name) v$($module.Version)" -ForegroundColor Green
Write-Host "Exported functions: $($module.ExportedFunctions.Count)" -ForegroundColor Gray

if ($UpdateExisting -and (Get-ChildItem $OutputPath -Filter '*.md' -ErrorAction SilentlyContinue)) {
    Write-Host "`nUpdating existing documentation..." -ForegroundColor Yellow
    Update-MarkdownHelpModule -Path $OutputPath -RefreshModulePage -AlphabeticParamsOrder
}
else {
    Write-Host "`nGenerating new documentation..." -ForegroundColor Yellow

    # Generate markdown for each function
    $params = @{
        Module                = 'PSAnthropic'
        OutputFolder          = $OutputPath
        AlphabeticParamsOrder = $true
        WithModulePage        = $true
        ExcludeDontShow       = $true
        Encoding              = [System.Text.Encoding]::UTF8
    }

    New-MarkdownHelp @params -Force
}

# Count generated files
$docFiles = Get-ChildItem $OutputPath -Filter '*.md'
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "DOCUMENTATION GENERATED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Output: $OutputPath" -ForegroundColor Gray
Write-Host "Files:  $($docFiles.Count) markdown files" -ForegroundColor Gray

# List generated files
Write-Host "`nGenerated files:" -ForegroundColor Cyan
$docFiles | ForEach-Object {
    Write-Host "  - $($_.Name)" -ForegroundColor Gray
}

Write-Host "`nTo generate MAML help (for Get-Help):" -ForegroundColor Yellow
Write-Host "  New-ExternalHelp -Path '$OutputPath' -OutputPath 'PSAnthropic/en-US'" -ForegroundColor Gray
