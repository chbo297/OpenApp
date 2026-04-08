# Providers

This guide covers the `LLMProvider` protocol, its supporting types, and how to implement a custom provider for any LLM backend.

## The LLMProvider Protocol

`LLMProvider` is the single abstraction that connects OpenAPP to an LLM service:

```swift
public protocol LLMProvider: Sendable {
    /// Send a conversation to the LLM and receive a stream of events.
    func sendMessage(
        messages: [Message],
        system: [ContentOrCacheControl],
        tools: [ToolSchema],
        maxTokens: Int
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error>
}
```

The framework never calls HTTP APIs directly. All network communication is encapsulated inside a provider, making it straightforward to swap backends, add middleware, or substitute a mock for testing.

---

## ProviderConfiguration

A value type that carries connection details:

```swift
public struct ProviderConfiguration: Sendable {
    public let apiKey: String
    public let model: String
    public let maxTokens: Int
    public let baseURL: URL?
    public let defaultHeaders: [String: String]
    public let options: [String: Any]

    public init(
        apiKey: String,
        model: String,
        maxTokens: Int = 4096,
        baseURL: URL? = nil,
        defaultHeaders: [String: String] = [:],
        options: [String: Any] = [:]
    )
}
```

| Property | Purpose |
|---|---|
| `apiKey` | Authentication token for the backend |
| `model` | Model identifier (e.g., `claude-sonnet-4-20250514`, `gpt-4o`) |
| `maxTokens` | Default maximum tokens per response |
| `baseURL` | Override the default API endpoint |
| `defaultHeaders` | Extra HTTP headers sent with every request |
| `options` | Provider-specific key-value pairs |

---

## ProviderStreamEvent

Events emitted by a provider during streaming:

```swift
public enum ProviderStreamEvent: Sendable {
    /// Incremental text content.
    case textDelta(String)

    /// The LLM is requesting a tool call.
    case toolUse(id: String, name: String, input: String)

    /// The stream has ended.
    case stop(StopReason)

    /// Usage metadata (input tokens, output tokens).
    case usage(inputTokens: Int, outputTokens: Int)
}
```

### StopReason

```swift
public enum StopReason: String, Sendable, Codable {
    case endTurn = "end_turn"
    case toolUse = "tool_use"
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
}
```

The `AIAgentLoop` inspects `StopReason` to decide whether to continue (`.toolUse`) or finish (`.endTurn`, `.maxTokens`, `.stopSequence`).

---

## ContentOrCacheControl

System prompts are passed as `[ContentOrCacheControl]` to support Anthropic-style prompt caching:

```swift
public enum ContentOrCacheControl: Codable, Sendable {
    case text(String)
    case cacheControl(String, CachePolicy)
}

public enum CachePolicy: String, Codable, Sendable {
    case ephemeral
}
```

Providers that do not support cache control can extract the text content from each element:

```swift
let plainText = systemBlocks.map { block -> String in
    switch block {
    case .text(let s): return s
    case .cacheControl(let s, _): return s
    }
}
```

Providers that do support it (like `AnthropicProvider`) serialize the full structure.

---

## Implementing a Custom Provider

Below is a skeleton for an OpenAI-compatible provider. It demonstrates the required conformance without a full networking implementation:

```swift
import Foundation
import OpenAPPCore

public final class OpenAIProvider: LLMProvider {
    private let configuration: ProviderConfiguration
    private let session: URLSession

    public init(configuration: ProviderConfiguration) {
        self.configuration = configuration
        self.session = URLSession(configuration: .default)
    }

    public func sendMessage(
        messages: [Message],
        system: [ContentOrCacheControl],
        tools: [ToolSchema],
        maxTokens: Int
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // 1. Build the request body
                    let body = try buildRequestBody(
                        messages: messages,
                        system: system,
                        tools: tools,
                        maxTokens: maxTokens
                    )

                    // 2. Create the URLRequest
                    var request = URLRequest(
                        url: configuration.baseURL
                            ?? URL(string: "https://api.openai.com/v1/chat/completions")!
                    )
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(configuration.apiKey)",
                                    forHTTPHeaderField: "Authorization")
                    request.setValue("application/json",
                                    forHTTPHeaderField: "Content-Type")
                    request.httpBody = body

                    // 3. Stream the response using URLSession bytes
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else {
                        throw AIAgentError.providerError("Non-200 response")
                    }

                    // 4. Parse SSE lines and yield ProviderStreamEvent values
                    for try await line in bytes.lines {
                        if let event = try parseSSELine(line) {
                            continuation.yield(event)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private Helpers

    private func buildRequestBody(
        messages: [Message],
        system: [ContentOrCacheControl],
        tools: [ToolSchema],
        maxTokens: Int
    ) throws -> Data {
        // Convert OpenAPP messages to OpenAI chat format
        // Convert ToolSchema to OpenAI function definitions
        // Return JSON-encoded body
        fatalError("Implement for your backend")
    }

    private func parseSSELine(_ line: String) throws -> ProviderStreamEvent? {
        // Parse "data: {...}" SSE lines
        // Map to ProviderStreamEvent cases
        fatalError("Implement for your backend")
    }
}
```

### Key Implementation Notes

1. **Map messages.** Translate OpenAPP `Message` values (which use Anthropic-style roles and content blocks) into the format your backend expects.

2. **Map tool schemas.** Convert `ToolSchema` into the backend's function/tool definition format.

3. **Emit the right events.** The `AIAgentLoop` relies on receiving:
   - `.textDelta` for incremental text
   - `.toolUse` when the model wants to call a tool (include the tool call `id` so the loop can pair results)
   - `.stop` with the correct `StopReason`

4. **Handle cancellation.** Respect `continuation.onTermination` so the caller can cancel mid-stream.

5. **Thread safety.** `LLMProvider` requires `Sendable` conformance. Avoid mutable shared state.

---

## Anthropic Provider Reference

The built-in `AnthropicProvider` serves as the reference implementation:

```swift
let config = ProviderConfiguration(
    apiKey: "sk-ant-xxxxxxxxxxxxxxxxxxxxxxxx",
    model: "claude-sonnet-4-20250514",
    maxTokens: 4096
)

let provider = AnthropicProvider(configuration: config)
```

It supports:

- Streaming via Anthropic's SSE `/v1/messages` endpoint
- Tool use with automatic JSON Schema serialization
- `ContentOrCacheControl` for prompt caching
- Beta header injection via `defaultHeaders`

Study its source in `Sources/OpenAPPCore/Providers/AnthropicProvider.swift` for a complete working example.

---

## Next Steps

- [Getting Started](GettingStarted.md) -- use a provider in a session
- [Tools](Tools.md) -- define tools that the LLM can invoke
- [Architecture](Architecture.md) -- see how providers fit into the overall design
