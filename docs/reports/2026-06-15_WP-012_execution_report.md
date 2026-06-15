# WP-012 批量执行报告

## 基本信息

- **团队名称**: `batch-20260615-WP012`
- **执行日期**: 2026-06-15
- **工作包**: WP-012（含 3 子包：WP-012-1-impl / WP-012-2-verify / WP-012-3-review）
- **执行模式**: agent-dispatcher，standard 拆分，严格串行链（impl → verify → review）
- **提交**: `0aa733b`

## 执行总览

| Task ID | 工作包 | 角色（Teamee） | 状态 | 依赖 | 说明 |
|---------|--------|----------------|------|------|------|
| #1 | WP-012-1-impl | implementer-t1 | ✅ 完成 | - | cboot.ps1 转 UTF-8 with BOM，正文逐字节不变 |
| #2 | WP-012-2-verify | tester-t2 | ✅ 完成 | #1 | verify 关卡通过：PS5.1 AST 37→0、PS7 0、启动正常 |
| #3 | WP-012-3-review | reviewer-t3 | ✅ 完成 | #2 | 版本号 v1.0.10、CHANGELOG、CLAUDE.md 编码规范 |

> 调度说明：严格串行链无并行机会，采用顺序调度（每任务一个专用 general-purpose teamee，完成后即时释放）。verify 作为关卡，通过才放行 review。受环境约束（SendMessage 无法发起 shutdown / 默认不清理 teams），teamee 完成后保持 idle、未走文件系统级销毁，不影响交付。

## 修复结果

### 根因（可追溯）
v1.0.9 误将 `cboot.ps1` 改为 UTF-8 无 BOM（见 CHANGELOG [1.0.9]「移除 cboot.ps1 文件开头 UTF-8 BOM」）。Windows PowerShell 5.1（双击 `.ps1` / `cboot.cmd` 默认调用的 `powershell.exe`）对无 BOM 的 `.ps1` 按系统 ANSI 代码页（中文系统为 GBK/CP936）解码，而非 UTF-8。中文 UTF-8 字节中的 `0x22`/`0x7D`/`0x29` 被 GBK 误读为 `"`/`}`/`)`，打乱字符串终止符与大括号配对，触发 **37 条 AST 解析错误**，脚本根本未能解析、PowerShell 立即退出 → 窗口「一闪而过」。PS 7（pwsh）默认按 UTF-8 解码，故开发者无感，问题在开发期隐蔽、只在终端用户侧爆发。

### 修复
`cboot.ps1` 由 UTF-8 无 BOM 恢复为 UTF-8 with BOM（首字节 `EF BB BF`），**仅前置 3 字节 BOM，正文逐字节不变**（86609 → 86612 字节，差值正好 3）。

### 验证（关卡）
| 验证项 | 结果 |
|--------|------|
| BOM 字节 | `EF BB BF` ✅ |
| PS 5.1 AST 解析（powershell.exe 真实 5.1 引擎） | **37 错误 → 0** ✅ |
| PS 7 AST 解析（pwsh） | **0**（无回归）✅ |
| 实际启动（5.1 引擎 `-File` 调用链） | 进入交互菜单、未闪退 ✅ |
| 全项目 `.ps1` 扫描 | 仅 `cboot.ps1` + `scripts\test-context-window.ps1` 含中文，**均已有 BOM**，无隐患 ✅ |
| 对照证据 | `.bak`（无 BOM）PS5.1=37 错误 vs 修复后（有 BOM）PS5.1=0 错误，闭环 ✅ |

## 📁 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `cboot.ps1` | M | 编码 UTF-8 无 BOM → with BOM（正文逐字节不变） |
| `README.md` | M | 徽章 v1.0.9 → v1.0.10；内置 Changelog 新增 v1.0.10 条目 |
| `CHANGELOG.md` | M | 顶部新增 `[1.0.10] - 2026-06-15` Fixed 条目 |
| `CLAUDE.md` | M（本地） | 版本号 v1.0.6 → v1.0.10；新增「编码规范」段（.gitignore 忽略，不入库） |
| `task.md` | M | WP-012 + 3 子任务 → ✅ 完成；最近完成顶部新增条目 |
| `.gitignore` | M | + `*.bak` |
| `docs/wp/WP-012.md` + 3 子文档 | A | 4 个 WP 定义文档（状态已置 ✅） |
| `docs/reports/2026-06-15_WP-012_execution_report.md` | A | 本报告 |
| `cboot.ps1.bak` | 本地保留 | 转换前备份（被 `*.bak` 忽略，不入库） |

## 💡 经验

含中文的 PowerShell 脚本必须存为 UTF-8 with BOM——详见 `CLAUDE.md`「编码规范」段与 `docs/EXPERIENCE.md`。

---
报告生成时间：2026-06-15
