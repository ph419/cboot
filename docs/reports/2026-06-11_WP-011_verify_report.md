# WP-011-3-verify 验证报告

| 属性 | 值 |
|------|-----|
| 工作包 | WP-011（修复 1M 上下文窗口误删 CLAUDE_CODE_AUTO_COMPACT_WINDOW — WP-010 回归修复） |
| 子任务 | WP-011-3-verify |
| 执行角色 | tester (verify) — tester-t3 |
| 验证日期 | 2026-06-11 |
| 前置依赖 | WP-011-1-impl ✅、WP-011-2-test ✅ |

## 验证目标

确认 `Set-ContextWindowEnv`（`cboot.ps1:189-216`）修复后：
- **<1M（如 200K）**：settings 含 `CLAUDE_CODE_DISABLE_1M_CONTEXT="1"` + `CLAUDE_CODE_AUTO_COMPACT_WINDOW="200000"`
- **>=1M（如 1M）**：settings 无 `CLAUDE_CODE_DISABLE_1M_CONTEXT`，且 `CLAUDE_CODE_AUTO_COMPACT_WINDOW="1000000"`（**不再被误删**，WP-010 回归 bug 已消除）
- hashtable 与 PSCustomObject 两种模板路径均正确
- 测试脚本全 PASS、cboot.ps1 语法无误

## 验证结果

### A1. 测试脚本全 PASS（退出码 0）

命令：`pwsh -NoProfile -File scripts/test-context-window.ps1`

```
[PASS] 用例1: hashtable+1M 无DISABLE_1M_CONTEXT, AUTO_COMPACT_WINDOW=1000000
[PASS] 用例2: hashtable+200K DISABLE_1M_CONTEXT=1, AUTO_COMPACT_WINDOW=200000
[PASS] 用例3(根因): PSCustomObject+1M 预含200K残留 → 无DISABLE_1M_CONTEXT, AUTO_COMPACT_WINDOW=1000000(覆盖200000)
[PASS] 用例4: PSCustomObject+1M 无残留 无DISABLE_1M_CONTEXT, AUTO_COMPACT_WINDOW=1000000
[PASS] 用例5: PSCustomObject+500K DISABLE_1M_CONTEXT=1, AUTO_COMPACT_WINDOW=500000
[PASS] 用例6(端到端): 200K模板→新建1M→JSON序列化 无DISABLE_1M_CONTEXT, 含AUTO_COMPACT_WINDOW=1000000
[PASS] 用例7: PSCustomObject+2M 无DISABLE_1M_CONTEXT, AUTO_COMPACT_WINDOW=2000000

Passed: 7 / Failed: 0
EXIT_CODE=0
```

**结论**：7/7 用例 PASS，退出码 0。✅

### A2. cboot.ps1 语法检查通过

注意：文档原命令 `[System.Management.Automation.PSParser]::TokenString(...)` 在 PowerShell 7 中方法名拼写有误（`PSParser` 上无 `TokenString` 方法），正确方法为静态 `Tokenize`。采用等效的正确语法检查：

```powershell
$errors = $null
[void][System.Management.Automation.PSParser]::Tokenize((Get-Content 'D:\cboot\cboot.ps1' -Raw), [ref]$errors)
```

输出：`OK (no syntax errors)`（0 个语法错误）。✅

### A3 / A4. 手动复现 200K / 1M 场景（针对 cboot.ps1 生产函数）

为避免仅验证测试脚本内的函数副本，本次复现**直接从 `cboot.ps1` 本体提取 `Set-ContextWindowEnv` 源码并在会话内执行**（in-memory dot-source 等效，绕过主循环），确保验证的是生产代码本身。

提取函数体长度 1345 字符，覆盖 hashtable / PSCustomObject 双分支。

#### 复现 A：200K 场景（应 DISABLE=1 + AUTO=200000）

| 用例 | env 类型 | 输入 size | DISABLE_1M_CONTEXT | AUTO_COMPACT_WINDOW | 结果 |
|------|----------|-----------|--------------------|---------------------|------|
| A1 | hashtable | 200000 | `"1"` ✅ | `"200000"` ✅ | PASS |
| A2 | PSCustomObject | 200000 | `"1"` ✅ | `"200000"` ✅ | PASS |

#### 复现 B：1M 场景（应无 DISABLE + AUTO=1000000）

