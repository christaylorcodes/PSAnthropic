Invoke-RestMethod 'https://assist.itnow.net/Labtech/Transfer/Scripts/LT/AzKeyVault-ITN.ps1' | Invoke-Expression

Import-Module ConnectWiseManageAPI

$null = _Connect-ITNKeyVault
$CWMConnection = _Get-KeyVaultSecret -Auto -Expand -Name 'ConnectWiseManage-Courser' | Convert-JsonToHash
Connect-CWM @CWMConnection -Force
Get-CWMServiceBoard -condition 'name like "ITN*noc*"'
# Get tickets to analyze
$Tickets = Get-CWMTicket -condition 'board/id=420 and closedFlag=false and actualHours > 1'

# Option 1: Analyze each ticket individually
# foreach ($Ticket in $Tickets) {
#     Write-Host "Processing Ticket #$($Ticket.id): $($Ticket.summary)" -ForegroundColor Cyan
#     $params = @{
#         TicketId       = $Ticket.id
#         SkipCWMConnect = $true
#         Verbose        = $true
#     }
#     .\Example\ConnectWise-PSA\Demo-CWMTicketAssistant.ps1 @params
#     Write-Host ''
# }

# Option 2: Analyze tickets and save each to individual JSON files (e.g., 12345.json)
# Note: $PSScriptRoot is empty when running interactively - use explicit path
$repoRoot = 'C:\_Code\PSAnthropic'
$params = @{
    Condition      = 'board/id=420 and closedFlag=false and actualHours > 1'
    MaxTickets     = 10
    SkipCWMConnect = $true
    OutputJsonDir  = Join-Path $repoRoot 'ticket-analysis'
}
& (Join-Path $repoRoot 'Example\ConnectWise-PSA\Demo-CWMTicketAssistant.ps1') @params -Verbose

# =============================================================================
# Test EML Parsing
# =============================================================================

# Load EML parsing functions
Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

function ConvertFrom-QuotedPrintable {
    param([string]$Text)
    if (-not $Text) { return $Text }
    $Text = $Text -replace "=`r?`n", ''
    [regex]::Replace($Text, '=([0-9A-Fa-f]{2})', { param($m) [char][Convert]::ToInt32($m.Groups[1].Value, 16) })
}

