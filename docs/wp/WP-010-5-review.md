# WP-010-5-review: 上下文窗口 env 修复 — 代码审查

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-010.md`
> - 前置子包: `docs/wp/WP-010-4-verify.md`（测试已全 PASS）
> - 包含: 验收标准、版本与文档要求

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | review |
| **父工作包** | WP-010 |
| **依赖** | WP-010-4-verify |
| **执行角色** | reviewer |
| **状态** | ✅ 完成 |

## 职责

对 WP-010-1/2-impl 的实现与 WP-010-3-test 的测试做基础代码审查，确认类型兼容完备、三处调用彻底去重无第四处遗漏、测试覆盖根因场景，并完成版本号更新。

## 任务清单

- [ ] 审查 `Set-ContextWindowEnv` 类型兼容：hashtable / PSCustomObject 两路径的 set 与 remove 均正确
- [ ] 审查三处调用点（New-SettingsTemplate / Add-Model / Edit-ModelConfig）是否彻底替换、无遗漏的第四处散落逻辑
- [ ] `grep -rn "CLAUDE_CODE_DISABLE_1M_CONTEXT\|CLAUDE_CODE_AUTO_COMPACT_WINDOW" cboot.ps1` 仅命中 `Set-ContextWindowEnv` 函数体
- [ ] 审查测试用例是否覆盖根因场景（PSCustomObject + 模板残留 + 1M 清除）
- [ ] 审查是否有回归风险：`< 1M` 分支行为与原逻辑一致（值不再乘 0.9，参考 WP-006）
- [ ] **版本号更新**：
  - `README.md` 徽章 v1.0.6 → v1.0.7
  - `CHANGELOG.md` 新增条目，描述：修复 `New-SettingsTemplate` 在 1M 场景下未清除模板遗留 `CLAUDE_CODE_DISABLE_1M_CONTEXT` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 的问题，并抽取 `Set-ContextWindowEnv` 统一三处逻辑
- [ ] 输出审查结论（通过 / 需修正项）

## 验收标准

- [ ] 类型兼容审查通过（无类型相关运行时异常风险）
- [ ] 三处调用去重审查通过，无第四处散落
- [ ] 测试覆盖根因场景
- [ ] README 徽章与 CHANGELOG 均更新至 v1.0.7
- [ ] 无回归（`< 1M` 行为不变）
- [ ] 审查结论记录（可写入 verify 报告同目录或 task.md 备注）

## 关键文件

- `cboot.ps1` — 审查 `Set-ContextWindowEnv` 及三处调用
- `scripts/test-context-window.ps1` — 审查测试覆盖度
- `README.md` — 版本徽章
- `CHANGELOG.md` — 新增条目