| 用例 | env 类型 | 输入 size | 模板残留 | DISABLE_1M_CONTEXT | AUTO_COMPACT_WINDOW | 结果 |
|------|----------|-----------|----------|--------------------|---------------------|------|
| B1（根因场景） | PSCustomObject | 1000000 | 预含 200K 两残留字段 | 不存在 ✅ | `"1000000"`（覆盖了残留的 200000）✅ | PASS |
| B2 | hashtable | 1000000 | 无 | 不存在 ✅ | `"1000000"` ✅ | PASS |

#### 端到端 JSON 序列化复现（模拟 New-SettingsTemplate 保存 settings 文件）

模拟「复用 200K 模板新建 1M 模型」的完整流程：对 env 调用 `Set-ContextWindowEnv(..., 1000000)` 后 `ConvertTo-Json -Depth 10`。

实际 JSON 输出：
```json
{
  "ANTHROPIC_API_KEY": "sk-e2e",
  "env": {
    "ANTHROPIC_API_KEY": "sk-e2e",
    "ANTHROPIC_BASE_URL": "https://api.example.com",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000"
  }
}
```

- `CLAUDE_CODE_DISABLE_1M_CONTEXT`：不存在 ✅
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW`：`"1000000"`（残留 200000 被正确覆盖，非删除）✅

**综合**：A1=A2=B1=B2=E2E=`True`，`ALL_PASS=True`。✅

## 验收标准达成情况

| 标准 | 描述 | 状态 |
|------|------|------|
| WP-011-3-A1 | 测试脚本全 PASS（退出码 0） | ✅ 7/7 PASS，退出码 0 |
| WP-011-3-A2 | cboot.ps1 语法检查通过 | ✅ 0 语法错误 |
| WP-011-3-A3 | 200K 场景字段符合预期（DISABLE=1 + AUTO=200000） | ✅ hashtable/PSCustomObject 双路径通过 |
| WP-011-3-A4 | 1M 场景字段符合预期（无 DISABLE + AUTO=1000000） | ✅ 含 200K 残留的根因场景通过 |
| WP-011-3-A5 | 验证报告已写入 | ✅ 本文件 |

## 父工作包 WP-011 整体验收标准

| WP-011 标准 | 验证方式 | 状态 |
|------|----------|------|
| 填 1M（含/不含 200K 残留模板）→ 无 DISABLE、AUTO=1000000 | 复现 B1 / B2 / E2E + 测试用例 3/4/6 | ✅ |
| 填 200K/500K → DISABLE=1 + AUTO=200000/500000 | 复现 A1/A2 + 测试用例 2/5 | ✅ |
| hashtable 与 PSCustomObject 两路径均通过 | 复现 A1/B2 (hashtable) + A2/B1 (PSCustomObject) | ✅ |
| 测试脚本全 PASS | A1 | ✅ |
| README/CHANGELOG 版本号 → v1.0.8 | 属于 WP-011-4-review 职责 | ⏳ 移交 review |

## 遇到的问题与解决方案

1. **测试输出中文乱码**：Bash 工具运行 pwsh 时 GBK/UTF-8 编码冲突导致中文显示乱码，但 `[PASS]`/`Passed: 7 / Failed: 0`/`EXIT_CODE=0` 等关键结果 ASCII 可读，不影响判断。改用 PowerShell 工具复现可正常显示中文。
2. **文档语法检查命令拼写错误**：`[System.Management.Automation.PSParser]::TokenString(...)` 在 PS7 中不存在该方法（正确为静态 `Tokenize`，返回 token 数组 + 错误引用）。采用 `Tokenize` 等效实现，结果可靠。建议后续 review 校正文档示例命令。
3. **cboot.ps1 不可直接 dot-source**：脚本末尾含顶层 `try/catch` + `while` 主循环，直接 dot-source 会执行主循环卡死。改用「正则/括号配平提取目标函数源码 → `Invoke-Expression` 在会话内定义」方式，等效验证且不触发主循环，确保验证的是生产代码而非测试脚本副本。

## 结论

**WP-011 回归修复验证通过**。`Set-ContextWindowEnv` 的 `>=1M` 分支不再误删 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`，而是正确设为上下文窗口大小（1M=1000000），同时保留 `DISABLE_1M_CONTEXT` 的移除逻辑。200K / 1M / 2M 各场景及双类型路径均符合预期，无回归。可移交 WP-011-4-review。
