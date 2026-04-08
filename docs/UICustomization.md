# UI Customization

This guide covers using the built-in `ChatViewController`, customizing its appearance, building a fully custom UI on top of `AISession`, and integrating with SwiftUI.

## Using ChatViewController Out of the Box

The fastest way to get a chat screen running is to use `ChatViewController` directly:

```swift
import OpenAPPCore
import OpenAPPUI

let config = ProviderConfiguration(
    apiKey: "sk-ant-xxxxxxxxxxxxxxxxxxxxxxxx",
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

Out of the box you get:

- A message input bar with a send button
- Streaming text rendering with a typing indicator
- User and assistant message bubbles
- Tool-use status indicators
- Automatic keyboard avoidance and scroll management
- Pull-to-load-earlier-messages (when backed by persistent storage)

---

## Injecting an AISession

`ChatViewController` does not create its own session. You provide one at initialization, giving you full control over:

- Which provider and model are used
- The system prompt
- Which tools are available
- Storage and session lifecycle

```swift
// Session with tools
let session = try await manager.createSession(
    systemPrompt: "You are a coding assistant.",
    tools: [CalculatorTool(), FileSearchTool()]
)

let chatVC = ChatViewController(session: session)
```

You can also resume an existing session:

```swift
let session = try await manager.resumeSession(id: savedSessionID)
let chatVC = ChatViewController(session: session)
```

The chat view controller loads the session's message history and renders it immediately.

---

## Subclassing ChatViewController

For deeper customization, subclass `ChatViewController` and override its hooks:

```swift
import OpenAPPUI

final class CustomChatViewController: ChatViewController {

    // MARK: - Appearance

    override func viewDidLoad() {
        super.viewDidLoad()

        // Customize the input bar
        inputBar.backgroundColor = .systemGroupedBackground
        inputBar.textView.font = .preferredFont(forTextStyle: .body)
        inputBar.sendButton.tintColor = .systemIndigo

        // Customize message bubbles
        assistantBubbleColor = UIColor.systemGray6
        userBubbleColor = UIColor.systemIndigo
        assistantTextColor = UIColor.label
        userTextColor = UIColor.white
    }

    // MARK: - Message Rendering

    /// Called before a message cell is displayed. Use this to apply
    /// custom styling or inject additional views.
    override func configureCell(
        _ cell: ChatMessageCell,
        for message: ChatMessage,
        at indexPath: IndexPath
    ) {
        super.configureCell(cell, for: message, at: indexPath)

        // Example: add a timestamp label to assistant messages
        if message.role == .assistant {
            cell.timestampLabel.isHidden = false
            cell.timestampLabel.text = dateFormatter.string(from: message.timestamp)
        }
    }

    // MARK: - Tool Use Display

    /// Called when a tool starts executing. Override to show a custom
    /// progress indicator.
    override func didBeginToolUse(name: String) {
        super.didBeginToolUse(name: name)
        showCustomSpinner(message: "Running \(name)...")
    }

    /// Called when a tool finishes. Override to dismiss custom indicators.
    override func didEndToolUse(name: String, output: ToolOutput) {
        super.didEndToolUse(name: name, output: output)
        hideCustomSpinner()
    }

    // MARK: - Error Handling

    /// Called when an AIAgentError occurs during streaming.
    override func didEncounterError(_ error: AIAgentError) {
        // Show a custom error banner instead of the default alert
        showErrorBanner(error.localizedDescription)
    }

    // MARK: - Private

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}
```

### Registering Custom Cells

If the built-in cell types are not sufficient, register your own:

```swift
override func viewDidLoad() {
    super.viewDidLoad()

    collectionView.register(
        CodeBlockCell.self,
        forCellWithReuseIdentifier: "CodeBlockCell"
    )
}

override func cellReuseIdentifier(for message: ChatMessage) -> String {
    if message.containsCodeBlock {
        return "CodeBlockCell"
    }
    return super.cellReuseIdentifier(for: message)
}
```

---

## Building a Custom UI with AISession

If you prefer to build your own interface from scratch -- for example with SwiftUI or a completely custom UIKit layout -- interact with `AISession` directly. The session is the sole dependency you need.

### Sending a Message

```swift
let events = session.sendMessage("Hello, world!")
```

This returns an `AsyncStream<AIAgentEvent>` that you consume however you like.

### Processing Events

```swift
Task {
    for await event in events {
        switch event {
        case .textDelta(let text):
            await MainActor.run {
                appendText(text)
            }

        case .toolUse(let name, let input):
            await MainActor.run {
                showToolIndicator(name: name)
            }

        case .toolResult(let name, let output):
            await MainActor.run {
                hideToolIndicator(name: name)
            }

        case .completed(let message):
            await MainActor.run {
                finalizeMessage(message)
            }

        case .error(let error):
            await MainActor.run {
                showError(error)
            }
        }
    }
}
```

### Accessing Message History

```swift
let history = session.messages  // [Message]
```

The array is updated after each completed turn, including tool-use rounds.

### Cancellation

```swift
// Store the task
let streamTask = Task {
    for await event in session.sendMessage("...") { ... }
}

