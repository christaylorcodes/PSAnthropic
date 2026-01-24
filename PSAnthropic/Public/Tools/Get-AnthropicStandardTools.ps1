function Get-AnthropicStandardTools {
    <#
    .SYNOPSIS
        Returns a set of standard tools for common operations.
    .DESCRIPTION
        Provides pre-defined tools similar to Anthropic's built-in tools:
        - pwsh: Execute PowerShell commands (like bash_20241022)
        - str_replace_editor: Text editor with view/create/replace (like text_editor_20250124)
        - read_file: Read file contents
        - list_directory: List directory contents
        - search_files: Search for files by pattern
        - search_content: Search for text within files
        - get_current_time: Get current date/time
        - web_fetch: Fetch and parse content from URLs
    .PARAMETER ToolSet
        Which set of tools to return: 'All', 'FileSystem', 'Editor', 'Shell'
    .EXAMPLE
        $tools = Get-AnthropicStandardTools
        Invoke-AnthropicMessage -Messages $messages -Tools $tools
    .EXAMPLE
        $tools = Get-AnthropicStandardTools -ToolSet FileSystem
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter()]
        [ValidateSet('All', 'FileSystem', 'Editor', 'Shell', 'Web')]
        [string]$ToolSet = 'All'
    )

    $tools = @{
        pwsh = @{
            name        = 'pwsh'
            description = 'Execute a PowerShell command and return the output. Use for system commands, getting environment info, running scripts, etc. Commands that modify files or system state may be restricted.'
            input_schema = @{
                type       = 'object'
                properties = @{
                    command = @{
                        type        = 'string'
                        description = 'The PowerShell command to execute'
                    }
                    working_directory = @{
                        type        = 'string'
                        description = 'Optional working directory for the command'
                    }
                }
                required = @('command')
            }
        }

        str_replace_editor = @{
            name        = 'str_replace_editor'
            description = @'
A text editor tool for viewing, creating, and editing files.
Commands:
- view: Read file contents (optionally specific line range)
- create: Create a new file with content
- str_replace: Replace exact text in a file (old_str must match exactly)
- insert: Insert text at a specific line number
'@
            input_schema = @{
                type       = 'object'
                properties = @{
                    command = @{
                        type        = 'string'
                        enum        = @('view', 'create', 'str_replace', 'insert')
                        description = 'The editor command to execute'
                    }
                    path = @{
                        type        = 'string'
                        description = 'Absolute path to the file'
                    }
                    file_text = @{
                        type        = 'string'
                        description = 'For create: the content to write to the file'
                    }
                    old_str = @{
                        type        = 'string'
                        description = 'For str_replace: the exact text to find and replace'
                    }
                    new_str = @{
                        type        = 'string'
                        description = 'For str_replace: the text to replace old_str with'
                    }
                    insert_line = @{
                        type        = 'integer'
                        description = 'For insert: line number to insert at (1-based)'
                    }
                    new_str_for_insert = @{
                        type        = 'string'
                        description = 'For insert: text to insert'
                    }
                    view_range = @{
                        type        = 'array'
                        items       = @{ type = 'integer' }
                        description = 'For view: optional [start_line, end_line] range (1-based)'
                    }
                }
                required = @('command', 'path')
            }
        }

        read_file = @{
            name        = 'read_file'
            description = 'Read the contents of a file. Returns the full content or an error if the file does not exist.'
            input_schema = @{
                type       = 'object'
                properties = @{
                    path = @{
                        type        = 'string'
                        description = 'The full path to the file to read'
                    }
                    max_lines = @{
                        type        = 'integer'
                        description = 'Optional maximum number of lines to read'
                    }
                }
                required = @('path')
            }
        }

        list_directory = @{
            name        = 'list_directory'
            description = 'List files and folders in a directory. Returns names, types, sizes, and modification times.'
            input_schema = @{
                type       = 'object'
                properties = @{
                    path = @{
                        type        = 'string'
                        description = 'The directory path to list'
                    }
                    pattern = @{
                        type        = 'string'
                        description = 'Optional filter pattern (e.g., *.ps1, *.txt)'
                    }
                    recursive = @{
                        type        = 'boolean'
                        description = 'Whether to list recursively (default: false)'
                    }
                }
                required = @('path')
            }
        }

        search_files = @{
            name        = 'search_files'
            description = 'Search for files by name pattern recursively. Returns matching file paths.'
            input_schema = @{
                type       = 'object'
                properties = @{
                    path = @{
                        type        = 'string'
                        description = 'The directory to search in'
                    }
                    pattern = @{
                        type        = 'string'
                        description = 'File name pattern (e.g., *.ps1, *test*, README*)'
                    }
                    max_results = @{
                        type        = 'integer'
                        description = 'Maximum results to return (default: 50)'
                    }
                }
                required = @('path', 'pattern')
            }
        }

        search_content = @{
            name        = 'search_content'
            description = 'Search for text content within files. Returns matching lines with file paths and line numbers.'
            input_schema = @{
                type       = 'object'
                properties = @{
                    path = @{
                        type        = 'string'
                        description = 'The directory to search in'
                    }
                    pattern = @{
                        type        = 'string'
                        description = 'Text or regex pattern to search for'
                    }
                    file_pattern = @{
                        type        = 'string'
                        description = 'Optional file filter (e.g., *.ps1)'
                    }
                    max_results = @{
                        type        = 'integer'
                        description = 'Maximum results to return (default: 50)'
                    }
                }
                required = @('path', 'pattern')
            }
        }

        get_current_time = @{
            name        = 'get_current_time'
            description = 'Get the current date and time, optionally in a specific timezone.'
            input_schema = @{
                type       = 'object'
                properties = @{
                    timezone = @{
                        type        = 'string'
                        description = 'Timezone ID (e.g., "UTC", "Pacific Standard Time"). Default is local time.'
                    }
                    format = @{
                        type        = 'string'
                        description = 'DateTime format string (e.g., "yyyy-MM-dd HH:mm:ss")'
                    }
                }
                required = @()
            }
        }

        web_fetch = @{
            name        = 'web_fetch'
            description = @'
Fetch content from a URL and return it as readable text.
Use this to retrieve documentation, web pages, API responses, or other online content.
HTML is automatically converted to plain text. JSON and plain text are returned as-is.
'@
            input_schema = @{
                type       = 'object'
                properties = @{
                    url = @{
                        type        = 'string'
                        description = 'The URL to fetch content from (must be http or https)'
                    }
                    max_length = @{
                        type        = 'integer'
                        description = 'Maximum content length to return in characters (default: 50000)'
                    }
                    include_headers = @{
                        type        = 'boolean'
                        description = 'Include HTTP response headers in output (default: false)'
                    }
                }
                required = @('url')
            }
        }
    }

    # Return tools based on selected set
    $result = switch ($ToolSet) {
        'FileSystem' { @($tools.read_file, $tools.list_directory, $tools.search_files, $tools.search_content) }
        'Editor'     { @($tools.str_replace_editor) }
        'Shell'      { @($tools.pwsh, $tools.get_current_time) }
        'Web'        { @($tools.web_fetch) }
        'All'        { @($tools.pwsh, $tools.str_replace_editor, $tools.read_file, $tools.list_directory, $tools.search_files, $tools.search_content, $tools.get_current_time, $tools.web_fetch) }
    }

    return $result
}
