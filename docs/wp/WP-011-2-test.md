# WP-011-2-test: 修正测试脚本 4 个用例预期

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-011.md`
> - 前置: WP-011-1-impl 已修正 `cboot.ps1` 的 `Set-ContextWindowEnv`

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | test |
| **父工作包** | WP-011 |
| **依赖** | WP-011-1-impl |
| **执行角色** | tester |
| **状态** | ✅ 完成 |

## 职责

修正 `scripts/test-context-window.ps1`，使其与 WP-011 新逻辑（`>=1M` 时 `AUTO_COMPACT_WINDOW` 设为 size 而非移除）一致。脚本顶部原样复制的 `Set-ContextWindowEnv` 实现须逐行对齐 `cboot.ps1`。

## 任务清单

- [x] 同步更新脚本顶部复制的 `Set-ContextWindowEnv`（`test-context-window.ps1:19-48`），逐行对齐 WP-011-1-impl 的修正版本（两处 else 分支改为赋值）
- [x] 用例 1（hashtable+1M）：断言改为「无 `DISABLE_1M_CONTEXT`、`AUTO_COMPACT_WINDOW=1000000`」
- [x] 用例 3（根因场景 PSCustomObject+1M 预含 200K 残留）：断言改为「无 `DISABLE_1M_CONTEXT`、`AUTO_COMPACT_WINDOW=1000000`」（验证残留 200000 被覆盖为 1000000）
- [x] 用例 4（PSCustomObject+1M 无残留）：断言改为「`AUTO_COMPACT_WINDOW=1000000`」
- [x] 用例 6（端到端 JSON）：断言改为「JSON 无 `DISABLE_1M_CONTEXT`、含 `AUTO_COMPACT_WINDOW` 且值=1000000」
- [x] 可选新增用例 7：2M（size=2000000）→ `AUTO_COMPACT_WINDOW=2000000`、无 `DISABLE_1M_CONTEXT`
- [x] 用例 2/5（200K/500K）断言**保持不变**

## 验收标准

- [x] WP-011-2-A1：6+ 用例全 PASS，断言与新逻辑一致（实际 7 用例全 PASS）
- [x] WP-011-2-A2：脚本顶部复制的函数与 `cboot.ps1` 实现逐行一致
- [x] WP-011-2-A3：用例 2/5（`<1M`）行为未受影响

## 关键文件

- `scripts/test-context-window.ps1`

## 测试用例变更对照

| 用例 | 场景 | 旧断言（错误逻辑） | 新断言（正确逻辑） |
|------|------|--------------------|--------------------|
| 1 | hashtable+1M | 两字段均不存在 | 无 DISABLE_1M_CONTEXT、AUTO_COMPACT_WINDOW=1000000 |
| 2 | hashtable+200K | DISABLE=1、AUTO=200000 | （不变） |
| 3 | PSCO+1M 残留 | 两字段被清除 | 无 DISABLE_1M_CONTEXT、AUTO=1000000（覆盖 200000） |
| 4 | PSCO+1M 无残留 | 两字段不存在 | AUTO_COMPACT_WINDOW=1000000 |
| 5 | PSCO+500K | DISABLE=1、AUTO=500000 | （不变） |
| 6 | 端到端 JSON | 无 DISABLE、无 AUTO | 无 DISABLE_1M_CONTEXT、含 AUTO=1000000 |
| 7 | （新）PSCO+2M | - | 无 DISABLE_1M_CONTEXT、AUTO=2000000 |