// Cancel when needed
streamTask.cancel()
```

---

## SwiftUI Integration

Wrap `ChatViewController` using `UIViewControllerRepresentable`:

```swift
import SwiftUI
import OpenAPPCore
import OpenAPPUI

struct ChatView: UIViewControllerRepresentable {
    let session: AISession

    func makeUIViewController(context: Context) -> ChatViewController {
        ChatViewController(session: session)
    }

    func updateUIViewController(
        _ uiViewController: ChatViewController,
        context: Context
    ) {
        // No dynamic updates needed -- the session drives the UI internally.
    }
}
```

Use it in a SwiftUI view hierarchy:

```swift
struct ContentView: View {
    @State private var session: AISession?

    var body: some View {
        Group {
            if let session {
                ChatView(session: session)
                    .ignoresSafeArea(.keyboard)
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            let config = ProviderConfiguration(
                apiKey: "sk-ant-xxxxxxxxxxxxxxxxxxxxxxxx",
                model: "claude-sonnet-4-20250514",
                maxTokens: 4096
            )
            let provider = AnthropicProvider(configuration: config)
            let manager = AISessionManager(provider: provider)
            session = try? await manager.createSession(
                systemPrompt: "You are a helpful assistant."
            )
        }
    }
}
```

### Building a Pure SwiftUI Chat

For a fully native SwiftUI chat, use `AISession` directly with an `ObservableObject` view model:

```swift
import SwiftUI
import OpenAPPCore

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [DisplayMessage] = []
    @Published var streamingText: String = ""
    @Published var isStreaming: Bool = false
    @Published var inputText: String = ""

    private let session: AISession
    private var streamTask: Task<Void, Never>?

    init(session: AISession) {
        self.session = session
    }

    func send() {
        let text = inputText
        guard !text.isEmpty else { return }
        inputText = ""

        messages.append(DisplayMessage(role: .user, text: text))
        isStreaming = true
        streamingText = ""

        streamTask = Task {
            let events = session.sendMessage(text)
            for await event in events {
                switch event {
                case .textDelta(let delta):
                    streamingText += delta
                case .completed:
                    messages.append(DisplayMessage(role: .assistant, text: streamingText))
                    streamingText = ""
                    isStreaming = false
                case .error(let error):
                    messages.append(DisplayMessage(role: .error, text: error.localizedDescription))
                    isStreaming = false
                default:
                    break
                }
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        if !streamingText.isEmpty {
            messages.append(DisplayMessage(role: .assistant, text: streamingText))
            streamingText = ""
        }
    }
}

struct DisplayMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String

    enum Role { case user, assistant, error }
}
```

Pair it with a SwiftUI view:

```swift
struct PureChatView: View {
    @StateObject var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isStreaming && !viewModel.streamingText.isEmpty {
                            Text(viewModel.streamingText)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let last = viewModel.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack {
                TextField("Message", text: $viewModel.inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.send() }

                if viewModel.isStreaming {
                    Button("Stop") { viewModel.cancel() }
                } else {
                    Button("Send") { viewModel.send() }
                        .disabled(viewModel.inputText.isEmpty)
                }
            }
            .padding()
        }
    }
}
```

---

## Summary

| Approach | Effort | Flexibility |
|---|---|---|
| `ChatViewController` out of the box | Minimal | Standard chat layout |
| Subclass `ChatViewController` | Low | Custom colors, cells, error handling |
| `UIViewControllerRepresentable` wrapper | Low | Embed UIKit chat in SwiftUI |
| Custom UI with `AISession` | Medium-High | Full control over every pixel |

Choose the level of customization that fits your project. In all cases, `AISession` is the data layer -- the UI is always optional and replaceable.

---

## Next Steps

- [Getting Started](GettingStarted.md) -- set up your first session
- [Tools](Tools.md) -- register tools that appear as actions in the chat
- [Architecture](Architecture.md) -- understand the module boundaries
