# WP-006-3-verify: 移除上下文窗口 90% 比例 — 测试验证

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-006.md`
> - 包含: 问题分析、实施计划、关键文件、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | verify |
| **父工作包** | WP-006 |
| **依赖** | WP-006-2-test |
| **执行角色** | tester |
| **状态** | ✅ 完成 |

## 职责

运行实际验证，确认修改后的 cboot.ps1 功能正常。

## 任务清单

- [ ] 验证 cboot.ps1 语法正确（`powershell -NoProfile -Command "& { . .\cboot.ps1 }"` 无解析错误）
- [ ] 模拟测试：当 contextWindowSize=200000 时，确认 AUTO_COMPACT_WINDOW=200000
- [ ] 模拟测试：当 contextWindowSize=1000000 时，确认不设置 AUTO_COMPACT_WINDOW
- [ ] 确认配置初始化流程中上下文窗口设置正确
- [ ] 确认添加模型流程中上下文窗口设置正确
- [ ] 确认编辑配置流程中上下文窗口设置正确

## 验收标准

- [ ] 脚本无语法错误
- [ ] 200K 输入 → AUTO_COMPACT_WINDOW = 200000（非 180000）
- [ ] 1M 输入 → 不设置 AUTO_COMPACT_WINDOW

## 关键文件

- `cboot.ps1`
