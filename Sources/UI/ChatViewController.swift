//
//  ChatViewController.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

/// A drop-in chat view controller for agent conversations.
/// Supports session switching: bind to an AIAgent, then use `switchSession(to:)`.
/// Subclass and override methods to customize behavior.
open class ChatViewController: UIViewController {

    // MARK: - Public API

    /// The agent powering this chat.
    public var agent: AIAgent?

    /// The currently displayed session ID.
    public private(set) var currentSessionId: String?

    /// Convenience: the current session object.
    public var currentSession: AISession? {
        guard let id = currentSessionId else { return nil }
        return agent?.session(id: id)
    }

    /// Switch to a different session. Cancels current stream observation,
    /// reloads history from the new session, and re-binds UI state observation.
    public func switchSession(to sessionId: String) {
        // 1. Cancel current stream observation
        currentStreamTask?.cancel()
        currentStreamTask = nil

        // 2. Unbind old session's UI state
        currentSession?.uiState.onChange = nil

        // 3. Update session ID
        currentSessionId = sessionId

        // 4. Reload UI from new session's messages
        reloadFromSession()

        // 5. Bind new session's UI state
        bindUIState()
    }

    /// Convenience initializer with a pre-configured agent and session.
    public init(agent: AIAgent? = nil, sessionId: String? = nil) {
        self.agent = agent
        self.currentSessionId = sessionId
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - UI

    private let tableView = UITableView()
    private let inputBar = UIView()
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)
    private var inputBarBottom: NSLayoutConstraint!

    // MARK: - Data

    private var chatMessages: [ChatMessage] = []
    private var currentStreamTask: Task<Void, Never>?

