# WP-004-1-impl: 上下文窗口功能（初始化 + 添加模型）

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-004.md`
> - 包含: 问题分析、完整实施计划、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | impl |
| **父工作包** | WP-004 |
| **依赖** | 无 |
| **执行角色** | implementer |
| **状态** | 📋 待执行 |

## 职责

在 cboot 初始化和添加模型流程中增加上下文窗口大小设置。当用户输入小于 1M 的窗口大小时，自动在生成的 settings 文件中注入 `CLAUDE_CODE_DISABLE_1M_CONTEXT` 和 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 环境变量。

## 任务清单

- [ ] 在 `New-SettingsTemplate` 之前添加 `Parse-ContextWindow` 函数
- [ ] 修改 `New-SettingsTemplate` 函数签名，添加 `contextWindowSize` 参数
- [ ] 在 `New-SettingsTemplate` 中注入上下文窗口 env 变量
- [ ] 修改 `Initialize-Config`：增加步骤 3/6（上下文窗口设置），调整步骤编号
- [ ] 修改 `Initialize-Config`：确认信息展示增加上下文窗口行
- [ ] 修改 `Initialize-Config`：model 对象增加 `contextWindow` 字段
- [ ] 修改 `Initialize-Config`：传递 `contextWindowSize` 给 `New-SettingsTemplate`
- [ ] 修改 `Add-Model`：增加上下文窗口输入步骤
- [ ] 修改 `Add-Model`：model 对象增加 `contextWindow` 字段
- [ ] 修改 `Add-Model`：传递 `contextWindowSize` 给 `New-SettingsTemplate`

## 验收标准

- [ ] 输入 `200K` → settings 含 `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` 和 `CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000`
- [ ] 输入 `1M` 或留空 → settings 不含上述 env 变量
- [ ] 输入无效值（如 "abc"）→ 提示重新输入
- [ ] `Parse-ContextWindow` 正确解析 K 和 M 后缀
- [ ] 向后兼容：旧配置无 `contextWindow` 字段时不报错

## 关键文件

- `cboot.ps1`（唯一修改文件）
  - ~165 行前：新增 `Parse-ContextWindow` 函数
  - 166-280 行：`New-SettingsTemplate` 函数
  - 282-478 行：`Initialize-Config` 函数
  - 1033-1191 行：`Add-Model` 函数

## 实施细节

### Parse-ContextWindow 函数

```powershell
function Parse-ContextWindow {
    param([string]$Input)

    if ([string]::IsNullOrWhiteSpace($Input)) {
        return @{ size = 1000000; original = "1M" }
    }

    $Input = $Input.Trim().ToUpper()

    if ($Input -match '^(\d+(?:\.\d+)?)\s*K$') {
        $value = [double]$Matches[1]
        return @{ size = [math]::Floor($value * 1000); original = "$($value)K" }
    }

    if ($Input -match '^(\d+(?:\.\d+)?)\s*M$') {
        $value = [double]$Matches[1]
        return @{ size = [math]::Floor($value * 1000000); original = "$($value)M" }
    }

    return $null
}
```

### New-SettingsTemplate 上下文窗口注入

在函数签名添加 `[int]$contextWindowSize = 1000000`，在步骤 4（替换 env 字段后）添加：

```powershell
if ($contextWindowSize -lt 1000000) {
    $template.env.CLAUDE_CODE_DISABLE_1M_CONTEXT = "1"
    $compactWindow = [math]::Floor($contextWindowSize * 0.9)
    $template.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW = "$compactWindow"
}
```

### Initialize-Config 上下文窗口步骤

在步骤 2/6 之后插入（需将原步骤 3→4, 4→5, 5→6）：

```
步骤 3/6: 上下文窗口设置

请输入上下文窗口大小（如 200K、500K、1M，默认 1M）:
```

### Add-Model 上下文窗口输入

在 API 参数输入后、模板生成前插入。如果配置文件已存在，也需要读取 → 修改 env → 写回。
