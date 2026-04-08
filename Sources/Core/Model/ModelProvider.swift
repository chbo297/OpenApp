//
//  ModelProvider.swift
//  OpenAPP
//

import Foundation

// MARK: - ContentOrCacheControl

/// Sequence element: either actual content or a cache control marker.
/// Used for system prompt arrays (T = String) and tools arrays (T = any ToolProtocol).
///
/// When a Provider serializes the array for an API request, `.cacheControl` causes
/// `"cache_control": { "type": "ephemeral" }` to be added to the preceding content element.
public enum ContentOrCacheControl<T: Sendable>: Sendable {
    /// Actual content (prompt text or Tool).
    case content(T)
    /// Cache breakpoint marker — the provider attaches cache_control to the previous item.
    case cacheControl
}

// MARK: - API Protocol

/// Wire-format protocol for communicating with a model provider.
/// Currently only `.anthropicMessages` is implemented; the rest are reserved for future use.
public enum APIProtocol: String, Sendable, Codable, CaseIterable {
    /// Anthropic Messages API (Claude models).
    case anthropicMessages = "anthropic-messages"
    /// OpenAI Chat Completions API.
    case openaiCompletions = "openai-completions"
    /// OpenAI Responses API.
    case openaiResponses = "openai-responses"
    /// OpenAI Codex Responses API.
    case openaiCodexResponses = "openai-codex-responses"
    /// Google Generative AI (Gemini models).
    case googleGenerativeAI = "google-generative-ai"
    /// GitHub Copilot.
    case githubCopilot = "github-copilot"
    /// AWS Bedrock Converse Stream API.
    case bedrockConverseStream = "bedrock-converse-stream"
    /// Ollama local models.
    case ollama = "ollama"
    /// Azure OpenAI Responses API.
    case azureOpenaiResponses = "azure-openai-responses"
}

// MARK: - Model Configuration

/// Per-model configuration within a provider.
public struct ModelConfiguration: Sendable, Codable {
    /// Model identifier sent to the API (e.g., "Claude Opus 4.6").
    public var id: String
    /// Human-friendly short name (e.g., "opus"). Defaults to `id`.
    public var name: String
    /// Whether this model supports extended thinking / reasoning mode.
    public var reasoning: Bool
    /// Input modalities the model accepts (e.g., ["text", "image"]).
    public var inputModalities: [String]
    /// Total context window size (input + output tokens). Default: 200000.
    public var contextWindow: Int
    /// Maximum output tokens per single response. Default: 64000.
    public var maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case id, name, reasoning, contextWindow, maxTokens
        case inputModalities = "input"
    }

    public init(
        id: String,
        name: String? = nil,
        reasoning: Bool = false,
        inputModalities: [String] = ["text"],
        contextWindow: Int = 200_000,
        maxTokens: Int = 64_000
    ) {
        self.id = id
        self.name = name ?? id
        self.reasoning = reasoning
        self.inputModalities = inputModalities
        self.contextWindow = contextWindow
        self.maxTokens = maxTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        reasoning = try container.decodeIfPresent(Bool.self, forKey: .reasoning) ?? false
        inputModalities = try container.decodeIfPresent([String].self, forKey: .inputModalities) ?? ["text"]
        contextWindow = try container.decodeIfPresent(Int.self, forKey: .contextWindow) ?? 200_000
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 64_000
    }
}


// MARK: - Provider Stream Events

/// Events emitted during a streaming model completion.
public enum ProviderStreamEvent: Sendable {
    /// A chunk of text from the assistant.
    case textDelta(String)
    /// The assistant wants to call a tool.
    case toolCall(AIAgentMessage.ToolCall)
    /// The stream has ended. `stopReason` indicates why.
    case done(stopReason: StopReason)
    /// Token usage information.
    case usage(inputTokens: Int, outputTokens: Int)
}

extension ProviderStreamEvent {
    /// Why the model stopped generating.
    public enum StopReason: String, Sendable {
        case endTurn = "end_turn"
        case toolUse = "tool_use"
        case maxTokens = "max_tokens"
        case stopSequence = "stop_sequence"
        case unknown
    }
}

// MARK: - Model Provider Protocol

/// Abstraction over model providers (Anthropic, OpenAI, etc.).
/// Each provider maps `ContentOrCacheControl` arrays to its own API format.
public protocol ModelProvider: Sendable {
    /// Provider name (e.g., "anthropic", "openai").
    var name: String { get }
    /// Base URL for the provider API (e.g., "https://api.anthropic.com").
    var baseURL: String { get }
    /// API key for authentication.
    var apiKey: String { get }
    /// Which API protocol to use for this provider.
    var apiProtocol: APIProtocol { get }
    /// Additional HTTP headers to include in API requests.
    var customHeaders: [String: String] { get }
    /// Available models for this provider. Must not be empty.
    var models: [ModelConfiguration] { get }
    /// API request timeout in seconds. LLM completions are long-running; default 300s.
    var requestTimeout: TimeInterval { get }

    /// Stream a completion from the model.
    /// - Parameters:
    ///   - messages: Conversation history.
    ///   - system: System prompt segments with optional cache control markers.
    ///   - tools: Tool definitions with optional cache control markers.
    ///   - model: The model configuration to use for this request.
    func streamCompletion(
        messages: [AIAgentMessage],
        system: [ContentOrCacheControl<SystemPrompt>],
        tools: [ContentOrCacheControl<any ToolProtocol>],
        model: ModelConfiguration
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error>
}
