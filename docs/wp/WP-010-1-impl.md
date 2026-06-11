# WP-010-1-impl: 抽取统一辅助函数 `Set-ContextWindowEnv`

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-010.md`
> - 包含: 问题分析（`200000` 残留根因）、实施计划、关键文件、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | impl |
| **父工作包** | WP-010 |
| **依赖** | 无（本子包仅新增函数，不改调用点） |
| **执行角色** | implementer |
| **状态** | ✅ 完成 |

## 职责

新增一个统一辅助函数 `Set-ContextWindowEnv`，封装"按上下文窗口大小 set / remove `CLAUDE_CODE_DISABLE_1M_CONTEXT` 与 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`，并兼容 hashtable / PSCustomObject 两种 env 对象类型"。此函数为纯新增，不改动任何现有调用点（WP-010-2-impl 负责替换调用）。

## 任务清单

- [ ] 在 `cboot.ps1` 中 `New-SettingsTemplate` 函数之前（`Parse-ContextWindow` 附近）新增函数
- [ ] 函数签名：`Set-ContextWindowEnv -EnvObject <object> -ContextWindowSize <int>`
- [ ] 实现核心逻辑：
  - 若 `ContextWindowSize -lt 1000000`：设置 `CLAUDE_CODE_DISABLE_1M_CONTEXT="1"`、`CLAUDE_CODE_AUTO_COMPACT_WINDOW="$ContextWindowSize"`
  - 否则（`>= 1M`）：移除这两个字段（若存在）
- [ ] 实现类型兼容（关键，参考 `cboot.ps1:306-315`）：
  - hashtable：`$EnvObject['KEY'] = $val` 设值；`$EnvObject.Remove('KEY')` 移除
  - PSCustomObject：`Add-Member -MemberType NoteProperty -Force` 设值；先 `PSObject.Properties['KEY']` 检查存在再 `Remove` 移除
- [ ] 通过 `$EnvObject -is [hashtable]` 判断分支
- [ ] 本地语法检查：`pwsh -NoProfile -Command "$null = [ScriptBlock]::Create((Get-Content cboot.ps1 -Raw)); 'OK'"` 无报错

## 验收标准

- [ ] `Set-ContextWindowEnv` 函数已定义，签名与参数齐全
- [ ] hashtable 与 PSCustomObject 两种类型路径均已实现 set / remove
- [ ] `< 1M` 与 `>= 1M` 两个分支均覆盖
- [ ] 本子包**不修改**任何现有调用点（保持 WP-010-2-impl 可独立替换）
- [ ] cboot.ps1 语法检查通过

## 关键文件

- `cboot.ps1` — 新增函数，建议插入位置：`Parse-ContextWindow`（`cboot.ps1:166`）之后、`New-SettingsTemplate`（`cboot.ps1:189`）之前

## 实现参考（伪代码）

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
            $EnvObject.Remove('CLAUDE_CODE_AUTO_COMPACT_WINDOW') | Out-Null
        }
    } else {
        # PSCustomObject
        if ($ContextWindowSize -lt 1000000) {
            $EnvObject | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_DISABLE_1M_CONTEXT' -Value "1" -Force
            $EnvObject | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' -Value "$ContextWindowSize" -Force
        } else {
            if ($EnvObject.PSObject.Properties['CLAUDE_CODE_DISABLE_1M_CONTEXT']) {
                $EnvObject.PSObject.Properties.Remove('CLAUDE_CODE_DISABLE_1M_CONTEXT')
            }
            if ($EnvObject.PSObject.Properties['CLAUDE_CODE_AUTO_COMPACT_WINDOW']) {
                $EnvObject.PSObject.Properties.Remove('CLAUDE_CODE_AUTO_COMPACT_WINDOW')
            }
        }
    }
}
```
