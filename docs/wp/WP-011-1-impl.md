# WP-011-1-impl: 修复 Set-ContextWindowEnv `>=1M` 分支误删 AUTO_COMPACT_WINDOW

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-011.md`
> - 包含: 问题分析（WP-010 矫枉过正根因）、修复方案、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | impl |
| **父工作包** | WP-011 |
| **依赖** | 无 |
| **执行角色** | implementer |
| **状态** | ✅ 完成 |

## 职责

修正 `Set-ContextWindowEnv`（`cboot.ps1:189-218`）的 `>=1M` 分支：将"移除 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`"改为"设置为 `"$ContextWindowSize"`"。`DISABLE_1M_CONTEXT` 的移除逻辑保持不变。hashtable 与 PSCustomObject 两条路径必须同步修正。

## 任务清单

- [x] hashtable `>=1M` 分支（`cboot.ps1:202`）：`$EnvObject.Remove('CLAUDE_CODE_AUTO_COMPACT_WINDOW') | Out-Null` → `$EnvObject['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] = "$ContextWindowSize"`
- [x] PSCustomObject `>=1M` 分支（`cboot.ps1:213-215`）：移除该字段的存在判断 + Remove 块 → `$EnvObject | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' -Value "$ContextWindowSize" -Force`
- [x] 确认 `DISABLE_1M_CONTEXT` 的移除逻辑（hashtable `cboot.ps1:201`、PSCustomObject `cboot.ps1:210-212`）**未被改动**
- [x] 确认 `<1M` 分支（`cboot.ps1:197-199`、`206-208`）**未被改动**
- [x] 本地语法检查：`pwsh -NoProfile -Command "$null = [ScriptBlock]::Create((Get-Content cboot.ps1 -Raw)); 'OK'"` 无报错

## 验收标准

- [x] WP-011-1-A1：`>=1M` 时 `CLAUDE_CODE_DISABLE_1M_CONTEXT` 被移除、`CLAUDE_CODE_AUTO_COMPACT_WINDOW` 被设为 `$ContextWindowSize`
- [x] WP-011-1-A2：`<1M` 行为不变（DISABLE_1M_CONTEXT=1 + AUTO_COMPACT_WINDOW=size）
- [x] WP-011-1-A3：hashtable 与 PSCustomObject 双类型路径均正确
- [x] cboot.ps1 语法检查通过

## 关键文件

- `cboot.ps1` — `Set-ContextWindowEnv` 函数（189-218 行）

## 实现参考（修正后完整函数）

```powershell
function Set-ContextWindowEnv {
    param(
        [object]$EnvObject,
        [int]$ContextWindowSize
    )

    if ($EnvObject -is [hashtable]) {
        if ($ContextWindowSize -lt 1000000) {
            $EnvObject['CLAUDE_CODE_DISABLE_1M_CONTEXT'] = "1"
            $EnvObject['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] = "$ContextWindowSize"
        } else {
            $EnvObject.Remove('CLAUDE_CODE_DISABLE_1M_CONTEXT') | Out-Null
            $EnvObject['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] = "$ContextWindowSize"   # ← 改为赋值
        }
    } else {
        if ($ContextWindowSize -lt 1000000) {
            $EnvObject | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_DISABLE_1M_CONTEXT' -Value "1" -Force
            $EnvObject | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' -Value "$ContextWindowSize" -Force
        } else {
            if ($EnvObject.PSObject.Properties['CLAUDE_CODE_DISABLE_1M_CONTEXT']) {
                $EnvObject.PSObject.Properties.Remove('CLAUDE_CODE_DISABLE_1M_CONTEXT')
            }
            $EnvObject | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' -Value "$ContextWindowSize" -Force   # ← 改为赋值
        }
    }
}
```

## 测试用例

| 测试ID | 测试内容 | 预期结果 |
|--------|----------|----------|
| WP-011-1-T1 | hashtable + 1M | 无 DISABLE_1M_CONTEXT、AUTO_COMPACT_WINDOW="1000000" |
| WP-011-1-T2 | PSCustomObject + 1M | 无 DISABLE_1M_CONTEXT、AUTO_COMPACT_WINDOW="1000000" |
| WP-011-1-T3 | hashtable + 200K | DISABLE_1M_CONTEXT="1"、AUTO_COMPACT_WINDOW="200000"（回归不变） |
