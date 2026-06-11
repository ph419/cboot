# WP-011-4-review: 代码审查 + 版本号 v1.0.8

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-011.md`
> - 前置: WP-011-3-verify 已通过测试与手动复现

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | review |
| **父工作包** | WP-011 |
| **依赖** | WP-011-3-verify |
| **执行角色** | reviewer |
| **状态** | ✅ 完成 |

## 职责

对 WP-011 全部改动做 4 维度代码审查，确认无回归与风格问题；更新 README 徽章与 CHANGELOG 至 v1.0.8；将审查结果写入审查报告。

## 任务清单

- [x] 4 维度审查：
  - 代码风格一致性（Add-Member -Force / 注释风格）
  - 功能正确性（`>=1M` 两分支均改赋值、`<1M` 未回归、DISABLE_1M_CONTEXT 移除未动）
  - 兼容性（hashtable / PSCustomObject 双类型）
  - 架构合规（沿用 `Set-ContextWindowEnv` 统一函数，无新增重复逻辑）
- [x] 更新 `README.md` 版本徽章：v1.0.7 → v1.0.8
- [x] 更新 `CHANGELOG.md`：顶部新增 `## [1.0.8] - 2026-06-11`，`### Fixed` 条目说明 1M 场景 `AUTO_COMPACT_WINDOW` 应设为 1000000（修正 WP-010 矫枉过正）
- [x] 将审查结果写入 `docs/reports/2026-06-11_WP-011_review_report.md`
- [x] 确认提交格式：`fix: 修复 1M 上下文窗口误删 CLAUDE_CODE_AUTO_COMPACT_WINDOW 字段，1M 场景应设为 1000000`

## 验收标准

- [x] WP-011-4-A1：4 维度审查通过，无严重问题
- [x] WP-011-4-A2：README 徽章 + CHANGELOG 版本号一致为 v1.0.8
- [x] WP-011-4-A3：审查报告已写入，记录发现的任何小问题及处理

## 关键文件

- `cboot.ps1` — 审查改动
- `scripts/test-context-window.ps1` — 审查测试断言
- `README.md` — 版本徽章
- `CHANGELOG.md` — 版本日志
- `docs/reports/2026-06-11_WP-011_review_report.md` — 审查报告（新建）
