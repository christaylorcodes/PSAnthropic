<#
.SYNOPSIS
    AI-powered ConnectWise Manage ticket analyzer using Ollama.

.DESCRIPTION
    Fetches tickets from ConnectWise Manage, gathers notes/history, and uses
    Ollama (via PSAnthropic) to provide intelligent analysis including:
    - Summary of the ticket and its history
    - Technical fix suggestions
    - Recommended next steps
    - Customer communication draft
    - Status/priority change recommendations

.PARAMETER TicketId
    Specific ticket ID to analyze. If not provided, uses -Condition to search.

.PARAMETER Condition
    ConnectWise condition syntax to find tickets. Default: "status/name='New'"

.PARAMETER MaxTickets
    Maximum number of tickets to analyze when using -Condition. Default: 5

.PARAMETER AddAsNote
    If specified, posts the AI analysis back to the ticket as an internal note.

.PARAMETER OutputJsonDir
    Directory to save analysis results as JSON. Each ticket is saved as {ticketId}.json.

.PARAMETER CWMServer
    ConnectWise Manage server URL. Default: $env:CWM_SERVER

.PARAMETER CWMCompany
    ConnectWise company identifier. Default: $env:CWM_COMPANY

.PARAMETER CWMPubKey
    API public key. Default: $env:CWM_PUBKEY

.PARAMETER CWMPrivateKey
    API private key. Default: $env:CWM_PRIVATEKEY

.PARAMETER CWMClientID
    API client ID. Default: $env:CWM_CLIENTID

.PARAMETER SkipCWMConnect
    If specified, skips connecting to CWM (assumes an existing connection).

.PARAMETER OllamaServer
    Ollama server address. Default: localhost:11434

.PARAMETER AnalysisModel
    Model for ticket analysis. Default: qwen3-coder-32k:latest

.EXAMPLE
    .\Demo-CWMTicketAssistant.ps1 -TicketId 45123

    Analyzes a specific ticket by ID.

.EXAMPLE
    .\Demo-CWMTicketAssistant.ps1 -Condition "status/name='New'" -MaxTickets 10

    Analyzes up to 10 tickets with 'New' status.

.EXAMPLE
    .\Demo-CWMTicketAssistant.ps1 -TicketId 45123 -AddAsNote

    Analyzes the ticket and posts the AI analysis as an internal note.

.NOTES
    Requires:
    - PSAnthropic module
    - ConnectWiseManageAPI module
    - Ollama running with specified model
    - Valid CWM API credentials
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [int]$TicketId = 0,

    [Parameter()]
    [string]$Condition = "status/name='New'",

    [Parameter()]
    [int]$MaxTickets = 5,

    [Parameter()]
    [switch]$AddAsNote,

    [Parameter()]
    [string]$OutputJsonDir,

    [Parameter()]
    [switch]$SkipCWMConnect,

    # CWM Connection
    [Parameter()]
    [string]$CWMServer = $env:CWM_SERVER,

    [Parameter()]
    [string]$CWMCompany = $env:CWM_COMPANY,

    [Parameter()]
    [string]$CWMPubKey = $env:CWM_PUBKEY,

    [Parameter()]
    [string]$CWMPrivateKey = $env:CWM_PRIVATEKEY,

    [Parameter()]
    [string]$CWMClientID = $env:CWM_CLIENTID,

    # Ollama Connection
    [Parameter()]
    [string]$OllamaServer = 'localhost:11434',

    [Parameter()]
    [string]$AnalysisModel = 'qwen3-coder-32k:latest'
)

#region Script-Scoped Initialization

# Load System.Web assembly once at script start (used for HTML decoding)
Add-Type -AssemblyName System.Web -ErrorAction Stop

# MSP workflow template patterns (compiled once for performance)
$script:MspPatterns = @(
    '(?i)TROUBLESHOOTING\s*\|\s*WORK PERFORMED\s*'
    '(?i)Glue Docs? (?:used to resolve this issue|referenced):?.*'
    '(?i)OUR NEXT STEPS:.*'
    '(?i)Called Client\s*\\?\(?y/?n?\\?\)?:?\s*\w*'
    '(?i)Emailed Client\s*\\?\(?y/?n?\\?\)?:?\s*\w*'
    '(?i)i\.?t\.?GLUE UPDATED:.*'
    '(?i)Documentation Updated:.*'
    '(?i)Summary Updated\??:.*'
    '(?i)Configuration added to ticket:.*'
    '(?i)Login info:.*'
    '(?i)Additional Notes:.*'
    '(?i)GLUE Link\\?\(?s?\\?\)? used:.*'
    '(?i)Suspected cause\\?\(?s?\\?\)?:.*'
    '(?i)Specific work to be performed:.*'
    '(?i)Problem description:.*'
    '(?i)Troubleshooting/Steps.*completed so far:.*'
    '(?i)Previous pre-authorization.*\?.*'
    '(?i)(?:putting in\s*)?waiting client response\s*'
    '(?i)Other References:.*'
    '(?i)TODAY WE ASSESSED:.*'
    '(?i)SOLUTION:.*'
    '(?i)Date/Time REQUIRED:.*'
    '(?i)Tech to escalate to:.*'
    '(?i)Priority:\s*P\d.*'
    '(?i)BEST Contact Info:.*'
    '(?i)WE NEED THE FOLLOWING FROM YOU:.*'
    '(?i)THINGS YOU CAN TRY IN THE MEANTIME:.*'
    "(?i)We've Left A Voice Mail"
    "(?i)We'll Continue To Follow-up"
    '(?i)NEW Message from i\.t\.NOW'
    '(?i)THIS IS AN AUTOMATED REMINDER'
    '(?i)Please review the last email from the technician.*'
    '(?i)Service Record #\d+.*'
    '(?i)Get \[Outlook for iOS\]\('
    '(?i)Get \[Outlook for Android\]\('
    '(?i)If there is a window of time you would like to schedule.*'
    '(?i)Changing status to.*'
    '(?i)Keeping status at.*'
    '(?i)Caller Name\s*\(First/Last\):.*'
    '(?i)Best Contact Number/Ext:.*'
    '(?i)Best Contact Email:.*'
    '(?i)Is this a new issue.*'
    '(?i)\(ie: New Workstation\).*'
    '(?i)Do you know if others are affected.*'
    '(?i)How does this impact your work:.*'
    '(?i)i\.t\.NOW Management ID/Hostname:.*'
    '(?i)Do you pre-authorize i\.t\.NOW.*'
    '(?i)We still may need you to be present.*'
    '(?i)Ticket number provided to client:.*'
    '(?i)Scheduling for\s+\w+.*'
    '(?i)Downgrading to P\d.*'
)

