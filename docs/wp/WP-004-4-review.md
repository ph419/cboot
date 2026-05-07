# WP-004-4-review: 代码审查

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-004.md`
> - 包含: 问题分析、完整实施计划、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | review |
| **父工作包** | WP-004 |
| **依赖** | WP-004-3-verify |
| **执行角色** | code-reviewer |
| **状态** | 📋 待执行 |

## 职责

审查 WP-004 所有代码变更，确保质量、安全性和一致性。

## 审查清单

### 代码质量

- [ ] `Parse-ContextWindow` 函数：边界情况处理（0K、0.5M、极大值）
- [ ] `Parse-ContextWindow` 函数：避免使用 PowerShell 保留变量名 `$input`（改为 `$Input` 或其他名）
- [ ] 上下文窗口 env 注入逻辑：`< 1M` 判断是否正确（边界值 999999 vs 1000000）
- [ ] JSON 读写：`ConvertTo-Json -Depth 10` 是否覆盖了嵌套结构

### 索引一致性

- [ ] 主菜单 switch 语句：所有 7 个 case 的索引正确
- [ ] Initialize-Config 步骤编号：从 5 步改为 6 步，编号连续无跳跃
- [ ] 菜单项数组和 switch case 数量匹配

### 向后兼容

- [ ] 旧配置无 `contextWindow` 字段时不报错
- [ ] `Edit-ModelConfig` 读取 settings 文件时，env 字段不存在时优雅处理
- [ ] 现有 settings 文件无 `CLAUDE_CODE_DISABLE_1M_CONTEXT` 时，修改配置功能正常

### 安全性

- [ ] 无命令注入风险（所有用户输入通过 Read-Host 获取，不执行为命令）
- [ ] JSON 文件写入使用 Set-Content -Encoding UTF8，无编码问题
- [ ] API 密钥显示时做了掩码处理

### ESC 行为

- [ ] `Edit-ModelConfig` 第一级 ESC 返回主菜单
- [ ] `Edit-ModelConfig` 第二级 ESC 返回第一级
- [ ] ESC 不会导致数据变更

## 关键文件

- `cboot.ps1` — 审查所有 WP-004 相关改动