    // MARK: - Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupTableView()
        setupInputBar()
        setupKeyboardObservers()
        reloadFromSession()
        bindUIState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        currentSession?.uiState.onChange = nil
    }

    // MARK: - AISession ↔ UI

    /// Reload chatMessages from the current session's message history.
    /// Called on viewDidLoad and on session switch.
    public func reloadFromSession() {
        guard let session = currentSession else {
            chatMessages = []
            if isViewLoaded {
                tableView.reloadData()
            }
            return
        }

        chatMessages = session.messages.map { Self.toChatMessage($0) }

        // If the session is currently streaming, append a streaming placeholder
        if session.isRunning {
            let streamText = session.uiState.streamingText
            chatMessages.append(ChatMessage(role: .assistant, text: streamText, status: .streaming))
        }

        if isViewLoaded {
            tableView.reloadData()
            scrollToBottom(animated: false)
        }
    }

    /// Convert an AIAgentMessage to a UI ChatMessage.
    public static func toChatMessage(_ msg: AIAgentMessage) -> ChatMessage {
        let role: ChatMessage.Role = msg.role == .user ? .user : .assistant
        var text = msg.text
        var toolInfo: String?

        // Summarize tool calls for history display
        let calls = msg.toolCalls
        if !calls.isEmpty {
            let names = calls.map { $0.name }.joined(separator: ", ")
            toolInfo = "Tools: \(names)"
            if text.isEmpty {
                text = "[Tool call: \(names)]"
            }
        }

        // Summarize tool results
        let results = msg.content.compactMap { content -> String? in
            if case .toolResult(let r) = content {
                let preview = r.content.prefix(100)
                return "Result: \(preview)\(r.content.count > 100 ? "..." : "")"
            }
            return nil
        }
        if !results.isEmpty && text.isEmpty {
            text = results.joined(separator: "\n")
        }

        return ChatMessage(role: role, text: text, toolInfo: toolInfo)
    }

    // MARK: - UI State Binding

    private func bindUIState() {
        guard let session = currentSession else { return }
        session.uiState.onChange = { [weak self] key in
            Task { @MainActor [weak self] in
                self?.handleUIStateChange(key: key)
            }
        }
    }

    private func handleUIStateChange(key: String) {
        guard let session = currentSession else { return }
        switch key {
        case "streamingText":
            // Update the last streaming message
            guard !chatMessages.isEmpty,
                  chatMessages[chatMessages.count - 1].status == .streaming else { return }
            chatMessages[chatMessages.count - 1].text = session.uiState.streamingText
            let indexPath = IndexPath(row: chatMessages.count - 1, section: 0)
            tableView.reloadRows(at: [indexPath], with: .none)
            scrollToBottom(animated: false)

        case "isStreaming":
            if !session.uiState.isStreaming {
                // Streaming finished — reload from session to get finalized messages
                reloadFromSession()
                setInputEnabled(true)
            }

        case "lastError":
            if let error = session.uiState.lastError {
                guard !chatMessages.isEmpty,
                      chatMessages[chatMessages.count - 1].role == .assistant else { return }
                chatMessages[chatMessages.count - 1].text = "Error: \(error.localizedDescription)"
                chatMessages[chatMessages.count - 1].status = .error
                let indexPath = IndexPath(row: chatMessages.count - 1, section: 0)
                tableView.reloadRows(at: [indexPath], with: .none)
                setInputEnabled(true)
            }

        default:
            break // custom state changes — subclasses can override handleUIStateChange
        }
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.keyboardDismissMode = .interactive
        tableView.register(ChatMessageCell.self, forCellReuseIdentifier: ChatMessageCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
    }

    private func setupInputBar() {
        inputBar.backgroundColor = .secondarySystemBackground
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(separator)

        textField.placeholder = "Type a message..."
        textField.borderStyle = .roundedRect
        textField.returnKeyType = .send
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(textField)

        sendButton.setTitle("Send", for: .normal)
        sendButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(sendButton)

        inputBarBottom = inputBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        NSLayoutConstraint.activate([
            // Table view
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            // Input bar
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarBottom,
            inputBar.heightAnchor.constraint(equalToConstant: 52),

            // Separator
            separator.topAnchor.constraint(equalTo: inputBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            // Text field
            textField.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            textField.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            textField.heightAnchor.constraint(equalToConstant: 36),

            // Send button
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 50),
        ])
    }

    // MARK: - Keyboard

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }
        let offset = frame.height - view.safeAreaInsets.bottom
        inputBarBottom.constant = -offset
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
        scrollToBottom(animated: true)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }
        inputBarBottom.constant = 0
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    // MARK: - Send

    @objc private func sendTapped() {
        sendMessage()
    }

    private func sendMessage() {
        guard let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        guard let session = currentSession else { return }

        textField.text = ""
        setInputEnabled(false)

        // Add user message to display
        chatMessages.append(ChatMessage(role: .user, text: text))

        // Add streaming placeholder for assistant
        chatMessages.append(ChatMessage(role: .assistant, text: "", status: .streaming))
        reloadAndScrollToBottom()

        // Start agent via session — UI state updates come through uiState.onChange
        let stream = session.sendMessage(text)

        // Keep a reference to cancel on session switch
        currentStreamTask = Task { @MainActor in
            for await _ in stream {
                // Events are handled via uiState.onChange binding
                // We consume the stream to keep it alive
            }
        }
    }

    private func setInputEnabled(_ enabled: Bool) {
        textField.isEnabled = enabled
        sendButton.isEnabled = enabled
        sendButton.alpha = enabled ? 1.0 : 0.5
    }

    // MARK: - Helpers

    private func reloadAndScrollToBottom() {
        tableView.reloadData()
        scrollToBottom(animated: true)
    }

    private func scrollToBottom(animated: Bool) {
        guard !chatMessages.isEmpty else { return }
        let indexPath = IndexPath(row: chatMessages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }
}

// MARK: - UITableViewDataSource

extension ChatViewController: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chatMessages.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as! ChatMessageCell
        cell.configure(with: chatMessages[indexPath.row])
        return cell
    }
}

// MARK: - UITextFieldDelegate

extension ChatViewController: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendMessage()
        return true
    }
}

#endif
