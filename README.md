# OpenAPP

[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013%20%7C%20macOS%2012-blue.svg)](https://developer.apple.com)
[![SPM Compatible](https://img.shields.io/badge/SPM-Compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![CocoaPods Compatible](https://img.shields.io/badge/CocoaPods-Compatible-brightgreen.svg)](https://cocoapods.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

OpenAPP is an iOS/macOS AI agent SDK for embedding conversational agents into an app. It includes a provider abstraction, Anthropic streaming provider, tool loop, memory, skills, session persistence, built-in tools, and an optional UIKit overlay UI. The package has zero third-party dependencies.

## Package Shape

The current Swift package exposes one library product:

```swift
.product(name: "OpenAPP", package: "OpenAPP")
```

All public types are imported from the single Swift module:

```swift
import OpenAPP
```

The repository keeps implementation files under `Sources/Core` and `Sources/UI` for organization, but these are directories inside the same `OpenAPP` target. There are not separate `OpenAPPCore` or `OpenAPPUI` products in the current package.

## Requirements

| Integration | Minimum OS | Notes |
|---|---:|---|
| Swift Package Manager | iOS 13, macOS 12 | Single `OpenAPP` product |
| CocoaPods | iOS 13 | Single `OpenAPP` pod |
| UIKit overlay UI | iOS 13 | UI files are guarded with `canImport(UIKit)` |

- Swift tools version: 5.10
- No third-party package dependencies

## Installation

### Swift Package Manager

Add the package to your app and depend on the single product:

```swift
dependencies: [
    .package(url: "https://github.com/chbo297/OpenAPP.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "OpenAPP", package: "OpenAPP")
        ]
    )
]
```

In Xcode, use **File > Add Package Dependencies...** and select the `OpenAPP` product.

### CocoaPods

Add OpenAPP to your `Podfile`:

```ruby
pod 'OpenAPP', '~> 0.1'
```

Then run:

```bash
pod install
```

## Quick Start

```swift
import OpenAPP

let providerCentral = ModelProviderCentral()
await providerCentral.register(
    name: "anthropic",
    provider: AnthropicProvider(
        baseURL: "https://api.anthropic.com",
        apiKey: "sk-ant-xxxxxxxxxxxxxxxxxxxxxxxx",
        models: [
            ModelSpec(id: "claude-sonnet-4-6")
        ]
    )
)

let agent = await AIAgentCentral.default.create(
    name: "main",
    profile: AIAgentProfile(identity: "You are a helpful assistant."),
    providerCentral: providerCentral,
    modelPolicy: ModelPolicy(primary: "anthropic/claude-sonnet-4-6")
)

let session = await agent.createSession(title: "Chat")
let stream = session.sendMessage("What is the capital of France?")

for await event in stream {
    switch event {
    case .streamingContent(let delta):
        print(delta, terminator: "")
    case .toolCallStarted(let call):
        print("\nCalling tool: \(call.name)")
    case .completed(let result):
        print("\nDone: \(result.text)")
    case .error(let error):
        print("Error: \(error.localizedDescription)")
    default:
        break
    }
}
```

## UIKit Overlay

On iOS, OpenAPP can run as a passthrough overlay window above the host app:

```swift
import UIKit
import OpenAPP

let overlay = await OpenAPPOverlay.start(
    in: windowScene,
    agent: agent,
    sessionTitle: "Chat"
)

overlay.show()
```

For direct embedding, create an `OpenAPPViewController`, assign an agent, and switch it to an existing session id.

## Documentation

| Guide | Description |
|---|---|
| [Getting Started](docs/GettingStarted.md) | Installation, provider registration, first session |
| [Architecture](docs/Architecture.md) | Current single-module architecture and runtime flow |
| [Providers](docs/Providers.md) | `ModelProvider`, `ModelSpec`, provider stream events |
| [Tools](docs/Tools.md) | `ToolProtocol`, schemas, outputs, tool registration |
| [UI Customization](docs/UICustomization.md) | Overlay UI, direct controller use, custom UI |

## Example App

The iOS demo lives in `Examples/iOS/OpenAPPDemo.xcodeproj`.

```bash
cp Examples/iOS/Resources/config.json.example Examples/iOS/config.json
```

Fill in `Examples/iOS/config.json`, open the demo project, choose an iOS Simulator or device, and run.

## License

OpenAPP is released under the Apache 2.0 License. See [LICENSE](LICENSE) for details.
