# Changelog

All notable changes to this project will be documented in this file.

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
