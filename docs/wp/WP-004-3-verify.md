# WP-004-3-verify: 手动验证

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-004.md`
> - 包含: 问题分析、完整实施计划、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | verify |
| **父工作包** | WP-004 |
| **依赖** | WP-004-2-impl |
| **执行角色** | tester |
| **状态** | 📋 待执行 |

## 职责

手动验证 WP-004-1-impl 和 WP-004-2-impl 的实现，确保所有功能正确、边界情况处理到位、原功能不受影响。

## 测试场景

### 场景 1: 初始化 - 200K 上下文

1. 删除 `~/.claude/claude-config.json`
2. 运行 `.\cboot.ps1`
3. 完成初始化，上下文窗口输入 `200K`
4. **预期**: settings 文件含 `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` 和 `CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000`

### 场景 2: 初始化 - 1M 上下文

1. 删除配置，重新初始化
2. 上下文窗口输入 `1M`
3. **预期**: settings 文件不含上述两个 env 变量

### 场景 3: 初始化 - 默认（留空）

1. 删除配置，重新初始化
2. 上下文窗口直接回车（留空）
3. **预期**: 同场景 2

### 场景 4: 初始化 - 无效输入

1. 删除配置，重新初始化
2. 上下文窗口输入 `abc`
3. **预期**: 提示重新输入

### 场景 5: 添加模型 - 500K 上下文

1. 运行 `.\cboot.ps1`
2. 选择「添加模型」
3. 输入模型信息，上下文窗口输入 `500K`
4. **预期**: settings 含 `CLAUDE_CODE_AUTO_COMPACT_WINDOW=450000`

### 场景 6: 修改配置 - 修改 API 密钥

1. 选择「修改配置」
2. 选择模型
3. 修改 API 密钥
4. **预期**: settings 文件中密钥已更新

### 场景 7: 修改配置 - 上下文窗口 200K → 1M

1. 选择「修改配置」
2. 选择模型
3. 修改上下文窗口为 `1M`
4. **预期**: env 中 `CLAUDE_CODE_DISABLE_1M_CONTEXT` 和 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 已移除

### 场景 8: 修改配置 - ESC 行为

1. 选择「修改配置」→ ESC → 返回主菜单
2. 选择「修改配置」→ 选择模型 → ESC → 返回模型选择
3. 编辑字段时输入空行 → 保持不变
4. **预期**: 无数据变更，导航正确

## 验证命令

```powershell
# 检查 settings 文件 env
cat ~/.claude/settings-test.json | ConvertFrom-Json | Select-Object -ExpandProperty env

# 检查 claude-config.json 的 contextWindow
cat ~/.claude/claude-config.json | ConvertFrom-Json | Select-Object -ExpandProperty models
```

## 验收标准

- [ ] 8 个测试场景全部通过
- [ ] 原功能（模型选择、项目选择、启动 Claude）不受影响
- [ ] 旧配置（无 contextWindow 字段）正常加载
