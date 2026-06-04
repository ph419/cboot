# WP-009-1-impl: 实现 Default Teammate Model 配置

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-009.md`
> - 分析报告: `docs/reports/2026-06-03_teammate-model-analysis.md`
> - 包含: 问题分析、技术要点、关键文件

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | impl |
| **父工作包** | WP-009 |
| **依赖** | 无 |
| **执行角色** | 领域专家 |
| **状态** | ✅ 完成 (2026-06-03) |

## 职责

修改 `cboot.ps1` 和 4 个示例 settings 文件，添加 `teammateDefaultModel` 和 `teammateMode` 配置支持。

## 任务清单

### cboot.ps1 修改

- [ ] **1.** `New-SettingsTemplate` 参数列表增加 `[string]$teammateModel = $null`（L189-198）
- [ ] **2.** 硬编码模板增加 `teammateDefaultModel = $null` 和 `teammateMode = "auto"`（L276 之前，`statusLine` 之前）
- [ ] **3.** 参数注入区增加 teammate 配置注入（L301 之后）：
  ```powershell
  $template | Add-Member -MemberType NoteProperty -Name "teammateDefaultModel" -Value $teammateModel -Force
  $template | Add-Member -MemberType NoteProperty -Name "teammateMode" -Value "auto" -Force
  ```
- [ ] **4.** `Add-Model` 在 HAIKU_MODEL 输入后增加 teammate 模型输入（L1219 之后）
- [ ] **5.** `Add-Model` 的 `New-SettingsTemplate` 调用增加 `-teammateModel $teammateModel` 参数（L1253）
- [ ] **6.** `Initialize-Config` 在 HAIKU_MODEL 输入后增加 teammate 模型输入（L380 之后）
- [ ] **7.** `Initialize-Config` 确认屏幕增加 teammate 模型显示
- [ ] **8.** `Initialize-Config` 的 `New-SettingsTemplate` 调用增加 `-teammateModel` 参数
- [ ] **9.** `Edit-ModelConfig` 字段列表增加 "Teammate 模型"（L1509-1517，Haiku 之后、上下文窗口之前）
- [ ] **10.** `Edit-ModelConfig` 更新 maxIndex 从 6 改为 7（L1536）
- [ ] **11.** `Edit-ModelConfig` switch 增加 case 5（Teammate 模型编辑），原 case 5→6、case 6→7

### 示例文件修改

- [ ] **12.** `config/settings/settings-glm.example.json` 添加 teammateDefaultModel + teammateMode
- [ ] **13.** `config/settings/settings-glm-5-turbo.example.json` 添加 teammateDefaultModel + teammateMode
- [ ] **14.** `config/settings/settings-glm-5v-turbo.example.json` 添加 teammateDefaultModel + teammateMode
- [ ] **15.** `config/settings/settings-glm-5.1.example.json` 添加 teammateDefaultModel + teammateMode

## 验收标准

- [ ] `New-SettingsTemplate` 接受 `$teammateModel` 参数并写入 settings
- [ ] `Add-Model` 流程包含 teammate 模型输入步骤
- [ ] `Initialize-Config` 流程包含 teammate 模型输入步骤
- [ ] `Edit-ModelConfig` 可编辑 Teammate 模型字段
- [ ] 旧版 settings.json（无 teammateDefaultModel）编辑时自动补全
- [ ] 4 个示例文件均包含 teammateDefaultModel 和 teammateMode

## 关键文件

- `cboot.ps1`
- `config/settings/settings-glm.example.json`
- `config/settings/settings-glm-5-turbo.example.json`
- `config/settings/settings-glm-5v-turbo.example.json`
- `config/settings/settings-glm-5.1.example.json`
