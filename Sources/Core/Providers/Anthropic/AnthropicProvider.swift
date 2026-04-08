//
//  AnthropicProvider.swift
//  OpenAPP
//

import Foundation

/// ModelProvider implementation for the Anthropic Messages API.
public final class AnthropicProvider: ModelProvider, @unchecked Sendable {
    public let name = "anthropic"
    public let baseURL: String
    public let apiKey: String
    public let apiProtocol: APIProtocol
    public let customHeaders: [String: String]
    public let models: [ModelConfiguration]
    public let requestTimeout: TimeInterval
    private let concurrencyLimiter: ConcurrencyLimiter

    /// Anthropic API version, managed internally.
    private let apiVersion = "2023-06-01"

    public init(
        baseURL: String,
        apiKey: String,
        apiProtocol: APIProtocol = .anthropicMessages,
        customHeaders: [String: String] = [:],
        models: [ModelConfiguration],
        requestTimeout: TimeInterval = 300,
        maxConcurrency: Int = 5
    ) {
        precondition(!models.isEmpty, "AnthropicProvider requires at least one model")
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.apiProtocol = apiProtocol
        self.customHeaders = customHeaders
        self.models = models
        self.requestTimeout = requestTimeout
        self.concurrencyLimiter = ConcurrencyLimiter(limit: maxConcurrency)
    }

    /// Stream a completion from the model.
    ///
    /// Full lifecycle:
    /// 1. Acquire a concurrency slot (waits if at limit)
    /// 2. Build the HTTP request via `buildRequest`
    /// 3. Send the request and stream the SSE response
    /// 4. Parse SSE events into `ProviderStreamEvent`s
    /// 5. Release the concurrency slot
    public func streamCompletion(
        messages: [AIAgentMessage],
        system: [ContentOrCacheControl<SystemPrompt>],
        tools: [ContentOrCacheControl<any ToolProtocol>],
        model: ModelConfiguration
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.concurrencyLimiter.wait()
                do {
                    let request = try self.buildRequest(messages: messages, system: system, tools: tools, model: model)
                    Logger.info("Anthropic", "streamCompletion: starting, model=\(model.id)")

                    if #available(iOS 15.0, macOS 12.0, *) {
                        Logger.debug("Anthropic", "streamCompletion: using bytes streaming (iOS 15+)")
                        try await self.streamWithBytes(request: request, continuation: continuation)
                    } else {
                        Logger.debug("Anthropic", "streamCompletion: using delegate streaming (iOS 13/14)")
                        await self.streamWithDelegate(request: request, continuation: continuation)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
                await self.concurrencyLimiter.signal()
            }
        }
    }

    // MARK: - iOS 15+ streaming via URLSession.bytes

    @available(iOS 15.0, macOS 12.0, *)
    private func streamWithBytes(
        request: URLRequest,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.finish(throwing: ModelError.invalidResponse)
            return
        }
        Logger.debug("Anthropic", "httpResponse: statusCode=\(httpResponse.statusCode)")

        if !(200..<300).contains(httpResponse.statusCode) {
            var body = ""
            for try await line in bytes.lines { body += line }
            Logger.error("Anthropic", "httpError: statusCode=\(httpResponse.statusCode), body=\(body.prefix(500))")
            continuation.finish(throwing: ModelError.httpError(
                statusCode: httpResponse.statusCode, body: body))
            return
        }

        var parser = SSEParser()
        var activeToolCalls: [Int: (id: String, name: String, jsonAccumulator: String)] = [:]

        for try await line in bytes.lines {
            if let sseEvent = parser.processLine(line) {
                for providerEvent in AnthropicMapper.parseSSEEvent(
                    sseEvent, activeToolCalls: &activeToolCalls) {
                    continuation.yield(providerEvent)
                }
            }
        }

        // Flush remaining SSE data
        if let sseEvent = parser.flush() {
            for providerEvent in AnthropicMapper.parseSSEEvent(
                sseEvent, activeToolCalls: &activeToolCalls) {
                continuation.yield(providerEvent)
            }
        }

        continuation.finish()
    }

    // MARK: - iOS 13+ fallback streaming via URLSessionDataDelegate

    private func streamWithDelegate(
        request: URLRequest,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async {
        let delegate = SSEStreamDelegate(continuation: continuation)
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.name = "openapp.sse-delegate"
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: delegateQueue)
        let task = session.dataTask(with: request)
        delegate.task = task
        task.resume()

        await delegate.waitUntilFinished()
        session.finishTasksAndInvalidate()
    }

    // MARK: - Private

    /// Build the URLRequest for the Anthropic Messages API.
    ///
    /// Constructs the URL, sets HTTP headers (x-api-key, anthropic-version, Content-Type,
    /// custom headers), and serializes the JSON body using the provided `model` configuration
    /// for model ID and max tokens.
    private func buildRequest(
        messages: [AIAgentMessage],
        system: [ContentOrCacheControl<SystemPrompt>],
        tools: [ContentOrCacheControl<any ToolProtocol>],
        model: ModelConfiguration
    ) throws -> URLRequest {
        let effectiveBaseURL = baseURL.isEmpty
            ? "https://api.anthropic.com"
            : baseURL
        let base = effectiveBaseURL.hasSuffix("/")
            ? String(effectiveBaseURL.dropLast())
            : effectiveBaseURL

        guard let url = URL(string: "\(base)/v1/messages") else {
            throw ModelError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Build request body manually to support cache_control in system/tools
        let anthropicMessages = AnthropicMapper.toAnthropicMessages(messages)
        let systemBlocks = AnthropicMapper.toAnthropicSystem(system)
        let toolsArray = AnthropicMapper.toAnthropicTools(tools)

        let messagesEncoder = JSONEncoder()
        let messagesData = try messagesEncoder.encode(anthropicMessages)
        let messagesJSON = try JSONSerialization.jsonObject(with: messagesData)

        var body: [String: Any] = [
            "model": model.id,
            "max_tokens": model.maxTokens,
            "stream": true,
            "messages": messagesJSON
        ]

        if !systemBlocks.isEmpty {
            body["system"] = systemBlocks
        }

        // Anthropic API rejects empty tools array
        if !toolsArray.isEmpty {
            body["tools"] = toolsArray
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Log the full request details
        Logger.debug("Anthropic", "buildRequest: url=\(url.absoluteString), model=\(model.id), maxTokens=\(model.maxTokens), messageCount=\(messages.count), systemSegments=\(system.count), toolCount=\(tools.count)")
        if Logger.isEnabled {
            if let bodyData = request.httpBody,
               let jsonObj = try? JSONSerialization.jsonObject(with: bodyData),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted, .sortedKeys]),
               let prettyStr = String(data: prettyData, encoding: .utf8) {
                Logger.debug("Anthropic", "buildRequest body:\n\(prettyStr)")
            }
        }

        return request
    }
}

