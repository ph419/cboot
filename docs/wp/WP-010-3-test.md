# WP-010-3-test: 上下文窗口 env 逻辑 — 独立测试脚本

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-010.md`
> - 前置子包: `docs/wp/WP-010-2-impl.md`（三处调用已替换）
> - 包含: 问题分析（根因场景）、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | test |
| **父工作包** | WP-010 |
| **依赖** | WP-010-2-impl |
| **执行角色** | tester |
| **状态** | ✅ 完成 |

## 职责

编写**独立可重复运行**的测试脚本 `scripts/test-context-window.ps1`，直接 dot-source `cboot.ps1` 中的 `Set-ContextWindowEnv` 函数（或复制函数定义），覆盖 hashtable / PSCustomObject 双类型、`<1M` / `>=1M` 双分支、模板残留场景及端到端复现。脚本须能独立 `pwsh scripts/test-context-window.ps1` 运行并输出 PASS/FAIL 汇总。

## 任务清单

- [ ] 新建 `scripts/test-context-window.ps1`
- [ ] 通过 dot-sourcing 或函数提取方式加载 `Set-ContextWindowEnv`
- [ ] 实现 PASS/FAIL 断言辅助函数（计数 + 汇总退出码）
- [ ] 编写测试用例 1：**hashtable + 1M** → 两个字段均不存在
- [ ] 编写测试用例 2：**hashtable + 200K** → `DISABLE_1M_CONTEXT=1`、`AUTO_COMPACT_WINDOW="200000"`
- [ ] 编写测试用例 3：**PSCustomObject + 1M（env 预含 200K 残留）** → 两个字段被**清除**（核心根因场景）
- [ ] 编写测试用例 4：**PSCustomObject + 1M（env 无残留）** → 两个字段不存在
- [ ] 编写测试用例 5：**PSCustomObject + 500K** → `DISABLE_1M_CONTEXT=1`、`AUTO_COMPACT_WINDOW="500000"`
- [ ] 编写测试用例 6：**端到端复现** — 构造一个 200K settings 模板文件，模拟 `New-SettingsTemplate` 复用模板新建 1M 模型，断言新文件无残留字段（完整复现并验证修复）
- [ ] 脚本末尾输出 `Passed: X / Failed: Y`，失败时退出码非 0

## 验收标准

- [ ] `scripts/test-context-window.ps1` 存在且可独立运行
- [ ] 6 个测试用例全部编写完成，覆盖双类型 × 双分支 + 模板残留 + 端到端
- [ ] 测试用例 3 明确复现根因（PSCustomObject 含 200K 残留 + 1M 清除）
- [ ] 脚本输出 PASS/FAIL 汇总与退出码
- [ ] **本子包仅编写测试脚本，不运行**（运行验证由 WP-010-4-verify 负责，保持工作包独立）

## 关键文件

- `scripts/test-context-window.ps1` — 新建
- `cboot.ps1` — 仅读取 `Set-ContextWindowEnv` 定义（不改）

## dot-source 提示

cboot.ps1 顶层有交互式主循环，直接 dot-source 会在加载时执行主循环。建议：
- 方式 A：将 `Set-ContextWindowEnv` 函数体复制进测试脚本（最简单，测试自包含）
- 方式 B：用 `[ScriptBlock]::Create` + `Get-Command -Type Function` 提取单一函数（更贴近真实代码）

推荐方式 A 保证测试脚本零依赖、可重复运行。
