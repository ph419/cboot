# WP-011-3-verify: 运行测试 + 手动复现 1M/200K 场景

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-011.md`
> - 前置: WP-011-1-impl（修复代码）+ WP-011-2-test（修正测试）均已完成

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | verify |
| **父工作包** | WP-011 |
| **依赖** | WP-011-2-test |
| **执行角色** | tester |
| **状态** | ✅ 已完成 |

## 职责

运行测试脚本全量 PASS，并通过手动复现验证 200K / 1M 两种真实场景的 settings 输出符合预期，确认无回归。将验证结果写入执行报告。

## 任务清单

- [x] 运行 `pwsh scripts/test-context-window.ps1`（或 `powershell -File ...`），确认 `Passed: 6+ / Failed: 0` → 7/7 PASS
- [x] 语法检查 cboot.ps1（`Tokenize` 等效，见报告） → 0 错误
- [x] 手动复现 A（200K）：直接对 cboot.ps1 本体提取的 `Set-ContextWindowEnv` 验证 → DISABLE=1 + AUTO=200000
- [x] 手动复现 B（1M，复用 200K 模板）：根因场景 → 无 DISABLE、AUTO=1000000（残留被覆盖非删除）
- [x] 将验证结果写入 `docs/reports/2026-06-11_WP-011_verify_report.md`

## 验收标准

- [x] WP-011-3-A1：测试脚本全 PASS（退出码 0）
- [x] WP-011-3-A2：cboot.ps1 语法检查通过
- [x] WP-011-3-A3：200K 场景 settings 字段符合预期（DISABLE=1 + AUTO=200000）
- [x] WP-011-3-A4：1M 场景 settings 字段符合预期（无 DISABLE + AUTO=1000000）
- [x] WP-011-3-A5：验证报告已写入

## 关键文件

- `scripts/test-context-window.ps1` — 运行测试
- `cboot.ps1` — 语法检查 + 手动复现载体
- `docs/reports/2026-06-11_WP-011_verify_report.md` — 验证报告（新建）