#endregion

#region Helper Functions

function ConvertFrom-Eml {
    <#
    .SYNOPSIS
        Parses EML (email) content into a structured object with clean body text.
    .DESCRIPTION
        Extracts headers (From, To, Subject, Date, Message-ID, threading info) and
        body content from raw EML data. Handles quoted-printable encoding, strips
        signatures and quoted replies, and extracts plain text from multipart messages.
    .PARAMETER Content
        Raw EML content as a string (e.g., from Get-CWMDocument -download).
    .PARAMETER Path
        Path to an .eml file.
    .PARAMETER KeepSignature
        Keep email signatures (after "-- " delimiter). By default, signatures are removed.
    .PARAMETER KeepQuotedReplies
        Keep quoted reply lines (starting with ">"). By default, quoted replies are removed.
    .EXAMPLE
        $emlContent = Get-CWMDocument -id $doc.id -download
        $email = ConvertFrom-Eml -Content $emlContent
    .EXAMPLE
        Get-ChildItem *.eml | ConvertFrom-Eml
    #>
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Content', ValueFromPipeline)]
        [string]$Content,

        [Parameter(Mandatory, ParameterSetName = 'Path', ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$Path,

        [Parameter()]
        [switch]$KeepSignature,

        [Parameter()]
        [switch]$KeepQuotedReplies
    )

    process {
        # Load content from file if path provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $Content = Get-Content -Path $Path -Raw -Encoding UTF8
        }

        if ([string]::IsNullOrWhiteSpace($Content)) {
            Write-Warning 'Empty EML content'
            return $null
        }

        # Normalize line endings
        $Content = $Content -replace '\r\n', "`n" -replace '\r', "`n"

        # Split headers from body (first blank line)
        $splitIndex = $Content.IndexOf("`n`n")
        if ($splitIndex -lt 0) {
            Write-Warning 'Invalid EML format: no header/body separator found'
            return $null
        }

        $headerBlock = $Content.Substring(0, $splitIndex)
        $bodyRaw = $Content.Substring($splitIndex + 2)

        # === PARSE HEADERS ===
        # Unfold continued headers (lines starting with whitespace are continuations)
        $headerBlock = $headerBlock -replace "`n\s+", ' '

        $headers = @{}
        foreach ($line in ($headerBlock -split "`n")) {
            if ($line -match '^([^:]+):\s*(.*)$') {
                $headerName = $Matches[1].Trim()
                $headerValue = $Matches[2].Trim()
                # Store first occurrence (some headers repeat)
                if (-not $headers.ContainsKey($headerName)) {
                    $headers[$headerName] = $headerValue
                }
            }
        }

        # Extract common headers with fallbacks
        $from = $headers['From']
        $to = $headers['To']
        $subject = $headers['Subject']
        $date = $headers['Date']
        $messageId = $headers['Message-ID'] -replace '[<>]', ''
        $inReplyTo = $headers['In-Reply-To'] -replace '[<>]', ''
        $references = $headers['References'] -replace '[<>]', '' -split '\s+'
        $contentType = $headers['Content-Type']
        $transferEncoding = $headers['Content-Transfer-Encoding']

        # === EXTRACT BODY ===
        $body = $bodyRaw

        # Handle multipart messages - extract text/plain part
        if ($contentType -match 'multipart/') {
            # Extract boundary
            if ($contentType -match 'boundary="?([^";]+)"?') {
                $boundary = $Matches[1]
                $parts = $body -split [regex]::Escape("--$boundary")

                # Find text/plain part (prefer it over text/html)
                $textPart = $null
                foreach ($part in $parts) {
                    if ($part -match '(?i)Content-Type:\s*text/plain') {
                        # Extract body after headers in this part
                        if ($part -match '(?s)\n\n(.+)$') {
                            $textPart = $Matches[1]
                            # Check for encoding in this part
                            if ($part -match '(?i)Content-Transfer-Encoding:\s*quoted-printable') {
                                $textPart = ConvertFrom-QuotedPrintable -Text $textPart
                            }
                            break
                        }
                    }
                }

                if ($textPart) {
                    $body = $textPart
                }
                else {
                    # Fallback: try to find any readable text part
                    foreach ($part in $parts) {
                        if ($part -match '(?s)\n\n(.+)$' -and $part -notmatch '(?i)Content-Type:\s*text/html') {
                            $body = $Matches[1]
                            break
                        }
                    }
                }
            }
        }
        elseif ($transferEncoding -match 'quoted-printable') {
            $body = ConvertFrom-QuotedPrintable -Text $body
        }
        elseif ($transferEncoding -match 'base64') {
            try {
                $body = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($body.Trim()))
            }
            catch {
                Write-Warning "Failed to decode base64 body: $_"
            }
        }

        # === CLEAN BODY ===
        # Decode any remaining HTML entities
        $body = [System.Web.HttpUtility]::HtmlDecode($body)

        # Strip signature (standard delimiter: "-- " on its own line)
        if (-not $KeepSignature) {
            $body = ($body -split '(?m)^-- ?\n')[0]
        }

        # Strip quoted replies (lines starting with >)
        if (-not $KeepQuotedReplies) {
            $lines = $body -split "`n"
            $cleanLines = [System.Collections.ArrayList]::new()
            $inQuoteBlock = $false

            foreach ($line in $lines) {
                # Detect "On ... wrote:" pattern that precedes quotes
                if ($line -match '(?i)^On .+ wrote:\s*$') {
                    $inQuoteBlock = $true
                    continue
                }
                # Skip quoted lines
                if ($line -match '^\s*>') {
                    $inQuoteBlock = $true
                    continue
                }
                # Reset quote block if we hit non-quoted content
                if ($inQuoteBlock -and $line -match '\S' -and $line -notmatch '^\s*>') {
                    $inQuoteBlock = $false
                }

                if (-not $inQuoteBlock) {
                    $cleanLines.Add($line) | Out-Null
                }
            }
            $body = $cleanLines -join "`n"
        }

        # Final cleanup
        $body = $body -replace "`n{3,}", "`n`n"  # Collapse multiple blank lines
        $body = $body.Trim()

        # Parse date if possible
        $parsedDate = $null
        if ($date) {
            try {
                $parsedDate = [datetime]::Parse($date)
            }
            catch {
                # Try common email date formats
                $formats = @(
                    'ddd, d MMM yyyy HH:mm:ss zzz',
                    'ddd, dd MMM yyyy HH:mm:ss zzz',
                    'd MMM yyyy HH:mm:ss zzz'
                )
                foreach ($fmt in $formats) {
                    try {
                        $parsedDate = [datetime]::ParseExact($date.Substring(0, [Math]::Min($date.Length, 31)), $fmt, $null)
                        break
                    }
                    catch { }
                }
            }
        }

        # Extract clean email address from "Name <email>" format
        $fromEmail = if ($from -match '<([^>]+)>') { $Matches[1] } else { $from }
        $fromName = if ($from -match '^([^<]+)<') { $Matches[1].Trim() } else { $null }

        [PSCustomObject]@{
            MessageId    = $messageId
            InReplyTo    = $inReplyTo
            References   = $references | Where-Object { $_ }
            From         = $from
            FromEmail    = $fromEmail
            FromName     = $fromName
            To           = $to
            Subject      = $subject
            Date         = $date
            DateParsed   = $parsedDate
            Body         = $body
            BodyLength   = $body.Length
            Headers      = $headers
        }
    }
}

