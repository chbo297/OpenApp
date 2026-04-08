# Tools

This guide covers the tool system in OpenAPP: defining tools, describing their schemas, registering them, and managing per-session tool state.

## Tool Protocol

Every tool conforms to `Tool`:

```swift
public protocol Tool: Sendable {
    /// A JSON Schema description of the tool and its parameters.
    var schema: ToolSchema { get }

    /// Execute the tool with the given input and return a result.
    func execute(input: [String: Any]) async throws -> ToolOutput
}
```

The `schema` property tells the LLM what the tool does and what arguments it accepts. When the LLM emits a `tool_use` block, the `AIAgentLoop` calls `execute(input:)` with the parsed arguments and feeds the result back into the conversation.

---

## ToolSchema

`ToolSchema` is a Swift representation of a JSON Schema object:

```swift
public struct ToolSchema: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: InputSchema

    public init(name: String, description: String, inputSchema: InputSchema)
}

public struct InputSchema: Codable, Sendable {
    public let type: String                          // always "object"
    public let properties: [String: PropertySchema]
    public let required: [String]

    public init(
        properties: [String: PropertySchema],
        required: [String] = []
    )
}
```

### PropertySchema

Describes a single property in the tool's input:

```swift
public struct PropertySchema: Codable, Sendable {
    public let type: String            // "string", "number", "integer", "boolean", "array", "object"
    public let description: String?
    public let enumValues: [String]?   // restrict to a fixed set
    public let items: PropertySchema?  // for arrays
    public let properties: [String: PropertySchema]?  // for nested objects
    public let required: [String]?     // for nested objects

    public init(
        type: String,
        description: String? = nil,
        enumValues: [String]? = nil,
        items: PropertySchema? = nil,
        properties: [String: PropertySchema]? = nil,
        required: [String]? = nil
    )
}
```

These types serialize directly to the JSON Schema format expected by LLM APIs.

---

## ToolOutput

The result returned from a tool execution:

```swift
public enum ToolOutput: Sendable {
    /// A plain text result.
    case text(String)

    /// A JSON-encodable result.
    case json(Encodable & Sendable)

    /// An error message to send back to the LLM.
    case error(String)

    /// An image (base64-encoded data and media type).
    case image(data: Data, mediaType: String)
}
```

The agent loop converts each `ToolOutput` into a `tool_result` content block and appends it to the message history before the next LLM call.

---

## Registering Tools with ToolRegistry

`ToolRegistry` is a thread-safe container for tools:

```swift
let registry = ToolRegistry()

// Register individual tools
registry.register(WeatherLookupTool())
registry.register(CalculatorTool())

// Or register a batch
registry.register(tools: [WeatherLookupTool(), CalculatorTool()])
```

When creating a session, pass tools directly -- the session builds its own registry internally:

```swift
let session = try await manager.createSession(
    systemPrompt: "You are a helpful assistant.",
    tools: [WeatherLookupTool(), CalculatorTool()]
)
```

### Tool Lookup

During the agent loop, tools are resolved by name:

```swift
// Internal to AIAgentLoop
if let tool = registry.tool(named: "weather_lookup") {
    let output = try await tool.execute(input: parsedInput)
}
```

If a tool is not found, the loop returns a `tool_result` with an error message so the LLM can recover gracefully.

---

## Shared Tools vs. Per-Session Tools (ToolFactory)

Some tools are stateless and can be shared across all sessions (e.g., a calculator). Others need per-session state (e.g., a tool that writes to a session-specific scratch pad).

### Shared Tools

Pass instances directly:

```swift
let calc = CalculatorTool()  // stateless, safe to share

let session1 = try await manager.createSession(
    systemPrompt: "...",
    tools: [calc]
)
let session2 = try await manager.createSession(
    systemPrompt: "...",
    tools: [calc]
)
```

### ToolFactory

Use `ToolFactory` when each session needs its own tool instance:

```swift
public struct ToolFactory: Sendable {
    public let name: String
    public let create: @Sendable () -> Tool

    public init(name: String, create: @escaping @Sendable () -> Tool)
}
```

Register factories with the session manager:

```swift
let manager = AISessionManager(
    provider: provider,
    toolFactories: [
        ToolFactory(name: "scratchpad") {
            ScratchpadTool()  // fresh instance per session
        }
    ]
)
```

