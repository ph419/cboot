# WP-009-2-test: Teammate Model 配置测试用例

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-009.md`
> - 实现工作包: `docs/wp/WP-009-1-impl.md`

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | test |
| **父工作包** | WP-009 |
| **依赖** | WP-009-1-impl |
| **执行角色** | test-reviewer |
| **状态** | ✅ 完成 (2026-06-03) |

## 职责

编写手动测试用例，覆盖 teammate 模型配置的所有场景。

## 测试用例

### TC-1: 新建模型时配置 Teammate 模型

**前置条件**: 已有至少一个模型配置

**步骤**:
1. 运行 `.\cboot.ps1`
2. 选择 "添加模型"
3. 输入模型 ID、名称、配置文件名
4. 输入 API 密钥、Base URL
5. 输入 Opus/Sonnet/Haiku 模型
6. 在 "Teammate 默认模型" 提示处输入一个模型 ID（如 `glm-5.1`）
7. 输入上下文窗口大小
8. 确认添加

**预期结果**:
- 新建的 settings 文件包含 `"teammateDefaultModel": "glm-5.1"`
- 新建的 settings 文件包含 `"teammateMode": "auto"`

### TC-2: 新建模型时留空 Teammate 模型

**步骤**: 同 TC-1，但在 Teammate 模型提示处直接回车留空

**预期结果**:
- 新建的 settings 文件包含 `"teammateDefaultModel": null`

### TC-3: 编辑已有模型的 Teammate 模型

**前置条件**: 已有模型配置，settings 文件包含 teammateDefaultModel 字段

**步骤**:
1. 运行 `.\cboot.ps1`
2. 选择 "修改配置"
3. 选择一个模型
4. 选择 "Teammate 模型" 字段
5. 输入新的模型 ID
6. 确认保存

**预期结果**:
- settings 文件中 teammateDefaultModel 更新为新值

### TC-4: 编辑旧版 settings（无 teammateDefaultModel 字段）

**前置条件**: settings 文件不包含 teammateDefaultModel 字段

**步骤**:
1. 手动删除 settings 文件中的 teammateDefaultModel 和 teammateMode 字段
2. 运行 `.\cboot.ps1`
3. 选择 "修改配置"
4. 选择该模型
5. 查看 Teammate 模型字段显示

**预期结果**:
- Teammate 模型字段显示 "系统默认"
- 编辑后 settings 文件自动创建 teammateDefaultModel 字段

### TC-5: 首次引导包含 Teammate 模型

**前置条件**: 无 claude-config.json（首次运行）

**步骤**:
1. 备份并删除 `~/.claude/claude-config.json` 和 `~/.claude/settings/` 目录
2. 运行 `.\cboot.ps1`
3. 按引导完成配置
4. 在 Teammate 模型步骤输入模型 ID

**预期结果**:
- 引导流程包含 Teammate 模型输入步骤
- 生成的 settings 文件包含正确的 teammateDefaultModel

### TC-6: 示例文件验证

**步骤**:
1. 检查 4 个 `config/settings/settings-*.example.json` 文件

**预期结果**:
- 所有文件包含 `"teammateDefaultModel": null`
- 所有文件包含 `"teammateMode": "auto"`

## 验收标准

- [x] 所有 6 个测试用例已编写
- [x] 测试用例覆盖：新建、编辑、兼容、首次引导
- [x] 每个用例有明确的前置条件、步骤、预期结果
