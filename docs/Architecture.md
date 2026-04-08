# Architecture

This document describes the layered architecture of OpenAPP, the module boundaries between `OpenAPPCore` and `OpenAPPUI`, and how the agent loop drives conversations.

## Layer Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        OpenAPPUI                            │
│  ChatViewController · ChatMessage · ChatMessageCell         │
├─────────────────────────────────────────────────────────────┤
│                       OpenAPPCore                           │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                  Session Layer                        │  │
│  │  AISession · AISessionManager · SessionStorage  │  │
│  ├───────────────────────────────────────────────────────┤  │
│  │                   Core Layer                          │  │
│  │  AIAgentLoop · AIAgentEvent · AIAgentError                  │  │
│  │  ContentOrCacheControl                                │  │
│  ├───────────────────────────────────────────────────────┤  │
│  │                  Tool System                          │  │
│  │  Tool · ToolSchema · ToolRegistry · ToolFactory  │  │
│  ├───────────────────────────────────────────────────────┤  │
│  │                 Provider Layer                        │  │
│  │  LLMProvider · ProviderConfiguration                  │  │
│  │  ProviderStreamEvent · AnthropicProvider               │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

Each layer depends only on the layers below it. `OpenAPPUI` depends on `OpenAPPCore`; `OpenAPPCore` depends only on Foundation.

---

## Provider Layer

The provider layer abstracts all LLM communication behind a single protocol.

### LLMProvider

```swift
public protocol LLMProvider: Sendable {
    func sendMessage(
        messages: [Message],
        system: [ContentOrCacheControl],
        tools: [ToolSchema],
        maxTokens: Int
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error>
}
```

Any backend that can produce a stream of `ProviderStreamEvent` values is a valid provider. The framework ships with `AnthropicProvider`, but adding support for OpenAI, Gemini, or a local model requires only a conforming type.

### ProviderConfiguration

A value type that holds connection details such as `apiKey`, `model`, `maxTokens`, `baseURL`, and any provider-specific options. Providers accept this at initialization.

### Streaming

All provider communication is streaming-first. The provider returns an `AsyncThrowingStream<ProviderStreamEvent, Error>` that emits deltas as they arrive from the backend, giving the caller real-time control over rendering.

---

## Core Layer

### AIAgentLoop

The `AIAgentLoop` is the engine of the framework. It orchestrates the cycle between the LLM and registered tools:

```
 ┌──────────────┐
 │  User sends   │
 │  a message    │
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │  AIAgentLoop    │◄──────────────────┐
 │  calls LLM    │                   │
 └──────┬───────┘                   │
        ▼                           │
 ┌──────────────┐    tool_use?      │
 │  Parse stream │───── yes ────►┌──┴───────────┐
 │  events       │               │  Execute tool │
 └──────┬───────┘               │  via registry  │
        │ no                    └──┬───────────┘
        ▼                          │
 ┌──────────────┐      tool result │
 │  Emit         │◄────────────────┘
 │  .completed   │
 └──────────────┘
```

1. The user sends a message through `AISession`.
2. `AIAgentLoop` forwards the full message history plus system prompt and tool schemas to the `LLMProvider`.
3. As stream events arrive, the loop emits `AIAgentEvent.textDelta` for text chunks.
4. If the LLM emits a `tool_use` block, the loop pauses streaming, looks up the tool in the `ToolRegistry`, executes it, appends the `tool_result` to the message history, and loops back to step 2.
5. When the LLM finishes without requesting another tool call, the loop emits `AIAgentEvent.completed` and stops.

A configurable maximum iteration count prevents infinite loops.

### AIAgentEvent

An enum delivered through the event stream:

| Case | Payload | Description |
|---|---|---|
| `.textDelta` | `String` | Incremental text token |
| `.toolUse` | `(name: String, input: [String: Any])` | The LLM is invoking a tool |
| `.toolResult` | `(name: String, output: ToolOutput)` | A tool has returned a result |
| `.completed` | `AssistantMessage` | The turn is finished |
| `.error` | `AIAgentError` | A recoverable or fatal error |