function ConvertFrom-QuotedPrintable {
    <#
    .SYNOPSIS
        Decodes quoted-printable encoded text.
    #>
    param([string]$Text)

    if (-not $Text) { return $Text }

    # Remove soft line breaks (=\n)
    $Text = $Text -replace "=`n", ''
    $Text = $Text -replace "=\r\n", ''

    # Decode =XX hex sequences
    $result = [regex]::Replace($Text, '=([0-9A-Fa-f]{2})', {
        param($match)
        [char][Convert]::ToInt32($match.Groups[1].Value, 16)
    })

    return $result
}

function Get-TicketEmailThread {
    <#
    .SYNOPSIS
        Fetches and parses all EML attachments from a CWM ticket into a clean email thread.
    .DESCRIPTION
        Retrieves all .eml file attachments from a ticket, parses them using ConvertFrom-Eml,
        and returns them sorted by date. This provides a clean email thread with proper
        threading information (Message-ID, In-Reply-To) and stripped signatures/quotes.
    .PARAMETER TicketId
        The CWM ticket ID to fetch attachments from.
    .EXAMPLE
        $emailThread = Get-TicketEmailThread -TicketId 10736115
        $emailThread | ForEach-Object { "[$($_.DateParsed)] $($_.FromName): $($_.Body)" }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('id')]
        [int]$TicketId
    )

    process {
        # Fetch all documents attached to the ticket
        $docs = Get-CWMDocument -recordType 'Ticket' -recordId $TicketId -all -ErrorAction SilentlyContinue

        if (-not $docs) {
            Write-Verbose "No documents found for ticket #$TicketId"
            return @()
        }

        # Filter for EML files
        $emlDocs = $docs | Where-Object { $_.fileName -like '*.eml' }

        if (-not $emlDocs) {
            Write-Verbose "No EML attachments found for ticket #$TicketId"
            return @()
        }

        Write-Verbose "Found $($emlDocs.Count) EML attachment(s) for ticket #$TicketId"

        $emails = [System.Collections.ArrayList]::new()

        foreach ($doc in $emlDocs) {
            try {
                # Download the EML content
                $emlContent = Get-CWMDocument -id $doc.id -download -ErrorAction Stop

                if ($emlContent) {
                    $parsed = ConvertFrom-Eml -Content $emlContent
                    if ($parsed) {
                        # Add document metadata
                        $parsed | Add-Member -NotePropertyName 'DocumentId' -NotePropertyValue $doc.id -Force
                        $parsed | Add-Member -NotePropertyName 'FileName' -NotePropertyValue $doc.fileName -Force
                        $emails.Add($parsed) | Out-Null
                    }
                }
            }
            catch {
                Write-Warning "Failed to parse EML attachment '$($doc.fileName)' (doc ID $($doc.id)): $_"
            }
        }

        # Sort by date and return
        $emails | Sort-Object { $_.DateParsed ?? [datetime]::MinValue }
    }
}

