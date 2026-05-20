# 校验报告

## 基本信息
- 执行日期: 2026-05-20
- 工作包: WP-008 (更新 statusLine 配置模板 — ccsp → ccstatusline)
- 拆分模式: simple
- 校验方式: 逐项对照验收标准，grep 全局搜索 + 文件内容审查

## 验收标准逐项校验

### 1. 4 个 settings 模板文件的 statusLine 已更新

| 文件 | 状态 | 说明 |
|------|------|------|
| `config/settings/settings-glm.example.json` (L93-96) | ✅ | `"command": "ccstatusline"`, `"refreshInterval": 10` |
| `config/settings/settings-glm-5-turbo.example.json` (L93-96) | ✅ | `"command": "ccstatusline"`, `"refreshInterval": 10` |
| `config/settings/settings-glm-5v-turbo.example.json` (L93-96) | ✅ | `"command": "ccstatusline"`, `"refreshInterval": 10` |
| `config/settings/settings-glm-5.1.example.json` (L93-96) | ✅ | `"command": "ccstatusline"`, `"refreshInterval": 10` |

每个文件的 statusLine 结构均为：
```json
"statusLine": {
  "type": "command",
  "command": "ccstatusline",
  "refreshInterval": 10
}
```

### 2. cboot.ps1 模板中 statusLine 已更新并增加 refreshInterval

- `cboot.ps1:277-281` — statusLine 模板块 ✅
  - `command = "ccstatusline"` ✅
  - `refreshInterval = 10` ✅

### 3. cboot.ps1 PostToolUse hook 命令已更新

- `cboot.ps1:233` — PostToolUse hook 中 `command = "ccstatusline"` ✅

### 4. 全局搜索 ccsp 无残留引用

- `grep "ccsp" cboot.ps1` — **0 处匹配** ✅
- `grep "ccsp" config/` — **0 处匹配** ✅
- `ccsp` 仅出现在文档文件 (`docs/wp/WP-008.md`, `task.md`) 中作为变更说明 ✅

## 额外验证

### ccstatusline 出现次数统计

| 位置 | 出现次数 | 说明 |
|------|----------|------|
| `cboot.ps1` | 2 | L233 (hook) + L279 (statusLine) |
| `settings-glm.example.json` | 2 | L9 (hook) + L95 (statusLine) |
| `settings-glm-5-turbo.example.json` | 2 | L9 (hook) + L95 (statusLine) |
| `settings-glm-5v-turbo.example.json` | 2 | L9 (hook) + L95 (statusLine) |
| `settings-glm-5.1.example.json` | 2 | L9 (hook) + L95 (statusLine) |
| **合计** | **10** | 与预期一致 |

### refreshInterval 出现次数统计

| 位置 | 出现次数 |
|------|----------|
| `cboot.ps1` | 1 (L280) |
| 4 个 settings 模板文件 | 4 (各 L96) |
| **合计** | **5** |

### Settings 模板 PostToolUse hook 验证

4 个 settings 模板文件的 `hooks.PostToolUse[0].hooks[0].command` 均为 `"ccstatusline"` ✅

## 📁 文件变更汇总

| 文件 | 变更点 |
|------|--------|
| `cboot.ps1` | L233: hook ccsp→ccstatusline; L277-280: statusLine 模板重写 |
| `config/settings/settings-glm.example.json` | L9: hook; L93-96: statusLine |
| `config/settings/settings-glm-5-turbo.example.json` | L9: hook; L93-96: statusLine |
| `config/settings/settings-glm-5v-turbo.example.json` | L9: hook; L93-96: statusLine |
| `config/settings/settings-glm-5.1.example.json` | L9: hook; L93-96: statusLine |

## 结论

WP-008 全部 4 项验收标准均通过校验。`ccsp` 已从所有代码和配置文件中完全移除，`ccstatusline` 正确出现在 10 处预期位置，`refreshInterval: 10` 在 5 处 statusLine 配置中一致添加。

---
报告生成时间: 2026-05-20