### AIAgentError

Typed errors covering provider failures, tool execution failures, iteration limits, cancellation, and decoding issues.

### ContentOrCacheControl

A wrapper enum used in system prompts and messages:

```swift
public enum ContentOrCacheControl: Codable, Sendable {
    case text(String)
    case cacheControl(String, CachePolicy)
}
```

This enables Anthropic-style prompt caching while remaining provider-agnostic -- providers that do not support cache control simply read the text content.

---

## Tool System

### Tool

```swift
public protocol Tool: Sendable {
    var schema: ToolSchema { get }
    func execute(input: [String: Any]) async throws -> ToolOutput
}
```

Each tool declares a JSON Schema describing its parameters and implements `execute(input:)`.

### ToolSchema

A Swift representation of a JSON Schema object. It contains the tool `name`, `description`, and a tree of `PropertySchema` nodes describing expected input properties, types, and constraints.

### ToolRegistry

A thread-safe container that holds the set of tools available to an agent loop. Tools are registered by name and looked up during tool-use resolution.

### ToolFactory

A closure-based factory for tools that need per-session state. When a new session is created, `ToolFactory` produces a fresh tool instance, ensuring sessions do not share mutable tool state.

---

## Session Layer

### AISession

Represents a single conversation. It owns:

- The message history
- A reference to the `LLMProvider`
- A `ToolRegistry` (session-scoped tools merged with shared tools)
- The system prompt

Its primary API is `sendMessage(_:) -> AsyncStream<AIAgentEvent>`, which feeds the user message into the `AIAgentLoop` and returns the resulting event stream.

### AISessionManager

Manages the lifecycle of multiple sessions:

- `createSession(systemPrompt:tools:)` -- starts a new conversation
- `resumeSession(id:)` -- restores a session from storage
- `listSessions()` -- returns metadata for all persisted sessions
- `deleteSession(id:)` -- removes a session and its stored data

### SessionStorage

A protocol for persistence backends:

```swift
public protocol SessionStorage: Sendable {
    func save(session: SessionData) async throws
    func load(id: SessionID) async throws -> SessionData
    func list() async throws -> [SessionMetadata]
    func delete(id: SessionID) async throws
}
```

The framework provides a default in-memory implementation. You can supply your own for Core Data, SQLite, the file system, or a remote backend.

---

## UI Layer (OpenAPPUI)

`OpenAPPUI` is an optional module that depends on `OpenAPPCore` and UIKit. It provides a turnkey chat interface.

### ChatViewController

A `UIViewController` subclass backed by a `UICollectionView` that renders a conversation. It accepts an `AISession` and subscribes to its event stream automatically. It supports:

- Streaming text rendering with a typing indicator
- Tool-use status display
- User message input bar
- Automatic scrolling and keyboard avoidance

### ChatMessage

A view model that maps `AIAgentEvent` payloads into renderable rows (user bubbles, assistant bubbles, tool indicators, error banners).

### ChatMessageCell

A collection of `UICollectionViewCell` subclasses for the different message types. They are designed to be subclassed or replaced for custom theming.

---

## Module Boundaries

| Aspect | OpenAPPCore | OpenAPPUI |
|---|---|---|
| **Frameworks** | Foundation | UIKit, OpenAPPCore |
| **Platforms** | iOS 15+, macOS 12+ | iOS 15+ |
| **Use case** | Headless agents, server-side, CLI tools, custom UI | Drop-in chat screens |
| **External deps** | None | None (beyond OpenAPPCore) |

If you only need the agent loop and provider abstraction -- for example in a macOS command-line tool or a SwiftUI app with a fully custom interface -- depend on `OpenAPPCore` alone. Add `OpenAPPUI` when you want a pre-built UIKit chat experience.
