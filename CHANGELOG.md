# Changelog

All notable changes to PSAnthropic will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Build automation with Sampler/ModuleBuilder framework
- CI/CD pipeline for automated testing and publishing to PSGallery
- PSScriptAnalyzer code quality checks
- Local pre-push validation script (`test-local.ps1`)
- Contributing guidelines and issue templates

## [0.2.0]

### Added

- **Backend detection.** `Connect-Anthropic` now detects the backend (`.Provider`:
  Anthropic / Ollama / Generic) and accepts `-Provider` to override, plus
  `-AnthropicVersion` and `-Beta` for header control.
- **Live model discovery.** `Get-AnthropicModel` queries the Anthropic Models API
  (`GET /v1/models`) on cloud and `/api/tags` on Ollama, cached on the connection
  (`-Refresh` to re-query). Tab-completion is driven from this - no hardcoded model list.
- **Capability-aware requests.** A new internal resolver (`Get-AnthropicModelCapability`)
  reads live model capabilities (or a per-provider profile) so requests only include
  fields the target accepts.
- `Invoke-AnthropicMessage`: `-Effort`, `-ThinkingDisplay`, `-Metadata`, `-CacheControl`
  / `-CacheTtl`, `-ResponseSchema` (structured outputs), and per-request `-Beta`.
- `Get-AnthropicTokenCount` - counts input tokens via `POST /v1/messages/count_tokens`
  (Anthropic Cloud).
- Refusal handling: responses expose `.Refused` and surface `stop_details` when the
  model declines (`stop_reason: "refusal"`).

### Changed

- **Thinking is now backend-aware.** `-Thinking` requests adaptive thinking on current
  Anthropic models (steer with `-Effort`) and enabled+budget on Ollama/legacy models.
- Sampling parameters (`temperature`/`top_p`/`top_k`), `-ToolChoice`, and `-Metadata`
  are omitted (with a warning) on backends/models that reject them, instead of causing
  a 400.
- Argument-completer no longer ships a hardcoded (and now retired) Claude model list.

### Fixed

- `Connect-Anthropic` no longer strips the URL scheme, fixing HTTPS endpoints being silently downgraded to HTTP (#1).
- Removed retired model IDs (`claude-3-5-sonnet-20241022`, `claude-3-5-haiku-20241022`,
  `claude-3-opus-20240229`) from tab-completion.

## [0.1.0] - 2026-01-23

### Added

#### Core Messaging
- `Invoke-AnthropicMessage` - Send messages to Anthropic-compatible APIs
- `Invoke-AnthropicWebRequest` - Low-level HTTP handler with retry logic
- `New-AnthropicMessage` - Create message objects
- `New-AnthropicConversation` - Start conversations with system prompts
- `Add-AnthropicMessage` - Add messages to existing conversations
- `Get-AnthropicResponseText` - Extract text from API responses
- Streaming support via Server-Sent Events (SSE)
- Extended thinking mode (`-Thinking`, `-ThinkingBudget`)

#### Authentication
- `Connect-Anthropic` - Initialize connection to API endpoints
- `Disconnect-Anthropic` - Clear connection state
- `Get-AnthropicConnection` - View current connection info
- `Test-AnthropicEndpoint` - Health check endpoints
- Environment variable support (`ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`)

#### Tool Support
- `New-AnthropicTool` - Create custom tool definitions
- `New-AnthropicToolResult` - Format tool execution results
- `Get-AnthropicStandardTools` - Pre-built standard tools (8 tools)
- `Invoke-AnthropicStandardTool` - Execute standard tool calls
- Shell safety levels (Restricted, ReadOnly, Standard, Full, Unsafe)
- Sandboxed PowerShell execution via ConstrainedLanguage mode

#### Content
- `New-AnthropicImageContent` - Create base64 image content blocks
- Support for PNG, JPEG, GIF, WebP formats
- Vision model integration

#### Model Router
- `Set-AnthropicRouterConfig` - Configure task-to-model mappings
- `Get-AnthropicRouterConfig` - View router configuration
- `Clear-AnthropicRouterConfig` - Reset router state
- `Invoke-AnthropicRouted` - Automatic model selection by task type
- `Get-AnthropicRouterLog` - View routing decision history
- CSV logging support

#### Utilities
- `Get-AnthropicModel` - List available models from server
- Retry logic with exponential backoff for 5xx errors
- `-WhatIf` support on state-changing functions

### Standard Tools Included
- `pwsh` - PowerShell command execution
- `str_replace_editor` - Text editor (view/create/replace/insert)
- `read_file` - Read file contents
- `list_directory` - List directory contents
- `search_files` - Search files by name pattern
- `search_content` - Search text within files
- `get_current_time` - Get current date/time
- `web_fetch` - Fetch and parse URL content

### Compatibility
- PowerShell 7.0+ required
- Ollama Anthropic compatibility layer
- Direct Anthropic API support
- Any Anthropic-compatible endpoint

[0.1.0]: https://github.com/christaylorcodes/PSAnthropic/releases/tag/v0.1.0