function Optimize-NoteText {
    <#
    .SYNOPSIS
        Cleans up note text by removing signatures, images, boilerplate, and excessive formatting.
    #>
    param([string]$Text)

    if (-not $Text) { return $null }

    $cleaned = $Text

    # === PHASE 1: Normalize encoding ===
    # Decode HTML entities using .NET (assembly loaded at script start)
    $cleaned = [System.Web.HttpUtility]::HtmlDecode($cleaned)
    # Normalize CWM escape sequences
    $cleaned = $cleaned -replace '\\\*', '*'
    $cleaned = $cleaned -replace '\\n', "`n"

    # === PHASE 2: Remove structural boilerplate ===
    # Hash separators - remove any sequence of 4+ hashes
    $cleaned = $cleaned -replace '[#]{4,}', ''
    # Asterisk separators - remove any sequence of 4+ asterisks
    $cleaned = $cleaned -replace '[*]{4,}', ''
    # Other repeated characters (====, ----, ____) - remove entire line
    $cleaned = $cleaned -replace '(?m)^\s*[=_-]{4,}\s*(\r?\n)?', ''
    # Ticket Escalation/Resolution templates with trailing asterisks
    $cleaned = $cleaned -replace '(?i)Ticket (?:Escalation|Resolution)\*+', ''
    # Voicemail/Follow-up templates with asterisks on both sides
    $cleaned = $cleaned -replace "(?i)\*+We've Left A Voice Mail\*+", ''
    $cleaned = $cleaned -replace "(?i)\*+We'll Continue To Follow-up\*+", ''
    # Message wrappers: "NEW Message from i.t.NOW******************" (asterisks at end)
    $cleaned = $cleaned -replace '(?i)NEW Message from i\.t\.NOW\s*\*+', ''
    # Also handle asterisks on both sides: ****...NEW Message...****
    $cleaned = $cleaned -replace '(?s)\*{4,}.*?(?:NEW Message|from i\.t\.NOW).*?\*{4,}', ''
    # Generic asterisk-wrapped lines (****text**** or ****)
    $cleaned = $cleaned -replace '\*{4,}[^*\n]*\*{4,}', ''
    # Replied/Original/Forwarded message headers and email thread headers
    $cleaned = $cleaned -replace '(?i)-{2,}\s*(?:Replied|Original|Forwarded)\s+Message\s*-{2,}', ''
    # Email thread headers (From: ... Sent: ... To: ... Subject:) - match across lines
    $cleaned = $cleaned -replace '(?m)^From:.*\r?\n(?:(?:Sent|To|Cc|Subject):.*\r?\n)*', ''
    # [External] email markers
    $cleaned = $cleaned -replace '(?i)\[External\]', ''
    $cleaned = $cleaned -replace '(?i)\\?\[External\\?\]', ''
    # Image tags and broken markdown links
    $cleaned = $cleaned -replace '!\[.*?\]\(.*?\)', ''
    $cleaned = $cleaned -replace '\[\]\([^)]*\)?', ''
    # Broken links with text but no URL: [text]( or [text](url-missing
    $cleaned = $cleaned -replace '\[[^\]]+\]\(\s*\)', ''
    $cleaned = $cleaned -replace '\[[^\]]+\]\([^)]*$', ''
    # Mailto links: [email](mailto:email) -> email
    $cleaned = $cleaned -replace '\[([^\]]+)\]\(mailto:[^)]+\)', '$1'
    # Telephone links: [number](tel:...) -> number
    $cleaned = $cleaned -replace '\[([^\]]+)\]\(tel:[^)]+\)', '$1'
    # IT Glue links: [Title — IT Glue](url) -> remove entirely
    $cleaned = $cleaned -replace '\[[^\]]*IT Glue[^\]]*\]\([^)]*\)?', ''
    # Microsoft Learn links
    $cleaned = $cleaned -replace '\[[^\]]*Microsoft Learn[^\]]*\]\([^)]*\)?', ''
    # Broken website links: [www.site.com]( -> www.site.com
    $cleaned = $cleaned -replace '\[(www\.[^\]]+)\]\([^)]*\)?', '$1'
    # Links with just URL as text: [url](url) or [url]( -> url
    $cleaned = $cleaned -replace '\[(https?://[^\]]+)\]\([^)]*\)?', '$1'
    $cleaned = $cleaned -replace '<img[^>]*>', ''

    # === PHASE 3: Remove MSP workflow templates ===
    # Note: Patterns are defined in $script:MspPatterns for performance
    foreach ($pattern in $script:MspPatterns) {
        $cleaned = $cleaned -replace $pattern, ''
    }

    # Remove Google review request blocks
    $cleaned = $cleaned -replace '(?s)If you would give us a 5-star review.*?We make IT look easy!', ''
    $cleaned = $cleaned -replace '(?s)Upon closing your request.*?how we are doing!', ''

    # Remove automated reminder blocks
    $cleaned = $cleaned -replace '(?s)Dear \w+,\s*Your service ticket #\d+.*?await your response.*?\.', ''

    # Remove embedded ticket discussion threads (replies that quote the full ticket)
    $cleaned = $cleaned -replace '(?s)This ticket has been updated by.*?(?=\n\n[A-Z]|\z)', ''

    # Remove i.t.NOW service desk footer blocks
    $cleaned = $cleaned -replace '(?s)i\.t\.NOW Service Desk.*?(?:O\n|F\n).*?(?=\n\n|\z)', ''
    $cleaned = $cleaned -replace '(?s)Serving: With you on the path to success!.*?(?=\n\n|\z)', ''

    # === PHASE 4: Remove email warnings and confidentiality ===
    $cleaned = $cleaned -replace '(?s)CAUTION: This email originated.*?organization\.', ''
    $cleaned = $cleaned -replace '(?s)\[EXTERNAL\].*?(?=\n\n)', ''
    $cleaned = $cleaned -replace '(?s)CONFIDENTIALITY STATEMENT:.*?(?=\n\n|\z)', ''
    $cleaned = $cleaned -replace '(?s)CONFIDENTIAL HEALTH INFORMATION:.*?(?=\n\n|\z)', ''

    # === PHASE 5: Remove signatures ===
    # Tech signatures: "Thank you,\nName\nTitle | i.t.NOW\nPhone"
    $cleaned = $cleaned -replace '(?s)Thank you,?\s*\n\w+\s+\w+\s*\n.*?i\.t\.NOW.*?(?:\d{3}[-.)]\d{3}[-.)]\d{4})?', ''
    # MSP signature: "Thank you,\n\ni.t.NOW" or just "i.t.NOW" at end
    $cleaned = $cleaned -replace '(?s)(?:Thank you,|Thanks,)?\s*\n*\s*i\.t\.NOW\s*$', ''
    # Standard signatures: "Regards,\nName\nTitle..." - limit to signature block (name + a few lines)
    $cleaned = $cleaned -replace '(?m)^(?:Regards|Best|Thanks|Sincerely|Cheers),?\s*\r?\n[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*(?:\r?\n[^\r\n]{0,60}){0,4}\s*$', ''
    # Dash separator signatures: "-- \n..." to end of text
    $cleaned = $cleaned -replace '(?m)^--\s*\r?\n[\s\S]*$', ''
    # Chase Baird signature block
    $cleaned = $cleaned -replace '(?s)Chase Baird\s*\|\s*IT Manager.*?84106', ''

    # === PHASE 6: Clean up formatting ===
    # Bold markdown: **text** -> text, then italic *text* -> text
    $cleaned = $cleaned -replace '\*\*([^*]+)\*\*', '$1'
    $cleaned = $cleaned -replace '\*([^*\n]+)\*', '$1'
    # Contact info lines
    $cleaned = $cleaned -replace '(?i)(?:Cell|Tel|Phone|Fax|Mobile):\s*[\d\-\.\(\)\s]+', ''
    $cleaned = $cleaned -replace '(?i)https?://[^\s]+', ''
    # Normalize whitespace
    $cleaned = $cleaned -replace '\r\n', "`n"
    $cleaned = $cleaned -replace '\n{3,}', "`n`n"
    $cleaned = $cleaned -replace '[ \t]+\n', "`n"
    $cleaned = $cleaned.Trim()

    # Return null if empty
    if ([string]::IsNullOrWhiteSpace($cleaned)) { return $null }

    return $cleaned
}

