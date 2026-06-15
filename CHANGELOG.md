# Changelog

All notable changes to this project will be documented in this file.

## [1.0.10] - 2026-06-15

### Fixed

- **cboot.ps1 编码恢复为 UTF-8 with BOM** — v1.0.9 误将 `cboot.ps1` 改为 UTF-8 无 BOM，导致 Windows PowerShell 5.1（双击 `cboot.cmd` / `powershell.exe` 默认环境）对无 BOM 的 `.ps1` 按系统 ANSI 代码页（中文系统为 GBK/CP936）解码，中文 UTF-8 字节中的 `0x22`/`0x7D`/`0x29` 等被 GBK 解码后打乱字符串终止符与大括号配对，触发 37 条 AST 解析错误（Line 356/357/370/372 等），脚本根本未能解析、PowerShell 立即退出，表现为窗口一闪而过。现已恢复为 UTF-8 with BOM（首字节 `EF BB BF`），PS 5.1 AST 解析 0 错误、PS 7 无回归。内容除新增 3 字节 BOM 外逐字节不变（与 v1.0.9 文本完全一致）

## [1.0.9] - 2026-06-13

### Added

- **glm-5.2 模型配置模板** — 新增 `config/settings/settings-glm-5.2[1m].example.json`，`ANTHROPIC_DEFAULT_SONNET_MODEL` / `OPUS_MODEL` 设为 `glm-5.2[1m]`、`HAIKU_MODEL` 设为 `glm-4.5-air`、`CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000`，开启 GLM 1M 上下文窗口，供初始化与添加模型时直接选用

### Changed

- **README 配置示例升级为 glm-5.2[1m]** — `claude-config.json` 与 `settings-*.json` 示例由 glm-5.1 更新为 glm-5.2[1m]；新增 GLM 1M 上下文窗口（`[1m]` 后缀 + `CLAUDE_CODE_AUTO_COMPACT_WINDOW`）与 `/effort` 思考强度切换说明；项目结构与模板列表补列 glm-5.2 模板

### Fixed

- **路径参数统一改用 `-LiteralPath`** — `cboot.ps1` 中全部 `Test-Path` / `Get-Content` / `Set-Content` / `Remove-Item` 路径参数改用 `-LiteralPath`（约 18 处），防止配置/项目路径含特殊字符（方括号 `[]`、空格）被 PowerShell 当通配符解析导致命令失败
- **移除 cboot.ps1 文件开头 UTF-8 BOM**

## [1.0.8] - 2026-06-11

### Fixed

- **1M 上下文窗口误删 CLAUDE_CODE_AUTO_COMPACT_WINDOW 字段（WP-010 回归修复）** — 修复 `Set-ContextWindowEnv` 的 `>=1M` 分支（WP-010 引入）将 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 一并移除的问题。该字段应始终等于上下文窗口大小，故 1M 场景现正确设为 `1000000`，仅在 `<1M` 时额外设置 `CLAUDE_CODE_DISABLE_1M_CONTEXT=1`。修正 hashtable 与 PSCustomObject 两类型路径的 `>=1M` 分支，`<1M` 分支与 `DISABLE_1M_CONTEXT` 移除逻辑保持不变

## [1.0.7] - 2026-06-11

### Fixed

