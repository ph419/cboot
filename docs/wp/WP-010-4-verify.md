# WP-010-4-verify: 上下文窗口 env 修复 — 测试验证

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-010.md`
> - 前置子包: `docs/wp/WP-010-3-test.md`（测试脚本已编写）
> - 包含: 验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | verify |
| **父工作包** | WP-010 |
| **依赖** | WP-010-3-test |
| **执行角色** | tester |
| **状态** | ✅ 完成 |

## 职责

运行 WP-010-3-test 编写的独立测试脚本确认全部 PASS，并进行真实环境手动复现验证（在 `~/.claude/` 下先建 200K 模型再建 1M 模型，确认新文件无残留）。本子包**只验证不修改实现**。

## 任务清单

- [ ] 运行 `pwsh scripts/test-context-window.ps1`，确认 6 个测试用例全 PASS
- [ ] 若有 FAIL，记录失败详情，**不自行修复实现**（反馈回 WP-010-1/2-impl）
- [ ] 手动复现步骤 1：在真实 `~/.claude/` 下用 cboot 初始化/添加一个 **200K** 模型，确认其 settings 含 `DISABLE_1M_CONTEXT=1` 与 `AUTO_COMPACT_WINDOW="200000"`
- [ ] 手动复现步骤 2：再用 cboot 添加一个 **1M** 模型（复用上一步的 settings 作为模板）
- [ ] 手动复现步骤 3：打开新生成的 1M 模型 settings 文件，确认**无** `CLAUDE_CODE_DISABLE_1M_CONTEXT`、**无** `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
- [ ] 启动验证：`claude --settings <新生成的1M-settings.json>` 启动无报错
- [ ] Edit-ModelConfig 验证：在 1M 模型上编辑上下文窗口切到 200K 再切回 1M，确认字段正确增删
- [ ] 将验证结果记录到 `docs/reports/2026-06-11_WP-010_verify_report.md`

## 验收标准

- [ ] `pwsh scripts/test-context-window.ps1` 全 PASS，退出码 0
- [ ] 真实环境手动复现：1M 模型 settings 无 `DISABLE_1M_CONTEXT`、无 `AUTO_COMPACT_WINDOW`
- [ ] `claude --settings <1M-settings>` 启动无报错
- [ ] Edit-ModelConfig 切换 1M↔200K 字段正确增删
- [ ] 验证报告写入 `docs/reports/`，记录 PASS 用例与手动复现结果

## 关键文件

- `scripts/test-context-window.ps1` — 运行
- `~/.claude/settings-*.json` — 手动复现目标（临时测试模型，验证后可清理）
- `docs/reports/2026-06-11_WP-010_verify_report.md` — 验证报告（新建）