function Group-SimilarNotes {
    <#
    .SYNOPSIS
        Consolidates duplicate/similar notes (e.g., follow-up attempts) into single entries.
    #>
    param(
        [Parameter(Mandatory)]
        [object[]]$Notes,

        [Parameter()]
        [double]$SimilarityThreshold = 0.85
    )

    if (-not $Notes -or $Notes.Count -eq 0) { return @() }

    # Helper: Calculate simple similarity ratio between two strings
    function Get-TextSimilarity {
        param([string]$Text1, [string]$Text2)

        if (-not $Text1 -or -not $Text2) { return 0 }

        # Normalize for comparison
        $t1 = $Text1.ToLower() -replace '\s+', ' ' -replace '\d{1,2}[:/]\d{2}', '[TIME]' -replace '\d{4}-\d{2}-\d{2}', '[DATE]'
        $t2 = $Text2.ToLower() -replace '\s+', ' ' -replace '\d{1,2}[:/]\d{2}', '[TIME]' -replace '\d{4}-\d{2}-\d{2}', '[DATE]'

        if ($t1 -eq $t2) { return 1.0 }

        # Use shorter text as base for comparison
        $shorter = if ($t1.Length -le $t2.Length) { $t1 } else { $t2 }
        $longer = if ($t1.Length -le $t2.Length) { $t2 } else { $t1 }

        # If shorter is contained in longer, high similarity
        if ($longer.Contains($shorter)) {
            return [math]::Min(1.0, $shorter.Length / $longer.Length + 0.3)
        }

        # Word-based Jaccard similarity
        $words1 = $t1 -split '\s+' | Where-Object { $_.Length -gt 2 }
        $words2 = $t2 -split '\s+' | Where-Object { $_.Length -gt 2 }

        if ($words1.Count -eq 0 -or $words2.Count -eq 0) { return 0 }

        $set1 = [System.Collections.Generic.HashSet[string]]::new([string[]]$words1)
        $set2 = [System.Collections.Generic.HashSet[string]]::new([string[]]$words2)

        $intersection = [System.Collections.Generic.HashSet[string]]::new($set1)
        $intersection.IntersectWith($set2)

        $union = [System.Collections.Generic.HashSet[string]]::new($set1)
        $union.UnionWith($set2)

        return $intersection.Count / $union.Count
    }

    $consolidated = [System.Collections.ArrayList]::new()
    $processed = [System.Collections.Generic.HashSet[int]]::new()

    for ($i = 0; $i -lt $Notes.Count; $i++) {
        if ($processed.Contains($i)) { continue }

        $current = $Notes[$i]
        $similarGroup = @($current)
        $processed.Add($i) | Out-Null

        # Find similar notes
        for ($j = $i + 1; $j -lt $Notes.Count; $j++) {
            if ($processed.Contains($j)) { continue }

            $candidate = $Notes[$j]

            # Must be same type to consolidate
            if ($current.type -ne $candidate.type) { continue }

            $similarity = Get-TextSimilarity -Text1 $current.text -Text2 $candidate.text
            if ($similarity -ge $SimilarityThreshold) {
                $similarGroup += $candidate
                $processed.Add($j) | Out-Null
            }
        }

        # If multiple similar notes found, consolidate
        if ($similarGroup.Count -gt 1) {
            $sortedGroup = $similarGroup | Sort-Object date
            $authors = ($sortedGroup | ForEach-Object { $_.author } | Select-Object -Unique) -join ', '

            # Use PSCustomObject for reliable JSON serialization
            $consolidated.Add([PSCustomObject]@{
                type      = 'followUp'
                count     = [int]$similarGroup.Count
                firstDate = [string]$sortedGroup[0].date
                lastDate  = [string]$sortedGroup[-1].date
                authors   = [string]$authors
                text      = [string]$sortedGroup[0].text  # Use first occurrence
            }) | Out-Null
        }
        else {
            $consolidated.Add($current) | Out-Null
        }
    }

    return $consolidated.ToArray()
}