function ConvertFrom-Eml {
    param(
        [Parameter(Mandatory, ValueFromPipeline)][string]$Content,
        [switch]$KeepSignature,
        [switch]$KeepQuotedReplies
    )
    process {
        if ([string]::IsNullOrWhiteSpace($Content)) { return $null }
        $Content = $Content -replace '\r\n', "`n" -replace '\r', "`n"
        $splitIndex = $Content.IndexOf("`n`n")
        if ($splitIndex -lt 0) { Write-Warning 'Invalid EML'; return $null }

        $headerBlock = ($Content.Substring(0, $splitIndex)) -replace "`n\s+", ' '
        $body = $Content.Substring($splitIndex + 2)

        $headers = @{}
        foreach ($line in ($headerBlock -split "`n")) {
            if ($line -match '^([^:]+):\s*(.*)$' -and -not $headers.ContainsKey($Matches[1])) {
                $headers[$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }

        $contentType = $headers['Content-Type']
        $encoding = $headers['Content-Transfer-Encoding']

        # Handle multipart
        if ($contentType -match 'multipart/' -and $contentType -match 'boundary="?([^";]+)"?') {
            $boundary = $Matches[1]
            foreach ($part in ($body -split [regex]::Escape("--$boundary"))) {
                if ($part -match '(?i)Content-Type:\s*text/plain' -and $part -match '(?s)\n\n(.+)$') {
                    $body = $Matches[1]
                    if ($part -match '(?i)Content-Transfer-Encoding:\s*quoted-printable') {
                        $body = ConvertFrom-QuotedPrintable $body
                    }
                    break
                }
            }
        }
        elseif ($encoding -match 'quoted-printable') {
            $body = ConvertFrom-QuotedPrintable $body
        }
        elseif ($encoding -match 'base64') {
            try { $body = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($body.Trim())) } catch {}
        }

        $body = [System.Web.HttpUtility]::HtmlDecode($body)
        if (-not $KeepSignature) { $body = ($body -split '(?m)^-- ?\n')[0] }
        if (-not $KeepQuotedReplies) {
            $body = (($body -split "`n") | Where-Object { $_ -notmatch '^\s*>' -and $_ -notmatch '(?i)^On .+ wrote:' }) -join "`n"
        }
        $body = ($body -replace "`n{3,}", "`n`n").Trim()

        $from = $headers['From']
        $dateParsed = try { [datetime]::Parse($headers['Date']) } catch { $null }
        $fromEmail = if ($from -match '<([^>]+)>') { $Matches[1] } else { $from }
        $fromName = if ($from -match '^([^<]+)<') { $Matches[1].Trim() } else { $null }

        [PSCustomObject]@{
            From       = $from
            FromEmail  = $fromEmail
            FromName   = $fromName
            To         = $headers['To']
            Subject    = $headers['Subject']
            Date       = $headers['Date']
            DateParsed = $dateParsed
            Body       = $body
            BodyLength = $body.Length
        }
    }
}
Write-Host 'Loaded EML parsing functions' -ForegroundColor Green

# Test on ticket 10736115
$testTicketId = 10736115

Write-Host "`n=== Testing EML Parsing on Ticket #$testTicketId ===" -ForegroundColor Cyan

# Get documents
$docs = Get-CWMDocument -recordType 'Ticket' -recordId $testTicketId -all
Write-Host "Found $($docs.Count) document(s)" -ForegroundColor Yellow

$docs | Select-Object id, fileName, @{N = 'SizeKB'; E = { [math]::Round($_.fileSize / 1KB, 1) } } | Format-Table -AutoSize

# Filter EML files
$emlDocs = $docs | Where-Object { $_.fileName -like '*.eml' }
Write-Host "EML files: $($emlDocs.Count)" -ForegroundColor Yellow

if ($emlDocs) {
    Write-Host "`nFirst 3 EML docs:" -ForegroundColor Cyan
    $emlDocs | Select-Object -First 3 | ForEach-Object {
        Write-Host "  ID: $($_.id) | File: $($_.fileName) | Size: $($_.fileSize)" -ForegroundColor Gray
    }

    foreach ($doc in $emlDocs | Select-Object -First 3) {
        Write-Host "`n--- $($doc.fileName) ---" -ForegroundColor Green
        Write-Host "Document ID: $($doc.id)" -ForegroundColor Yellow
        Write-Host 'Attempting download...' -ForegroundColor Yellow

        # Check what properties the doc has
        Write-Host "Doc properties: $($doc.PSObject.Properties.Name -join ', ')" -ForegroundColor DarkGray

        try {
            # Try download with verbose
            $emlContent = Get-CWMDocument -id $doc.id -download -Verbose -ErrorAction Stop
            Write-Host "Download result type: $($emlContent.GetType().Name)" -ForegroundColor Yellow
            Write-Host "Content length: $($emlContent.Length) chars" -ForegroundColor Yellow

            if ($emlContent) {
                # Show first 200 chars of raw content
                $rawPreview = if ($emlContent.Length -gt 200) { $emlContent.Substring(0, 200) } else { $emlContent }
                Write-Host "Raw preview:`n$rawPreview" -ForegroundColor DarkGray

                $parsed = ConvertFrom-Eml -Content $emlContent

                if ($parsed) {
                    Write-Host "`nParsed successfully:" -ForegroundColor Green
                    Write-Host "From:    $($parsed.FromName) <$($parsed.FromEmail)>"
                    Write-Host "Date:    $($parsed.DateParsed)"
                    Write-Host "Subject: $($parsed.Subject)"
                    Write-Host "Body:    $($parsed.BodyLength) chars (~$([math]::Round($parsed.BodyLength/4)) tokens)"
                    Write-Host ''
                    # Preview first 300 chars
                    $preview = if ($parsed.Body.Length -gt 300) { $parsed.Body.Substring(0, 300) + '...' } else { $parsed.Body }
                    Write-Host $preview -ForegroundColor Gray
                }
                else {
                    Write-Host 'ConvertFrom-Eml returned null' -ForegroundColor Red
                }
            }
            else {
                Write-Host 'Download returned null/empty' -ForegroundColor Red
            }
        }
        catch {
            Write-Host "ERROR: $_" -ForegroundColor Red
            Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
else {
    Write-Host 'No EML attachments on this ticket' -ForegroundColor Yellow
    Write-Host 'Attachment types found:'
    $docs | Group-Object { [System.IO.Path]::GetExtension($_.fileName) } |
        Select-Object Name, Count | Format-Table -AutoSize
}

# =============================================================================
# Investigate Note Structure - find email indicators
# =============================================================================
Write-Host "`n=== Investigating Note Structure ===" -ForegroundColor Cyan

$notes = Get-CWMTicketNote -parentId $testTicketId -all
Write-Host "Found $($notes.Count) notes" -ForegroundColor Yellow

# Show all properties on first note
if ($notes.Count -gt 0) {
    Write-Host "`nNote properties available:" -ForegroundColor Cyan
    $notes[0].PSObject.Properties | ForEach-Object {
        $val = if ($_.Value) {
            $str = $_.Value.ToString()
            if ($str.Length -gt 50) { $str.Substring(0,50) + '...' } else { $str }
        } else { '(null)' }
        Write-Host "  $($_.Name): $val" -ForegroundColor Gray
    }

    # Look for email-related flags/properties
    Write-Host "`nLooking for email indicators..." -ForegroundColor Cyan
    $emailIndicators = @('email', 'external', 'source', 'flag', 'type', 'document')
    foreach ($note in $notes | Select-Object -First 5) {
        Write-Host "`n--- Note ID: $($note.id) ---" -ForegroundColor Yellow
        foreach ($prop in $note.PSObject.Properties) {
            if ($emailIndicators | Where-Object { $prop.Name -match $_ }) {
                Write-Host "  $($prop.Name): $($prop.Value)" -ForegroundColor Green
            }
        }
        # Show createdBy - might indicate email connector
        Write-Host "  createdBy: $($note.createdBy)" -ForegroundColor Gray
        # Show first 100 chars of text
        $preview = if ($note.text.Length -gt 100) { $note.text.Substring(0,100) + '...' } else { $note.text }
        Write-Host "  text: $preview" -ForegroundColor DarkGray
    }
}