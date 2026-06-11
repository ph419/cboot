# WP-010-2-impl: 三处调用替换 + 修复 1M 遗漏 bug

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-010.md`
> - 前置子包: `docs/wp/WP-010-1-impl.md`（`Set-ContextWindowEnv` 已定义）
> - 包含: 问题分析（`200000` 残留根因）、关键文件、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | impl |
| **父工作包** | WP-010 |
| **依赖** | WP-010-1-impl |
| **执行角色** | implementer |
| **状态** | ✅ 完成 |

## 职责

将三处散落的上下文窗口 env 写入逻辑替换为调用 `Set-ContextWindowEnv`（WP-010-1-impl 新增）。其中 `New-SettingsTemplate` 处的替换**即修复 1M 场景不清除模板遗留字段的核心 bug**。

## 任务清单

- [ ] **`New-SettingsTemplate`（`cboot.ps1:297-302`）** — 删除现有 `if ($contextWindowSize -lt 1000000) { ... }` 块，替换为：
  ```powershell
  # 上下文窗口设置（>=1M 时清除模板可能遗留的字段）
  Set-ContextWindowEnv -EnvObject $template.env -ContextWindowSize $contextWindowSize
  ```
  > 注意：此处无 `$template.env` 存在性判断（`cboot.ps1:287-289` 已确保 env 存在），直接调用即可
- [ ] **`Add-Model` 已存在文件分支（`cboot.ps1:1290-1304`）** — 保留外层 `if ($settings.env) { ... }` 防御，将内部 if/else 块替换为：
  ```powershell
  Set-ContextWindowEnv -EnvObject $settings.env -ContextWindowSize $contextWindowSize
  ```
- [ ] **`Edit-ModelConfig`（`cboot.ps1:1666-1678`）** — 保留外层条件，将 if/else 块替换为：
  ```powershell
  Set-ContextWindowEnv -EnvObject $settings.env -ContextWindowSize $newContextSize
  ```
- [ ] 确认三处替换后不再有裸 `CLAUDE_CODE_DISABLE_1M_CONTEXT` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 字面量赋值（应仅存在于 `Set-ContextWindowEnv` 函数体内）
- [ ] 语法检查通过

## 验收标准

- [ ] `New-SettingsTemplate` 调用 `Set-ContextWindowEnv`，1M 场景下模板遗留字段被清除（核心 bug 修复）
- [ ] `Add-Model`、`Edit-ModelConfig` 两处调用替换完成，行为与原 else 分支一致
- [ ] `grep -n "CLAUDE_CODE_DISABLE_1M_CONTEXT\|CLAUDE_CODE_AUTO_COMPACT_WINDOW" cboot.ps1` 仅命中 `Set-ContextWindowEnv` 函数体（约 6-8 行）
- [ ] 保留各处外层 `if ($settings.env)` / `$template.env` 存在性防御
- [ ] cboot.ps1 语法检查通过

## 关键文件

- `cboot.ps1` — `cboot.ps1:297-302`（New-SettingsTemplate）、`cboot.ps1:1290-1304`（Add-Model）、`cboot.ps1:1666-1678`（Edit-ModelConfig）

## 注意事项

- `New-SettingsTemplate` 的 env 在 `cboot.ps1:287-289` 已确保存在，调用前无需再判空
- 替换后该函数体外的 if/else 缩进需对齐周围代码风格
