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

## 发包流程

1. 确认当前分支
   - 发包前必须先确认当前分支和目标分支。
   - 正式发包必须基于 `main`，不要在功能分支或临时分支上直接发 Release。
   - 检查命令：

```sh
git status --short --branch
git log --oneline --decorate -5
```

2. 合并到 main
   - 如果改动在非 `main` 分支，先提交当前改动。
   - 切换到 `main` 后合并该分支。
   - 合并后推送 `origin/main`。
   - 验证 `main` 和 `origin/main` 指向同一个最新提交。

3. 更新版本号
   - 修改 Xcode 工程里的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`。
   - 版本号与发布包、GitHub Release tag 保持一致。
   - 常规发包优先递增 `0.x.0` 小版本，不使用过细的 `0.x.y` 补丁版本，除非用户特别指定。
   - 示例：

```text
MARKETING_VERSION = 0.4.0
CURRENT_PROJECT_VERSION = 4
```

4. 构建 Release
   - 使用完整 Xcode 路径构建：

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage -configuration Release -derivedDataPath /private/tmp/CodexUsageReleaseDerivedData build
```

   - 构建必须看到 `BUILD SUCCEEDED`。

5. 生成 DMG
   - 从 Release 构建产物复制 `CodexUsage.app` 到临时打包目录。
   - 添加 `/Applications` 快捷方式。
   - 使用 `hdiutil` 生成：

```text
dist/CodexUsage-vX.Y.Z.dmg
```

   - 生成后必须运行：

```sh
hdiutil verify dist/CodexUsage-vX.Y.Z.dmg
codesign --verify --deep --strict --verbose=2 /private/tmp/CodexUsageReleaseDerivedData/Build/Products/Release/CodexUsage.app
```

6. 提交发布产物
   - 提交版本号变更、代码变更和新的 `dist/CodexUsage-vX.Y.Z.dmg`。
   - commit message 使用中文，格式遵守：

```text
type(scope): subject
```

   - 推送 `main`。

7. 创建 GitHub Release
   - 先检查现有 Releases：

```sh
gh release list --repo songcbo/CodexUsage --limit 10
```

   - 创建正式 Release：

```sh
gh release create vX.Y.Z dist/CodexUsage-vX.Y.Z.dmg --repo songcbo/CodexUsage --target main --title "CodexUsage vX.Y.Z" --notes "..." --latest
```

   - 验证：

```sh
gh release view vX.Y.Z --repo songcbo/CodexUsage
gh release list --repo songcbo/CodexUsage --limit 5
```

8. 最终确认
   - GitHub Releases 中 `vX.Y.Z` 必须是 Latest。
   - Release 附件必须包含对应 DMG。
   - `main` 必须已经推送到 `origin/main`。
