# cboot

[![Version](https://img.shields.io/badge/version-1.0.10-blue)](https://github.com/ph419/cboot) [![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

一个 PowerShell 版 Claude Code 交互式启动器，支持多模型切换、项目管理、权限控制和智能排序。

## 功能特性

- **交互式菜单** — 方向键导航，回车选择，ESC 返回
- **多模型支持** — 配置多个 AI 模型，按使用频率智能排序
- **模型管理** — 运行时添加/移除模型，自动生成 settings 配置文件
- **项目管理** — 添加/移除项目目录，自动清理无效路径
- **权限控制** — 可选择跳过权限检查或手动确认
- **使用统计** — 记录模型和项目的使用频率，常用项自动排到前面
- **配置修复** — 自动检测配置缺失并提供逐项修复或重新初始化

## 快速开始

### 前置要求

- Windows PowerShell 5.1+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 已安装并可用

### 安装

```powershell
# 克隆项目
git clone https://github.com/ph419/cboot.git
cd cboot
```

### 使用

```powershell
# PowerShell 中运行
.\cboot.ps1

# 或双击 cboot.cmd 直接启动（自动绕过执行策略）
```

首次运行时，cboot 会检测配置是否缺失，并引导你完成初始化或逐项修复。

启动后进入交互式菜单：

```
=== Claude 启动器 ===

主菜单

  使用 Claude
  添加模型
  移除模型
  添加项目目录
  移除项目目录
  退出

使用方向键导航，回车选择，ESC取消，H获取帮助
```

操作流程：选择模型 → 选择项目目录 → 选择权限 → 启动 Claude Code

### 使用示例

首次运行时，cboot 会引导你完成初始化配置：

**步骤 1/5 ~ 5/7 — 配置模型信息、API 参数、Teammate 模型、上下文窗口、权限和项目目录**

![初始化配置流程](docs/1.png)

**步骤 7/7 — 确认配置并生成文件**

![配置确认](docs/2.png)





## 配置说明

### claude-config.json

启动器主配置文件：

```json
{
    "models": [
        {
            "id": "glm-5.2[1m]",
            "name": "glm-5.2[1m]",
            "configFile": "settings-glm-5.2[1m].json",
            "usageCount": 0
        }
    ],
    "defaultModel": "glm-5.2[1m]",
    "defaultPermission": "yes",
    "projects": [
        {
            "path": "C:\\Users\\YourName\\projects\\my-project",
            "usageCount": 0
        }
    ]
}
```

| 字段 | 说明 |
|------|------|
| `models` | 可用模型列表，每个模型需要 `id`、`name`、`configFile` |
| `defaultModel` | 默认选中的模型 id |
| `defaultPermission` | 默认权限选择：`yes`（跳过权限检查）或 `no`（手动确认） |
| `projects` | 项目目录列表 |

### settings-*.json

每个模型对应一个 Claude Code settings 文件，核心字段：

```json
{
    "env": {
        "ANTHROPIC_AUTH_TOKEN": "YOUR_API_KEY_HERE",
        "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic",
        "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-4.5-air",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5.2[1m]",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.2[1m]"
    }
}
```

| 字段 | 说明 |
|------|------|
| `ANTHROPIC_AUTH_TOKEN` | API 密钥（必须替换） |
| `ANTHROPIC_BASE_URL` | API 地址 |
| `ANTHROPIC_DEFAULT_*_MODEL` | 模型映射，模型名加 `[1m]` 后缀（如 `glm-5.2[1m]`）开启 GLM 1M 上下文 |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | 上下文自动压缩窗口，开启 1M 时设为 `1000000` |

#### GLM 1M 上下文与 effort 切换

GLM-5.2 支持通过模型名后缀开启 1M 上下文窗口，并可在会话中切换思考强度：

- **1M 上下文**：模型名加 `[1m]` 后缀（即 `glm-5.2[1m]`）开启 GLM 1M 上下文，需同时设置 `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000`。在 cboot 初始化或添加模型时，将上下文窗口填写为 `1M`，会自动配置这两项。
- **effort 思考强度**：Claude Code 会话中输入 `/effort` 切换思考强度，映射关系如下：

| Claude Code 中的 effort | GLM-5.2 实际映射 |
|---|---|
| low / medium / high（默认） | high |
| xhigh / max / ultracode | max |

> 💡 Coding 任务推荐切换至 `max` effort，以获取更深度的推理与更稳定的复杂任务表现。

## 快捷键

| 按键 | 功能 |
|------|------|
| ↑/↓ | 导航选项 |
| Enter | 选择当前项（使用次数 +1） |
| ESC | 返回上一级（使用次数 -1） |
| H | 显示帮助信息 |

## 项目结构

```
cboot/
├── cboot.ps1                      # 主启动脚本
├── cboot.cmd                      # 批处理启动器（双击运行）
├── config/
│   ├── claude-config.example.json # 启动器配置示例
│   └── settings/                  # 模型配置示例
│       ├── settings-glm-5.2[1m].example.json
│       ├── settings-glm-5.1.example.json
│       ├── settings-glm.example.json
│       ├── settings-glm-5-turbo.example.json
│       └── settings-glm-5v-turbo.example.json
├── docs/                          # 使用截图
│   ├── 1.png
│   └── 2.png
├── README.md
└── LICENSE
```

## Changelog

### v1.0.10 (2026-06-15)

- 修复：`cboot.ps1` 编码恢复为 **UTF-8 with BOM**（v1.0.9 误将其改为 UTF-8 无 BOM），解决 Windows PowerShell 5.1 下中文按 GBK 解码导致引号/大括号配对错乱、脚本解析失败（37 条 AST 错误）、双击 `cboot.cmd` 一闪而过的问题。PowerShell 5.1 对无 BOM 的 `.ps1` 按 ANSI（GBK）解码，含中文的脚本必须存为 UTF-8 with BOM 才能兼容 PS 5.1 与 PS 7

### v1.0.9 (2026-06-13)

- 新增 glm-5.2 配置模板（`glm-5.2[1m]` + 1M 上下文窗口 `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000`）
- README 配置示例升级为 glm-5.2[1m]，补充 GLM 1M 上下文与 `/effort` 思考强度说明
- 修复：`cboot.ps1` 路径参数统一改用 `-LiteralPath`，防止含特殊字符（方括号、空格）的路径解析失败
- 修复：移除 `cboot.ps1` 文件开头 UTF-8 BOM

### v1.0.8 (2026-06-11)

- 修复 `Set-ContextWindowEnv` 在 `>=1M` 上下文窗口场景下误删 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 字段的回归 bug（WP-010 矫枉过正），1M 场景该字段应设为 `1000000` 而非移除；`CLAUDE_CODE_DISABLE_1M_CONTEXT` 仍仅在 `<1M` 时设置

### v1.0.7 (2026-06-11)

- 修复 `New-SettingsTemplate` 在 1M 上下文窗口场景下未清除模板遗留的 `CLAUDE_CODE_DISABLE_1M_CONTEXT` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 字段的问题；抽取 `Set-ContextWindowEnv` 辅助函数统一 `New-SettingsTemplate` / `Add-Model` / `Edit-ModelConfig` 三处上下文窗口 env 逻辑

### v1.0.6 (2026-06-04)

- 新增 Teammate 默认模型配置（`teammateDefaultModel` / `teammateMode`），初始化、添加模型、编辑配置全流程支持

### v1.0.5 (2026-05-20)

- statusLine 配置模板迁移 ccsp → ccstatusline

### v1.0.4 (2026-05-17)

- 修复 CLAUDE_CODE_DISABLE_1M_CONTEXT 属性设置异常

### v1.0.2 (2026-05-07)

- 新增上下文窗口设置（200K/500K/1M）
- 新增配置文件编辑功能（修改 API 密钥、Base URL、模型映射等）

### v1.0.1 (2026-04-26)

- 新增 `cboot.cmd` 批处理启动器，支持双击运行，自动绕过 PowerShell 执行策略

### v1.0.0 (2026-04-24)

- 初始发布

## License

[MIT](LICENSE)