When `createSession` is called, the manager invokes each factory and merges the resulting tools with any tools passed directly to the session.

---

## SystemPrompt.toolPrompts

If your tools need additional instructions in the system prompt (beyond the JSON Schema), use `SystemPrompt.toolPrompts`:

```swift
let systemPrompt = SystemPrompt(
    base: "You are a helpful assistant.",
    toolPrompts: [
        "weather_lookup": "When reporting weather, always include the temperature in both Celsius and Fahrenheit.",
        "calculator": "Show your work step by step before giving the final answer."
    ]
)

let session = try await manager.createSession(
    systemPrompt: systemPrompt,
    tools: [WeatherLookupTool(), CalculatorTool()]
)
```

The session assembles the final system prompt by appending each tool prompt to the base prompt. This keeps tool-specific instructions co-located with tool definitions.

---

## Complete Example: Weather Lookup Tool

Below is a full implementation of a tool that fetches current weather data.

### 1. Define the Tool

```swift
import Foundation
import OpenAPPCore

public final class WeatherLookupTool: Tool {
    public var schema: ToolSchema {
        ToolSchema(
            name: "weather_lookup",
            description: "Look up the current weather for a given city.",
            inputSchema: InputSchema(
                properties: [
                    "city": PropertySchema(
                        type: "string",
                        description: "The city name, e.g. 'San Francisco'"
                    ),
                    "unit": PropertySchema(
                        type: "string",
                        description: "Temperature unit",
                        enumValues: ["celsius", "fahrenheit"]
                    )
                ],
                required: ["city"]
            )
        )
    }

    public init() {}

    public func execute(input: [String: Any]) async throws -> ToolOutput {
        guard let city = input["city"] as? String else {
            return .error("Missing required parameter: city")
        }

        let unit = (input["unit"] as? String) ?? "celsius"

        // In production, call a real weather API here.
        let weather = try await fetchWeather(city: city, unit: unit)

        return .text(
            "Current weather in \(city): \(weather.temperature)\u{00B0}\(unit == "celsius" ? "C" : "F"), "
            + "\(weather.condition). Humidity: \(weather.humidity)%."
        )
    }

    private func fetchWeather(city: String, unit: String) async throws -> WeatherData {
        // Replace with a real API call
        let url = URL(string: "https://api.example.com/weather?city=\(city)&unit=\(unit)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(WeatherData.self, from: data)
    }
}

private struct WeatherData: Decodable {
    let temperature: Double
    let condition: String
    let humidity: Int
}
```

### 2. Register and Use

```swift
import OpenAPPCore

let provider = AnthropicProvider(configuration: ProviderConfiguration(
    apiKey: "sk-ant-xxxxxxxxxxxxxxxxxxxxxxxx",
    model: "claude-sonnet-4-20250514",
    maxTokens: 4096
))

let manager = AISessionManager(provider: provider)

let session = try await manager.createSession(
    systemPrompt: "You are a helpful assistant with access to real-time weather data.",
    tools: [WeatherLookupTool()]
)

let events = session.sendMessage("What's the weather like in Tokyo right now?")

for await event in events {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .toolUse(let name, _):
        print("\n[Calling \(name)...]")
    case .toolResult(let name, let output):
        print("[Result from \(name): \(output)]")
    case .completed:
        print("\n--- Done ---")
    case .error(let error):
        print("Error: \(error)")
    }
}
```

### 3. What Happens at Runtime

1. The user asks about Tokyo weather.
2. The LLM sees the `weather_lookup` tool schema and emits a `tool_use` block with `{"city": "Tokyo"}`.
3. The `AIAgentLoop` finds `WeatherLookupTool` in the registry and calls `execute(input:)`.
4. The tool fetches data and returns `.text("Current weather in Tokyo: ...")`.
5. The loop appends the `tool_result` to the message history and calls the LLM again.
6. The LLM incorporates the weather data into a natural language response.
7. The loop emits `.completed`.

---

## Next Steps

- [Providers](Providers.md) -- understand the LLM communication layer
- [Architecture](Architecture.md) -- see how tools fit into the agent loop
- [UI Customization](UICustomization.md) -- display tool results in the chat UI
