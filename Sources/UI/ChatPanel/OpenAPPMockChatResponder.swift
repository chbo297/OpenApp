//
//  OpenAPPMockChatResponder.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import Foundation

/// 模拟大模型回复源：对话流 UI 调试阶段替代真实 session 通路。
///
/// 事件形状与真实流式消费一致（开始 → 逐段增量 → 完成），
/// 第二阶段把它换成 AISession.sendMessage 绑定时，面板与列表无需改动。
/// 主线程使用。
@MainActor
final class OpenAPPMockChatResponder {

    enum Event {
        /// 回复开始（宿主应插入一条流式占位消息）。
        case began

        /// 流式增量：累积后的完整文本。
        case partial(String)

        /// 回复完成：最终完整文本。
        case completed(String)
    }

    var onEvent: ((Event) -> Void)?

    /// 首字延迟与逐段吐字间隔，模拟真实模型的响应节奏。
    private static let firstTokenDelay: TimeInterval = 0.6
    private static let tokenInterval: TimeInterval = 0.05
    private static let charactersPerTick = 2

    private var timer: Timer?
    private var pendingReply: [Character] = []
    private var emittedCount = 0

    deinit {
        timer?.invalidate()
    }

    func send(text: String) {
        cancel()
        pendingReply = Array(Self.mockReply(for: text))
        emittedCount = 0
        onEvent?(.began)

        let timer = Timer(
            fire: Date(timeIntervalSinceNow: Self.firstTokenDelay),
            interval: Self.tokenInterval,
            repeats: true
        ) { [weak self] _ in
            // Timer 已明确加入主 RunLoop；把 Foundation 的非隔离闭包签名还原为真实执行上下文。
            MainActor.assumeIsolated {
                self?.emitNextChunk()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    private func emitNextChunk() {
        emittedCount = min(pendingReply.count, emittedCount + Self.charactersPerTick)
        let text = String(pendingReply.prefix(emittedCount))
        if emittedCount >= pendingReply.count {
            cancel()
            onEvent?(.completed(text))
        } else {
            onEvent?(.partial(text))
        }
    }

    private static func mockReply(for text: String) -> String {
        "收到：\(text)\n（这是一条模拟回复，用于对话流 UI 调试；接入真实模型通路后这里将展示流式生成内容。）"
    }
}

#endif