function Remove-BoldMarkdown {
    <#
    .SYNOPSIS
        Strips bold markdown (**text**) from a string.
    #>
    param([string]$Text)
    if ($Text) { $Text -replace '\*\*([^*]+)\*\*', '$1' } else { $null }
}

function Format-TicketForAI {
    <#
    .SYNOPSIS
        Formats a CWM ticket, notes, and time entries as JSON for AI consumption.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Ticket,

        [Parameter()]
        [object[]]$Notes,

        [Parameter()]
        [object[]]$TimeEntries
    )

    # Build structured ticket object with explicit types for reliable serialization
    $ticketData = [ordered]@{
        id            = [int]$Ticket.id
        summary       = [string]$Ticket.summary
        status        = Remove-BoldMarkdown $Ticket.status.name
        priority      = Remove-BoldMarkdown $Ticket.priority.name
        board         = Remove-BoldMarkdown $Ticket.board.name
        company       = Remove-BoldMarkdown $Ticket.company.name
        contact       = Remove-BoldMarkdown $Ticket.contact.name
        owner         = Remove-BoldMarkdown $Ticket.owner.name
        type          = Remove-BoldMarkdown $Ticket.type.name
        subType       = Remove-BoldMarkdown $Ticket.subType.name
        source        = Remove-BoldMarkdown $Ticket.source.name
        dateEntered   = if ($Ticket.dateEntered) { $Ticket.dateEntered.ToString('o') } else { $null }
        description   = if ($Ticket.initialDescription) { [string]$Ticket.initialDescription } else { $null }
        internalNotes = if ($Ticket.initialInternalAnalysis) { [string]$Ticket.initialInternalAnalysis } else { $null }
        resolution    = if ($Ticket.initialResolution) { [string]$Ticket.initialResolution } else { $null }
    }

    # Build notes array (clean text and filter empty)
    $notesArray = [System.Collections.ArrayList]::new()
    if ($Notes -and $Notes.Count -gt 0) {
        foreach ($note in $Notes | Sort-Object dateCreated) {
            $cleanedText = Optimize-NoteText -Text $note.text

            # Skip notes that are empty after cleaning
            if (-not $cleanedText) { continue }

            $noteType = if ($note.internalAnalysisFlag) { 'internal' }
                        elseif ($note.resolutionFlag) { 'resolution' }
                        elseif ($note.detailDescriptionFlag) { 'detail' }
                        elseif ($note.externalFlag) { 'external' }
                        else { 'note' }

            # Use PSCustomObject for reliable JSON serialization
            $noteEntry = [PSCustomObject]@{
                type   = [string]$noteType
                date   = if ($note.dateCreated) { $note.dateCreated.ToString('o') } else { $null }
                author = if ($note.createdBy) { [string]$note.createdBy } else { 'System' }
                text   = $cleanedText
            }
            $notesArray.Add($noteEntry) | Out-Null
        }

        # Consolidate duplicate/similar notes (e.g., follow-up attempts)
        if ($notesArray.Count -gt 1) {
            $notesArray = Group-SimilarNotes -Notes $notesArray
        }
    }

    # Build time entries array
    $timeArray = [System.Collections.ArrayList]::new()
    if ($TimeEntries -and $TimeEntries.Count -gt 0) {
        foreach ($entry in $TimeEntries | Sort-Object timeStart) {
            $cleanedNotes = Optimize-NoteText -Text $entry.notes

            # Use PSCustomObject for reliable JSON serialization
            $timeEntry = [PSCustomObject]@{
                date     = if ($entry.timeStart) { $entry.timeStart.ToString('o') } else { $null }
                member   = if ($entry.member) { [string]$entry.member.name } else { $null }
                hours    = [double]$entry.actualHours
                billable = [string]$entry.billableOption
                workType = if ($entry.workType) { [string]$entry.workType.name } else { $null }
                notes    = $cleanedNotes
            }
            $timeArray.Add($timeEntry) | Out-Null
        }

        # Consolidate duplicate time entries (e.g., repeated follow-up checks)
        # Convert notes->text for compatibility with Group-SimilarNotes, then convert back
        if ($timeArray.Count -gt 1) {
            $tempForGrouping = $timeArray | ForEach-Object {
                [PSCustomObject]@{
                    type     = 'timeEntry'
                    date     = $_.date
                    member   = $_.member
                    hours    = $_.hours
                    billable = $_.billable
                    workType = $_.workType
                    text     = $_.notes  # Group-SimilarNotes expects 'text'
                }
            }
            $grouped = Group-SimilarNotes -Notes $tempForGrouping -SimilarityThreshold 0.90

            # Convert back to notes property
            $timeArray = $grouped | ForEach-Object {
                if ($_.count) {
                    # Consolidated entry
                    [PSCustomObject]@{
                        date     = $_.firstDate
                        member   = $_.authors
                        hours    = $_.count * 0.03  # Approximate, since we lose individual hours
                        billable = 'Billable'
                        workType = 'Remote Support'
                        notes    = "$($_.text) (repeated $($_.count)x from $($_.firstDate) to $($_.lastDate))"
                    }
                }
                else {
                    # Regular entry - convert text back to notes
                    [PSCustomObject]@{
                        date     = $_.date
                        member   = $_.member
                        hours    = $_.hours
                        billable = $_.billable
                        workType = $_.workType
                        notes    = $_.text
                    }
                }
            }
        }
    }

    # Combine into final structure using PSCustomObject for reliable serialization
    $output = [PSCustomObject]@{
        ticket      = [PSCustomObject]$ticketData
        notes       = @($notesArray)
        timeEntries = @($timeArray)
    }

    # Use higher depth for reliable JSON
    return ($output | ConvertTo-Json -Depth 10)
}

