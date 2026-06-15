# WP-012-1-impl: 转换 cboot.ps1 编码为 UTF-8 with BOM

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-012.md`
> - 包含: 问题分析（编码与 PS 5.1 解码不匹配根因）、实施计划、关键文件、验收标准

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | impl |
| **父工作包** | WP-012 |
| **依赖** | 无 |
| **执行角色** | implementer |
| **状态** | 📋 待执行 |

## 职责

备份原文件，将 `cboot.ps1` 由 UTF-8 无 BOM 转为 UTF-8 with BOM（前置 `EF BB BF`），**不改动任何内容字节**。

## 任务清单

- [ ] 备份 `D:\cboot\cboot.ps1` → `D:\cboot\cboot.ps1.bak`
- [ ] 用 `UTF8Encoding($true)` 重写文件（前置 BOM）：
  ```powershell
  $src = 'D:\cboot\cboot.ps1'
  $content = Get-Content -LiteralPath $src -Raw -Encoding UTF8
  $utf8Bom = New-Object System.Text.UTF8Encoding($true)
  [System.IO.File]::WriteAllText($src, $content, $utf8Bom)
  ```
- [ ] 转换后立即自查首三字节为 `EF BB BF`：
  ```powershell
  $bytes = [System.IO.File]::ReadAllBytes('D:\cboot\cboot.ps1')
  ($bytes[0..2] | ForEach-Object { $_.ToString('X2') }) -join ' '   # 期望: EF BB BF
  ```
- [ ] 内容完整性自查：`.bak` 去掉 BOM 后与转换后文件内容一致（无字节篡改）

## 验收标准

- [ ] `cboot.ps1` 首三字节为 `EF BB BF`
- [ ] `cboot.ps1.bak` 已生成（保留原始无 BOM 版本）
- [ ] 内容字节未被篡改（仅前置 3 字节 BOM，其余字节逐位一致）
- [ ] 本子包**不**执行多环境 AST 验证（留给 WP-012-2-verify）

## 关键文件

- `D:\cboot\cboot.ps1` — 转换目标
- `D:\cboot\cboot.ps1.bak` — 转换前备份（新建）

## 注意事项

- **不要**用记事本另存为"UTF-8"——记事本的"UTF-8"默认不加 BOM，会再次触发本问题
- 必须确认写入编码为 `UTF8Encoding($true)`（`$true` = emit BOM）
- 转换是字节级操作，禁止用任何会重新转码/格式化的中间步骤（如编辑器另存）
