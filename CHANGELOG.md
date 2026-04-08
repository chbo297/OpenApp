# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-04-07

### Added
- Initial release
- Provider-agnostic `LLMProvider` protocol for LLM integration
- `AIAgentLoop` with automatic LLM-tool execution cycle and streaming
- `Tool` protocol with JSON Schema parameter definitions
- `ToolRegistry` for shared and per-session tool registration
- `AISession` and `AISessionManager` for multi-session management
- `SystemPrompt` with configurable prompt segments and cache control
- Anthropic provider implementation with SSE streaming
- `InMemorySessionStorage` and `FileSessionStorage` for session persistence
- `ChatViewController` drop-in UIKit chat interface
- Swift Package Manager support
- CocoaPods support