function Write-TicketHeader {
    <#
    .SYNOPSIS
        Writes a formatted ticket header to the console.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Ticket
    )

    $title = "TICKET #$($Ticket.id): $($Ticket.summary)"
    if ($title.Length -gt 70) {
        $title = $title.Substring(0, 67) + '...'
    }

    $border = [string]::new([char]0x2550, $title.Length + 4)

    Write-Host ''
    Write-Host ([char]0x2554 + $border + [char]0x2557) -ForegroundColor Cyan
    Write-Host ([char]0x2551 + " $title " + [char]0x2551) -ForegroundColor Cyan
    Write-Host ([char]0x255A + $border + [char]0x255D) -ForegroundColor Cyan

    $owner = if ($Ticket.owner) { $Ticket.owner.name } else { 'Unassigned' }
    $contact = if ($Ticket.contact) { $Ticket.contact.name } else { 'N/A' }
    $company = if ($Ticket.company) { $Ticket.company.name } else { 'Unknown' }

    Write-Host "Company: $company | Contact: $contact | Status: $($Ticket.status.name) | Priority: $($Ticket.priority.name)" -ForegroundColor Gray
    Write-Host "Owner: $owner | Board: $($Ticket.board.name)" -ForegroundColor Gray
    Write-Host ''
}

#endregion

#region System Prompt

$SystemPrompt = @'
You are an IT service desk analyst helping technicians work tickets efficiently at a Managed Service Provider (MSP).

You will receive ticket data in JSON format with three main sections:
- "ticket": Contains ticket metadata (id, summary, status, priority, company, contact, owner, description, etc.)
- "notes": Array of all notes/communications on the ticket, each with type, date, author, and text
- "timeEntries": Array of time worked on the ticket, each with date, member, hours, workType, and notes

Analyze the ticket AND all notes thoroughly, then provide a structured response with ALL of these sections:

## Summary
Brief 2-3 sentence overview of the issue and its current state based on the ticket and notes.

## Technical Assessment
- Root cause analysis: What's likely causing this issue?
- Technical fix steps: Numbered, specific actions to resolve
- Tools/access needed: What does the tech need?
- Estimated complexity: Simple / Moderate / Complex

## Recommended Next Steps
Prioritized action list for the technician. Be specific and actionable.

## Customer Communication
Draft a professional message to send to the customer. Be clear, set expectations, and maintain a helpful tone.

## Status Recommendation
Current: [current status from ticket]
Recommended: [suggested status]
Reason: Why change or keep the current status

## Priority Assessment
Current: [current priority from ticket]
Recommended: [suggested priority]
Reason: If a change is needed, explain why. If keeping current, confirm it's appropriate.

Keep responses focused and actionable. Avoid unnecessary verbosity.
'@

#endregion

#region Main Script