// MARK: - SSEStreamDelegate (iOS 13/14 fallback for streaming)

/// URLSessionDataDelegate that receives streaming SSE data and feeds parsed events
/// into an `AsyncThrowingStream` continuation. Used on iOS 13/14 where `URLSession.bytes` is unavailable.
private final class SSEStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    private var parser = SSEParser()
    private var activeToolCalls: [Int: (id: String, name: String, jsonAccumulator: String)] = [:]
    private var httpStatusCode: Int?
    private var errorBody = Data()
    private var isErrorResponse = false

    private let finishLock = NSLock()
    private var _didFinish = false
    private var _finishContinuation: CheckedContinuation<Void, Never>?

    var task: URLSessionDataTask?

    init(continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    /// Awaitable gate — resolves when the delegate receives `didCompleteWithError`.
    func waitUntilFinished() async {
        finishLock.lock()
        if _didFinish {
            finishLock.unlock()
            return
        }
        await withCheckedContinuation { continuation in
            _finishContinuation = continuation
            finishLock.unlock()
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            httpStatusCode = http.statusCode
            Logger.debug("Anthropic", "delegate httpResponse: statusCode=\(http.statusCode)")
            if !(200..<300).contains(http.statusCode) {
                isErrorResponse = true
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if isErrorResponse {
            errorBody.append(data)
            return
        }

        // Split incoming data into lines and feed them to the SSE parser
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            if let sseEvent = parser.processLine(line) {
                for providerEvent in AnthropicMapper.parseSSEEvent(
                    sseEvent, activeToolCalls: &activeToolCalls) {
                    continuation.yield(providerEvent)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Logger.error("Anthropic", "delegate connectionError: \(error)")
            continuation.finish(throwing: error)
        } else if isErrorResponse {
            let body = String(data: errorBody, encoding: .utf8) ?? ""
            Logger.error("Anthropic", "delegate httpError: statusCode=\(httpStatusCode ?? 0), body=\(body.prefix(500))")
            continuation.finish(throwing: ModelError.httpError(
                statusCode: httpStatusCode ?? 0, body: body))
        } else {
            // Flush remaining SSE data
            if let sseEvent = parser.flush() {
                for providerEvent in AnthropicMapper.parseSSEEvent(
                    sseEvent, activeToolCalls: &activeToolCalls) {
                    continuation.yield(providerEvent)
                }
            }
            continuation.finish()
        }
        finishLock.lock()
        _didFinish = true
        let cont = _finishContinuation
        _finishContinuation = nil
        finishLock.unlock()
        cont?.resume()
    }
}
