# Getting Started

This guide walks you through installing OpenAPP, configuring a provider, creating your first session, and sending a message.

## Prerequisites

- Xcode 15 or later
- Swift 5.9 or later
- An LLM API key (the examples below use Anthropic, but any provider works)
- iOS 15+ or macOS 12+ deployment target

## Installation

### Swift Package Manager

In Xcode, go to **File > Add Package Dependencies...** and enter:

```
https://github.com/anthropics/OpenAPP.git
```

Select the modules you need:

- **OpenAPPCore** -- agent loop, providers, tools, sessions (Foundation only)
- **OpenAPPUI** -- UIKit chat components (iOS only)

Or add the dependency directly in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/anthropics/OpenAPP.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "OpenAPPCore", package: "OpenAPP"),
            .product(name: "OpenAPPUI", package: "OpenAPP"),
        ]
    )
]
```

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'OpenAPP/Core', '~> 1.0'
pod 'OpenAPP/UI', '~> 1.0'   # optional
```

Then run:

```bash
pod install
```

Open the generated `.xcworkspace` file.

---

## Creating a Provider

A provider connects OpenAPP to an LLM backend. The framework ships with `AnthropicProvider`:

```swift
import OpenAPPCore

let configuration = ProviderConfiguration(
    apiKey: "sk-ant-xxxxxxxxxxxxxxxxxxxxxxxx",
    model: "claude-sonnet-4-20250514",
    maxTokens: 4096
)

let provider = AnthropicProvider(configuration: configuration)
```

`ProviderConfiguration` also accepts optional parameters:

```swift
let configuration = ProviderConfiguration(
    apiKey: "sk-ant-xxxxxxxxxxxxxxxxxxxxxxxx",
    model: "claude-sonnet-4-20250514",
    maxTokens: 4096,
    baseURL: URL(string: "https://api.anthropic.com")!,
    defaultHeaders: ["anthropic-beta": "prompt-caching-2024-07-31"]
)
```

> **Tip:** Never hard-code API keys in source. Load them from the keychain, environment variables, or a secure configuration file.

---

## Creating a Session Manager

The `AISessionManager` is responsible for creating, resuming, and persisting sessions:

```swift
let manager = AISessionManager(
    provider: provider,
    storage: InMemorySessionStorage()   // default; swap for your own
)
```

You typically create one manager per provider and hold it for the lifetime of your app.

---

## Creating a Session and Sending a Message

```swift
// Create a new session with a system prompt
let session = try await manager.createSession(
    systemPrompt: "You are a helpful coding assistant."
)

// Send a user message -- returns an AsyncStream of AIAgentEvent
let events = session.sendMessage("Explain the difference between a struct and a class in Swift.")
```

`sendMessage(_:)` returns immediately with an `AsyncStream<AIAgentEvent>`. The agent loop runs in the background, streaming events as they arrive.

---

## Handling the AIAgentEvent Stream

Iterate over the stream with `for await`:

```swift
for await event in events {
    switch event {
    case .textDelta(let text):
        // Append text to the UI in real time
        print(text, terminator: "")

    case .toolUse(let name, let input):
        // The LLM is calling a tool
        print("\n[Tool call: \(name)]")

    case .toolResult(let name, let output):
        // A tool returned a result
        print("[Tool result: \(name) -> \(output)]")

    case .completed(let message):
        // The assistant turn is finished
        print("\n--- Turn complete ---")
        print("Full response: \(message.content)")

    case .error(let error):
        // Handle the error
        print("Error: \(error.localizedDescription)")
    }
}
```

### Common Patterns

**Collect the full response:**

```swift
var fullText = ""
for await event in events {
    if case .textDelta(let text) = event {
        fullText += text
    }
}
print(fullText)
```

**Cancel a running stream:**

```swift
let task = Task {
    for await event in session.sendMessage("Tell me a long story.") {
        // process events
    }
}

// Later, if the user taps "Stop"
task.cancel()
```

---

## Registering Tools

You can register tools when creating a session:

```swift
let weatherTool = WeatherLookupTool()

let session = try await manager.createSession(
    systemPrompt: "You are a helpful assistant with access to weather data.",
    tools: [weatherTool]
)
```

When the LLM decides to use a tool, the agent loop executes it automatically and feeds the result back. See [Tools](Tools.md) for the full guide.

---

## Running the Example App

The repository includes an Example app that demonstrates a complete chat interface. It is built as a Package-internal executable target (`OpenAPPDemoApp`), so no separate Xcode project is needed.

1. Open `Package.swift` in Xcode.
2. Copy and fill in your config: `cp Examples/iOS/Resources/config.json.example Examples/iOS/Resources/config.json`.
3. Select the `OpenAPPDemoApp` scheme and a simulator or device with iOS 15+.
4. Build and run.

The example uses `AnthropicProvider` and `ChatViewController` to present a working chat in under 50 lines of code.

---

## Next Steps

- [Architecture](Architecture.md) -- understand the layered design
- [Providers](Providers.md) -- implement a custom LLM provider
- [Tools](Tools.md) -- build and register agent tools
- [UI Customization](UICustomization.md) -- theme or replace the chat UI
