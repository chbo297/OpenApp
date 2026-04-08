# OpenAPP

[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015%20%7C%20macOS%2012-blue.svg)](https://developer.apple.com)
[![SPM Compatible](https://img.shields.io/badge/SPM-Compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![CocoaPods Compatible](https://img.shields.io/badge/CocoaPods-Compatible-brightgreen.svg)](https://cocoapods.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Overview

OpenAPP is a provider-agnostic AI agent framework for iOS and macOS. It gives you a complete agent loop -- LLM calls, tool execution, streaming responses, multi-session management -- with zero external dependencies and a clean protocol-oriented architecture. Plug in any LLM provider, register custom tools, and optionally drop in a ready-made chat UI.

## Features

- **Provider-agnostic** -- `LLMProvider` protocol lets you swap between Anthropic, OpenAI, or any other backend without changing application code
- **Anthropic provider included** -- production-ready provider shipped out of the box
- **AIAgent loop** -- automatic LLM-to-tool execution cycle with configurable iteration limits
- **Tool protocol** -- define tools with JSON Schema descriptions that the LLM can invoke
- **Streaming responses** -- first-class `AsyncStream`-based streaming for real-time token delivery
- **Multi-session management** -- create, persist, and resume independent conversation sessions
- **Pluggable storage** -- `SessionStorage` protocol for custom persistence backends
- **Cache control support** -- `ContentOrCacheControl` pattern for Anthropic-style prompt caching
- **Drop-in Chat UI** -- `ChatViewController` provides a polished chat interface with minimal setup
- **Zero external dependencies** -- `OpenAPPCore` builds on Foundation alone
- **Two focused modules** -- `OpenAPPCore` for headless use, `OpenAPPUI` for UIKit components

## Requirements

| Module | Minimum OS | Frameworks |
|---|---|---|
| `OpenAPPCore` | iOS 15.0 / macOS 12.0 | Foundation |
| `OpenAPPUI` | iOS 15.0 | UIKit |

- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager

Add OpenAPP to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/anthropics/OpenAPP.git", from: "1.0.0")
]
```

Then add the modules you need to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "OpenAPPCore", package: "OpenAPP"),
        .product(name: "OpenAPPUI", package: "OpenAPP"),   // optional
    ]
)
```

Or in Xcode: **File > Add Package Dependencies...** and enter the repository URL.

### CocoaPods

Add OpenAPP to your `Podfile`:

```ruby
# Core only (Foundation, no UI)
pod 'OpenAPP/Core', '~> 1.0'

# Core + UIKit chat components
pod 'OpenAPP/UI', '~> 1.0'
```

Then run:

```bash
pod install
```

## Quick Start

```swift
import OpenAPPCore

// 1. Configure the provider
let config = ProviderConfiguration(
    apiKey: "your-api-key",
    model: "claude-sonnet-4-20250514",
    maxTokens: 4096
)
let provider = AnthropicProvider(configuration: config)

// 2. Create a session manager and a new session
let manager = AISessionManager(provider: provider)
let session = try await manager.createSession(
    systemPrompt: "You are a helpful assistant."
)

// 3. Send a message and handle the stream
let events = session.sendMessage("What is the capital of France?")

for await event in events {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .toolUse(let name, let input):
        print("Tool call: \(name)")
    case .completed(let message):
        print("\nDone: \(message.content)")
    case .error(let error):
        print("Error: \(error)")
    }
}
```

## Using the Chat UI

`OpenAPPUI` provides a ready-made chat interface you can present in one line:

```swift
import OpenAPPCore
import OpenAPPUI

let config = ProviderConfiguration(
    apiKey: "your-api-key",
    model: "claude-sonnet-4-20250514",
    maxTokens: 4096
)
let provider = AnthropicProvider(configuration: config)
let manager = AISessionManager(provider: provider)
let session = try await manager.createSession(
    systemPrompt: "You are a helpful assistant."
)

let chatVC = ChatViewController(session: session)
navigationController?.pushViewController(chatVC, animated: true)
```

See [UICustomization](docs/UICustomization.md) for theming, subclassing, and SwiftUI integration.

## Architecture

OpenAPP is organized into layered modules with clear boundaries:

```
┌──────────────────────────────┐
│         OpenAPPUI            │  UIKit chat components
├──────────────────────────────┤
│        OpenAPPCore           │  AIAgent loop, sessions, tools, providers
│  ┌────────┐ ┌──────────────┐ │
│  │Provider│ │  AIAgentLoop   │ │
│  │ Layer  │ │  + Tools     │ │
│  └────────┘ └──────────────┘ │
│  ┌──────────────────────────┐│
│  │   Session Management     ││
│  └──────────────────────────┘│
└──────────────────────────────┘
```

Read the full breakdown in [docs/Architecture.md](docs/Architecture.md).

## Documentation

| Guide | Description |
|---|---|
| [Architecture](docs/Architecture.md) | Layered design, module boundaries, agent loop cycle |
| [Getting Started](docs/GettingStarted.md) | Installation, first provider, first message |
| [Providers](docs/Providers.md) | `LLMProvider` protocol, custom provider implementation |
| [Tools](docs/Tools.md) | `Tool` protocol, JSON Schema, tool registry |
| [UI Customization](docs/UICustomization.md) | Chat UI theming, subclassing, SwiftUI integration |

## Contributing

We welcome contributions. Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on issues, pull requests, and code style.

## License

OpenAPP is released under the Apache 2.0 License. See [LICENSE](LICENSE) for details.
