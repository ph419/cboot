# WP-006-1-impl: 移除上下文窗口 90% 比例 — 代码实现

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-006.md`
> - 包含: 问题分析、实施计划、关键文件、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | impl |
| **父工作包** | WP-006 |
| **依赖** | 无 |
| **执行角色** | implementer |
| **状态** | ✅ 完成 |

## 职责

移除 cboot.ps1 中 3 处将上下文窗口值乘以 0.9 的逻辑，改为直接使用用户填写的原始值。

## 任务清单

- [x] 修改行 298: `$compactWindow = [math]::Floor($contextWindowSize * 0.9)` → `$compactWindow = $contextWindowSize`
- [x] 修改行 1264: `$compactWindow = [math]::Floor($contextWindowSize * 0.9)` → `$compactWindow = $contextWindowSize`
- [x] 修改行 1616: `$compactWindow = [math]::Floor($newContextSize * 0.9)` → `$compactWindow = $newContextSize`
- [x] 确认无其他遗漏的 0.9 比例代码

## 验收标准

- [x] `grep -n "0\.9" cboot.ps1` 无匹配结果
- [x] 3 处修改均直接使用原始值，不再乘以 0.9

## 关键文件

- `cboot.ps1` — 行 298、1264、1616
