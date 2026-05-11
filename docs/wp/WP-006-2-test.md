# WP-006-2-test: 移除上下文窗口 90% 比例 — 测试编写

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-006.md`
> - 包含: 问题分析、实施计划、关键文件、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | test |
| **父工作包** | WP-006 |
| **依赖** | WP-006-1-impl |
| **执行角色** | tester |
| **状态** | ✅ 完成 |

## 职责

验证 WP-006-1-impl 的 3 处修改是否正确，确保：

1. 不再存在 0.9 比例计算
2. AUTO_COMPACT_WINDOW 使用用户填写的原始值
3. 1M 上下文窗口的逻辑不受影响

## 任务清单

- [ ] 测试 1: 验证行 298 修改 — New-SettingsTemplate 函数中 `$compactWindow` 直接等于 `$contextWindowSize`
- [ ] 测试 2: 验证行 1264 修改 — 更新模型配置时 `$compactWindow` 直接等于 `$contextWindowSize`
- [ ] 测试 3: 验证行 1616 修改 — 编辑上下文窗口时 `$compactWindow` 直接等于 `$newContextSize`
- [ ] 测试 4: 全局搜索确认无残留 `[math]::Floor` 或 `* 0.9` 代码
- [ ] 测试 5: 验证 1M 边界条件（≥1000000 时仍不设置 AUTO_COMPACT_WINDOW）

## 验收标准

- [ ] `grep -n "0\.9" cboot.ps1` 无匹配
- [ ] `grep -n "Floor" cboot.ps1` 无与上下文窗口相关的匹配
- [ ] 3 处 compactWindow 赋值均直接使用原始变量

## 关键文件

- `cboot.ps1` — 行 296-300、1262-1269、1614-1625
