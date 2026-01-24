# JsonParser.ps1 - JSON parsing utilities
# Contains subtle parsing bugs

function ConvertFrom-ApiJson {
    param(
        [Parameter(Mandatory)]
        [string]$JsonString
    )

    # BUG 1: Doesn't handle null or empty string
    # BUG 2: No error handling for invalid JSON

    if ([string]::IsNullOrWhiteSpace($JsonString)) {
        # BUG: Returns $null instead of empty object
        return $null
    }

    # BUG: Assumes JSON is always valid
    $result = $JsonString | ConvertFrom-Json

    # BUG: Doesn't convert nested objects properly
    return $result
}

function ConvertTo-ApiJson {
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [int]$Depth = 5  # BUG: Default depth too shallow for complex objects
    )

    # BUG: Doesn't handle circular references
    return $Object | ConvertTo-Json -Depth $Depth -Compress
}

function Get-JsonProperty {
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Path  # e.g., "user.address.city"
    )

    # BUG: Doesn't handle array indices in path like "users[0].name"
    $parts = $Path.Split('.')
    $current = $Object

    foreach ($part in $parts) {
        if ($null -eq $current) {
            return $null
        }

        # BUG: Uses string indexer which may not work for PSCustomObject
        $current = $current.$part
    }

    return $current
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [object]$Value
    )

    $parts = $Path.Split('.')
    $current = $Object

    # Navigate to parent
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $part = $parts[$i]

        # BUG: Doesn't create intermediate objects if they don't exist
        if ($null -eq $current.$part) {
            # This throws instead of creating the path
            throw "Path '$($parts[0..$i] -join '.')' does not exist"
        }

        $current = $current.$part
    }

    # Set the value
    $lastPart = $parts[-1]
    $current | Add-Member -NotePropertyName $lastPart -NotePropertyValue $Value -Force
}

function Merge-JsonObjects {
    param(
        [Parameter(Mandatory)]
        [object]$Base,

        [Parameter(Mandatory)]
        [object]$Override
    )

    # BUG: Shallow merge only - nested objects are replaced, not merged
    $result = $Base.PSObject.Copy()

    foreach ($prop in $Override.PSObject.Properties) {
        $result | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    }

    return $result
}

function Test-JsonSchema {
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter(Mandatory)]
        [hashtable]$Schema
    )

    $errors = @()

    foreach ($field in $Schema.Keys) {
        $spec = $Schema[$field]
        $value = $Object.$field

        # Check required
        if ($spec.Required -and $null -eq $value) {
            $errors += "Missing required field: $field"
            continue
        }

        # BUG: Type check uses GetType() which fails on $null
        if ($spec.Type -and $null -ne $value) {
            $actualType = $value.GetType().Name
            if ($actualType -ne $spec.Type) {
                # BUG: Doesn't handle type aliases (int vs Int32)
                $errors += "Field '$field' expected $($spec.Type), got $actualType"
            }
        }
    }

    return [PSCustomObject]@{
        IsValid = $errors.Count -eq 0
        Errors  = $errors
    }
}
