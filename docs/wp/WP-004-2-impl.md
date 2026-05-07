# WP-004-2-impl: 配置文件编辑交互流程

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-004.md`
> - 包含: 问题分析、完整实施计划、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | impl |
| **父工作包** | WP-004 |
| **依赖** | WP-004-1-impl |
| **执行角色** | implementer |
| **状态** | 📋 待执行 |

## 职责

为已初始化的用户提供交互式配置编辑功能。用户可通过菜单选择模型、选择要修改的 env 字段、输入新值并保存。同时更新主菜单，在「添加模型」之后插入「修改配置」选项。

## 任务清单

- [ ] 新增 `Edit-ModelConfig` 函数：第一级菜单（选择模型）
- [ ] `Edit-ModelConfig` 函数：第二级菜单（选择字段，显示当前值）
- [ ] `Edit-ModelConfig` 函数：字段编辑逻辑（Read-Host 输入新值，空行保持不变）
- [ ] `Edit-ModelConfig` 函数：上下文窗口编辑（解析 + 同步更新 settings 和 claude-config.json）
- [ ] `Edit-ModelConfig` 函数：ESC 返回逻辑（第一级返回主菜单，第二级返回第一级）
- [ ] 更新主菜单：添加「修改配置」选项
- [ ] 更新 switch 语句：调整所有菜单索引

## 验收标准

- [ ] 主菜单包含「修改配置」选项，位于「添加模型」之后
- [ ] 修改配置流程：选择模型 → 选择字段 → 输入新值 → 保存成功
- [ ] 字段菜单显示当前值（API 密钥显示前 8 位 + ...）
- [ ] 上下文窗口编辑时同步更新 env 变量和 claude-config.json 的 model.contextWindow
- [ ] ESC 在第一级返回主菜单，第二级返回第一级
- [ ] 空行输入保持原值不变
- [ ] 所有原菜单功能（添加模型、移除模型等）索引正确不受影响

## 关键文件

- `cboot.ps1`（唯一修改文件）
  - ~1291 行后：新增 `Edit-ModelConfig` 函数
  - ~1510 行：主菜单 `$menuItems` 数组
  - ~1536 行：switch 语句

## 实施细节

### Edit-ModelConfig 函数结构

```powershell
function Edit-ModelConfig {
    # 第一级：选择模型
    while ($true) {
        $config = Get-Config
        # 显示模型列表，使用方向键导航
        # ESC → 返回
        # 回车 → 进入第二级
    }

    # 第二级：选择字段
    while ($true) {
        # 读取 settings 文件
        # 显示 7 个选项（6 个字段 + 返回），显示当前值
        # ESC → 返回第一级
        # 回车 → 编辑选中字段
    }

    # 编辑字段
    # 显示当前值，Read-Host 输入新值
    # 空行保持不变
    # 修改后保存 settings 文件
}
```

### 可编辑字段列表

| 序号 | 字段名 | env 键 | 显示方式 |
|------|--------|--------|----------|
| 1 | API 密钥 | ANTHROPIC_AUTH_TOKEN | 前 8 位 + ... |
| 2 | Base URL | ANTHROPIC_BASE_URL | 完整显示 |
| 3 | Opus 模型 | ANTHROPIC_DEFAULT_OPUS_MODEL | 完整显示 |
| 4 | Sonnet 模型 | ANTHROPIC_DEFAULT_SONNET_MODEL | 完整显示 |
| 5 | Haiku 模型 | ANTHROPIC_DEFAULT_HAIKU_MODEL | 完整显示 |
| 6 | 上下文窗口 | (组合字段) | 显示原始输入如 "200K" |
| 7 | 返回 | - | - |

### 上下文窗口编辑特殊逻辑

编辑上下文窗口时：
1. 使用 `Parse-ContextWindow` 解析新值
2. 更新 settings 文件的 env：
   - 如果新值 < 1M：设置 `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` 和 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
   - 如果新值 >= 1M：移除这两个 env 变量
3. 同步更新 `claude-config.json` 中对应 model 的 `contextWindow` 字段

### 主菜单更新

```powershell
$menuItems = @(
    "使用 Claude",     # 0
    "添加模型",        # 1 → 原 1
    "修改配置",        # 2 ← 新增
    "移除模型",        # 3 → 原 2
    "添加项目目录",    # 4 → 原 3
    "移除项目目录",    # 5 → 原 4
    "退出"             # 6 → 原 5
)

switch ($selectedIndex) {
    0 { ... }   # 使用 Claude
    1 { Add-Model }
    2 { Edit-ModelConfig }  # 新增
    3 { Remove-Model }
    4 { Add-ProjectDirectory }
    5 { Remove-ProjectDirectory }
    6 { exit }  # 或 return
}
```
