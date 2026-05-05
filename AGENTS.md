# CodexUsage 项目协作规则

## 用量扫描口径

- 不能按 `sessions/YYYY/MM/DD` 路径日期直接归属用量；用户可能在今天继续昨天创建的会话，jsonl 仍保留在昨天目录。
- 增量刷新时，先在 `~/.codex/sessions` 里按文件 `mtime` 找候选 jsonl，再按每一行 JSON 的 `timestamp` 归属到本地日期。
- `token_count` 的 `last_token_usage` 按该行 `timestamp` 所在日期计入，不要把整个 jsonl 都算到文件路径日期或文件修改日期。
- 日常 today/recent 刷新优先只扫 active `sessions`；`archived_sessions` 更适合在全量 rebuild 时处理，避免每次刷新都做重活。

## macOS 构建验证

- 本机安装了完整 Xcode：`/Applications/Xcode.app`。
- `xcode-select -p` 可能返回 `/Library/Developer/CommandLineTools`，这不代表没有 Xcode，只是命令行默认开发者目录没有选中 Xcode.app。
- 需要构建验证时，优先直接调用：

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage -configuration Debug -derivedDataPath /private/tmp/CodexUsageDerivedData build
```

- 使用 `/private/tmp/CodexUsageDerivedData` 避免沙盒环境写 `~/Library/Developer/Xcode/DerivedData` 或日志目录时被权限拦住。
