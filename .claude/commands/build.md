---
description: Run swift build and report only errors/warnings concisely
---

跑 `swift build` 验证 SDK 编译。

执行步骤：

1. 在仓库根目录运行 `swift build` 并捕获完整输出。
2. 如果命令以非零退出码结束：
   - 提取 `error:` 和 `warning:` 行（用 `grep -E '(error|warning):'`），按文件路径分组打印。
   - 不要输出整页编译日志。
3. 如果命令成功且无 warning：一句话回复（如"`swift build` 通过"），不要复述输出。
4. 如果成功但有 warning：列出 warning 文件:line:column 与文本，建议修复但不强制。

注意：
- **不要**自动跑 `swift test`，测试由用户手动执行。
- 如果首次构建很慢（解析依赖、编译 actor 模型），耐心等待，不要重试。
- 编译失败常见原因：iOS 13 兼容、Sendable 边界、actor 隔离 —— 修复时考虑调用 swift-reviewer agent 复核。