try {
    # Import modules
    Write-Host 'Loading modules...' -ForegroundColor Cyan

    # Look for PSAnthropic module relative to script location (repo structure)
    $exampleDir = Split-Path $PSScriptRoot -Parent
    $repoRoot = Split-Path $exampleDir -Parent
    $psAnthropicPath = Join-Path $repoRoot 'PSAnthropic'

    if (Test-Path $psAnthropicPath) {
        Import-Module $psAnthropicPath -Force
    }
    else {
        Import-Module PSAnthropic -Force
    }

    if (-not $SkipCWMConnect) {
        Import-Module ConnectWiseManageAPI -Force
    }

    # Connect to CWM (unless already connected externally)
    if (-not $SkipCWMConnect) {
        # Validate required parameters
        $missingParams = @()
        if (-not $CWMServer) { $missingParams += 'CWMServer (or $env:CWM_SERVER)' }
        if (-not $CWMCompany) { $missingParams += 'CWMCompany (or $env:CWM_COMPANY)' }
        if (-not $CWMPubKey) { $missingParams += 'CWMPubKey (or $env:CWM_PUBKEY)' }
        if (-not $CWMPrivateKey) { $missingParams += 'CWMPrivateKey (or $env:CWM_PRIVATEKEY)' }
        if (-not $CWMClientID) { $missingParams += 'CWMClientID (or $env:CWM_CLIENTID)' }

        if ($missingParams.Count -gt 0) {
            throw "Missing required parameters: $($missingParams -join ', ')"
        }

        Write-Host "Connecting to ConnectWise Manage ($CWMServer)..." -ForegroundColor Cyan

        $cwmParams = @{
            Server     = $CWMServer
            Company    = $CWMCompany
            PubKey     = $CWMPubKey
            PrivateKey = $CWMPrivateKey
            ClientID   = $CWMClientID
        }
        Connect-CWM @cwmParams -Force | Out-Null
    }
    else {
        Write-Host 'Using existing CWM connection...' -ForegroundColor Cyan
    }

    # Connect to Ollama
    Write-Host "Connecting to Ollama ($OllamaServer)..." -ForegroundColor Cyan
    Write-Host "  Model: $AnalysisModel" -ForegroundColor Gray
    Connect-Anthropic -Server $OllamaServer -Model $AnalysisModel

    # Start model warmup in background (first request can be slow while model loads)
    Write-Host 'Warming up model (background)...' -ForegroundColor Gray
    $warmupStart = Get-Date
    $warmupJob = Start-ThreadJob -ScriptBlock {
        param($Server, $Model)
        Import-Module PSAnthropic -Force
        Connect-Anthropic -Server $Server -Model $Model
        Invoke-AnthropicMessage -Messages @(
            New-AnthropicMessage -Role 'user' -Content 'Reply with OK'
        ) -MaxTokens 10
    } -ArgumentList $OllamaServer, $AnalysisModel

    # Fetch tickets (while model warms up)
    Write-Host 'Fetching tickets...' -ForegroundColor Cyan

    # Fields to retrieve from CWM
    $ticketFields = @(
        'id', 'summary', 'status', 'priority', 'board', 'company', 'contact',
        'owner', 'type', 'source', 'dateEntered', 'initialDescription'
    )

    if ($TicketId -gt 0) {
        $tickets = @(Get-CWMTicket -id $TicketId -fields $ticketFields)
        if (-not $tickets -or $tickets.Count -eq 0) {
            throw "Ticket #$TicketId not found"
        }
    }
    else {
        $tickets = Get-CWMTicket -condition $Condition -pageSize $MaxTickets
        if (-not $tickets -or $tickets.Count -eq 0) {
            Write-Host "No tickets found matching condition: $Condition" -ForegroundColor Yellow
            return
        }
    }

    Write-Host "Found $($tickets.Count) ticket(s) to analyze." -ForegroundColor Green

    # Wait for model warmup to complete
    $null = $warmupJob | Wait-Job
    if ($warmupJob.State -eq 'Failed') {
        $warmupError = $warmupJob | Receive-Job -ErrorAction SilentlyContinue
        Remove-Job $warmupJob -Force
        throw "Failed to warm up model '$AnalysisModel': $warmupError"
    }
    $warmupJob | Remove-Job -Force
    $warmupTime = ((Get-Date) - $warmupStart).TotalSeconds
    Write-Host "Model ready ($([math]::Round($warmupTime, 1))s)`n" -ForegroundColor Green

    # Ensure output directory exists if specified
    if ($OutputJsonDir) {
        if (-not (Test-Path $OutputJsonDir)) {
            New-Item -Path $OutputJsonDir -ItemType Directory -Force | Out-Null
            Write-Host "Created output directory: $OutputJsonDir" -ForegroundColor Gray
        }
    }

    # Process each ticket
    foreach ($ticket in $tickets) {
        Write-TicketHeader -Ticket $ticket

        # Get notes
        Write-Host 'Fetching notes...' -ForegroundColor Gray
        try {
            $notes = @(Get-CWMTicketNote -parentId $ticket.id -all -ErrorAction Stop)
        }
        catch {
            Write-Warning "Failed to fetch notes for ticket #$($ticket.id): $_"
            $notes = @()
        }
        Write-Host "Found $($notes.Count) notes" -ForegroundColor Yellow

        # Get time entries
        Write-Host 'Fetching time entries...' -ForegroundColor Gray
        $timeCondition = "chargeToType='ServiceTicket' and chargeToId=$($ticket.id)"
        try {
            $timeEntries = @(Get-CWMTimeEntry -condition $timeCondition -all -ErrorAction Stop)
        }
        catch {
            Write-Warning "Failed to fetch time entries for ticket #$($ticket.id): $_"
            $timeEntries = @()
        }
        Write-Host "Found $($timeEntries.Count) time entries" -ForegroundColor Yellow

        # Format for AI (includes text cleaning and note deduplication)
        $ticketContext = Format-TicketForAI -Ticket $ticket -Notes $notes -TimeEntries $timeEntries

        # Show context data when -Verbose is used
        Write-Verbose "--- TICKET CONTEXT (cleaned & deduplicated) ---"
        Write-Verbose $ticketContext
        Write-Verbose "--- END TICKET CONTEXT ---"

        # Build message with cleaned data
        $userPrompt = @"
Please analyze the following ticket and provide your assessment:

$ticketContext
"@

        $messages = @(
            New-AnthropicMessage -Role 'user' -Content $userPrompt
        )

        # Call AI for analysis
        Write-Host 'Analyzing with AI...' -ForegroundColor Gray
        $response = Invoke-AnthropicMessage -Messages $messages -System $SystemPrompt -MaxTokens 2000

        $analysis = $response.Answer

        # Display analysis
        $separator = [string]::new('=', 20)
        Write-Host ""
        Write-Host "$separator AI ANALYSIS $separator" -ForegroundColor Green
        Write-Host ""
        Write-Host $analysis
        Write-Host ""
        Write-Host ([string]::new('=', 53)) -ForegroundColor Green

        # Add as note if requested
        if ($AddAsNote) {
            Write-Host "`nPosting analysis to ticket as internal note..." -ForegroundColor Yellow

            $noteText = @"
=== AI Analysis (via Ollama) ===
Model: $AnalysisModel
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

$analysis
"@

            New-CWMTicketNote -parentId $ticket.id -text $noteText -internalAnalysisFlag $true | Out-Null
            Write-Host 'Note added successfully.' -ForegroundColor Green
        }

        # Save to JSON if requested
        if ($OutputJsonDir) {
            $analysisResult = [ordered]@{
                ticketId    = $ticket.id
                summary     = $ticket.summary
                company     = if ($ticket.company) { $ticket.company.name } else { $null }
                status      = if ($ticket.status) { $ticket.status.name } else { $null }
                priority    = if ($ticket.priority) { $ticket.priority.name } else { $null }
                model       = $AnalysisModel
                generatedAt = Get-Date -Format 'o'
                analysis    = $analysis
                usage       = [ordered]@{
                    inputTokens  = $response.usage.input_tokens
                    outputTokens = $response.usage.output_tokens
                }
            }
            $jsonPath = Join-Path $OutputJsonDir "$($ticket.id).json"
            $analysisResult | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding UTF8
            Write-Host "Saved: $jsonPath" -ForegroundColor Gray
        }

        # Separator between tickets
        if ($tickets.Count -gt 1) {
            Write-Host "`n" + [string]::new('-', 70) + "`n" -ForegroundColor DarkGray
        }
    }
}
catch {
    throw
}
finally {
    # Clean up (only if we initiated the connection)
    if (-not $SkipCWMConnect -and (Get-Command Disconnect-CWM -ErrorAction SilentlyContinue)) {
        Disconnect-CWM -ErrorAction SilentlyContinue
    }
}

#endregion
