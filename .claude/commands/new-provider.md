---
description: Scaffold a new LLM provider following the AnthropicProvider 4-file structure
argument-hint: <ProviderName>
---

为 `$ARGUMENTS` 创建新 LLM provider。

## 前置阅读（必做）

读以下 4 个参考文件理解模式：
- `Sources/Core/Providers/Anthropic/AnthropicProvider.swift` — Provider 协议实现
- `Sources/Core/Providers/Anthropic/AnthropicMapper.swift` — 双向映射
- `Sources/Core/Providers/Anthropic/AnthropicTypes.swift` — Codable wire format
- `Sources/Core/Providers/Anthropic/SSEParser.swift` — 流式解析

也读 `Sources/Core/Model/ModelProvider.swift` 看协议定义和 `ModelSpec` / `ProviderStreamEvent`。

## 参数处理

如果 `$ARGUMENTS` 为空，问用户：
- Provider 名（PascalCase，如 `OpenAI`）
- API base URL
- 主要模型 ID 列表（用于 `ModelSpec`）
- 是否支持流式 SSE（默认是）
- 鉴权方式（Bearer token / API key header）

## 文件结构

在 `Sources/Core/Providers/<Name>/` 下创建：

```
<Name>Provider.swift   ← 实现 ModelProvider 协议
<Name>Mapper.swift     ← AIAgentMessage ↔ wire format
<Name>Types.swift      ← Codable 请求/响应类型
SSEParser.swift        ← 如果 SSE 格式与 Anthropic 不同，复制并改；否则复用 Anthropic 的
```

## 关键约束

### iOS 13 双路径流式

参考 `AnthropicProvider.swift` 中 `streamCompletion` 实现。**必须**：

```swift
if #available(iOS 15, *) {
    let (asyncBytes, response) = try await urlSession.bytes(for: request)
    // 用 asyncBytes.lines 处理
} else {
    // iOS 13/14 走 URLSessionDataDelegate 降级
    // 通过 AsyncStream + delegate 桥接
}
```

不要只写 iOS 15+ 路径。

### ConcurrencyLimiter

复用 `Sources/Core/Foundation/ConcurrencyLimiter.swift`，给 provider 加默认 limit=5 的 actor 限流。

### ModelSpec

在 provider 内提供 `modelSpec(for modelId:)`，返回 `ModelSpec(id, reasoning, inputModalities, contextWindow, maxTokens)`。最少注册 1-2 个主力模型。

### 注册到 ModelProviderCentral

在文档（不是代码）里告诉调用方如何注册：

```swift
ModelProviderCentral.default.register(<Name>Provider(apiKey: "..."))
```

不要改 `ModelProviderCentral.swift` 自动注册——保持 provider 解耦。

## 验证

1. 跑 `/build` 确认编译通过。
2. 检查 `DemoConfig.swift` 是否需要扩展支持新 provider 配置（早期非必需）。
3. 提醒：完整流式测试需要真实 API key，建议在 demo app 里手测。

## 输出

简洁列出创建的 4 个文件路径 + 关键 TODO（如果有未实现的部分如 reasoning models 支持）。
