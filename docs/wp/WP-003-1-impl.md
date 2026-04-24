# WP-003-1-impl: 核心代码实现

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-003.md`
> - 包含: 问题分析、完整实施计划、关键文件、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | impl |
| **父工作包** | WP-003 |
| **依赖** | 无 |
| **执行角色** | implementer |
| **状态** | 📋 待执行 |

## 职责

实现添加模型流程的三项增强：
1. `New-SettingsTemplate` 改为模板复制模式
2. `Add-Model` 添加空行取消退出和 5 个核心参数输入
3. `Initialize-Config` 同步增强参数输入

## 任务清单

- [ ] 重写 `New-SettingsTemplate` 函数（第 36-116 行）
  - 支持从已有 settings 文件读取作为模板
  - 新增参数：authToken, baseUrl, opusModel, sonnetModel, haikuModel
  - 无模板时 fallback 到硬编码模板
- [ ] 改造 `Add-Model` 函数（第 663-755 行）
  - 支持空行取消退出（每步可取消返回主菜单）
  - 新增 5 个参数输入步骤（AUTH_TOKEN/BASE_URL/OPUS/SONNET/HAIKU）
  - 有默认值的参数空行取默认值，无默认值的空行取消
- [ ] 改造 `Initialize-Config` 函数（第 118-232 行）
  - 同步添加 5 个参数输入步骤
  - 支持空行取消退出

## 关键文件

- `cboot.ps1` — 唯一需要修改的文件，三个区域

## 参考模板文件

- `C:\Users\41290\.claude\settings-glm-5.1.json` — 用户实际 settings 文件，包含完整结构
  - env 中有 `ENABLE_PROMPT_CACHING_1H` 等额外字段需保留
  - permissions 中有用户自定义的 `Bash(rm -rf D:/*)` 等条目需保留
