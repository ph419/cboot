# Claude Code Default Teammate Model 配置分析报告

> 分析日期: 2026-06-03
> Claude Code 版本: v2.1.160
> 分析方式: 二进制字符串提取 + settings.json 实证

## 1. 背景

Claude Code 支持 Agent Teams（实验性功能），允许创建多个 teammate 协同工作。每个 teammate 可以使用不同的模型。用户希望在 cboot 启动器中支持配置 teammate 的默认模型。

## 2. 关键发现

### 2.1 配置方式：settings JSON 顶级字段（非环境变量）

通过分析 `claude.exe` 二进制文件，确认 teammate 模型通过 **settings JSON 顶级字段** 配置，而非环境变量。

**相关字段：**

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `teammateDefaultModel` | `string \| null` | Teammate 默认模型 ID，null 表示使用系统默认 |
| `teammateMode` | `enum` | Teammate 执行方式：`"auto"` / `"tmux"` |

### 2.2 不存在 `ANTHROPIC_DEFAULT_TEAMMATE_MODEL` 环境变量

二进制文件中搜索到的 `ANTHROPIC_DEFAULT_*` 环境变量仅有：
- `ANTHROPIC_DEFAULT_HAIKU_MODEL`
- `ANTHROPIC_DEFAULT_OPUS_MODEL`
- `ANTHROPIC_DEFAULT_SONNET_MODEL`

**不存在** `ANTHROPIC_DEFAULT_TEAMMATE_MODEL`。这是一个常见的误解。

### 2.3 二进制证据

从 `claude.exe` 提取的关键代码片段：

```
teammateDefaultModel — "Default teammate model"
type: "managedEnum"

function VM_(H) {
  let q = I8().teammateDefaultModel;
  if (q === null) return H ?? Bv8();  // null → 使用默认模型
  if (q !== void 0) return __(q);     // 有值 → 使用指定模型
  return Bv8()                         // undefined → 使用默认模型
}
```

逻辑：
- `null` → 回退到默认模型（通常是 Sonnet）
- `undefined`（字段不存在）→ 同 null，回退到默认模型
- 具体模型 ID → 使用该模型

### 2.4 设置入口

`teammateDefaultModel` 在 Claude Code 的 `/config` 界面中作为可配置项暴露：
- 路径: `/config` → "Default teammate model"
- 类型: managedEnum（受管理的枚举，从可用模型列表中选择）

## 3. cboot 现状分析

### 3.1 当前支持的 settings 字段

| 字段 | cboot 支持 | 位置 |
|------|-----------|------|
| `env.ANTHROPIC_AUTH_TOKEN` | ✅ | Add-Model + Edit-ModelConfig |
| `env.ANTHROPIC_BASE_URL` | ✅ | Add-Model + Edit-ModelConfig |
| `env.ANTHROPIC_DEFAULT_OPUS_MODEL` | ✅ | Add-Model + Edit-ModelConfig |
| `env.ANTHROPIC_DEFAULT_SONNET_MODEL` | ✅ | Add-Model + Edit-ModelConfig |
| `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | ✅ | Add-Model + Edit-ModelConfig |
| `teammateDefaultModel` | ❌ 缺失 | — |
| `teammateMode` | ❌ 缺失 | — |

### 3.2 需要修改的位置

| 位置 | 修改内容 |
|------|----------|
| `New-SettingsTemplate` 硬编码模板 (L224-282) | 添加 teammateDefaultModel + teammateMode |
| `New-SettingsTemplate` 参数注入 (L286-301) | 增加 $teammateModel 参数和注入逻辑 |
| `Add-Model` 交互流程 (L1096-1305) | 增加 teammate 模型输入提示 |
| `Initialize-Config` 引导流程 (L316-540) | 增加 teammate 模型输入步骤 |
| `Edit-ModelConfig` 字段菜单 (L1407-1667) | 增加 teammate 模型编辑字段 |
| 4 个示例 settings 文件 | 添加 teammateDefaultModel + teammateMode |

## 4. 兼容性挑战

现有用户的 settings.json **可能没有** `teammateDefaultModel` 属性。处理策略：

1. **读取时**: 不存在等同于 `null`，显示 "系统默认"
2. **写入时**: 使用 `Add-Member -Force` 自动创建属性
3. **模板复制模式**: `New-SettingsTemplate` 从已有 settings 文件复制时，如果源文件也缺此字段，需要补全

## 5. 建议方案

### 5.1 新建模型时

在 HAIKU 模型输入之后、上下文窗口之前，增加一步：
```
输入 Teammate 默认模型（留空使用系统默认）:
```
留空 → 设置为 `null`（使用系统默认 Sonnet）

### 5.2 编辑已有模型时

在 Edit-ModelConfig 字段列表中，在 Haiku 模型之后增加：
```
Teammate 模型 : 系统默认    (或显示具体模型 ID)
```

### 5.3 示例配置文件

```json
{
  "teammateDefaultModel": null,
  "teammateMode": "auto",
  ...
}
```

## 6. 影响范围

- **代码修改**: `cboot.ps1` 约 6 处
- **模板修改**: 4 个示例 settings 文件
- **向后兼容**: 完全兼容，旧 settings 文件无需迁移即可使用
- **预估工作量**: 15-20 分钟