- **1M 上下文窗口新建模型残留 DISABLE_1M_CONTEXT / AUTO_COMPACT_WINDOW** — 修复 `New-SettingsTemplate` 在用户填写 1M 上下文窗口、复用含 200K 残留字段的旧模板时，未清除模板遗留的 `CLAUDE_CODE_DISABLE_1M_CONTEXT` 与 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`（导致出现 `200000` 残留值）的问题。`>=1M` 分支现正确移除两字段，且兼容 hashtable 与 PSCustomObject 两种模板类型

### Changed

- **抽取 `Set-ContextWindowEnv` 辅助函数** — 将 `New-SettingsTemplate` / `Add-Model` / `Edit-ModelConfig` 三处重复的上下文窗口 env 设置/移除逻辑统一抽取为 `Set-ContextWindowEnv`，既修复 `New-SettingsTemplate` 的遗漏，又消除三处重复逻辑，防止后续新增调用点时再次遗漏

## [1.0.6] - 2026-06-04

### Added

- **Teammate 默认模型配置** — 支持在 settings 中设置 `teammateDefaultModel` 和 `teammateMode`，控制 Claude Code 的 teammate 子代理使用指定模型。涉及 `cboot.ps1` 6 处修改 + 4 个 settings 模板文件：
  - `New-SettingsTemplate` 新增 `-teammateModel` 参数，模板生成时写入 `teammateDefaultModel` / `teammateMode`
  - `Initialize-Config` 新增步骤 3/7 交互输入 Teammate 模型（步骤从 6 步扩展为 7 步）
  - `Add-Model` 新增 Teammate 模型输入，已有配置文件更新时写入 teammate 字段
  - `Edit-ModelConfig` 编辑菜单新增「Teammate 模型」选项，支持修改或输入 `null` 清除为系统默认

## [1.0.5] - 2026-05-20

### Changed

- **statusLine 配置模板迁移** — 将所有 statusLine 从 `ccsp --preset MBTC --theme powerline` 迁移到 `ccstatusline`，新增 `refreshInterval: 10` 属性。涉及 4 个 settings 模板文件和 `cboot.ps1` 共 10 处更新

## [1.0.4] - 2026-05-17

### Fixed

- **CLAUDE_CODE_DISABLE_1M_CONTEXT 属性设置异常** — 修复 `Add-Model` 和 `Edit-ModelConfig` 中直接赋值 `CLAUDE_CODE_DISABLE_1M_CONTEXT` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 在旧版 settings 文件（无对应属性）时抛出异常的问题，改用 `Add-Member -Force` 设置属性、先检查存在性再 `Remove`

## [1.0.3] - 2026-05-11

### Changed

- **移除上下文窗口 90% 比例设定** — 上下文窗口值不再乘以 0.9，直接使用用户填写的原始值（如填 200K 则设为 200000）

## [1.0.2] - 2026-05-07

### Added

- **上下文窗口设置** — 初始化和添加模型时支持设置上下文窗口大小（如 200K、500K、1M），自动配置 `CLAUDE_CODE_DISABLE_1M_CONTEXT` 和 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 环境变量
- **配置文件编辑功能** — 主菜单新增「修改配置」选项，支持交互式编辑 API 密钥、Base URL、模型映射、上下文窗口等字段，ESC 可安全返回

### Fixed

- **contextWindow 属性设置异常** — 修复旧配置（无 contextWindow 字段）时编辑上下文窗口报错的问题，改用 `Add-Member -Force` 安全设置属性

## [1.0.1] - 2026-04-26

### Added

- **批处理启动器 `cboot.cmd`** — 支持双击运行，自动绕过 PowerShell 执行策略，方便新用户零门槛启动

## [1.0.0] - 2025-04-25

### Added

- **首次运行引导初始化配置** — 首次启动 `cboot.ps1` 时自动检测配置缺失，引导用户完成 5 步初始化：
  - 步骤 1/5：配置模型基础信息（模型 ID、显示名称）
  - 步骤 2/5：配置 API 参数（密钥、Base URL、模型映射）
  - 步骤 3/5：选择默认权限（是否允许所有操作）
  - 步骤 4/5：设置项目目录路径（可跳过）
  - 步骤 5/5：确认并生成配置文件
- 配置文件自动生成到 `~/.claude/` 目录，包含 `claude-config.json` 和对应的 `settings-*.json`
- 支持从 `config/` 目录示例配置快速初始化
- 模型运行时添加/移除管理
- 项目目录添加/移除管理，自动清理无效路径
- 交互式菜单：方向键导航、回车选择、ESC 返回
- 多模型按使用频率智能排序
- 使用统计持久化记录
- 配置缺失时提供逐项修复选项
