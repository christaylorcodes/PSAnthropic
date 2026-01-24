# Test script for EML parsing
param([int]$TicketId = 10736115)

# Load helper functions from the demo script
Add-Type -AssemblyName System.Web -ErrorAction Stop

# Dot-source just the functions we need (copy them here to avoid running the whole script)
$scriptPath = Join-Path $PSScriptRoot 'Demo-CWMTicketAssistant.ps1'
$scriptContent = Get-Content $scriptPath -Raw

# Extract and execute just the helper functions region
if ($scriptContent -match '(?s)#region Helper Functions(.+?)#endregion') {
    $helperFunctions = $Matches[1]
    # Create a script block and invoke it to define the functions
    $sb = [scriptblock]::Create($helperFunctions)
    . $sb
}

# Import CWM module
Import-Module ConnectWiseManageAPI -ErrorAction Stop

# Connect using environment variables
if (-not $env:CWM_SERVER) {
    Write-Error "CWM environment variables not set. Need: CWM_SERVER, CWM_COMPANY, CWM_PUBKEY, CWM_PRIVATEKEY, CWM_CLIENTID"
    return
}

Write-Host "Connecting to CWM ($env:CWM_SERVER)..." -ForegroundColor Cyan
Connect-CWM -Server $env:CWM_SERVER -Company $env:CWM_COMPANY -PubKey $env:CWM_PUBKEY -PrivateKey $env:CWM_PRIVATEKEY -ClientID $env:CWM_CLIENTID -Force | Out-Null

# Get documents for the ticket
Write-Host "`nFetching documents for ticket #$TicketId..." -ForegroundColor Cyan
$docs = Get-CWMDocument -recordType 'Ticket' -recordId $TicketId -all

if (-not $docs) {
    Write-Host "No documents found for ticket #$TicketId" -ForegroundColor Yellow
    return
}

Write-Host "Found $($docs.Count) document(s):" -ForegroundColor Green
$docs | Select-Object id, fileName, @{N='SizeKB';E={[math]::Round($_.fileSize/1KB,1)}} | Format-Table -AutoSize

# Filter for EML files
$emlDocs = $docs | Where-Object { $_.fileName -like '*.eml' }
Write-Host "`nEML attachments: $($emlDocs.Count)" -ForegroundColor Cyan

if ($emlDocs.Count -eq 0) {
    Write-Host "No EML files attached to this ticket." -ForegroundColor Yellow
    Write-Host "`nOther attachment types found:"
    $docs | Group-Object { [System.IO.Path]::GetExtension($_.fileName) } |
        Select-Object Name, Count | Format-Table -AutoSize
    return
}

# Parse each EML
Write-Host "`n=== Parsing EML Attachments ===" -ForegroundColor Green
$totalBodyChars = 0

foreach ($doc in $emlDocs) {
    Write-Host "`n--- $($doc.fileName) ---" -ForegroundColor Yellow

    try {
        $emlContent = Get-CWMDocument -id $doc.id -download -ErrorAction Stop

        if ($emlContent) {
            $parsed = ConvertFrom-Eml -Content $emlContent

            if ($parsed) {
                Write-Host "From:    $($parsed.FromName) <$($parsed.FromEmail)>"
                Write-Host "Date:    $($parsed.DateParsed)"
                Write-Host "Subject: $($parsed.Subject)"
                Write-Host "Body:    $($parsed.BodyLength) chars"
                Write-Host ""

                # Show first 200 chars of body
                $preview = if ($parsed.Body.Length -gt 200) {
                    $parsed.Body.Substring(0, 200) + "..."
                } else {
                    $parsed.Body
                }
                Write-Host $preview -ForegroundColor Gray

                $totalBodyChars += $parsed.BodyLength
            }
        }
    }
    catch {
        Write-Warning "Failed to parse: $_"
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Green
Write-Host "Total EML files:     $($emlDocs.Count)"
Write-Host "Total body chars:    $totalBodyChars"
Write-Host "Estimated tokens:    $([math]::Round($totalBodyChars / 4))"

# Cleanup
Disconnect-CWM -ErrorAction SilentlyContinue
